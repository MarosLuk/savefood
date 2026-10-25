import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:marketplace_domain/marketplace_domain.dart';
import 'package:marketplace_fixtures/marketplace_fixtures.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;
import 'package:uuid/uuid.dart';
import 'auth.dart';
import 'config.dart';
import 'database.dart';
import 'payments.dart';
import 'push.dart';
import 'geocoding.dart';
import 'merchant.dart';
import 'showcase.dart';
import 'finance.dart';
import 'support.dart';
import 'connect.dart';
import 'mail.dart';
import 'accounts.dart';
import 'media.dart';
import 'reviews.dart';
import 'platform.dart';
import 'billing.dart';
import 'legal.dart';
import 'runtime_status.dart';
part 'operations_routes.dart';
part 'account_routes.dart';
part 'media_routes.dart';
part 'platform_routes.dart';
part 'billing_routes.dart';
part 'completion_demo.dart';

class MarketplaceServer {
  MarketplaceServer(
    this.config, {
    MarketplaceDatabase? database,
    PaymentGateway? payments,
    StockPushGateway? push,
    ConnectGateway? connect,
    MailGateway? mail,
    http.Client? authClient,
    DateTime Function()? clock,
  }) : database = database ?? MarketplaceDatabase(config.databasePath),
       payments =
           payments ??
           (config.paymentMode == 'stripe'
               ? StripePaymentGateway(config)
               : config.paymentMode == 'disabled'
               ? DisabledPaymentGateway()
               : SandboxPaymentGateway()),
       push =
           push ??
           (config.firebaseServiceAccount.isEmpty
               ? DisabledPushGateway()
               : FirebasePushGateway(config.firebaseServiceAccount)),
       clock = clock ?? DateTime.now {
    tz_data.initializeTimeZones();
    config.validateShowcase();
    auth = AuthService(
      this.database,
      config,
      clock: this.clock,
      client: authClient,
    );
    this.mail = MailService(
      this.database,
      mail ??
          (config.mailApiKey.isEmpty
              ? DisabledMailGateway()
              : ResendMailGateway(config.mailApiKey, config.mailFrom)),
      clock: this.clock,
    );
    places = PlaceSearch(config.geocoderUrl);
    merchants = MerchantService(
      this.database,
      clock: this.clock,
      allowDemoImages: config.demoShowcase,
      mediaBaseUrl: config.publicUrl,
      appUrl: config.merchantAppUrl,
      mail: this.mail,
      requireVerifiedEmails: config.production,
    );
    finance = FinanceService(
      this.database,
      config,
      connect ??
          (config.paymentMode == 'stripe'
              ? StripeConnectGateway(config)
              : config.paymentMode == 'disabled'
              ? DisabledConnectGateway()
              : SandboxConnectGateway()),
      _working,
      clock: this.clock,
    );
    support = SupportService(this.database, clock: this.clock, mail: this.mail);
    accounts = AccountService(this.database, auth, this.mail);
    media = MediaService(this.database, config, clock: this.clock);
    reviews = ReviewService(this.database, media, clock: this.clock);
    platform = PlatformService(this.database, support, clock: this.clock);
    billing = BillingService(this.database, finance, config, clock: this.clock);
    finance.documentsChanged = billing.queue;
    legal = LegalService(
      this.database,
      production: config.production,
      demo: config.demoShowcase,
      clock: this.clock,
    );
    runtime = RuntimeStatus(this.database, config, this.mail, billing, legal);
    _seed();
    _ensureShowcase();
    finance.backfill();
    billing.prepareDemo();
    if (config.demoShowcase) {
      this.database.db.execute(
        "UPDATE users SET email_verified=1 WHERE id='showcase-support'",
      );
      this.database.db.execute(
        "INSERT OR IGNORE INTO platform_roles VALUES('showcase-support','admin')",
      );
    }
    platform.bootstrap(config.platformAdminEmails);
    _merchantTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      try {
        merchants.runScheduled();
        _scanSupportEvents();
        support.cleanPhotos();
        legal.clean();
        billing.retryPending();
        billing.cleanExpired();
        unawaited(this.mail.drain());
        unawaited(finance.drain());
      } catch (error) {
        stderr.writeln('Merchant automation failed (${error.runtimeType}).');
      }
    });
    if (this.push.configured) {
      _pushTimer = Timer.periodic(
        const Duration(seconds: 20),
        (_) => unawaited(drainPush()),
      );
    }
  }
  final ServerConfig config;
  final MarketplaceDatabase database;
  final PaymentGateway payments;
  final StockPushGateway push;
  late final PlaceSearch places;
  late final MerchantService merchants;
  late final FinanceService finance;
  late final SupportService support;
  late final MailService mail;
  late final AccountService accounts;
  late final MediaService media;
  late final ReviewService reviews;
  late final PlatformService platform;
  late final BillingService billing;
  late final LegalService legal;
  late final RuntimeStatus runtime;
  Timer? _merchantTimer;
  Timer? _pushTimer;
  bool _draining = false;
  final DateTime Function() clock;
  late final AuthService auth;
  final Set<String> _working = {};
  Map<String, dynamic>? _clubPlan;
  DateTime? _clubPlanLoaded;

  void _ensureShowcase() {
    if (config.demoShowcase) {
      DemoShowcase(database, merchants, clock).ensure();
      finance.backfill();
      _seedOperationsDemo();
    }
  }

  Handler get handler {
    final router = Router();
    router.get(
      '/health',
      (Request r) => _json({'status': 'ok', 'paymentMode': config.paymentMode}),
    );
    router.get(
      '/v1/config',
      (Request r) async => _json({
        'paymentMode': config.paymentMode,
        'paymentsEnabled': config.paymentMode != 'disabled',
        'payments': config.paymentConfiguration,
        'demoCatalog': config.seedDemo,
        'demoShowcase': config.demoShowcase,
        'providers': auth.providers,
        'firebaseAuth': {
          'projectId': config.firebaseAuthEnabled
              ? config.firebaseAuthProjectId
              : '',
          'google': auth.firebase.enabled('google'),
          'apple': auth.firebase.enabled('apple'),
        },
        'clubPlan': await _membershipPlan(),
        'pushEnabled': push.configured,
        'placeSearchEnabled': config.geocoderUrl.isNotEmpty,
        'merchantPortalEnabled': true,
        'supportEnabled': true,
        'financeEnabled': true,
        'emailEnabled': mail.gateway.configured || config.demoShowcase,
      }),
    );
    _accountRoutes(router);
    _mediaRoutes(router);
    router.get(
      '/health/ready',
      (Request r) => _json({
        'ready': runtime.databaseReady,
      }, status: runtime.databaseReady ? 200 : 503),
    );
    router.get('/v1/platform/readiness', (Request r) {
      platform.require(_user(r));
      return _json(runtime.report());
    });
    _platformRoutes(router);
    _billingRoutes(router);
    router.get(
      '/v1/legal',
      (Request r) => _json(
        legal.current(
          version: int.tryParse(r.url.queryParameters['version'] ?? ''),
        ),
      ),
    );
    router.post(
      '/v1/legal/accept',
      (Request r) => _merchantMutation(r, (u, b) {
        legal.accept(u, b);
        return {'ok': true};
      }),
    );
    router.get('/v1/platform/legal', (Request r) {
      platform.require(_user(r));
      return _json(legal.draft());
    });
    router.post(
      '/v1/platform/legal',
      (Request r) => _merchantMutation(r, (u, b) {
        platform.require(u, write: true);
        final result = legal.save(b, publish: b['publish'] == true);
        database.db.execute(
          'INSERT INTO platform_audit VALUES(?,?,?,?,?,?,?)',
          [
            const Uuid().v4(),
            u,
            'legal-updated',
            'legal',
            'policy',
            jsonEncode({'published': b['publish'] == true}),
            clock().toUtc().toIso8601String(),
          ],
        );
        return result;
      }),
    );
    router.get('/v1/places', (Request r) async {
      final query = (r.url.queryParameters['q'] ?? '').trim();
      if (query.length > 150) {
        throw const ApiFailure(400, 'Príliš dlhá adresa.');
      }
      try {
        return _json({
          'places': await places.search(
            query,
            r.url.queryParameters['lang'] ?? 'sk',
          ),
        });
      } catch (_) {
        throw const ApiFailure(
          503,
          'Adresu sa nepodarilo vyhľadať. Miesto môžeš označiť na mape.',
        );
      }
    });
    router.get('/v1/catalog', (Request r) async {
      await _expire();
      _seed();
      _ensureShowcase();
      return _json({'offers': catalog().map((o) => o.toJson()).toList()});
    });
    router.post('/v1/auth/register', (Request r) async {
      auth.rateLimit('register:${_ip(r)}');
      if (config.production && !mail.gateway.configured) {
        throw const ApiFailure(
          503,
          'Registrácia bude dostupná po aktivácii e-mailovej služby.',
        );
      }
      final body = await _body(r),
          consent = Map<String, dynamic>.from(
            (body['legalConsent'] as Map?) ?? {},
          );
      if (config.production || consent.isNotEmpty) {
        legal.validateAcceptance(consent);
      }
      final result = await auth.register(body);
      if (consent.isNotEmpty) legal.accept(result['userId'] as String, consent);
      if (mail.gateway.configured || config.demoShowcase) {
        await accounts.request(
          {'purpose': 'verify'},
          user: result['userId'] as String,
          session: 'Bearer ${result['token']}',
        );
      }
      return _json(result, status: 201);
    });
    router.post('/v1/auth/login', (Request r) async {
      auth.rateLimit('login:${_ip(r)}');
      return _json(await auth.login(await _body(r)));
    });
    router.post('/v1/auth/firebase', (Request r) async {
      auth.rateLimit('firebase:${_ip(r)}');
      final body = await _body(r);
      final consent = Map<String, dynamic>.from(
        body['legalConsent'] as Map? ?? {},
      );
      return _json(
        await auth.loginFirebase(
          body,
          beforeCreate: () {
            if (config.production && consent.isEmpty) {
              throw const ApiFailure(
                428,
                'Pred vytvorením účtu potvrď aktuálne podmienky.',
              );
            }
            if (config.production || consent.isNotEmpty) {
              legal.validateAcceptance(consent);
            }
          },
          afterCreate: (id) {
            if (consent.isNotEmpty) legal.accept(id, consent);
          },
        ),
      );
    });
    if (config.demoShowcase) {
      router.post('/v1/auth/demo', (Request r) async {
        final persona = stringField(await _body(r), 'persona');
        if (!demoPersonas.any((p) => p.id == persona)) {
          throw const ApiFailure(400, 'Vyber pripravený demo profil.');
        }
        auth.rateLimit('demo:${_ip(r)}:$persona');
        _ensureShowcase();
        return _json(auth.createSession('${DemoShowcase.userPrefix}$persona'));
      });
    }
    router.post('/v1/auth/logout', (Request r) {
      final authorization = r.headers['authorization'];
      if (authorization?.startsWith('Bearer ') ?? false) {
        database.db.execute('DELETE FROM devices WHERE session_hash=?', [
          hashToken(authorization!.substring(7)),
        ]);
      }
      auth.logout(r.headers['authorization']);
      return _json({'ok': true});
    });
    router.post('/v1/devices', (Request r) async {
      final user = _user(r);
      final body = await _body(r);
      final token = stringField(body, 'token');
      final platform = stringField(body, 'platform');
      if (token.length < 20 ||
          token.length > 4096 ||
          !{'ios', 'android', 'web'}.contains(platform)) {
        throw const ApiFailure(400, 'Neplatná registrácia zariadenia.');
      }
      database.db.execute(
        'INSERT INTO devices(token,user_id,session_hash,platform) VALUES(?,?,?,?) ON CONFLICT(token) DO UPDATE SET user_id=excluded.user_id,session_hash=excluded.session_hash,platform=excluded.platform',
        [
          token,
          user,
          hashToken(r.headers['authorization']!.substring(7)),
          platform,
        ],
      );
      return _json({'ok': true});
    });
    router.post('/v1/devices/remove', (Request r) {
      final user = _user(r);
      database.db.execute(
        'DELETE FROM devices WHERE user_id=? AND session_hash=?',
        [user, hashToken(r.headers['authorization']!.substring(7))],
      );
      return _json({'ok': true});
    });
    router.post('/v1/auth/oauth/<provider>', (Request r, String provider) {
      auth.rateLimit('oauth:${_ip(r)}');
      return _json(auth.beginOAuth(provider));
    });
    router.get('/v1/auth/oauth/<provider>/callback', _oauthCallback);
    router.post('/v1/auth/oauth/<provider>/callback', _oauthCallback);
    router.post('/v1/auth/oauth/poll/<id>', (Request r, String id) async {
      auth.rateLimit('poll:${_ip(r)}:$id');
      final body = await _body(r);
      return _json(auth.pollOAuth(id, stringField(body, 'pollSecret')));
    });
    router.get('/v1/me', (Request r) async {
      await _expire();
      return _json(profile(_user(r)));
    });
    router.patch('/v1/me', (Request r) async {
      final id = _user(r);
      _updateProfile(id, await _body(r));
      return _json(profile(id));
    });
    router.get('/v1/orders', (Request r) async {
      await _expire();
      return _json({
        'orders': _orders(_user(r)).map((o) => o.toJson()).toList(),
      });
    });
    router.post(
      '/v1/orders',
      (Request r) async => _json(
        (await reserve(_user(r), await _body(r))).toJson(),
        status: 201,
      ),
    );
    router.post('/v1/orders/<id>/collect', (Request r, String id) async {
      final body = await _body(r);
      return _json(
        collect(
          _user(r),
          id,
          stringField(body, 'pickupCode'),
          offerId: body['offerId'] as String?,
        ).toJson(),
      );
    });
    router.post(
      '/v1/orders/<id>/cancel',
      (Request r, String id) async =>
          _json((await cancel(_user(r), id)).toJson()),
    );
    router.post('/v1/orders/<id>/refresh', (Request r, String id) async {
      final user = _user(r);
      _ownedOrder(user, id);
      await _refreshPayment(id);
      return _json(_ownedOrder(user, id).toJson());
    });
    router.post('/v1/orders/<id>/payment-sheet', (Request r, String id) async {
      final user = _user(r);
      await _expire();
      final order = _ownedOrder(user, id);
      if (order.paymentFlow != PaymentFlow.native ||
          order.status != OrderStatus.awaitingPayment ||
          !config.nativePaymentsEnabled ||
          payments is! StripePaymentGateway) {
        throw const ApiFailure(
          409,
          'Táto rezervácia nemá otvorenú platbu v aplikácii.',
        );
      }
      final row = database.db.select(
        'SELECT payment_session FROM orders WHERE id=? AND user_id=?',
        [id, user],
      ).first;
      final intentId = row['payment_session'] as String?;
      if (intentId == null) {
        throw const ApiFailure(409, 'Platba sa ešte pripravuje. Skús znova.');
      }
      final secret = await (payments as StripePaymentGateway).clientSecret(
        intentId,
        order,
      );
      return _json({...config.paymentConfiguration, 'clientSecret': secret});
    });
    router.post('/v1/club/trial', (Request r) async {
      final user = _user(r);
      final body = await _body(r);
      _activateTrial(user, body['code'] as String? ?? '');
      return _json(profile(user));
    });
    router.post(
      '/v1/club/checkout',
      (Request r) async => _json(await _membershipCheckout(_user(r))),
    );
    router.post('/v1/club/cancel', (Request r) async {
      final user = _user(r);
      final subscription = auth.user(user)['subscription_id'] as String?;
      if (subscription != null && payments is StripePaymentGateway) {
        await (payments as StripePaymentGateway).cancelRenewal(subscription);
        database.db.execute(
          'UPDATE users SET subscription_cancelled=1 WHERE id=?',
          [user],
        );
      } else {
        database.db.execute('UPDATE users SET member_until=NULL WHERE id=?', [
          user,
        ]);
      }
      return _json(profile(user));
    });
    router.get(
      '/v1/offers/<id>/reviews',
      (Request r, String id) => _json(
        reviews.list(
          id,
          user: r.headers['authorization'] == null ? null : _user(r),
          before: r.url.queryParameters['before'],
        ),
      ),
    );
    router.post('/v1/offers/<id>/reviews', (Request r, String id) async {
      final user = _user(r);
      _review(user, id, await _body(r));
      return _json({'ok': true}, status: 201);
    });
    router.post('/v1/offers/<id>/reviews/delete', (Request r, String id) {
      reviews.remove(_user(r), id);
      return _json({'deleted': true});
    });
    router.post('/v1/offers/<id>/review-photos', (Request r, String id) async {
      final user = _user(r);
      reviews.requireEligible(user, id);
      auth.rateLimit('review-photo:$user');
      return _json(
        await media.add(user, await _imageBody(r), kind: 'review'),
        status: 201,
      );
    });
    router.post('/v1/admin/offers', (Request r) async {
      _admin(r);
      final body = await _body(r);
      _putOffer(body);
      return _json({'ok': true}, status: 201);
    });
    router.post('/v1/admin/orders/<id>/cancel', (Request r, String id) async {
      _admin(r);
      final rows = database.db.select('SELECT user_id FROM orders WHERE id=?', [
        id,
      ]);
      if (rows.isEmpty) throw const ApiFailure(404, 'Objednávka sa nenašla.');
      return _json(
        (await cancel(
          rows.first['user_id'] as String,
          id,
          expired: true,
        )).toJson(),
      );
    });
    router.post('/v1/payments/webhook', _webhook);
    _merchantRoutes(router);
    _operationsRoutes(router);
    router.get(
      '/payment/return',
      (Request r) => Response.ok(
        _returnPage,
        headers: {
          'content-type': 'text/html; charset=utf-8',
          'content-security-policy':
              "default-src 'none'; style-src 'unsafe-inline'",
        },
      ),
    );
    Future<Response> dispatch(Request request) async {
      final origin = request.headers['origin'];
      if (origin != null && !config.allowedOrigins.contains(origin)) {
        return _json({'error': 'Origin nie je povolený.'}, status: 403);
      }
      final cors = <String, String>{
        'access-control-allow-origin': ?origin,
        'access-control-allow-methods': 'GET,POST,PATCH,OPTIONS',
        'access-control-allow-headers': 'Authorization,Content-Type',
        'vary': 'Origin',
        'cache-control': 'no-store',
        'x-content-type-options': 'nosniff',
      };
      if (request.method == 'OPTIONS') return Response(204, headers: cors);
      try {
        return (await router.call(request)).change(headers: cors);
      } on ApiFailure catch (e) {
        return _json({
          'error': e.message,
        }, status: e.status).change(headers: cors);
      } on FormatException {
        return _json({
          'error': 'Neplatný formát požiadavky.',
        }, status: 400).change(headers: cors);
      } on TypeError {
        return _json({
          'error': 'Neplatné údaje požiadavky.',
        }, status: 400).change(headers: cors);
      } on ArgumentError {
        return _json({
          'error': 'Neplatné údaje požiadavky.',
        }, status: 400).change(headers: cors);
      } catch (e) {
        stderr.writeln('API request failed (${e.runtimeType})');
        return _json({
          'error': 'Služba je dočasne nedostupná. Skús to znova.',
        }, status: 503).change(headers: cors);
      }
    }

    return (request) async {
      final watch = Stopwatch()..start();
      final response = await dispatch(request);
      watch.stop();
      runtime.observe(
        request.method,
        request.url.path,
        response.statusCode,
        watch.elapsedMicroseconds,
      );
      return response.change(headers: {'x-request-id': const Uuid().v4()});
    };
  }

  String _user(Request r) => auth.requireUser(r.headers['authorization']);
  Future<Response> _merchantMutation(
    Request r,
    Map<String, dynamic> Function(String, Map<String, dynamic>) action, {
    int status = 200,
  }) async {
    final user = _user(r), body = await _body(r);
    final result = merchants.mutate(
      user,
      '${r.method}:${r.url.path}',
      body,
      () => action(user, body),
    );
    return _json(result, status: status);
  }

  void _merchantRoutes(Router router) {
    router.get('/v1/merchant/workspace', (Request r) async {
      final user = _user(r);
      await _expire();
      return _json(
        config.production || r.url.queryParameters['paged'] == 'true'
            ? merchants.pagedWorkspace(user, r.url.queryParameters)
            : merchants.workspace(user),
      );
    });
    void post(
      String path,
      Map<String, dynamic> Function(String, Map<String, dynamic>) action, {
      int status = 200,
    }) {
      router.post(
        '/v1/merchant/$path',
        (Request r) => _merchantMutation(r, action, status: status),
      );
    }

    post('organizations', merchants.createOrganization, status: 201);
    post('stores', merchants.createStore, status: 201);
    post('products', merchants.createProduct, status: 201);
    post('stock/receive', merchants.receive, status: 201);
    router.get(
      '/v1/merchant/stock/operations',
      (Request r) => _json(
        merchants.warehouse(
          _user(r),
          r.url.queryParameters['storeId'] ?? '',
          beforeCounts: int.tryParse(
            r.url.queryParameters['beforeCounts'] ?? '',
          ),
          beforeTransfers: int.tryParse(
            r.url.queryParameters['beforeTransfers'] ?? '',
          ),
        ),
      ),
    );
    post('stock/counts', merchants.createCount, status: 201);
    router.get(
      '/v1/merchant/stock/counts/<id>',
      (Request r, String id) => _json(
        merchants.countDetail(
          _user(r),
          id,
          before: int.tryParse(r.url.queryParameters['after'] ?? ''),
          search: r.url.queryParameters['query'] ?? '',
        ),
      ),
    );
    router.post(
      '/v1/merchant/stock/counts/<id>',
      (Request r, String id) =>
          _merchantMutation(r, (u, b) => merchants.updateCount(u, id, b)),
    );
    post('stock/transfers', merchants.createTransfer, status: 201);
    router.get(
      '/v1/merchant/stock/transfers/<id>',
      (Request r, String id) => _json(merchants.transferDetail(_user(r), id)),
    );
    router.post(
      '/v1/merchant/stock/transfers/<id>',
      (Request r, String id) =>
          _merchantMutation(r, (u, b) => merchants.updateTransfer(u, id, b)),
    );
    router.post(
      '/v1/merchant/lots/<id>/adjust',
      (Request r, String id) =>
          _merchantMutation(r, (user, b) => merchants.adjust(user, id, b)),
    );
    router.post(
      '/v1/merchant/lots/<id>/quality',
      (Request r, String id) =>
          _merchantMutation(r, (user, b) => merchants.quality(user, id, b)),
    );
    post('offers', merchants.createOffer, status: 201);
    router.post(
      '/v1/merchant/offers/<id>/state',
      (Request r, String id) =>
          _merchantMutation(r, (user, b) => merchants.offerState(user, id, b)),
    );
    router.patch(
      '/v1/merchant/offers/<id>',
      (Request r, String id) =>
          _merchantMutation(r, (user, b) => merchants.editOffer(user, id, b)),
    );
    post('rules', (user, b) => merchants.saveRule(user, b), status: 201);
    router.patch(
      '/v1/merchant/rules/<id>',
      (Request r, String id) => _merchantMutation(
        r,
        (user, b) => merchants.saveRule(user, b, id: id),
      ),
    );
    router.post(
      '/v1/merchant/stores/<id>/automation',
      (Request r, String id) =>
          _merchantMutation(r, (user, b) => merchants.runRules(user, id)),
    );
    router.post(
      '/v1/merchant/stores/<id>/import',
      (Request r, String id) =>
          _merchantMutation(r, (user, b) => merchants.importCsv(user, id, b)),
    );
    post('integrations', merchants.createIntegration, status: 201);
    router.post(
      '/v1/merchant/integrations/<id>/revoke',
      (Request r, String id) => _merchantMutation(r, (user, b) {
        merchants.revokeIntegration(user, id);
        return {'ok': true};
      }),
    );
    post('members', (user, b) {
      merchants.setMember(user, b);
      return {'ok': true};
    });
    post('invites', merchants.invite, status: 201);
    post('invites/accept', merchants.acceptInvite);
    router.get(
      '/v1/merchant/access',
      (Request r) => _json(
        merchants.accessOverview(
          _user(r),
          r.url.queryParameters['organizationId'] ?? '',
        ),
      ),
    );
    router.post(
      '/v1/merchant/invites/<id>/revoke',
      (Request r, String id) => _merchantMutation(
        r,
        (user, body) => merchants.revokeInvite(user, id),
      ),
    );
    router.post('/v1/merchant/ownership', (Request r) async {
      final user = _user(r), body = await _body(r);
      await accounts.authorize(user, body, r.headers['authorization']!);
      return _json(
        merchants.mutate(
          user,
          r.url.path,
          body,
          () => merchants.transferOwnership(user, body),
        ),
      );
    });
    router.post(
      '/v1/merchant/stores/<store>/orders/<id>/collect',
      (Request r, String store, String id) => _merchantMutation(r, (user, b) {
        final code = stringField(b, 'pickupCode');
        final target = merchants.pickupTarget(user, store, id, code);
        collect(
          target['userId'] as String,
          id,
          code.trim().toUpperCase(),
          offerIds: (target['offerIds'] as List<String>).toSet(),
        );
        return {'ok': true};
      }),
    );
    router.post('/v1/merchant/stores/<store>/orders/<id>/cancel', (
      Request r,
      String store,
      String id,
    ) async {
      final user = _user(r),
          body = await _body(r),
          reason = stringField(body, 'reason', max: 300);
      if (reason.length < 3) throw const ApiFailure(400, 'Uveď dôvod storna.');
      final customer = merchants.cancellationTarget(user, store, id);
      await cancel(customer, id, expired: true);
      merchants.auditCancellation(user, store, id, reason);
      return _json({'ok': true});
    });
    router.get(
      '/v1/integrations/changes',
      (Request r) => _json(
        merchants.changes(
          r.headers['authorization'],
          after: int.tryParse(r.url.queryParameters['after'] ?? ''),
        ),
      ),
    );
    router.post(
      '/v1/integrations/changes/ack',
      (Request r) async => _json(
        merchants.acknowledge(r.headers['authorization'], await _body(r)),
      ),
    );
    router.get(
      '/v1/integrations/stock',
      (Request r) => _json(
        merchants.integrationStock(
          r.headers['authorization'],
          after: int.tryParse(r.url.queryParameters['after'] ?? ''),
        ),
      ),
    );
    router.post(
      '/v1/integrations/stock',
      (Request r) async => _json(
        merchants.integrationEvent(r.headers['authorization'], await _body(r)),
      ),
    );
  }

  String _ip(Request r) =>
      (r.context['shelf.io.connection_info'] as HttpConnectionInfo?)
          ?.remoteAddress
          .address ??
      'local';
  Response _json(Object data, {int status = 200}) => Response(
    status,
    body: jsonEncode(data),
    headers: {
      'content-type': 'application/json; charset=utf-8',
      'cache-control': 'private, no-store',
    },
  );
  Future<String> _rawBody(Request request) async {
    final bytes = <int>[];
    await for (final chunk in request.read()) {
      bytes.addAll(chunk);
      if (bytes.length > 65536) {
        throw const ApiFailure(413, 'Požiadavka je príliš veľká.');
      }
    }
    return utf8.decode(bytes);
  }

  Future<Map<String, dynamic>> _body(Request r) async =>
      Map<String, dynamic>.from(jsonDecode(await _rawBody(r)) as Map);
  void _seed() {
    if (!config.seedDemo) return;
    final zone = tz.getLocation('Europe/Bratislava');
    final date = tz.TZDateTime.from(clock(), zone);
    final day = '${date.year}-${date.month}-${date.day}';
    if (database.db.select(
      'SELECT id FROM offers WHERE fixture_day=? LIMIT 1',
      [day],
    ).isNotEmpty) {
      return;
    }
    database.transaction(() {
      database.db.execute('DELETE FROM offers WHERE fixture_day IS NOT NULL');
      for (final offer in seedCatalog(date)) {
        final json = offer.toJson();
        for (final entry in {
          'pickupStart': offer.pickupStart,
          'pickupEnd': offer.pickupEnd,
        }.entries) {
          final d = entry.value;
          json[entry.key] = tz.TZDateTime(
            zone,
            d.year,
            d.month,
            d.day,
            d.hour,
            d.minute,
          ).toUtc().toIso8601String();
        }
        database.db.execute(
          'INSERT OR IGNORE INTO offers(id,payload,fixture_day) VALUES(?,?,?)',
          [offer.id, jsonEncode(json), day],
        );
      }
    });
  }

  List<FoodOffer> catalog() => database.db
      .select('SELECT payload FROM offers')
      .where(
        (row) => merchants.visible(
          database.decode(row['payload'] as String)['id'] as String,
        ),
      )
      .map((row) {
        final json = database.decode(row['payload'] as String);
        final offer = FoodOffer.fromJson(json);
        json['stock'] = _remaining(offer);
        final ratings = database.db.select(
          "SELECT AVG(rating) AS average,COUNT(*) AS count FROM reviews WHERE offer_id=? AND moderation='visible'",
          [offer.id],
        ).first;
        if (!config.seedDemo || (ratings['count'] as int) > 0) {
          json['rating'] = ((ratings['average'] as num?) ?? 0).toDouble();
          json['reviews'] = ratings['count'];
        }
        return FoodOffer.fromJson(json);
      })
      .toList();
  FoodOffer _offer(String id) {
    final rows = database.db.select('SELECT payload FROM offers WHERE id=?', [
      id,
    ]);
    if (rows.isEmpty) throw const ApiFailure(404, 'Ponuka sa nenašla.');
    return FoodOffer.fromJson(database.decode(rows.first['payload'] as String));
  }

  int _remaining(FoodOffer offer) {
    if (!merchants.visible(offer.id)) return 0;
    if (merchants.managed(offer.id) != null) {
      return merchants.remaining(
        offer.id,
        (offer.stock - merchants.committed(offer.id)).clamp(0, offer.stock),
      );
    }
    var reserved = 0;
    for (final row in database.db.select(
      "SELECT payload FROM orders WHERE status IN ('awaitingPayment','reserved','collected','cancelling')",
    )) {
      for (final item in RescueOrder.fromJson(
        database.decode(row['payload'] as String),
      ).items) {
        if (item.offerId == offer.id &&
            item.pickupStart.isAtSameMomentAs(offer.pickupStart)) {
          reserved += item.remainingQuantity;
        }
      }
    }
    return merchants.remaining(
      offer.id,
      (offer.stock - reserved).clamp(0, offer.stock),
    );
  }

  List<RescueOrder> _orders(String user) => database.db
      .select(
        'SELECT payload FROM orders WHERE user_id=? ORDER BY rowid DESC',
        [user],
      )
      .map((r) => RescueOrder.fromJson(database.decode(r['payload'] as String)))
      .toList();
  RescueOrder _ownedOrder(String user, String id) {
    final rows = database.db.select(
      'SELECT payload FROM orders WHERE id=? AND user_id=?',
      [id, user],
    );
    if (rows.isEmpty) throw const ApiFailure(404, 'Objednávka sa nenašla.');
    return RescueOrder.fromJson(
      database.decode(rows.first['payload'] as String),
    );
  }

  Map<String, dynamic> profile(String user) {
    final row = auth.user(user);
    final preferences = database.decode(row['profile'] as String);
    return {
      ...preferences,
      'id': row['id'],
      'name': row['name'],
      'email': row['email'],
      'emailVerified': row['email_verified'] == 1,
      'hasPassword': row['password_hash'] != null,
      'platformRole': platform.role(user),
      'credit': row['credit'],
      'memberUntil': row['member_until'],
      'trialUsed': row['trial_used'] == 1,
      'clubRenewalCancelled': row['subscription_cancelled'] == 1,
      'orders': _orders(user).map((o) => o.toJson()).toList(),
    };
  }

  void _updateProfile(String user, Map<String, dynamic> body) {
    final current = auth.user(user);
    final profile = database.decode(current['profile'] as String);
    if (body['invoice'] != null) {
      final invoice = InvoiceDetails.fromJson(
        Map<String, dynamic>.from(body['invoice'] as Map),
      );
      if (!invoice.isValid) {
        throw const ApiFailure(400, 'Skontroluj fakturačné údaje.');
      }
      profile['invoice'] = invoice.toJson();
    }
    if (body['favorites'] != null) {
      final favorites = (body['favorites'] as List).cast<String>();
      if (favorites.length > 500 || favorites.any((s) => s.length > 100)) {
        throw const ApiFailure(400, 'Príliš veľa obľúbených.');
      }
      profile['favorites'] = favorites.toSet().toList();
    }
    for (final key in [
      'favoriteAlerts',
      'supportAlerts',
      'pickupReminders',
      'marketing',
      'analytics',
      'emailNotifications',
    ]) {
      if (body[key] != null) {
        if (body[key] is! bool) throw const ApiFailure(400, 'Neplatná voľba.');
        profile[key] = body[key];
      }
    }
    if (body['name'] != null) {
      final name = stringField(body, 'name');
      if (name.length < 2) throw const ApiFailure(400, 'Zadaj platné meno.');
      database.db.execute('UPDATE users SET name=? WHERE id=?', [name, user]);
    }
    database.db.execute('UPDATE users SET profile=? WHERE id=?', [
      jsonEncode(profile),
      user,
    ]);
  }

  Future<RescueOrder> reserve(String user, Map<String, dynamic> body) async {
    if (config.paymentMode == 'disabled') {
      throw const ApiFailure(503, 'Rezervácie spustíme po aktivácii platieb.');
    }
    await _expire();
    final key = stringField(body, 'idempotencyKey', max: 100);
    if (key.length < 16) {
      throw const ApiFailure(400, 'Chýba identifikátor nákupu.');
    }
    final requestHash = hashToken(jsonEncode(body));
    final flowName = body['paymentFlow'] ?? 'hosted';
    if (!{'hosted', 'native'}.contains(flowName)) {
      throw const ApiFailure(400, 'Neplatný spôsob otvorenia platby.');
    }
    final flow = PaymentFlow.values.byName(flowName as String);
    if (flow == PaymentFlow.native &&
        (!config.nativePaymentsEnabled || payments is! StripePaymentGateway)) {
      throw const ApiFailure(
        503,
        'Platba v aplikácii ešte nie je nakonfigurovaná.',
      );
    }
    final previous = database.db.select(
      'SELECT id,request_hash,payload,payment_session FROM orders WHERE user_id=? AND idempotency=?',
      [user, key],
    );
    if (previous.isNotEmpty) {
      if (previous.first['request_hash'] != requestHash) {
        throw const ApiFailure(
          409,
          'Tento identifikátor už patrí inému nákupu.',
        );
      }
      final id = previous.first['id'] as String;
      if (_working.contains(id)) {
        throw const ApiFailure(409, 'Nákup sa ešte pripravuje. Skús to znova.');
      }
      final previousOrder = RescueOrder.fromJson(
        database.decode(previous.first['payload'] as String),
      );
      if (previous.first['payment_session'] == null &&
          previousOrder.status == OrderStatus.awaitingPayment) {
        return _preparePayment(previousOrder, user);
      }
      return previousOrder;
    }
    final order = database.transaction(() {
      final row = auth.user(user);
      legal.requireAccepted(user);
      if (config.production && row['email_verified'] != 1) {
        throw const ApiFailure(
          403,
          'Pred rezerváciou over svoj e-mail v nastaveniach účtu.',
        );
      }
      final member =
          DateTime.tryParse(
            row['member_until'] as String? ?? '',
          )?.isAfter(clock()) ??
          false;
      final invoice = InvoiceDetails.fromJson(
        Map<String, dynamic>.from(body['invoice'] as Map),
      );
      if (!invoice.isValid) {
        throw const ApiFailure(400, 'Vyplň platné fakturačné údaje.');
      }
      final entries = body['items'];
      if (entries is! List || entries.isEmpty || entries.length > 30) {
        throw const ApiFailure(400, 'Košík je prázdny alebo príliš veľký.');
      }
      final seen = <String>{};
      final items = <OrderItem>[];
      for (final raw in entries) {
        final entry = Map<String, dynamic>.from(raw as Map);
        final id = stringField(entry, 'offerId', max: 100);
        final quantity = entry['quantity'];
        if (quantity is! int ||
            quantity < 1 ||
            quantity > 50 ||
            !seen.add(id)) {
          throw const ApiFailure(400, 'Neplatné množstvo v košíku.');
        }
        final offer = _offer(id);
        if (!offer.pickupEnd.isAfter(clock()) || quantity > _remaining(offer)) {
          throw ApiFailure(
            409,
            'Dostupnosť balíčka ${offer.title} sa zmenila.',
          );
        }
        if (offer.type == OfferType.club && !member) {
          throw const ApiFailure(
            403,
            'Táto ponuka je dostupná iba členom Klubu.',
          );
        }
        items.add(
          OrderItem(
            offerId: id,
            store: offer.store,
            title: offer.title,
            image: offer.image,
            quantity: quantity,
            unitPrice: offer.price,
            pickupStart: offer.pickupStart,
            pickupEnd: offer.pickupEnd,
            address: offer.address,
            category: offer.category,
          ),
        );
      }
      CheckoutQuote quote;
      try {
        quote = CheckoutQuote.calculate(
          subtotal: items.fold(0, (n, i) => n + i.total),
          coupon: body['coupon'] as String? ?? '',
          credit: row['credit'] as int,
          useCredit: body['useCredit'] == true,
          clubMember: member,
          minimumExternalPayment: config.paymentMode == 'stripe' ? 50 : 0,
        );
      } on ArgumentError {
        throw const ApiFailure(400, 'Kupón nie je platný.');
      }
      billing.validateCheckout(items, serviceFee: quote.serviceFee);
      if (config.paymentMode == 'stripe' &&
          quote.total > 0 &&
          quote.total < 50) {
        throw const ApiFailure(
          400,
          'Minimálna platba kartou je 0,50 €. Pridaj balíček alebo uhraď celú sumu kreditom.',
        );
      }
      final currentProfile = database.decode(row['profile'] as String)
        ..['invoice'] = invoice.toJson();
      database.db.execute('UPDATE users SET profile=? WHERE id=?', [
        jsonEncode(currentProfile),
        user,
      ]);
      final order = RescueOrder(
        id: const Uuid().v4(),
        createdAt: clock().toUtc(),
        items: items,
        total: quote.total,
        discount: quote.discount,
        serviceFee: quote.serviceFee,
        creditUsed: quote.creditUsed,
        cashback: quote.cashback,
        invoice: invoice,
        paymentFlow: flow,
        status: quote.total == 0
            ? OrderStatus.reserved
            : OrderStatus.awaitingPayment,
        pickupCode: randomSecret(6).toUpperCase(),
      );
      database.db.execute(
        'INSERT INTO orders(id,user_id,idempotency,request_hash,payload,status,expires) VALUES(?,?,?,?,?,?,?)',
        [
          order.id,
          user,
          key,
          requestHash,
          jsonEncode(order.toJson()),
          order.status.name,
          clock().add(const Duration(minutes: 30)).toUtc().toIso8601String(),
        ],
      );
      database.db.execute('UPDATE users SET credit=credit-? WHERE id=?', [
        quote.creditUsed,
        user,
      ]);
      merchants.hold(order);
      finance.capture(order);
      if (quote.creditUsed > 0) {
        _ledger(user, order.id, 'spend', -quote.creditUsed);
      }
      return order;
    });
    if (order.total == 0) {
      finance.syncOrder(order);
      return order;
    }
    return _preparePayment(order, user);
  }

  Future<RescueOrder> _preparePayment(RescueOrder order, String user) async {
    _working.add(order.id);
    try {
      final checkout = await payments.create(
        order,
        auth.user(user)['email'] as String,
      );
      _validateNativePayment(checkout, order);
      final json = order.toJson()
        ..['paymentUrl'] = checkout.url
        ..['status'] = checkout.paid
            ? OrderStatus.reserved.name
            : OrderStatus.awaitingPayment.name;
      final updated = RescueOrder.fromJson(json);
      database.db.execute(
        'UPDATE orders SET payload=?,status=?,payment_session=?,payment_intent=? WHERE id=?',
        [
          jsonEncode(updated.toJson()),
          updated.status.name,
          checkout.sessionId,
          checkout.paymentIntent,
          order.id,
        ],
      );
      finance.syncOrder(updated);
      return updated;
    } catch (_) {
      support.systemTicket(
        user,
        order.id,
        TicketCategory.payment,
        'payment:${order.id}',
        'Overenie platby',
        'Platobná brána zatiaľ nepotvrdila vytvorenie platby. Objednávka je uložená; stav treba preveriť.',
      );
      // Preserve a durable hold: a request timeout may still have created a Stripe session.
      // Retrying the same key reuses Stripe's order-id idempotency key.
      throw const ApiFailure(
        503,
        'Platba sa ešte pripravuje. Košík zostal zachovaný; skús znova.',
      );
    } finally {
      _working.remove(order.id);
    }
  }

  void _ledger(
    String user,
    String order,
    String kind,
    int amount,
  ) => database.db.execute(
    'INSERT OR IGNORE INTO ledger(id,user_id,order_id,kind,amount,created_at) VALUES(?,?,?,?,?,?)',
    [
      const Uuid().v4(),
      user,
      order,
      kind,
      amount,
      clock().toUtc().toIso8601String(),
    ],
  );
  RescueOrder collect(
    String user,
    String id,
    String pickupCode, {
    String? offerId,
    Set<String>? offerIds,
  }) => database.transaction(() {
    final order = _ownedOrder(user, id);
    if (_working.contains(id) ||
        finance.rows(
          "SELECT id FROM finance_refunds WHERE order_id=? AND status='processing'",
          [id],
        ).isNotEmpty) {
      throw const ApiFailure(409, 'Objednávka sa práve finančne spracúva.');
    }
    if (order.status == OrderStatus.collected) return order;
    final row = database.db.select('SELECT status FROM orders WHERE id=?', [
      id,
    ]).first;
    if (row['status'] != 'reserved' || order.status != OrderStatus.reserved) {
      throw const ApiFailure(409, 'Túto rezerváciu teraz nemožno vyzdvihnúť.');
    }
    if (order.pickupCode != pickupCode) {
      throw const ApiFailure(403, 'Kód vyzdvihnutia nie je správny.');
    }
    if (offerId != null && !order.items.any((i) => i.offerId == offerId)) {
      throw const ApiFailure(404, 'Balíček sa nenašiel.');
    }
    final selected = order.items
        .where(
          (i) =>
              !i.collected &&
              !i.refunded &&
              (offerId == null || i.offerId == offerId) &&
              (offerIds == null || offerIds.contains(i.offerId)),
        )
        .toList();
    if (selected.isEmpty) return order;
    if (config.production &&
        selected.any(
          (i) =>
              clock().isBefore(i.pickupStart) || clock().isAfter(i.pickupEnd),
        )) {
      throw const ApiFailure(
        409,
        'Vyzdvihnutie potvrď v čase uvedenom na objednávke.',
      );
    }
    final items = order.items
        .map(
          (i) => selected.any((s) => s.offerId == i.offerId)
              ? i.withCollected()
              : i,
        )
        .toList();
    final complete = items.every((i) => i.collected || i.refunded);
    final updated = order.withStatus(
      complete ? OrderStatus.collected : OrderStatus.reserved,
      updatedItems: items,
    );
    merchants.consume(order, selected);
    _writeOrder(updated);
    finance.syncOrder(updated);
    if (complete && order.cashback > 0) {
      database.db.execute('UPDATE users SET credit=credit+? WHERE id=?', [
        order.cashback,
        user,
      ]);
      _ledger(user, id, 'cashback', order.cashback);
    }
    return updated;
  });
  Future<RescueOrder> cancel(
    String user,
    String id, {
    bool expired = false,
  }) async {
    final order = _ownedOrder(user, id);
    if (order.status == OrderStatus.cancelled) return order;
    finance.ensureCanCancel(id);
    if (order.items.any((i) => i.collected)) {
      throw const ApiFailure(
        409,
        'Čiastočne vyzdvihnutú objednávku už nemožno zrušiť naraz.',
      );
    }
    final row = database.db.select('SELECT * FROM orders WHERE id=?', [
      id,
    ]).first;
    if (!{'reserved', 'awaitingPayment'}.contains(row['status']) ||
        _working.contains(id)) {
      throw const ApiFailure(409, 'Túto objednávku už nemožno zrušiť.');
    }
    if (config.production &&
        !expired &&
        order.items.any((i) => !clock().isBefore(i.pickupStart))) {
      throw const ApiFailure(
        409,
        'Rezerváciu možno zrušiť pred začiatkom vyzdvihnutia.',
      );
    }
    _working.add(id);
    database.db.execute("UPDATE orders SET status='cancelling' WHERE id=?", [
      id,
    ]);
    try {
      if (row['payment_session'] != null) {
        await payments.cancel(
          row['payment_session'] as String,
          row['payment_intent'] as String?,
        );
      }
      final cancelled = database.transaction(() {
        final updated = order.withStatus(OrderStatus.cancelled);
        merchants.release(order);
        _writeOrder(updated);
        finance.syncOrder(updated);
        if (order.creditUsed > 0) {
          database.db.execute('UPDATE users SET credit=credit+? WHERE id=?', [
            order.creditUsed,
            user,
          ]);
          _ledger(user, id, 'return', order.creditUsed);
        }
        return updated;
      });
      try {
        for (final item in cancelled.items) {
          _queueStockAlert(_offer(item.offerId));
        }
      } catch (_) {
        // A notification queue failure must not roll back a completed refund.
        stderr.writeln('Stock alert queue unavailable after cancellation.');
      }
      return cancelled;
    } catch (_) {
      database.db.execute('UPDATE orders SET status=? WHERE id=?', [
        order.status.name,
        id,
      ]);
      throw const ApiFailure(
        503,
        'Zrušenie alebo vrátenie platby sa nepodarilo. Skús to znova.',
      );
    } finally {
      _working.remove(id);
    }
  }

  void _writeOrder(RescueOrder order) {
    database.db.execute('UPDATE orders SET payload=?,status=? WHERE id=?', [
      jsonEncode(order.toJson()),
      order.status.name,
      order.id,
    ]);
    finance.syncOrder(order);
    billing.sync(order);
    final signature =
        '${order.status.name}:${order.items.map((i) => '${i.offerId}:${i.collected}:${i.refundCount}').join(',')}:${order.refundedAmount}';
    final owner =
        database.db.select('SELECT user_id FROM orders WHERE id=?', [
              order.id,
            ]).first['user_id']
            as String;
    mail.notice(
      owner,
      'Save Food · Stav rezervácie sa zmenil',
      'Rezervácia ${order.id}\nStav: ${switch (order.status) {
        OrderStatus.awaitingPayment => 'Čaká na platbu',
        OrderStatus.reserved => 'Rezervované',
        OrderStatus.collected => 'Prevzaté',
        OrderStatus.cancelled => 'Zrušené',
      }}\n${order.items.map((i) => '${i.title}: ${i.remainingQuantity} ks${i.refundCount > 0 ? ' · vrátené ${i.refundCount} ks' : ''}').join('\n')}\nPodrobnosti a doklady nájdeš v aplikácii.',
      dedupe: 'order:${order.id}:$signature',
    );
  }

  void _validateNativePayment(PaymentCheckout payment, RescueOrder order) {
    if (order.paymentFlow == PaymentFlow.native &&
        (payment.amount != order.total ||
            payment.currency != 'eur' ||
            payment.referenceId != order.id)) {
      throw const ApiFailure(
        503,
        'Platba sa nezhoduje s rezerváciou. Over stav znova.',
      );
    }
  }

  Future<void> _refreshPayment(String id) async {
    final rows = database.db.select('SELECT * FROM orders WHERE id=?', [id]);
    if (rows.isEmpty) return;
    final row = rows.first;
    if (row['status'] != 'awaitingPayment' ||
        row['payment_session'] == null ||
        _working.contains(id)) {
      return;
    }
    _working.add(id);
    try {
      final payment = await payments.retrieve(row['payment_session'] as String);
      _validateNativePayment(
        payment,
        RescueOrder.fromJson(database.decode(row['payload'] as String)),
      );
      if (payment.paid) {
        _writeOrder(
          RescueOrder.fromJson(
            database.decode(row['payload'] as String),
          ).withStatus(OrderStatus.reserved),
        );
        database.db.execute('UPDATE orders SET payment_intent=? WHERE id=?', [
          payment.paymentIntent,
          id,
        ]);
      }
    } finally {
      _working.remove(id);
    }
  }

  Future<void> _expire() async {
    for (final row in database.db.select(
      "SELECT id,user_id FROM orders WHERE status='awaitingPayment' AND expires<?",
      [clock().toUtc().toIso8601String()],
    )) {
      final id = row['id'] as String;
      if (_working.contains(id)) continue;
      await _refreshPayment(id);
      final order = _ownedOrder(row['user_id'] as String, id);
      if (order.status == OrderStatus.awaitingPayment) {
        await cancel(row['user_id'] as String, id, expired: true);
      }
    }
  }

  void _activateTrial(String user, String code) {
    final normalized = code.trim().toUpperCase();
    if (normalized.isNotEmpty && normalized != 'KLUB30') {
      throw const ApiFailure(400, 'Klubový kupón nie je platný.');
    }
    database.transaction(() {
      final row = auth.user(user);
      if (row['trial_used'] == 1) {
        throw const ApiFailure(409, 'Skúšobné členstvo už bolo využité.');
      }
      database.db
          .execute('UPDATE users SET trial_used=1,member_until=? WHERE id=?', [
            clock()
                .add(Duration(days: normalized.isEmpty ? 14 : 30))
                .toUtc()
                .toIso8601String(),
            user,
          ]);
    });
  }

  Future<Map<String, dynamic>?> _membershipPlan() async {
    if (payments is! StripePaymentGateway || config.stripeClubPriceId.isEmpty) {
      return null;
    }
    if (_clubPlanLoaded != null &&
        clock().difference(_clubPlanLoaded!) < const Duration(minutes: 10)) {
      return _clubPlan;
    }
    final price = await (payments as StripePaymentGateway).membershipPrice();
    if (price['active'] != true ||
        price['currency'] != 'eur' ||
        price['unit_amount'] is! int ||
        price['recurring'] is! Map) {
      throw const ApiFailure(
        503,
        'Klubový plán nie je správne nakonfigurovaný.',
      );
    }
    _clubPlan = {
      'amount': price['unit_amount'],
      'interval': (price['recurring'] as Map)['interval'],
      'intervalCount': (price['recurring'] as Map)['interval_count'],
    };
    _clubPlanLoaded = clock();
    return _clubPlan;
  }

  Future<Map<String, dynamic>> _membershipCheckout(String user) async {
    if (await _membershipPlan() == null) {
      throw const ApiFailure(503, 'Platené členstvo ešte nie je k dispozícii.');
    }
    final profile = auth.user(user);
    if (DateTime.tryParse(
          profile['member_until'] as String? ?? '',
        )?.isAfter(clock()) ??
        false) {
      throw const ApiFailure(409, 'Členstvo už máš aktívne.');
    }
    final previous = database.db.select(
      'SELECT url FROM membership_checkouts WHERE user_id=? AND expires>?',
      [user, clock().toUtc().toIso8601String()],
    );
    if (previous.isNotEmpty) return {'url': previous.first['url']};
    final key = 'membership:$user';
    if (!_working.add(key)) {
      throw const ApiFailure(409, 'Členstvo sa pripravuje. Skús znova.');
    }
    try {
      final session = await (payments as StripePaymentGateway).createMembership(
        user,
        profile['email'] as String,
      );
      final url = session['url'] as String;
      database.db.execute(
        'INSERT INTO membership_checkouts(user_id,session_id,url,expires) VALUES(?,?,?,?) ON CONFLICT(user_id) DO UPDATE SET session_id=excluded.session_id,url=excluded.url,expires=excluded.expires',
        [
          user,
          session['id'],
          url,
          clock().add(const Duration(minutes: 30)).toUtc().toIso8601String(),
        ],
      );
      return {'url': url};
    } finally {
      _working.remove(key);
    }
  }

  void _applySubscription(Map<String, dynamic> subscription) {
    final user = (subscription['metadata'] as Map?)?['user_id'] as String?;
    if (user == null) return;
    final rows = database.db.select(
      'SELECT subscription_id FROM users WHERE id=?',
      [user],
    );
    if (rows.isEmpty || rows.first['subscription_id'] != subscription['id']) {
      return;
    }
    final items = (subscription['items'] as Map?)?['data'] as List? ?? [];
    final end =
        subscription['current_period_end'] ??
        (items.isEmpty ? null : (items.first as Map)['current_period_end']);
    final active = {'active', 'trialing'}.contains(subscription['status']);
    final until = active && end is num
        ? DateTime.fromMillisecondsSinceEpoch(
            end.toInt() * 1000,
            isUtc: true,
          ).toIso8601String()
        : null;
    database.db.execute(
      'UPDATE users SET member_until=?,subscription_cancelled=? WHERE id=?',
      [until, subscription['cancel_at_period_end'] == true ? 1 : 0, user],
    );
  }

  void _review(String user, String id, Map<String, dynamic> body) =>
      reviews.save(user, id, body);

  void _admin(Request r) {
    if (config.adminToken.length < 32 ||
        !constantTimeEqual(
          utf8.encode(r.headers['authorization'] ?? ''),
          utf8.encode('Bearer ${config.adminToken}'),
        )) {
      throw const ApiFailure(403, 'Táto akcia je určená správcovi.');
    }
  }

  void _putOffer(Map<String, dynamic> body) {
    final offer = FoodOffer.fromJson(body);
    if (merchants.managed(offer.id) != null) {
      throw const ApiFailure(409, 'Skladovú ponuku uprav cez portál predajcu.');
    }
    if (offer.id.isEmpty ||
        offer.id.length > 100 ||
        offer.price < 1 ||
        offer.originalPrice < offer.price ||
        offer.stock < 0 ||
        offer.stock > 1000 ||
        !offer.pickupEnd.isAfter(offer.pickupStart) ||
        offer.store.isEmpty) {
      throw const ApiFailure(400, 'Neplatné údaje ponuky.');
    }
    database.db.execute(
      'INSERT INTO offers(id,payload) VALUES(?,?) ON CONFLICT(id) DO UPDATE SET payload=excluded.payload,fixture_day=NULL',
      [offer.id, jsonEncode(offer.toJson())],
    );
    _queueStockAlert(offer);
  }

  void _queueStockAlert(FoodOffer offer) {
    if (!push.configured ||
        _remaining(offer) <= 0 ||
        !offer.pickupEnd.isAfter(clock())) {
      return;
    }
    final pickup = offer.pickupStart.toUtc().toIso8601String();
    for (final row in database.db.select(
      'SELECT d.token,d.user_id,u.profile FROM devices d JOIN users u ON u.id=d.user_id JOIN sessions s ON s.token_hash=d.session_hash WHERE s.expires>?',
      [clock().toUtc().toIso8601String()],
    )) {
      final preferences = database.decode(row['profile'] as String);
      if (preferences['favoriteAlerts'] != true ||
          !(preferences['favorites'] as List? ?? []).contains(offer.id)) {
        continue;
      }
      database.db.execute(
        'INSERT OR IGNORE INTO push_outbox(id,token,user_id,offer_id,pickup,title,body) VALUES(?,?,?,?,?,?,?)',
        [
          const Uuid().v4(),
          row['token'],
          row['user_id'],
          offer.id,
          pickup,
          '${offer.store} má nové balíčky',
          '${offer.title} · ${euro(offer.price)}',
        ],
      );
    }
  }

  Future<void> drainPush() async {
    if (_draining || !push.configured) return;
    _draining = true;
    try {
      await support.drainSupportPush(push);
      final rows = database.db.select(
        'SELECT * FROM push_outbox WHERE processed=0 AND attempts<5 LIMIT 50',
      );
      for (final row in rows) {
        final devices = database.db.select(
          'SELECT u.profile FROM devices d JOIN users u ON u.id=d.user_id JOIN sessions s ON s.token_hash=d.session_hash WHERE d.token=? AND d.user_id=? AND s.expires>?',
          [row['token'], row['user_id'], clock().toUtc().toIso8601String()],
        );
        final preferences = devices.isEmpty
            ? <String, dynamic>{}
            : database.decode(devices.first['profile'] as String);
        final offers = catalog().where(
          (o) =>
              o.id == row['offer_id'] &&
              o.pickupStart.toUtc().toIso8601String() == row['pickup'] &&
              o.stock > 0 &&
              o.pickupEnd.isAfter(clock()),
        );
        if (preferences['favoriteAlerts'] != true ||
            !(preferences['favorites'] as List? ?? []).contains(
              row['offer_id'],
            ) ||
            offers.isEmpty) {
          database.db.execute('UPDATE push_outbox SET processed=1 WHERE id=?', [
            row['id'],
          ]);
          continue;
        }
        try {
          final valid = await push.send(
            row['token'] as String,
            row['title'] as String,
            row['body'] as String,
            {'offerId': row['offer_id'] as String},
          );
          database.db.execute('UPDATE push_outbox SET processed=1 WHERE id=?', [
            row['id'],
          ]);
          if (!valid) {
            database.db.execute('DELETE FROM devices WHERE token=?', [
              row['token'],
            ]);
          }
        } catch (_) {
          database.db.execute(
            'UPDATE push_outbox SET attempts=attempts+1 WHERE id=?',
            [row['id']],
          );
        }
      }
    } finally {
      _draining = false;
    }
  }

  Future<Response> _oauthCallback(Request r, String provider) async {
    final params = r.method == 'POST'
        ? Uri.splitQueryString(await _rawBody(r))
        : r.url.queryParameters;
    await auth.finishOAuth(provider, params);
    return Response.ok(
      _returnPage,
      headers: {
        'content-type': 'text/html; charset=utf-8',
        'content-security-policy':
            "default-src 'none'; style-src 'unsafe-inline'",
      },
    );
  }

  Future<Response> _webhook(Request r) async {
    if (config.paymentMode != 'stripe') {
      throw const ApiFailure(404, 'Platobná brána nie je aktívna.');
    }
    final raw = await _rawBody(r);
    if (!verifyStripeSignature(
      raw,
      r.headers['stripe-signature'] ?? '',
      config.stripeWebhookSecret,
      clock(),
    )) {
      throw const ApiFailure(400, 'Podpis webhooku nie je platný.');
    }
    final event = Map<String, dynamic>.from(jsonDecode(raw) as Map);
    final eventId = event['id'] as String;
    if (database.db.select('SELECT id FROM payment_events WHERE id=?', [
      eventId,
    ]).isNotEmpty) {
      return _json({'ok': true});
    }
    final payload = Map<String, dynamic>.from(
      (event['data'] as Map)['object'] as Map,
    );
    if (event['type'] == 'payment_intent.succeeded' ||
        event['type'] == 'payment_intent.canceled') {
      final id = (payload['metadata'] as Map?)?['order_id'] as String?;
      if (id != null) {
        final rows = database.db.select(
          'SELECT user_id,payment_session FROM orders WHERE id=?',
          [id],
        );
        if (rows.isNotEmpty && rows.first['payment_session'] == payload['id']) {
          if (event['type'] == 'payment_intent.succeeded') {
            await _refreshPayment(id);
          } else {
            await cancel(rows.first['user_id'] as String, id, expired: true);
          }
        }
      }
    }
    if (event['type'] == 'checkout.session.completed' ||
        event['type'] == 'checkout.session.async_payment_succeeded') {
      if (payload['mode'] == 'subscription' &&
          payments is StripePaymentGateway) {
        final user = (payload['metadata'] as Map?)?['user_id'] as String?;
        final subscriptionId = payload['subscription'] as String?;
        if (user != null && subscriptionId != null) {
          final checkout = database.db.select(
            'SELECT session_id FROM membership_checkouts WHERE user_id=?',
            [user],
          );
          if (checkout.isNotEmpty &&
              checkout.first['session_id'] == payload['id']) {
            final subscription = await (payments as StripePaymentGateway)
                .subscription(subscriptionId);
            database.db.execute(
              'UPDATE users SET subscription_id=? WHERE id=?',
              [subscriptionId, user],
            );
            _applySubscription(subscription);
          }
        }
      }
      final id = payload['client_reference_id'] as String?;
      if (id != null) {
        final rows = database.db.select(
          'SELECT id,payment_session FROM orders WHERE id=?',
          [id],
        );
        if (rows.isNotEmpty && rows.first['payment_session'] == payload['id']) {
          await _refreshPayment(id);
        }
      }
    }
    if (event['type'] == 'charge.refunded' ||
        event['type'] == 'charge.dispute.created') {
      final intent = payload['payment_intent'] as String?;
      if (intent != null) {
        for (final row in finance.rows(
          'SELECT id,user_id,status FROM orders WHERE payment_intent=? OR payment_session=?',
          [intent, intent],
        )) {
          final id = row['id'] as String;
          if (event['type'] == 'charge.dispute.created') {
            await finance.reverseDisputed(id);
          } else {
            final expected =
                finance.one(
                      'SELECT COALESCE(SUM(external),0) n FROM finance_refunds WHERE order_id=?',
                      [id],
                    )['n']
                    as int;
            if ((payload['amount_refunded'] as int? ?? 0) <= expected ||
                {'cancelled', 'cancelling'}.contains(row['status'])) {
              continue;
            }
            finance.hold(
              id,
              'Stripe eviduje refundáciu, ktorá čaká na zosúladenie.',
            );
          }
          support.systemTicket(
            row['user_id'] as String,
            id,
            TicketCategory.payment,
            'stripe-review:$id',
            'Preverenie platby',
            'Stripe zaznamenal finančnú udalosť. Podpora preverí jej priradenie k objednávke.',
          );
        }
      }
    }
    if (event['type'] == 'customer.subscription.updated' ||
        event['type'] == 'customer.subscription.deleted') {
      _applySubscription(payload);
    }
    database.db.execute(
      'INSERT OR IGNORE INTO payment_events(id,received_at) VALUES(?,?)',
      [eventId, clock().toUtc().toIso8601String()],
    );
    return _json({'ok': true});
  }

  void close() {
    _merchantTimer?.cancel();
    _pushTimer?.cancel();
    finance.gateway.close();
    push.close();
    places.close();
    auth.client.close();
    if (mail.gateway is ResendMailGateway) {
      (mail.gateway as ResendMailGateway).client.close();
    }
    if (payments is StripePaymentGateway) {
      (payments as StripePaymentGateway).client.close();
    }
    database.close();
  }

  Future<void> prepareShowcasePresentation() async {
    if (config.demoShowcase) {
      await _seedWarehousePresentation();
      await _prepareCompletionDemo();
    }
  }
}

const _returnPage =
    '''<!doctype html><html lang="sk"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Save Food</title><style>body{background:#101723;color:#f3f6fc;font:17px -apple-system,system-ui,sans-serif;display:grid;place-items:center;min-height:90vh;margin:24px}main{max-width:430px}b{color:#79aaff;font-size:28px}h1{letter-spacing:-1px}p{line-height:1.6;color:#a8b5cc}</style><main><b>Save Food</b><h1>Vráť sa k niečomu dobrému.</h1><p>Môžeš zavrieť toto okno a vrátiť sa do aplikácie. Prihlásenie alebo stav platby sa bezpečne overí na serveri.</p></main></html>''';

import 'dart:convert';
import 'package:marketplace_domain/marketplace_domain.dart';
import 'package:marketplace_server/marketplace_server.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

void main() {
  late MarketplaceServer app;
  late DateTime now;
  Future<Map<String, dynamic>> call(
    String method,
    String path, {
    Map<String, dynamic>? body,
    String? token,
    int status = 200,
  }) async {
    final r = await app.handler(
      Request(
        method,
        Uri.parse('http://localhost$path'),
        headers: {
          'content-type': 'application/json',
          if (token != null) 'authorization': 'Bearer $token',
        },
        body: body == null ? null : jsonEncode(body),
      ),
    );
    final json = Map<String, dynamic>.from(
      jsonDecode(await r.readAsString()) as Map,
    );
    expect(r.statusCode, status, reason: json['error'] as String?);
    return json;
  }

  Future<String> session(String persona) async =>
      (await call('POST', '/v1/auth/demo', body: {'persona': persona}))['token']
          as String;
  setUp(() {
    now = DateTime.utc(2026, 10, 25, 12);
    app = MarketplaceServer(
      const ServerConfig(databasePath: ':memory:', demoShowcase: true),
      clock: () => now,
    );
  });
  tearDown(() => app.close());

  test(
    'prepared profiles have real scoped workspaces, orders and photos',
    () async {
      final config = await call('GET', '/v1/config');
      expect(config['demoShowcase'], true);
      for (final persona in ['bakery', 'restaurant', 'grocery']) {
        final token = await session(persona);
        final w = MerchantWorkspace.fromJson(
          await call('GET', '/v1/merchant/workspace', token: token),
        );
        expect(w.organizations, hasLength(1));
        expect(w.stores, hasLength(persona == 'bakery' ? 2 : 1));
        expect(w.products, hasLength(3));
        expect(w.lots.length, greaterThanOrEqualTo(6));
        expect(
          w.offers.any((o) => o.state == 'draft' && o.ruleId != null),
          true,
        );
        expect(w.offers.any((o) => o.state == 'paused'), true);
        expect(w.orders.any((o) => o.status == 'collected'), true);
        expect(w.orders.any((o) => o.status == 'cancelled'), true);
        expect(w.orders.any((o) => o.status == 'reserved'), true);
        expect(
          w.lots.every((l) => l.onHand >= l.reserved && l.reserved >= 0),
          true,
        );
        expect(w.lots.any((l) => l.quality == StockQuality.quarantine), true);
        expect(w.lots.any((l) => l.deadline.isBefore(now)), true);
        expect(w.products.every((p) => !p.image.startsWith('http')), true);
        for (final l in w.lots) {
          if (l.quality != StockQuality.checked || l.deadline.isBefore(now)) {
            expect(l.reserved, 0);
          }
        }
      }
      final me = await call('GET', '/v1/me', token: await session('customer'));
      expect((me['orders'] as List).length, greaterThanOrEqualTo(9));
      expect(me['credit'] as int, greaterThan(650));
      expect((me['favorites'] as List).length, 4);
      expect(DateTime.parse(me['memberUntil'] as String).isAfter(now), true);
    },
  );

  test(
    'seed stays idempotent and a new business day supplies fresh stock',
    () async {
      final before = app.database.db
          .select('SELECT COUNT(*) AS n FROM stock_lots')
          .first['n'];
      for (var i = 0; i < 3; i++) {
        await call('GET', '/v1/catalog');
      }
      expect(
        app.database.db
            .select('SELECT COUNT(*) AS n FROM stock_lots')
            .first['n'],
        before,
      );
      now = now.add(const Duration(days: 1));
      await call('GET', '/v1/catalog');
      final after = app.database.db
          .select('SELECT COUNT(*) AS n FROM stock_lots')
          .first['n'];
      expect(after as int, greaterThan(before as int));
      expect(
        app.database.db
            .select('SELECT COUNT(*) AS n FROM merchant_organizations')
            .first['n'],
        3,
      );
      expect(
        app.database.db
            .select('SELECT COUNT(*) AS n FROM stock_products')
            .first['n'],
        9,
      );
      await call('GET', '/v1/catalog');
      expect(
        app.database.db
            .select('SELECT COUNT(*) AS n FROM stock_lots')
            .first['n'],
        after,
      );
    },
  );

  test(
    'customer reservation, merchant pickup and cancellation update real lots',
    () async {
      final owner = await session('bakery'),
          customer = await session('customer');
      Future<MerchantWorkspace> ws() async => MerchantWorkspace.fromJson(
        await call('GET', '/v1/merchant/workspace', token: owner),
      );
      final before = await ws();
      final offer = before.offers.firstWhere(
        (o) => o.state == 'published' && o.offer.pickupEnd.isAfter(now),
      );
      final recipeUnits = offer.recipe.values.fold(0, (a, b) => a + b);
      int held(MerchantWorkspace w) => w.lots.fold(0, (a, l) => a + l.reserved);
      int physical(MerchantWorkspace w) =>
          w.lots.fold(0, (a, l) => a + l.onHand);
      final me = await call('GET', '/v1/me', token: customer);
      Future<RescueOrder> buy(String key) async => RescueOrder.fromJson(
        await call(
          'POST',
          '/v1/orders',
          token: customer,
          status: 201,
          body: {
            'idempotencyKey': key,
            'items': [
              {'offerId': offer.offer.id, 'quantity': 1},
            ],
            'invoice': me['invoice'],
            'useCredit': false,
          },
        ),
      );
      final order = await buy('showcase-reserve-collect-123');
      expect(held(await ws()), held(before) + recipeUnits);
      expect(physical(await ws()), physical(before));
      await call(
        'POST',
        '/v1/merchant/stores/${offer.storeId}/orders/${order.id}/collect',
        token: owner,
        body: {
          'pickupCode': order.pickupCode,
          'idempotencyKey': 'showcase-collect-order-123',
        },
      );
      expect(held(await ws()), held(before));
      expect(physical(await ws()), physical(before) - recipeUnits);
      final cancelled = await buy('showcase-reserve-cancel-123');
      await call(
        'POST',
        '/v1/orders/${cancelled.id}/cancel',
        token: customer,
        body: {},
      );
      expect(held(await ws()), held(before));
      expect(physical(await ws()), physical(before) - recipeUnits);
    },
  );

  test(
    'demo endpoint rejects unknown users and is absent by default',
    () async {
      await call(
        'POST',
        '/v1/auth/demo',
        body: {'persona': 'visitor'},
        status: 400,
      );
      final regular = MarketplaceServer(
        const ServerConfig(databasePath: ':memory:', seedDemo: false),
      );
      addTearDown(regular.close);
      final r = await regular.handler(
        Request('POST', Uri.parse('http://localhost/v1/auth/demo'), body: '{}'),
      );
      expect(r.statusCode, 404);
      expect(
        regular.database.db.select(
          "SELECT name FROM sqlite_master WHERE name='demo_showcase'",
        ),
        isEmpty,
      );
    },
  );

  test(
    'showcase cannot coexist with production, Stripe, push or no fixtures',
    () {
      for (final env in [
        {'APP_ENV': 'production'},
        {'PAYMENT_MODE': 'stripe'},
        {'SEED_DEMO': 'false'},
        {'STRIPE_SECRET_KEY': 'sk_test_never_used'},
        {'FIREBASE_SERVICE_ACCOUNT_FILE': '/no/file'},
      ]) {
        expect(
          () => ServerConfig.fromEnvironment({'DEMO_SHOWCASE': 'true', ...env}),
          throwsArgumentError,
        );
      }
      expect(
        () => const ServerConfig(
          demoShowcase: true,
          production: true,
        ).validateShowcase(),
        throwsArgumentError,
      );
    },
  );
}

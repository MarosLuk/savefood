import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:marketplace_domain/marketplace_domain.dart';
import 'package:marketplace_server/marketplace_server.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

void main() {
  var now = DateTime.utc(2026, 10, 24, 12);
  const config = ServerConfig(
    databasePath: ':memory:',
    paymentMode: 'stripe',
    stripeSecret: 'sk_test_mock',
    stripePublishableKey: 'pk_test_mock',
    stripeWebhookSecret: 'whsec_mock',
    applePayMerchantId: 'merchant.example.test',
  );
  late MarketplaceServer app;
  late String token;
  var status = 'requires_payment_method', creates = 0, cancels = 0, refunds = 0;
  var received = 398;
  Map<String, String> intentForm = {};
  Map<String, dynamic> intent() => {
    'id': 'pi_native',
    'client_secret': 'pi_native_secret_do_not_persist',
    'status': status,
    'currency': 'eur',
    'amount': received,
    'metadata': {'order_id': intentForm['metadata[order_id]']},
  };
  setUp(() {
    now = DateTime.utc(2026, 10, 24, 12);
    status = 'requires_payment_method';
    creates = 0;
    cancels = 0;
    refunds = 0;
    received = 398;
    intentForm = {};
    final gateway = StripePaymentGateway(
      config,
      client: MockClient((r) async {
        Map<String, dynamic> response;
        if (r.method == 'POST' && r.url.path == '/v1/payment_intents') {
          creates++;
          intentForm = Uri.splitQueryString(r.body);
          received = int.parse(intentForm['amount']!);
          expect(intentForm['payment_method_types[0]'], 'card');
          expect(intentForm['currency'], 'eur');
          expect(
            r.headers['Idempotency-Key'],
            intentForm['metadata[order_id]'],
          );
          response = intent();
        } else if (r.url.path.endsWith('/cancel')) {
          cancels++;
          status = 'canceled';
          response = intent();
        } else if (r.url.path == '/v1/refunds') {
          refunds++;
          expect(Uri.splitQueryString(r.body)['payment_intent'], 'pi_native');
          expect(r.headers['Idempotency-Key'], 'refund-pi_native');
          response = {'id': 're_native'};
        } else {
          response = intent();
        }
        return http.Response(
          jsonEncode(response),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    app = MarketplaceServer(config, payments: gateway, clock: () => now);
    app.database.db.execute('INSERT INTO users(id,email,name) VALUES(?,?,?)', [
      'owner',
      'owner@example.test',
      'Jana',
    ]);
    token = app.auth.createSession('owner')['token'] as String;
  });
  tearDown(() => app.close());
  Future<Response> call(
    String method,
    String path, {
    Map<String, dynamic>? body,
    String? auth,
  }) async => app.handler(
    Request(
      method,
      Uri.parse('http://localhost$path'),
      headers: {
        'authorization': 'Bearer ${auth ?? token}',
        'content-type': 'application/json',
      },
      body: body == null ? null : jsonEncode(body),
    ),
  );
  Map<String, dynamic> basket({bool useCredit = false}) => {
    'idempotencyKey': 'native-order-idempotency-key',
    'paymentFlow': 'native',
    'items': [
      {'offerId': 'butter', 'quantity': 1},
    ],
    'invoice': {
      'name': 'Jana Nová',
      'email': 'owner@example.test',
      'street': 'Ulica 1',
      'city': 'Bratislava',
      'postcode': '81101',
    },
    'useCredit': useCredit,
  };
  Future<RescueOrder> reserve({bool useCredit = false}) async {
    final response = await call(
      'POST',
      '/v1/orders',
      body: basket(useCredit: useCredit),
    );
    expect(response.statusCode, 201);
    return RescueOrder.fromJson(
      Map<String, dynamic>.from(
        jsonDecode(await response.readAsString()) as Map,
      ),
    );
  }

  Future<Response> webhook(
    String type,
    String eventId, {
    String? orderId,
  }) async {
    final body = jsonEncode({
      'id': eventId,
      'type': type,
      'data': {
        'object': {
          'id': 'pi_native',
          'metadata': {'order_id': orderId ?? intentForm['metadata[order_id]']},
        },
      },
    });
    final stamp = now.millisecondsSinceEpoch ~/ 1000;
    final signature = Hmac(
      sha256,
      utf8.encode('whsec_mock'),
    ).convert(utf8.encode('$stamp.$body'));
    return app.handler(
      Request(
        'POST',
        Uri.parse('http://localhost/v1/payments/webhook'),
        headers: {'stripe-signature': 't=$stamp,v1=$signature'},
        body: body,
      ),
    );
  }

  test(
    'native checkout creates one card intent and never persists its client secret',
    () async {
      final order = await reserve();
      final retried = await reserve();
      expect(order.paymentFlow, PaymentFlow.native);
      expect(order.paymentUrl, isNull);
      expect(order.status, OrderStatus.awaitingPayment);
      expect(retried.id, order.id);
      expect(creates, 1);
      expect(order.total, 398);
      expect(jsonEncode(order.toJson()), isNot(contains('_secret_')));
      expect(
        app.database.db.select('SELECT payload FROM orders').first['payload'],
        isNot(contains('_secret_')),
      );
      final response = await call(
        'POST',
        '/v1/orders/${order.id}/payment-sheet',
        body: {},
      );
      expect(response.statusCode, 200);
      expect(response.headers['cache-control'], contains('no-store'));
      final data = jsonDecode(await response.readAsString()) as Map;
      expect(data['clientSecret'], 'pi_native_secret_do_not_persist');
      expect(data['publishableKey'], 'pk_test_mock');
      expect(data['livemode'], false);
    },
  );
  test('another account cannot retrieve a payment secret', () async {
    final order = await reserve();
    app.database.db.execute('INSERT INTO users(id,email,name) VALUES(?,?,?)', [
      'other',
      'other@example.test',
      'Other',
    ]);
    final other = app.auth.createSession('other')['token'] as String;
    expect(
      (await call(
        'POST',
        '/v1/orders/${order.id}/payment-sheet',
        body: {},
        auth: other,
      )).statusCode,
      404,
    );
  });
  test('payment details must still match the server amount', () async {
    final order = await reserve();
    received = 1;
    expect(
      (await call(
        'POST',
        '/v1/orders/${order.id}/payment-sheet',
        body: {},
      )).statusCode,
      503,
    );
  });
  test(
    'confirmation is checked with Stripe rather than trusting a success event',
    () async {
      final order = await reserve();
      status = 'requires_action';
      expect(
        (await webhook(
          'payment_intent.succeeded',
          'evt_false_success',
        )).statusCode,
        200,
      );
      expect(
        (app.profile('owner')['orders'] as List).first['status'],
        'awaitingPayment',
      );
      status = 'succeeded';
      expect(
        (await webhook(
          'payment_intent.succeeded',
          'evt_real_success',
        )).statusCode,
        200,
      );
      expect(
        (await webhook(
          'payment_intent.succeeded',
          'evt_real_success',
        )).statusCode,
        200,
      );
      expect(
        (app.profile('owner')['orders'] as List).first['status'],
        'reserved',
      );
      expect(
        (await call(
          'POST',
          '/v1/orders/${order.id}/payment-sheet',
          body: {},
        )).statusCode,
        409,
      );
    },
  );
  test(
    'a paid intent with a different amount cannot fulfill the order',
    () async {
      await reserve();
      received = 1;
      status = 'succeeded';
      expect(
        (await webhook(
          'payment_intent.succeeded',
          'evt_wrong_amount',
        )).statusCode,
        503,
      );
      expect(
        (app.profile('owner')['orders'] as List).first['status'],
        'awaitingPayment',
      );
      received = 398;
      expect(
        (await webhook(
          'payment_intent.succeeded',
          'evt_wrong_amount',
        )).statusCode,
        200,
      );
      expect(
        (app.profile('owner')['orders'] as List).first['status'],
        'reserved',
      );
    },
  );
  test('cancelling an unpaid intent cancels once and releases stock', () async {
    final order = await reserve();
    expect(
      (await call(
        'POST',
        '/v1/orders/${order.id}/cancel',
        body: {},
      )).statusCode,
      200,
    );
    expect(
      (await call(
        'POST',
        '/v1/orders/${order.id}/cancel',
        body: {},
      )).statusCode,
      200,
    );
    expect(cancels, 1);
    expect(refunds, 0);
    expect(app.catalog().firstWhere((o) => o.id == 'butter').stock, 4);
  });
  test('a paid native order is refunded once when cancelled', () async {
    final order = await reserve();
    status = 'succeeded';
    await webhook('payment_intent.succeeded', 'evt_paid');
    expect(
      (await call(
        'POST',
        '/v1/orders/${order.id}/cancel',
        body: {},
      )).statusCode,
      200,
    );
    await call('POST', '/v1/orders/${order.id}/cancel', body: {});
    expect(refunds, 1);
    expect(cancels, 0);
  });
  test(
    'expired native orders revoke the payment intent before releasing stock',
    () async {
      final order = await reserve();
      now = now.add(const Duration(minutes: 31));
      expect((await call('GET', '/v1/catalog')).statusCode, 200);
      expect(cancels, 1);
      expect(
        (app.profile('owner')['orders'] as List).first['status'],
        'cancelled',
      );
      expect(
        (await call(
          'POST',
          '/v1/orders/${order.id}/payment-sheet',
          body: {},
        )).statusCode,
        409,
      );
    },
  );
  test(
    'small remainder uses less credit and a fully covered order avoids Stripe',
    () async {
      app.database.db.execute('UPDATE users SET credit=397 WHERE id=?', [
        'owner',
      ]);
      final partial = await reserve(useCredit: true);
      expect(partial.total, 50);
      expect(received, 50);
      expect(partial.creditUsed, 348);
      await call('POST', '/v1/orders/${partial.id}/cancel', body: {});
      app.database.db.execute('UPDATE users SET credit=398 WHERE id=?', [
        'owner',
      ]);
      final body = basket(useCredit: true)
        ..['idempotencyKey'] = 'second-fully-covered-order';
      final response = await call('POST', '/v1/orders', body: body);
      final full = jsonDecode(await response.readAsString()) as Map;
      expect(full['total'], 0);
      expect(full['status'], 'reserved');
      expect(creates, 1);
    },
  );
  test(
    'production refuses test keys and mismatched public/secret environments',
    () {
      final env = {
        'APP_ENV': 'production',
        'PAYMENT_MODE': 'stripe',
        'STRIPE_SECRET_KEY': 'sk_test_x',
        'STRIPE_WEBHOOK_SECRET': 'whsec_x',
        'PUBLIC_URL': 'https://api.example.test',
        'APP_URL': 'https://app.example.test',
        'SEED_DEMO': 'false',
      };
      expect(() => ServerConfig.fromEnvironment(env), throwsArgumentError);
      env['STRIPE_SECRET_KEY'] = 'sk_live_x';
      env['STRIPE_PUBLISHABLE_KEY'] = 'pk_test_x';
      expect(() => ServerConfig.fromEnvironment(env), throwsArgumentError);
      env['STRIPE_PUBLISHABLE_KEY'] = 'pk_live_x';
      expect(ServerConfig.fromEnvironment(env).nativePaymentsEnabled, true);
    },
  );
}

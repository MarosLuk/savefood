import 'dart:convert';
import 'package:marketplace_domain/marketplace_domain.dart';
import 'package:marketplace_server/marketplace_server.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

class FlakyGateway implements PaymentGateway {
  int calls = 0;
  bool fail = true, paid = false;
  @override
  Future<PaymentCheckout> create(RescueOrder order, String email) async {
    calls++;
    if (fail) throw StateError('network timeout');
    return PaymentCheckout(
      sessionId: order.id,
      url: 'https://checkout.stripe.com/test',
      paid: paid,
    );
  }

  @override
  Future<PaymentCheckout> retrieve(String id) async =>
      PaymentCheckout(sessionId: id, paid: paid);
  @override
  Future<void> cancel(String id, String? intent) async {}
}

final now = DateTime.utc(2026, 10, 23, 12);
const invoice = {
  'name': 'Jana Nová',
  'email': 'jana@example.test',
  'street': 'Ulica 1',
  'city': 'Bratislava',
  'postcode': '81101',
};
Map<String, dynamic> basket({
  int quantity = 1,
  String key = 'idempotency-test-key-123',
  String offer = 'butter',
}) => {
  'items': [
    {'offerId': offer, 'quantity': quantity},
  ],
  'invoice': invoice,
  'idempotencyKey': key,
};

void main() {
  late MarketplaceServer app;
  late String token, user;
  Future<Response> call(
    String method,
    String path, {
    Map<String, dynamic>? body,
    String? auth,
    bool authenticated = true,
  }) async => app.handler(
    Request(
      method,
      Uri.parse('http://localhost$path'),
      headers: {
        'content-type': 'application/json',
        if (authenticated) 'authorization': 'Bearer ${auth ?? token}',
      },
      body: body == null ? null : jsonEncode(body),
    ),
  );
  Future<Map<String, dynamic>> decode(Response response) async =>
      Map<String, dynamic>.from(
        jsonDecode(await response.readAsString()) as Map,
      );
  setUp(() {
    app = MarketplaceServer(
      const ServerConfig(databasePath: ':memory:'),
      clock: () => now,
    );
    user = 'test-user';
    app.database.db.execute('INSERT INTO users(id,email,name) VALUES(?,?,?)', [
      user,
      'jana@example.test',
      'Jana',
    ]);
    token = app.auth.createSession(user)['token'] as String;
  });
  tearDown(() => app.close());
  test(
    'catalog is public and supplies real timestamps and integer prices',
    () async {
      final response = await call('GET', '/v1/catalog', authenticated: false);
      expect(response.statusCode, 200);
      final json = await decode(response);
      final offers = (json['offers'] as List)
          .map((o) => FoodOffer.fromJson(Map<String, dynamic>.from(o as Map)))
          .toList();
      expect(offers, hasLength(14));
      expect(offers.first.price, 390);
      expect(offers.first.pickupStart.toUtc().hour, 15);
    },
  );
  test('profile requires a valid session', () async {
    expect((await call('GET', '/v1/me', authenticated: false)).statusCode, 401);
    expect((await call('GET', '/v1/me', auth: 'bad')).statusCode, 401);
  });
  test('email registration and password login use hashed passwords', () async {
    final body = {
      'name': 'Nový účet',
      'email': 'new@example.test',
      'password': 'A long safe password 123',
    };
    final registration = await call(
      'POST',
      '/v1/auth/register',
      body: body,
      authenticated: false,
    );
    expect(registration.statusCode, 201);
    final row = app.database.db.select('SELECT * FROM users WHERE email=?', [
      'new@example.test',
    ]).first;
    expect(row['password_hash'], isNot(body['password']));
    expect(row['salt'], isNotEmpty);
    final login = await call(
      'POST',
      '/v1/auth/login',
      body: body,
      authenticated: false,
    );
    expect(login.statusCode, 200);
    final wrong = await call(
      'POST',
      '/v1/auth/login',
      body: {...body, 'password': 'wrong'},
      authenticated: false,
    );
    expect(wrong.statusCode, 401);
    final duplicate = await call(
      'POST',
      '/v1/auth/register',
      body: body,
      authenticated: false,
    );
    expect(duplicate.statusCode, 409);
  });
  test('server computes the amount and ignores forged client prices', () async {
    final response = await call(
      'POST',
      '/v1/orders',
      body: {...basket(), 'total': 1, 'credit': 5000},
    );
    expect(response.statusCode, 201);
    final order = await decode(response);
    expect(order['total'], 398);
    expect(order['status'], 'reserved');
    expect(app.catalog().firstWhere((o) => o.id == 'butter').stock, 3);
  });
  test(
    'same idempotency key returns one order without consuming stock twice',
    () async {
      final first = await decode(
        await call('POST', '/v1/orders', body: basket()),
      );
      final second = await decode(
        await call('POST', '/v1/orders', body: basket()),
      );
      expect(first['id'], second['id']);
      expect(app.database.db.select('SELECT id FROM orders'), hasLength(1));
      expect(app.catalog().firstWhere((o) => o.id == 'butter').stock, 3);
    },
  );
  test('same key with changed contents is rejected', () async {
    await call('POST', '/v1/orders', body: basket());
    expect(
      (await call('POST', '/v1/orders', body: basket(quantity: 2))).statusCode,
      409,
    );
  });
  test('concurrent requests cannot oversell a finite stock', () async {
    final responses = await Future.wait([
      call(
        'POST',
        '/v1/orders',
        body: basket(quantity: 3, key: 'concurrent-one-key'),
      ),
      call(
        'POST',
        '/v1/orders',
        body: basket(quantity: 3, key: 'concurrent-two-key'),
      ),
    ]);
    expect(responses.map((r) => r.statusCode).toList()..sort(), [201, 409]);
  });
  test('order access is scoped to the authenticated account', () async {
    final order = await decode(
      await call('POST', '/v1/orders', body: basket()),
    );
    app.database.db.execute('INSERT INTO users(id,email,name) VALUES(?,?,?)', [
      'other',
      'other@example.test',
      'Other',
    ]);
    final other = app.auth.createSession('other')['token'] as String;
    expect(
      (await call(
        'POST',
        '/v1/orders/${order['id']}/cancel',
        auth: other,
        body: {},
      )).statusCode,
      404,
    );
  });
  test('club access is enforced on the server', () async {
    expect(
      (await call(
        'POST',
        '/v1/orders',
        body: basket(offer: 'toast'),
      )).statusCode,
      403,
    );
    await call('POST', '/v1/club/trial', body: {'code': 'KLUB30'});
    expect(
      (await call(
        'POST',
        '/v1/orders',
        body: basket(offer: 'toast'),
      )).statusCode,
      201,
    );
  });
  test('cashback is credited only after pickup and only once', () async {
    await call('POST', '/v1/club/trial', body: {});
    final order = await decode(
      await call('POST', '/v1/orders', body: basket()),
    );
    expect(app.profile(user)['credit'], 0);
    final path = '/v1/orders/${order['id']}/collect';
    expect(
      (await call('POST', path, body: {'pickupCode': 'WRONG'})).statusCode,
      403,
    );
    expect(
      (await call(
        'POST',
        path,
        body: {'pickupCode': order['pickupCode']},
      )).statusCode,
      200,
    );
    await call('POST', path, body: {'pickupCode': order['pickupCode']});
    expect(app.profile(user)['credit'], 39);
  });
  test('cancellation returns credit and inventory exactly once', () async {
    app.database.db.execute('UPDATE users SET credit=100 WHERE id=?', [user]);
    final order = await decode(
      await call('POST', '/v1/orders', body: {...basket(), 'useCredit': true}),
    );
    expect(app.profile(user)['credit'], 0);
    await call('POST', '/v1/orders/${order['id']}/cancel', body: {});
    await call('POST', '/v1/orders/${order['id']}/cancel', body: {});
    expect(app.profile(user)['credit'], 100);
    expect(app.catalog().firstWhere((o) => o.id == 'butter').stock, 4);
  });
  test(
    'client cannot overwrite wallet or membership through profile',
    () async {
      await call(
        'PATCH',
        '/v1/me',
        body: {
          'credit': 100000,
          'memberUntil': '2099-01-01',
          'trialUsed': false,
          'favorites': ['butter'],
        },
      );
      expect(app.profile(user)['credit'], 0);
      expect(app.profile(user)['memberUntil'], isNull);
      expect(app.profile(user)['favorites'], ['butter']);
    },
  );
  test('reviews require a collected purchase', () async {
    expect(
      (await call(
        'POST',
        '/v1/offers/butter/reviews',
        body: {'rating': 5, 'comment': 'Dobré'},
      )).statusCode,
      403,
    );
  });
  test(
    'unconfigured OAuth is explicit and never creates a fake login',
    () async {
      expect(
        (await call('POST', '/v1/auth/oauth/google', body: {})).statusCode,
        503,
      );
      expect(app.database.db.select('SELECT * FROM oauth_handoffs'), isEmpty);
    },
  );
  test('untrusted web origins are rejected', () async {
    final r = await app.handler(
      Request(
        'GET',
        Uri.parse('http://localhost/v1/catalog'),
        headers: {'origin': 'https://untrusted.example'},
      ),
    );
    expect(r.statusCode, 403);
  });
  test('logout revokes the current server session', () async {
    await call('POST', '/v1/auth/logout', body: {});
    expect((await call('GET', '/v1/me')).statusCode, 401);
  });
  test(
    'unpaid or interrupted Stripe preparation can be retried safely',
    () async {
      app.close();
      final gateway = FlakyGateway();
      app = MarketplaceServer(
        const ServerConfig(databasePath: ':memory:'),
        payments: gateway,
        clock: () => now,
      );
      app.database.db.execute(
        'INSERT INTO users(id,email,name) VALUES(?,?,?)',
        [user, 'jana@example.test', 'Jana'],
      );
      token = app.auth.createSession(user)['token'] as String;
      expect(
        (await call('POST', '/v1/orders', body: basket())).statusCode,
        503,
      );
      expect(app.catalog().firstWhere((o) => o.id == 'butter').stock, 3);
      gateway.fail = false;
      final response = await call('POST', '/v1/orders', body: basket());
      expect(response.statusCode, 201);
      final order = await decode(response);
      expect(order['paymentUrl'], isNotNull);
      expect(order['status'], 'awaitingPayment');
      expect(gateway.calls, 2);
      expect(
        (await call(
          'POST',
          '/v1/orders/${order['id']}/collect',
          body: {'pickupCode': order['pickupCode']},
        )).statusCode,
        409,
      );
      gateway.paid = true;
      await call('POST', '/v1/orders/${order['id']}/refresh', body: {});
      expect((app.profile(user)['orders'] as List).first['status'], 'reserved');
    },
  );
  test('production configuration refuses a sandbox payment setup', () {
    expect(
      () => ServerConfig.fromEnvironment({'APP_ENV': 'production'}),
      throwsArgumentError,
    );
  });
  test('a malformed body cannot crash the server', () async {
    final response = await app.handler(
      Request(
        'POST',
        Uri.parse('http://localhost/v1/orders'),
        headers: {'authorization': 'Bearer $token'},
        body: 'not json',
      ),
    );
    expect(response.statusCode, 400);
    expect((await call('GET', '/health')).statusCode, 200);
  });
}

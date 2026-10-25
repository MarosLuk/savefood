import 'dart:convert';
import 'package:marketplace_domain/marketplace_domain.dart';
import 'package:marketplace_server/marketplace_server.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

class RecordingPush implements StockPushGateway {
  final sent = <String>[];
  bool fail = false;
  @override
  bool get configured => true;
  @override
  void close() {}
  @override
  Future<bool> send(
    String token,
    String title,
    String body,
    Map<String, String> data,
  ) async {
    if (fail) throw StateError('Temporary outage');
    sent.add(token);
    return true;
  }
}

void main() {
  final now = DateTime.utc(2026, 10, 23, 12);
  late MarketplaceServer app;
  late RecordingPush push;
  late String token;
  const user = 'edge-user', device = 'a-valid-device-registration-token';
  const admin = 'abcdefghijklmnopqrstuvwxyz1234567890';
  setUp(() {
    push = RecordingPush();
    app = MarketplaceServer(
      const ServerConfig(databasePath: ':memory:', adminToken: admin),
      push: push,
      clock: () => now,
    );
    app.database.db.execute('INSERT INTO users(id,email,name) VALUES(?,?,?)', [
      user,
      'edge@example.test',
      'Jana',
    ]);
    token = app.auth.createSession(user)['token'] as String;
  });
  tearDown(() => app.close());
  Future<Response> call(
    String method,
    String path, {
    Map<String, dynamic>? body,
    String? bearer,
  }) async => app.handler(
    Request(
      method,
      Uri.parse('http://localhost$path'),
      headers: {
        'authorization': 'Bearer ${bearer ?? token}',
        'content-type': 'application/json',
      },
      body: body == null ? null : jsonEncode(body),
    ),
  );
  Future<void> enroll() async {
    expect(
      (await call(
        'PATCH',
        '/v1/me',
        body: {
          'favorites': ['butter'],
          'favoriteAlerts': true,
        },
      )).statusCode,
      200,
    );
    expect(
      (await call(
        'POST',
        '/v1/devices',
        body: {'token': device, 'platform': 'ios'},
      )).statusCode,
      200,
    );
  }

  Future<void> publish() async {
    final offer = app.catalog().firstWhere((o) => o.id == 'butter');
    expect(
      (await call(
        'POST',
        '/v1/admin/offers',
        body: offer.toJson(),
        bearer: admin,
      )).statusCode,
      201,
    );
  }

  test('stock alerts honor consent and deduplicate a pickup window', () async {
    await enroll();
    await publish();
    await publish();
    await app.drainPush();
    expect(push.sent, [device]);
    await publish();
    await app.drainPush();
    expect(push.sent, hasLength(1));
  });
  test(
    'queued push is suppressed after consent is revoked or logout',
    () async {
      await enroll();
      await publish();
      await call('PATCH', '/v1/me', body: {'favoriteAlerts': false});
      await app.drainPush();
      expect(push.sent, isEmpty);
      await call('POST', '/v1/auth/logout', body: {});
      expect(app.database.db.select('SELECT * FROM devices'), isEmpty);
    },
  );
  test(
    'failed push delivery stays queued and retries without duplicating success',
    () async {
      await enroll();
      await publish();
      push.fail = true;
      await app.drainPush();
      expect(push.sent, isEmpty);
      expect(
        app.database.db
            .select('SELECT attempts FROM push_outbox')
            .first['attempts'],
        1,
      );
      push.fail = false;
      await app.drainPush();
      await app.drainPush();
      expect(push.sent, [device]);
    },
  );
  test(
    'partial pickup keeps the order active and defers cashback until complete',
    () async {
      await call('POST', '/v1/club/trial', body: {});
      final response = await call(
        'POST',
        '/v1/orders',
        body: {
          'idempotencyKey': 'partial-pickup-key-12345',
          'items': [
            {'offerId': 'butter', 'quantity': 1},
            {'offerId': 'green', 'quantity': 1},
          ],
          'invoice': {
            'name': 'Jana Nová',
            'email': 'edge@example.test',
            'street': 'Ulica 1',
            'city': 'Bratislava',
            'postcode': '81101',
          },
        },
      );
      expect(response.statusCode, 201);
      final order = RescueOrder.fromJson(
        Map<String, dynamic>.from(
          jsonDecode(await response.readAsString()) as Map,
        ),
      );
      final first = app.collect(
        user,
        order.id,
        order.pickupCode!,
        offerId: 'butter',
      );
      expect(first.status, OrderStatus.reserved);
      expect(first.items.where((i) => i.collected), hasLength(1));
      expect(app.profile(user)['credit'], 0);
      expect(
        (await call(
          'POST',
          '/v1/orders/${order.id}/cancel',
          body: {},
        )).statusCode,
        409,
      );
      app.collect(user, order.id, order.pickupCode!, offerId: 'butter');
      final complete = app.collect(
        user,
        order.id,
        order.pickupCode!,
        offerId: 'green',
      );
      expect(complete.status, OrderStatus.collected);
      app.collect(user, order.id, order.pickupCode!);
      expect(app.profile(user)['credit'], order.cashback);
    },
  );
  test('review requires actual pickup and updates catalog aggregate', () async {
    final response = await call(
      'POST',
      '/v1/orders',
      body: {
        'idempotencyKey': 'review-order-key-12345',
        'items': [
          {'offerId': 'butter', 'quantity': 1},
        ],
        'invoice': {
          'name': 'Jana Nová',
          'email': 'edge@example.test',
          'street': 'Ulica 1',
          'city': 'Bratislava',
          'postcode': '81101',
        },
      },
    );
    final order = RescueOrder.fromJson(
      Map<String, dynamic>.from(
        jsonDecode(await response.readAsString()) as Map,
      ),
    );
    app.collect(user, order.id, order.pickupCode!);
    expect(
      (await call(
        'POST',
        '/v1/offers/butter/reviews',
        body: {'rating': 4, 'comment': 'Dobré pečivo'},
      )).statusCode,
      201,
    );
    expect(app.catalog().firstWhere((o) => o.id == 'butter').rating, 4);
    expect(app.catalog().firstWhere((o) => o.id == 'butter').reviews, 1);
    expect(
      (await call(
        'POST',
        '/v1/offers/butter/reviews',
        body: {'rating': 5, 'comment': 'Znova'},
      )).statusCode,
      201,
    );
    expect(app.catalog().firstWhere((o) => o.id == 'butter').reviews, 1);
    expect(app.catalog().firstWhere((o) => o.id == 'butter').rating, 5);
  });
}

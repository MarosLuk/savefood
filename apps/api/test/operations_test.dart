import 'dart:convert';
import 'package:marketplace_domain/marketplace_domain.dart';
import 'package:marketplace_server/marketplace_server.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

class TestConnect extends SandboxConnectGateway {
  final transfers = <String, int>{}, reversals = <String, String>{};
  var refunds = 0;
  bool loseTransferResponse = false, failRefund = false, failTransfers = false;
  @override
  Future<String> transfer(
    String key,
    String account,
    int amount,
    String order, {
    String? charge,
  }) async {
    transfers.putIfAbsent(key, () => amount);
    if (loseTransferResponse || failTransfers) {
      loseTransferResponse = false;
      throw StateError('lost response');
    }
    return 'demo_tr_$key';
  }

  @override
  Future<String> reverse(String key, String transfer, {int? amount}) async {
    reversals.putIfAbsent(key, () => transfer);
    return 'rev_$key';
  }

  @override
  Future<Map<String, dynamic>> refund(
    String key,
    String session,
    String? intent,
    RescueOrder order,
    int amount, {
    String? existing,
  }) async {
    if (failRefund) {
      failRefund = false;
      throw StateError('provider offline');
    }
    refunds++;
    return {'id': 'ref_$key', 'status': 'succeeded'};
  }
}

void main() {
  late MarketplaceServer app;
  late DateTime now;
  late TestConnect gateway;
  final tokens = <String, String>{};
  Future<Map<String, dynamic>> call(
    String method,
    String path, {
    String actor = 'customer',
    Map<String, dynamic>? body,
    int status = 200,
  }) async {
    final response = await app.handler(
      Request(
        method,
        Uri.parse('http://localhost$path'),
        headers: {
          'content-type': 'application/json',
          'authorization': 'Bearer ${tokens[actor]}',
        },
        body: body == null ? null : jsonEncode(body),
      ),
    );
    final j = Map<String, dynamic>.from(
      jsonDecode(await response.readAsString()) as Map,
    );
    expect(response.statusCode, status, reason: j['error'] as String?);
    return j;
  }

  Future<Map<String, dynamic>> mutate(
    String path,
    Map<String, dynamic> b, {
    String actor = 'customer',
    int status = 200,
  }) => call(
    'POST',
    path,
    actor: actor,
    status: status,
    body: {
      ...b,
      'idempotencyKey':
          b['idempotencyKey'] ??
          'test-${DateTime.now().microsecondsSinceEpoch}',
    },
  );
  String org(String actor) =>
      (app.merchants.workspace('showcase-$actor')['organizations'] as List)
              .first['id']
          as String;
  setUp(() {
    now = DateTime.utc(2026, 10, 25, 12);
    gateway = TestConnect();
    app = MarketplaceServer(
      const ServerConfig(
        databasePath: ':memory:',
        demoShowcase: true,
        settlementDelayHours: 0,
        commissionBps: 1000,
      ),
      connect: gateway,
      clock: () => now,
    );
    for (final actor in [
      'customer',
      'bakery',
      'grocery',
      'support',
      'restaurant',
    ]) {
      tokens[actor] =
          app.auth.createSession('showcase-$actor')['token'] as String;
    }
  });
  tearDown(() => app.close());
  test(
    'customer tickets are scoped, idempotent and have automatic answers; notes stay private',
    () async {
      final body = {
        'subject': 'Kde je môj balíček?',
        'message': 'Prosím o informáciu k vyzdvihnutiu.',
        'category': 'pickup',
        'idempotencyKey': 'support-create-test-key',
      };
      final ticket = await mutate('/v1/support/tickets', body, status: 201),
          id = ticket['id'] as String;
      final repeat = await mutate('/v1/support/tickets', body, status: 201);
      expect(repeat['id'], id);
      expect((ticket['messages'] as List).length, 2);
      await call(
        'GET',
        '/v1/support/tickets/$id',
        actor: 'bakery',
        status: 404,
      );
      await mutate(
        '/v1/support/tickets/$id/messages',
        {'message': 'Interné preverenie skladu', 'internal': true},
        actor: 'support',
        status: 201,
      );
      final mine = await call('GET', '/v1/support/tickets/$id');
      expect((mine['messages'] as List).length, 2);
      expect(
        (await call(
          'GET',
          '/v1/support/tickets/$id',
          actor: 'support',
        ))['messages'],
        hasLength(3),
      );
      await mutate('/v1/support/tickets/$id/messages', {
        'message': 'Skrytá poznámka',
        'internal': true,
      }, status: 403);
      await call('GET', '/v1/support/tickets?inbox=true', status: 403);
    },
  );
  test(
    'tickets cannot attach someone else’s order and operator status uses versions',
    () async {
      final other = app.finance
          .rows(
            "SELECT id FROM orders WHERE user_id='showcase-visitor' LIMIT 1",
          )
          .first['id'];
      await mutate('/v1/support/tickets', {
        'subject': 'Objednávka',
        'message': 'Toto nie je moja objednávka',
        'category': 'other',
        'orderId': other,
      }, status: 404);
      final t =
          (await call(
                'GET',
                '/v1/support/tickets?inbox=true',
                actor: 'support',
              ))['tickets']
              as List;
      final id = t.first['id'] as String;
      final first = await call(
        'GET',
        '/v1/support/tickets/$id',
        actor: 'support',
      );
      await mutate('/v1/support/tickets/$id/status', {
        'status': 'inProgress',
        'priority': 'urgent',
        'assignToMe': true,
        'expectedVersion': first['version'],
      }, actor: 'support');
      await mutate(
        '/v1/support/tickets/$id/status',
        {
          'status': 'resolved',
          'priority': 'normal',
          'expectedVersion': first['version'],
        },
        actor: 'support',
        status: 409,
      );
    },
  );
  test('financial access is owner scoped and journal balances by line', () async {
    await call(
      'GET',
      '/v1/merchant/finance/${org('bakery')}',
      actor: 'grocery',
      status: 404,
    );
    final summary = await call(
      'GET',
      '/v1/merchant/finance/${org('bakery')}',
      actor: 'bakery',
    );
    expect((summary['entries'] as List).isNotEmpty, true);
    expect(
      app.finance
          .rows(
            'SELECT line_id,SUM(amount) n FROM finance_journal GROUP BY line_id',
          )
          .every((r) => r['n'] == 0),
      true,
    );
    final export = await call(
      'GET',
      '/v1/merchant/finance/${org('bakery')}/export',
      actor: 'bakery',
    );
    expect(export['content'], contains('debit_cents'));
    expect(export['content'], contains('not_determined'));
    expect((export['content'] as String).split('\r\n').length, greaterThan(2));
    final day = await call(
      'GET',
      '/v1/merchant/finance/${org('bakery')}/export?from=2026-10-25&to=2026-10-26',
      actor: 'bakery',
    );
    expect((day['content'] as String).split('\r\n').length, greaterThan(2));
    final before = await call(
      'GET',
      '/v1/merchant/finance/${org('bakery')}/export?from=2026-10-24&to=2026-10-25',
      actor: 'bakery',
    );
    expect((before['content'] as String).split('\r\n').length, 2);
  });
  test('finance totals include history beyond the 500 displayed entries', () {
    final organization = org('bakery');
    final line = app.finance.one(
      'SELECT * FROM finance_lines WHERE org_id=? AND collected_at IS NOT NULL LIMIT 1',
      [organization],
    );
    final original = app.finance.order(line['order_id'] as String);
    final before = app.finance.summary('showcase-bakery', organization);
    final amount = (before['totals'] as Map)['sales'] as int;
    final unit = app.finance.allocation(line).goodsNet;
    app.database.transaction(() {
      for (var i = 0; i < 501; i++) {
        final id = 'history-order-$i';
        final copy = RescueOrder.fromJson({...original.toJson(), 'id': id});
        app.database.db.execute(
          'INSERT INTO orders(id,user_id,idempotency,request_hash,payload,status) VALUES(?,?,?,?,?,?)',
          [
            id,
            'showcase-customer',
            id,
            id,
            jsonEncode(copy.toJson()),
            copy.status.name,
          ],
        );
        app.finance.syncOrder(copy);
      }
    });
    final after = app.finance.summary('showcase-bakery', organization);
    expect(after['entries'], hasLength(500));
    expect((after['totals'] as Map)['sales'], amount + 501 * unit);
  });
  test(
    'only support can release a hold and unsafe stock still blocks release',
    () async {
      final tickets =
          (await call(
                'GET',
                '/v1/support/tickets?inbox=true',
                actor: 'support',
              ))['tickets']
              as List;
      final ticket = tickets.firstWhere((t) => t['category'] == 'pickup');
      final id = ticket['id'] as String, order = ticket['orderId'] as String;
      app.database.db.execute('INSERT INTO finance_holds VALUES(?,?,?)', [
        order,
        'Overenie',
        now.toIso8601String(),
      ]);
      await mutate('/v1/support/tickets/$id/release-finance', {}, status: 403);
      app.database.db.execute(
        "UPDATE stock_lots SET quality='quarantined' WHERE id IN (SELECT lot_id FROM stock_reservations WHERE order_id=? AND state='held')",
        [order],
      );
      await mutate(
        '/v1/support/tickets/$id/release-finance',
        {},
        actor: 'support',
        status: 409,
      );
      expect(
        app.finance.rows('SELECT * FROM finance_holds WHERE order_id=?', [
          order,
        ]),
        isNotEmpty,
      );
      app.database.db.execute(
        "UPDATE stock_lots SET quality='checked' WHERE id IN (SELECT lot_id FROM stock_reservations WHERE order_id=? AND state='held')",
        [order],
      );
      await mutate(
        '/v1/support/tickets/$id/release-finance',
        {},
        actor: 'support',
      );
      expect(
        app.finance.rows('SELECT * FROM finance_holds WHERE order_id=?', [
          order,
        ]),
        isEmpty,
      );
    },
  );
  test(
    'only collected lines settle, repeated queue and lost Stripe response cannot double transfer',
    () async {
      final organization = org('bakery');
      gateway.loseTransferResponse = true;
      final queued = app.finance.queue('showcase-bakery', organization);
      expect(queued, greaterThan(0));
      await app.finance.drain();
      final first = gateway.transfers.length;
      expect(app.finance.queue('showcase-bakery', organization), 0);
      await app.finance.drain();
      expect(gateway.transfers.length, first);
      final jobs = app.finance.rows(
        'SELECT t.*,l.collected_at FROM finance_transfers t JOIN finance_lines l ON l.id=t.line_id',
      );
      expect(
        jobs.every(
          (r) => r['collected_at'] != null && r['status'] == 'transferred',
        ),
        true,
      );
    },
  );
  test(
    'failed transfers do not starve later jobs in a longer settlement queue',
    () async {
      final organization = org('bakery');
      final line = app.finance.one(
        'SELECT * FROM finance_lines WHERE org_id=? AND collected_at IS NOT NULL LIMIT 1',
        [organization],
      );
      final original = app.finance.order(line['order_id'] as String);
      for (var i = 0; i < 21; i++) {
        final id = 'worker-order-$i';
        final copy = RescueOrder.fromJson({...original.toJson(), 'id': id});
        app.database.db.execute(
          'INSERT INTO orders(id,user_id,idempotency,request_hash,payload,status,payment_session) VALUES(?,?,?,?,?,?,?)',
          [
            id,
            'showcase-customer',
            id,
            id,
            jsonEncode(copy.toJson()),
            copy.status.name,
            'demo-$id',
          ],
        );
        app.finance.syncOrder(copy);
      }
      app.finance.queue('showcase-bakery', organization);
      gateway.failTransfers = true;
      await app.finance.drain();
      expect(gateway.transfers.length, 20);
      now = now.add(const Duration(minutes: 1));
      gateway.failTransfers = false;
      await app.finance.drain();
      expect(gateway.transfers.length, greaterThan(20));
    },
  );
  test(
    'operator refund reverses seller transfer, returns credit and does not restock consumed food',
    () async {
      final ticket =
          (await call(
                'GET',
                '/v1/support/tickets?inbox=true',
                actor: 'support',
              ))['tickets']
              as List;
      final t = ticket.firstWhere((t) => t['category'] == 'foodQuality'),
          id = t['id'] as String;
      final order = app.finance.order(t['orderId'] as String),
          line = order.items.first;
      await app.finance.connect('showcase-grocery', org('grocery'));
      app.finance.queue('showcase-grocery', org('grocery'));
      await app.finance.drain();
      final before = app.finance
          .rows('SELECT SUM(on_hand) n FROM stock_lots')
          .first['n'];
      final body = {
        'offerIds': [line.offerId],
        'reason': 'Demo reklamácia kvality',
        'idempotencyKey': 'refund-quality-test-123',
      };
      await mutate('/v1/support/tickets/$id/refund', body, actor: 'support');
      expect(gateway.reversals, isNotEmpty);
      expect(gateway.refunds, 1);
      expect(app.finance.order(order.id).items.first.refunded, true);
      expect(
        app.finance.rows('SELECT SUM(on_hand) n FROM stock_lots').first['n'],
        before,
      );
      await mutate('/v1/support/tickets/$id/refund', body, actor: 'support');
      expect(gateway.refunds, 1);
      expect(
        app.finance
            .rows(
              'SELECT line_id,SUM(amount) n FROM finance_journal GROUP BY line_id',
            )
            .every((r) => r['n'] == 0),
        true,
      );
    },
  );
  test(
    'refund of an uncollected line releases stock and retries safely after provider failure',
    () async {
      final t =
          (await call(
                'GET',
                '/v1/support/tickets?inbox=true',
                actor: 'support',
              ))['tickets']
              as List;
      final ticket = t.firstWhere((t) => t['category'] == 'pickup'),
          id = ticket['id'] as String;
      final order = app.finance.order(ticket['orderId'] as String);
      final before =
          app.finance.rows(
                "SELECT SUM(quantity) n FROM stock_reservations WHERE order_id=? AND state='held'",
                [order.id],
              ).first['n']
              as int;
      final body = {
        'offerIds': [order.items.first.offerId],
        'reason': 'Prevádzka nemá balíček',
        'idempotencyKey': 'refund-pickup-failed-123',
      };
      gateway.failRefund = true;
      await mutate(
        '/v1/support/tickets/$id/refund',
        body,
        actor: 'support',
        status: 503,
      );
      expect(app.finance.order(order.id).items.first.refunded, false);
      await mutate('/v1/support/tickets/$id/refund', body, actor: 'support');
      expect(
        app.finance.rows(
          "SELECT SUM(quantity) n FROM stock_reservations WHERE order_id=? AND state='held'",
          [order.id],
        ).first['n'],
        isNull,
      );
      expect(before, greaterThan(0));
      expect(gateway.refunds, 1);
      await call(
        'POST',
        '/v1/orders/${order.id}/collect',
        body: {'pickupCode': order.pickupCode},
        status: 409,
      );
    },
  );
  test(
    'ambiguous transfer older than Stripe idempotency window stops for review',
    () async {
      gateway.loseTransferResponse = true;
      app.finance.queue('showcase-bakery', org('bakery'));
      await app.finance.drain();
      final count = gateway.transfers.length;
      now = now.add(const Duration(hours: 24));
      await app.finance.drain();
      expect(gateway.transfers.length, count);
      expect(
        app.finance.rows(
          "SELECT id FROM finance_transfers WHERE status='review'",
        ),
        isNotEmpty,
      );
    },
  );
  test(
    'mixed-store credit purchase settles only collected goods and refunds remaining lines without duplicate cashback',
    () async {
      final w1 = app.merchants.workspace('showcase-bakery'),
          w2 = app.merchants.workspace('showcase-restaurant');
      String pick(Map<String, dynamic> w) =>
          (w['offers'] as List).firstWhere(
                (o) =>
                    o['state'] == 'published' &&
                    DateTime.parse(
                      o['offer']['pickupEnd'] as String,
                    ).isAfter(now),
              )['offer']['id']
              as String;
      final bakery = pick(w1),
          restaurant = pick(w2),
          me = app.profile('showcase-customer');
      final bought = await call(
        'POST',
        '/v1/orders',
        status: 201,
        body: {
          'idempotencyKey': 'mixed-credit-basket-001',
          'invoice': me['invoice'],
          'coupon': 'VITAJ10',
          'useCredit': true,
          'items': [
            {'offerId': bakery, 'quantity': 2},
            {'offerId': restaurant, 'quantity': 2},
          ],
        },
      );
      final o = RescueOrder.fromJson(bought);
      expect(o.creditUsed, greaterThan(0));
      expect(o.total, greaterThan(0));
      final allocations = app.finance.rows(
        'SELECT * FROM finance_lines WHERE order_id=?',
        [o.id],
      );
      expect(
        allocations.fold(0, (n, l) => n + app.finance.allocation(l).external),
        o.total,
      );
      final baked = app.finance.allocation(
        allocations.firstWhere((l) => l['offer_id'] == bakery),
      );
      expect(baked.commission, greaterThan(0));
      app.collect('showcase-customer', o.id, o.pickupCode!, offerId: bakery);
      app.finance.queue('showcase-bakery', org('bakery'));
      await app.finance.drain();
      final line = allocations.firstWhere((l) => l['offer_id'] == bakery);
      expect(
        app.finance.one(
          'SELECT SUM(amount) n FROM finance_transfers WHERE line_id=?',
          [line['id']],
        )['n'],
        baked.sellerNet,
      );
      expect(
        app.finance.one(
          "SELECT SUM(amount) n FROM finance_journal WHERE line_id=? AND account='seller_payable'",
          [line['id']],
        )['n'],
        0,
      );
      final ticket = await mutate('/v1/support/tickets', {
        'subject': 'Zvyšok objednávky',
        'message': 'Chcem reklamovať druhú položku.',
        'category': 'cancellation',
        'orderId': o.id,
      }, status: 201);
      final rest = app.finance.allocation(
        allocations.firstWhere((l) => l['offer_id'] == restaurant),
      );
      final body = {
        'offerIds': [restaurant],
        'reason': 'Balíček už nie je k dispozícii',
        'idempotencyKey': 'mixed-refund-restaurant-001',
      };
      await mutate(
        '/v1/support/tickets/${ticket['id']}/refund',
        body,
        actor: 'support',
      );
      final updated = app.finance.order(o.id);
      expect(updated.status, OrderStatus.collected);
      expect(
        updated.items.firstWhere((i) => i.offerId == restaurant).refunded,
        true,
      );
      expect(
        app.profile('showcase-customer')['credit'],
        rest.credit + updated.cashback,
      );
      final credit = app.profile('showcase-customer')['credit'];
      await mutate(
        '/v1/support/tickets/${ticket['id']}/refund',
        body,
        actor: 'support',
      );
      expect(app.profile('showcase-customer')['credit'], credit);
      await call('POST', '/v1/orders/${o.id}/cancel', body: {}, status: 409);
    },
  );
}

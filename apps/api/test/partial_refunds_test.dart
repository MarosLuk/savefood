import 'dart:convert';
import 'package:marketplace_domain/marketplace_domain.dart';
import 'package:marketplace_server/marketplace_server.dart';
import 'package:marketplace_server/src/finance.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

class UnitConnect extends SandboxConnectGateway {
  final transfers = <String, int>{},
      reversals = <String, int>{},
      refunds = <String, int>{};
  bool loseRefund = false, loseReverse = false;
  @override
  Future<String> transfer(
    String key,
    String account,
    int amount,
    String order, {
    String? charge,
  }) async {
    transfers.putIfAbsent(key, () => amount);
    return 'tr_$key';
  }

  @override
  Future<String> reverse(String key, String transfer, {int? amount}) async {
    reversals.putIfAbsent(key, () => amount!);
    if (loseReverse) {
      loseReverse = false;
      throw StateError('lost reversal response');
    }
    return 'rev_$key';
  }

  @override
  Future<Map<String, dynamic>> lookupReversal(
    String transfer,
    String id,
  ) async {
    final key = id.substring('rev_'.length);
    return {
      'id': id,
      'amount': reversals[key],
      'currency': 'eur',
      'transfer': transfer,
      'metadata': {'refund_id': key},
    };
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
    refunds.putIfAbsent(key, () => amount);
    if (loseRefund) {
      loseRefund = false;
      throw StateError('lost refund response');
    }
    return {'id': 'ref_$key', 'status': 'succeeded'};
  }

  @override
  Future<Map<String, dynamic>> charge(
    String session,
    String? intent,
    RescueOrder order,
  ) async => {
    'id': 'charge_${order.id}',
    'amount': order.total,
    'refunded': refunds.values.fold<int>(0, (a, b) => a + b),
  };
}

void main() {
  test(
    'unit allocation preserves every cent and balances each selected slice',
    () {
      for (var q = 1; q <= 50; q++) {
        final a = OrderAllocation(
          offerId: 'x',
          gross: q * 199,
          discount: q + 1,
          fee: 7,
          credit: 30,
          external: q * 199 - (q + 1) + 7 - 30,
          commission: 20,
          sellerNet: q * 199 - (q + 1) - 20,
        );
        final units = [for (var i = 0; i < q; i++) a.unitSlice(q, i, 1)];
        for (final key in a.toJson().keys.where((k) => k != 'offerId')) {
          expect(
            units.fold<int>(0, (n, u) => n + (u.toJson()[key] as int)),
            a.toJson()[key],
          );
        }
        expect(
          units.every(
            (u) => u.external + u.credit == u.sellerNet + u.commission + u.fee,
          ),
          true,
        );
      }
    },
  );
  late MarketplaceServer app;
  late UnitConnect gateway;
  late DateTime clock;
  late String org, offer, support;
  late RescueOrder order;
  late String ticket;
  setUp(() async {
    clock = DateTime.utc(2026, 10, 25, 12);
    gateway = UnitConnect();
    app = MarketplaceServer(
      const ServerConfig(
        databasePath: ':memory:',
        demoShowcase: true,
        settlementDelayHours: 0,
        commissionBps: 1000,
      ),
      connect: gateway,
      clock: () => clock,
    );
    final w = app.merchants.workspace('showcase-bakery');
    org = (w['organizations'] as List).first['id'] as String;
    offer =
        (w['offers'] as List).firstWhere(
              (o) => o['state'] == 'published' && (o['available'] as int) >= 3,
            )['offer']['id']
            as String;
    app.database.db.execute(
      "UPDATE users SET credit=200 WHERE id='showcase-customer'",
    );
    order = await app.reserve('showcase-customer', {
      'idempotencyKey': 'unit-refund-order-001',
      'invoice': app.profile('showcase-customer')['invoice'],
      'coupon': 'VITAJ10',
      'useCredit': true,
      'items': [
        {'offerId': offer, 'quantity': 3},
      ],
    });
    ticket =
        app.support.create('showcase-customer', {
              'subject': 'Čiastočná reklamácia',
              'message': 'Prosím refundovať časť objednávky.',
              'category': 'foodQuality',
              'orderId': order.id,
            })['id']
            as String;
    support = app.auth.createSession('showcase-support')['token'] as String;
  });
  tearDown(() => app.close());
  Future<Map> refund(int count, String key, {int status = 200}) async {
    final response = await app.handler(
      Request(
        'POST',
        Uri.parse('http://localhost/v1/support/tickets/$ticket/refund'),
        headers: {
          'authorization': 'Bearer $support',
          'content-type': 'application/json',
        },
        body: jsonEncode({
          'offerIds': [offer],
          'quantities': {offer: count},
          'reason': 'Vrátenie časti balíčkov',
          'idempotencyKey': key,
        }),
      ),
    );
    final result = jsonDecode(await response.readAsString()) as Map;
    expect(response.statusCode, status, reason: result.toString());
    return result;
  }

  test(
    'one of three uncollected packs releases only its stock and later refunds conserve total payment',
    () async {
      final held =
          app.database.db.select(
                "SELECT SUM(quantity) n FROM stock_reservations WHERE order_id=? AND state='held'",
                [order.id],
              ).first['n']
              as int;
      await refund(1, 'unit-refund-first-001');
      final updated = app.finance.order(order.id).items.single;
      expect(updated.refundCount, 1);
      expect(updated.refunded, false);
      expect(updated.remainingQuantity, 2);
      expect(
        app.database.db.select(
          "SELECT SUM(quantity) n FROM stock_reservations WHERE order_id=? AND state='held'",
          [order.id],
        ).first['n'],
        held * 2 ~/ 3,
      );
      await refund(1, 'unit-refund-first-001');
      expect(gateway.refunds, hasLength(1));
      await refund(3, 'unit-refund-too-many-001', status: 409);
      await refund(2, 'unit-refund-second-001');
      expect(app.finance.order(order.id).items.single.refunded, true);
      expect(
        app.finance.order(order.id).refundedAmount,
        order.total + order.creditUsed,
      );
      expect(gateway.refunds.values.fold<int>(0, (a, b) => a + b), order.total);
      expect(
        app.database.db.select(
          "SELECT SUM(quantity) n FROM stock_reservations WHERE order_id=? AND state='held'",
          [order.id],
        ).first['n'],
        isNull,
      );
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
    'partial refund of collected goods reverses only the required seller amount and never restocks',
    () async {
      clock = order.items.single.pickupStart.toUtc().add(
        const Duration(minutes: 1),
      );
      app.collect('showcase-customer', order.id, order.pickupCode!);
      await app.finance.connect('showcase-bakery', org);
      app.finance.queue('showcase-bakery', org);
      await app.finance.drain();
      final physical = app.database.db
          .select('SELECT SUM(on_hand) n FROM stock_lots')
          .first['n'];
      final line = app.finance.one(
        'SELECT * FROM finance_lines WHERE order_id=?',
        [order.id],
      );
      final first = app.finance.allocation(line).unitSlice(3, 0, 1);
      await refund(1, 'unit-collected-first-001');
      expect(
        gateway.reversals.values.fold<int>(0, (a, b) => a + b),
        first.sellerNet,
      );
      expect(
        app.database.db
            .select('SELECT SUM(on_hand) n FROM stock_lots')
            .first['n'],
        physical,
      );
      final net = app.finance.one(
        "SELECT SUM(t.amount-t.reversed_amount) n FROM finance_transfers t JOIN finance_lines l ON l.id=t.line_id WHERE l.order_id=? AND t.status='transferred'",
        [order.id],
      )['n'];
      expect(net, app.finance.remainingAllocation(line).sellerNet);
      await refund(2, 'unit-collected-second-001');
      expect(
        gateway.reversals.values.fold<int>(0, (a, b) => a + b),
        app.finance.allocation(line).sellerNet,
      );
      expect(
        app.database.db
            .select('SELECT SUM(on_hand) n FROM stock_lots')
            .first['n'],
        physical,
      );
    },
  );
  test(
    'lost partial refund response recovers its same provider operation and credits once',
    () async {
      gateway.loseRefund = true;
      await refund(1, 'unit-lost-response-001', status: 503);
      expect(app.finance.order(order.id).items.single.refundCount, 0);
      await refund(1, 'unit-lost-response-001');
      expect(gateway.refunds, hasLength(1));
      expect(app.finance.order(order.id).items.single.refundCount, 1);
    },
  );
  test(
    'lost reversal beyond provider idempotency window requires exact reconciliation and never reverses twice',
    () async {
      clock = order.items.single.pickupStart.toUtc().add(
        const Duration(minutes: 1),
      );
      app.collect('showcase-customer', order.id, order.pickupCode!);
      await app.finance.connect('showcase-bakery', org);
      app.finance.queue('showcase-bakery', org);
      await app.finance.drain();
      gateway.loseReverse = true;
      await refund(1, 'unit-reversal-expired-01', status: 503);
      final pending = app.database.db
          .select(
            "SELECT * FROM finance_reversals WHERE status='pending' AND attempted_at IS NOT NULL",
          )
          .single;
      final rid = pending['refund_id'] as String,
          job = pending['transfer_id'] as String;
      clock = clock.add(const Duration(hours: 24));
      await refund(1, 'unit-reversal-expired-01', status: 409);
      expect(gateway.reversals, hasLength(1));
      await app.finance.reconcileUnitReversal(rid, job, 'rev_$rid-$job');
      await app.finance.reconcileUnitReversal(rid, job, 'rev_$rid-$job');
      await refund(1, 'unit-reversal-expired-01');
      expect(gateway.reversals, hasLength(2));
      expect(gateway.refunds, hasLength(1));
      expect(app.finance.order(order.id).items.single.refundCount, 1);
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
    'lost external refund after a day can only resume after verifying the existing refund',
    () async {
      gateway.loseRefund = true;
      await refund(1, 'unit-old-refund-response', status: 503);
      clock = clock.add(const Duration(hours: 24));
      await refund(1, 'unit-old-refund-response', status: 409);
      final r = app.database.db
          .select("SELECT id FROM finance_refunds WHERE status!='completed'")
          .single;
      await app.finance.reconcileUnitRefund(
        r['id'] as String,
        'ref_${r['id']}',
      );
      await refund(1, 'unit-old-refund-response');
      expect(gateway.refunds, hasLength(1));
      expect(app.finance.order(order.id).items.single.refundCount, 1);
    },
  );
}

part of 'finance.dart';

extension UnitRefunds on FinanceService {
  void initializeRefundUnits() {
    final columns = rows(
      'PRAGMA table_info(finance_refunds)',
    ).map((r) => r['name']).toSet();
    if (!columns.contains('quantities')) {
      database.db.execute(
        "ALTER TABLE finance_refunds ADD COLUMN quantities TEXT NOT NULL DEFAULT '{}' ",
      );
    }
    if (!columns.contains('provider_attempted_at')) {
      database.db.execute(
        'ALTER TABLE finance_refunds ADD COLUMN provider_attempted_at TEXT',
      );
      database.db.execute(
        "UPDATE finance_refunds SET provider_attempted_at=created_at WHERE status!='completed'",
      );
    }
    if (!columns.contains('quantity_request')) {
      database.db.execute(
        'ALTER TABLE finance_refunds ADD COLUMN quantity_request INTEGER NOT NULL DEFAULT 0',
      );
    }
    if (!rows(
      'PRAGMA table_info(finance_transfers)',
    ).any((r) => r['name'] == 'reversed_amount')) {
      database.db.execute(
        'ALTER TABLE finance_transfers ADD COLUMN reversed_amount INTEGER NOT NULL DEFAULT 0',
      );
      database.db.execute(
        "UPDATE finance_transfers SET reversed_amount=amount WHERE status='reversed'",
      );
    }
    database.db.execute(
      '''CREATE TABLE IF NOT EXISTS finance_refund_parts(refund_id TEXT NOT NULL REFERENCES finance_refunds(id),
      line_id TEXT NOT NULL REFERENCES finance_lines(id),quantity INTEGER NOT NULL CHECK(quantity>0),allocation TEXT NOT NULL,PRIMARY KEY(refund_id,line_id));
      CREATE TABLE IF NOT EXISTS finance_reversals(refund_id TEXT NOT NULL REFERENCES finance_refunds(id),transfer_id TEXT NOT NULL REFERENCES finance_transfers(id),
      amount INTEGER NOT NULL CHECK(amount>0),status TEXT NOT NULL DEFAULT 'pending',provider_id TEXT,PRIMARY KEY(refund_id,transfer_id));''',
    );
    if (!rows(
      'PRAGMA table_info(finance_reversals)',
    ).any((r) => r['name'] == 'attempted_at')) {
      database.db.execute(
        'ALTER TABLE finance_reversals ADD COLUMN attempted_at TEXT',
      );
      database.db.execute(
        "UPDATE finance_reversals SET attempted_at=(SELECT created_at FROM finance_refunds WHERE id=finance_reversals.refund_id) WHERE status='pending'",
      );
    }
  }

  void completeUnitReversal(
    Map<String, dynamic> reversal,
    String provider,
  ) => database.transaction(() {
    final rid = reversal['refund_id'], count = reversal['amount'] as int;
    final current = one(
      'SELECT status FROM finance_reversals WHERE refund_id=? AND transfer_id=?',
      [rid, reversal['transfer_id']],
    );
    if (current['status'] == 'completed') return;
    database.db.execute(
      "UPDATE finance_reversals SET status='completed',provider_id=? WHERE refund_id=? AND transfer_id=?",
      [provider, rid, reversal['transfer_id']],
    );
    database.db.execute(
      "UPDATE finance_transfers SET reversed_amount=reversed_amount+?,status=CASE WHEN reversed_amount+?=amount THEN 'reversed' ELSE 'transferred' END,reversal_id=? WHERE id=?",
      [count, count, provider, reversal['transfer_id']],
    );
    _transferJournal({
      'id': '${reversal['transfer_id']}:$rid',
      'line_id': reversal['line_id'],
      'part': reversal['part'],
      'amount': count,
    }, true);
  });
  Future<void> reconcileUnitReversal(
    String rid,
    String job,
    String provider,
  ) async {
    final r = one(
      'SELECT r.*,t.provider_id transfer_provider,t.line_id,t.part,f.order_id FROM finance_reversals r JOIN finance_transfers t ON t.id=r.transfer_id JOIN finance_refunds f ON f.id=r.refund_id WHERE r.refund_id=? AND r.transfer_id=?',
      [rid, job],
    );
    final lock = r['order_id'] as String;
    if (!working.add(lock)) {
      throw const ApiFailure(409, 'Objednávka sa práve spracúva.');
    }
    try {
      final actual = await gateway.lookupReversal(
        r['transfer_provider'] as String,
        provider,
      );
      if (actual['id'] != provider ||
          actual['amount'] != r['amount'] ||
          actual['currency'] != 'eur' ||
          actual['transfer'] != r['transfer_provider'] ||
          (actual['metadata'] as Map?)?['refund_id'] != '$rid-$job') {
        throw const ApiFailure(
          409,
          'Reverzia nesúhlasí s pôvodnou požiadavkou.',
        );
      }
      completeUnitReversal(r, provider);
    } finally {
      working.remove(lock);
    }
  }

  Future<void> reconcileUnitRefund(String rid, String provider) async {
    final r = one('SELECT * FROM finance_refunds WHERE id=?', [rid]),
        id = r['order_id'] as String;
    if (!working.add(id)) {
      throw const ApiFailure(409, 'Objednávka sa práve spracúva.');
    }
    try {
      final payment = one('SELECT * FROM orders WHERE id=?', [id]);
      final result = await gateway.refund(
        rid,
        payment['payment_session'] as String,
        payment['payment_intent'] as String?,
        order(id),
        r['external'] as int,
        existing: provider,
      );
      database.db.execute(
        'UPDATE finance_refunds SET provider_id=? WHERE id=?',
        [result['id'], rid],
      );
    } finally {
      working.remove(id);
    }
  }

  OrderAllocation remainingAllocation(Map<String, dynamic> line) {
    final a = allocation(line), o = order(line['order_id'] as String);
    final item = o.items.firstWhere((i) => i.offerId == line['offer_id']);
    return a.unitSlice(
      item.quantity,
      line['refunded'] == 1 ? item.quantity : item.refundCount,
      line['refunded'] == 1 ? 0 : item.remainingQuantity,
    );
  }

  Map<String, int> refundQuantities(String refund) => {
    for (final part in rows(
      'SELECT l.offer_id,p.quantity FROM finance_refund_parts p JOIN finance_lines l ON l.id=p.line_id WHERE p.refund_id=?',
      [refund],
    ))
      part['offer_id'] as String: part['quantity'] as int,
  };
  Future<void> _reverseUnits(
    String rid,
    Map<String, dynamic> line,
    OrderAllocation amount,
  ) async {
    final jobs = rows(
      'SELECT t.*,l.order_id FROM finance_transfers t JOIN finance_lines l ON l.id=t.line_id WHERE t.line_id=? ORDER BY t.id',
      [line['id']],
    );
    for (final job in jobs) {
      if (job['status'] == 'processing' ||
          job['status'] == 'failed' && job['attempted_at'] != null) {
        await _transfer(job);
      }
      final current = one('SELECT * FROM finance_transfers WHERE id=?', [
        job['id'],
      ]);
      if (current['status'] == 'review') {
        throw const ApiFailure(
          409,
          'Prevod potrebuje zosúladenie pred refundáciou.',
        );
      }
      if (current['provider_id'] == null) {
        database.db.execute(
          "UPDATE finance_transfers SET status='cancelled' WHERE id=?",
          [job['id']],
        );
      }
    }
    if (rows(
      'SELECT transfer_id FROM finance_reversals WHERE refund_id=? AND transfer_id IN (SELECT id FROM finance_transfers WHERE line_id=?)',
      [rid, line['id']],
    ).isEmpty) {
      final paid = rows(
        "SELECT * FROM finance_transfers WHERE line_id=? AND status='transferred' AND provider_id IS NOT NULL AND amount>reversed_amount ORDER BY id",
        [line['id']],
      );
      final weights = paid
          .map((j) => (j['amount'] as int) - (j['reversed_amount'] as int))
          .toList();
      final available = weights.fold(0, (a, b) => a + b);
      final parts = allocateCents(
        math.min(amount.sellerNet, available),
        weights,
      );
      database.transaction(() {
        for (var i = 0; i < paid.length; i++) {
          if (parts[i] > 0) {
            database.db.execute(
              'INSERT INTO finance_reversals(refund_id,transfer_id,amount) VALUES(?,?,?)',
              [rid, paid[i]['id'], parts[i]],
            );
          }
        }
      });
    }
    for (final reversal in rows(
      "SELECT r.*,t.provider_id transfer_provider,t.amount original,t.reversed_amount,t.line_id,t.part FROM finance_reversals r JOIN finance_transfers t ON t.id=r.transfer_id WHERE r.refund_id=? AND t.line_id=? AND r.status='pending'",
      [rid, line['id']],
    )) {
      final count = reversal['amount'] as int;
      if (reversal['attempted_at'] != null &&
          clock().difference(
                DateTime.parse(reversal['attempted_at'] as String),
              ) >
              const Duration(hours: 23)) {
        throw const ApiFailure(
          409,
          'Reverziu treba spárovať so záznamom Stripe pred ďalším pokračovaním.',
        );
      }
      database.db.execute(
        'UPDATE finance_reversals SET attempted_at=COALESCE(attempted_at,?) WHERE refund_id=? AND transfer_id=?',
        [now, rid, reversal['transfer_id']],
      );
      final provider = await gateway.reverse(
        '$rid-${reversal['transfer_id']}',
        reversal['transfer_provider'] as String,
        amount: count,
      );
      completeUnitReversal(reversal, provider);
    }
  }

  Future<Map<String, dynamic>> refundUnits(
    String actor,
    String id,
    Map<String, dynamic> body,
    void Function(RescueOrder, List<String>, int, int, String) apply,
  ) async {
    final key = stringField(body, 'idempotencyKey', max: 100),
        reason = stringField(body, 'reason', max: 500);
    final input = body['quantities'] as Map?;
    final ids =
        (body['offerIds'] as List? ?? input?.keys.toList() ?? [])
            .cast<String>()
            .toSet()
            .toList()
          ..sort();
    if (key.length < 16 ||
        reason.length < 3 ||
        ids.isEmpty ||
        ids.length > 30 ||
        input != null &&
            (!input.keys.every(ids.contains) || input.length != ids.length)) {
      throw const ApiFailure(400, 'Vyber položky, počty a dôvod refundácie.');
    }
    if (input != null &&
        input.values.any((v) => v is! int || v < 1 || v > 50)) {
      throw const ApiFailure(400, 'Vyber celé kladné počty kusov.');
    }
    final quantities = input == null
        ? null
        : {for (final offer in ids) offer: input[offer] as int};
    final hash = hashToken(
      jsonEncode({
        'order': id,
        'offers': ids,
        'reason': reason,
        'quantities': ?quantities,
      }),
    );
    var request = rows(
      'SELECT * FROM finance_refunds WHERE actor=? AND idempotency=?',
      [actor, key],
    ).firstOrNull;
    if (request != null && request['request_hash'] != hash) {
      throw const ApiFailure(409, 'Identifikátor patrí inej refundácii.');
    }
    if (request?['status'] == 'completed') {
      return {'id': request!['id'], 'status': 'completed'};
    }
    if (!working.add(id)) {
      throw const ApiFailure(409, 'Objednávka sa práve spracúva.');
    }
    try {
      final o = order(id);
      if (o.status == OrderStatus.awaitingPayment ||
          o.status == OrderStatus.cancelled) {
        throw const ApiFailure(409, 'Objednávku teraz nemožno refundovať.');
      }
      syncOrder(o);
      if (request == null) {
        if (rows(
          "SELECT id FROM finance_refunds WHERE order_id=? AND status NOT IN ('completed','rejected') LIMIT 1",
          [id],
        ).isNotEmpty) {
          throw const ApiFailure(409, 'Najprv obnov nedokončenú refundáciu.');
        }
        if (o.total > 0) {
          final payment = one('SELECT * FROM orders WHERE id=?', [id]);
          final charge = await gateway.charge(
            payment['payment_session'] as String,
            payment['payment_intent'] as String?,
            o,
          );
          final known =
              one(
                    "SELECT COALESCE(SUM(external),0) n FROM finance_refunds WHERE order_id=? AND status='completed'",
                    [id],
                  )['n']
                  as int;
          if ((charge['refunded'] as int) > known) {
            hold(id, 'Stripe eviduje nesúlad refundácií.');
            throw const ApiFailure(409, 'Najprv zosúlaď refundáciu zo Stripe.');
          }
        }
        request = database.transaction(() {
          final rid = const Uuid().v4();
          var external = 0, credit = 0;
          final frozen = <String, int>{};
          final parts = <Map<String, dynamic>>[];
          for (final offer in ids) {
            final item = o.items.where((i) => i.offerId == offer).firstOrNull;
            if (item == null) {
              throw const ApiFailure(404, 'Položka nie je v objednávke.');
            }
            final count = quantities?[offer] ?? item.remainingQuantity;
            if (count < 1 || count > item.remainingQuantity) {
              throw const ApiFailure(
                409,
                'Počet prevyšuje nerefundované kusy.',
              );
            }
            final line = one(
              'SELECT * FROM finance_lines WHERE order_id=? AND offer_id=?',
              [id, offer],
            );
            if (line['refunded'] == 1 || line['refund_id'] != null) {
              throw const ApiFailure(
                409,
                'Položka už má rozpracovanú refundáciu.',
              );
            }
            final a = allocation(
              line,
            ).unitSlice(item.quantity, item.refundCount, count);
            external += a.external;
            credit += a.credit;
            frozen[offer] = count;
            parts.add({
              'line': line['id'],
              'quantity': count,
              'allocation': jsonEncode(a.toJson()),
            });
          }
          database.db.execute(
            'INSERT INTO finance_refunds(id,order_id,actor,idempotency,request_hash,offer_ids,reason,external,credit,status,created_at,quantities,quantity_request) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?)',
            [
              rid,
              id,
              actor,
              key,
              hash,
              jsonEncode(ids),
              reason,
              external,
              credit,
              'processing',
              now,
              jsonEncode(frozen),
              quantities == null ? 0 : 1,
            ],
          );
          for (final part in parts) {
            database.db.execute(
              'INSERT INTO finance_refund_parts VALUES(?,?,?,?)',
              [rid, part['line'], part['quantity'], part['allocation']],
            );
            database.db.execute(
              'UPDATE finance_lines SET refund_id=? WHERE id=?',
              [rid, part['line']],
            );
          }
          return one('SELECT * FROM finance_refunds WHERE id=?', [rid]);
        });
      }
      final rid = request!['id'] as String;
      var parts = rows(
        'SELECT p.*,l.* FROM finance_refund_parts p JOIN finance_lines l ON l.id=p.line_id WHERE p.refund_id=?',
        [rid],
      );
      // A pending full-row refund written by an older release remains recoverable.
      if (parts.isEmpty) {
        database.transaction(() {
          for (final line in rows(
            'SELECT * FROM finance_lines WHERE refund_id=?',
            [rid],
          )) {
            final item = o.items.firstWhere(
              (i) => i.offerId == line['offer_id'],
            );
            database.db.execute(
              'INSERT INTO finance_refund_parts VALUES(?,?,?,?)',
              [rid, line['id'], item.remainingQuantity, line['allocation']],
            );
          }
        });
        parts = rows(
          'SELECT p.quantity,p.allocation part_allocation,l.* FROM finance_refund_parts p JOIN finance_lines l ON l.id=p.line_id WHERE p.refund_id=?',
          [rid],
        );
      } else {
        parts = rows(
          'SELECT p.quantity,p.allocation part_allocation,l.* FROM finance_refund_parts p JOIN finance_lines l ON l.id=p.line_id WHERE p.refund_id=?',
          [rid],
        );
      }
      for (final part in parts) {
        await _reverseUnits(
          rid,
          part,
          OrderAllocation.fromJson(
            database.decode(part['part_allocation'] as String),
          ),
        );
      }
      if ((request['external'] as int) > 0) {
        final payment = one('SELECT * FROM orders WHERE id=?', [id]);
        if (request['provider_id'] == null &&
            request['provider_attempted_at'] != null &&
            clock().difference(
                  DateTime.parse(request['provider_attempted_at'] as String),
                ) >
                const Duration(hours: 23)) {
          throw const ApiFailure(
            409,
            'Refundácia potrebuje overiť stav v Stripe.',
          );
        }
        database.db.execute(
          'UPDATE finance_refunds SET provider_attempted_at=COALESCE(provider_attempted_at,?) WHERE id=?',
          [now, rid],
        );
        final result = await gateway.refund(
          rid,
          payment['payment_session'] as String,
          payment['payment_intent'] as String?,
          o,
          request['external'] as int,
          existing: request['provider_id'] as String?,
        );
        database.db.execute(
          'UPDATE finance_refunds SET provider_id=? WHERE id=?',
          [result['id'], rid],
        );
        if (result['status'] != 'succeeded') {
          throw const ApiFailure(
            503,
            'Stripe refundáciu ešte nepotvrdil. Obnov jej stav.',
          );
        }
      }
      database.transaction(() {
        apply(
          o,
          ids,
          request!['external'] as int,
          request['credit'] as int,
          rid,
        );
        final updated = order(id);
        for (final part in parts) {
          _journal(
            part,
            'refund:$rid',
            -1,
            part: OrderAllocation.fromJson(
              database.decode(part['part_allocation'] as String),
            ),
          );
          final item = updated.items.firstWhere(
            (i) => i.offerId == part['offer_id'],
          );
          database.db.execute(
            'UPDATE finance_lines SET refunded=?,refund_id=NULL WHERE id=?',
            [item.refunded ? 1 : 0, part['id']],
          );
        }
        database.db.execute(
          "UPDATE finance_refunds SET status='completed',error=NULL WHERE id=?",
          [rid],
        );
        documentsChanged?.call(id);
      });
      return {
        'id': rid,
        'status': 'completed',
        'quantities': refundQuantities(rid),
      };
    } catch (e) {
      if (request != null) {
        database.db.execute('UPDATE finance_refunds SET error=? WHERE id=?', [
          _error(e),
          request['id'],
        ]);
      }
      rethrow;
    } finally {
      working.remove(id);
    }
  }
}

import 'dart:convert';
import 'dart:math' as math;
import 'package:marketplace_domain/marketplace_domain.dart';
import 'package:uuid/uuid.dart';
import 'auth.dart';
import 'config.dart';
import 'connect.dart';
import 'database.dart';
part 'partial_refunds.dart';

class FinanceService {
  FinanceService(
    this.database,
    this.config,
    this.gateway,
    this.working, {
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now {
    database.db.execute('''
      CREATE TABLE IF NOT EXISTS finance_lines(id TEXT PRIMARY KEY,order_id TEXT NOT NULL REFERENCES orders(id),
        offer_id TEXT NOT NULL,org_id TEXT REFERENCES merchant_organizations(id),store_id TEXT REFERENCES merchant_stores(id),
        allocation TEXT NOT NULL,commission_bps INTEGER NOT NULL,created_at TEXT NOT NULL,collected_at TEXT,
        refunded INTEGER NOT NULL DEFAULT 0,refund_id TEXT,UNIQUE(order_id,offer_id));
      CREATE INDEX IF NOT EXISTS finance_lines_org ON finance_lines(org_id,created_at);
      CREATE TABLE IF NOT EXISTS finance_journal(id INTEGER PRIMARY KEY AUTOINCREMENT,line_id TEXT NOT NULL REFERENCES finance_lines(id),
        kind TEXT NOT NULL,account TEXT NOT NULL,amount INTEGER NOT NULL,created_at TEXT NOT NULL,
        UNIQUE(line_id,kind,account));
      CREATE TABLE IF NOT EXISTS finance_accounts(org_id TEXT PRIMARY KEY REFERENCES merchant_organizations(id),
        account_id TEXT,ready INTEGER NOT NULL DEFAULT 0,status TEXT NOT NULL DEFAULT 'notConnected',
        auto_enabled INTEGER NOT NULL DEFAULT 0,attempted_at TEXT,updated_at TEXT NOT NULL);
      CREATE TABLE IF NOT EXISTS finance_transfers(id TEXT PRIMARY KEY,line_id TEXT NOT NULL REFERENCES finance_lines(id),
        part TEXT NOT NULL,amount INTEGER NOT NULL,destination TEXT NOT NULL,source_charge TEXT,
        status TEXT NOT NULL DEFAULT 'queued',provider_id TEXT,reversal_id TEXT,attempted_at TEXT,last_attempt_at TEXT,error TEXT,
        UNIQUE(line_id,part));
      CREATE TABLE IF NOT EXISTS finance_refunds(id TEXT PRIMARY KEY,order_id TEXT NOT NULL REFERENCES orders(id),
        actor TEXT NOT NULL,idempotency TEXT NOT NULL,request_hash TEXT NOT NULL,offer_ids TEXT NOT NULL,
        reason TEXT NOT NULL,external INTEGER NOT NULL,credit INTEGER NOT NULL,status TEXT NOT NULL,
        provider_id TEXT,created_at TEXT NOT NULL,error TEXT,UNIQUE(actor,idempotency));
      CREATE TABLE IF NOT EXISTS finance_holds(order_id TEXT PRIMARY KEY REFERENCES orders(id),reason TEXT NOT NULL,created_at TEXT NOT NULL);
    ''');
    if (!rows(
      'PRAGMA table_info(finance_transfers)',
    ).any((r) => r['name'] == 'last_attempt_at')) {
      database.db.execute(
        'ALTER TABLE finance_transfers ADD COLUMN last_attempt_at TEXT',
      );
    }
    initializeRefundUnits();
  }
  final MarketplaceDatabase database;
  final ServerConfig config;
  final ConnectGateway gateway;
  final Set<String> working;
  final DateTime Function() clock;
  bool _draining = false;
  void Function(String orderId)? documentsChanged;
  String get now => clock().toUtc().toIso8601String();
  List<Map<String, dynamic>> rows(
    String sql, [
    List<Object?> args = const [],
  ]) => database.db
      .select(sql, args)
      .map((r) => Map<String, dynamic>.from(r))
      .toList();
  Map<String, dynamic> one(String sql, List<Object?> args) {
    final r = rows(sql, args);
    if (r.isEmpty) throw const ApiFailure(404, 'Záznam sa nenašiel.');
    return r.first;
  }

  Map<String, dynamic> requireOwner(String user, String org) => one(
    "SELECT o.* FROM merchant_organizations o JOIN merchant_members m ON m.org_id=o.id WHERE o.id=? AND m.user_id=? AND m.role='owner'",
    [org, user],
  );
  RescueOrder order(String id) => RescueOrder.fromJson(
    database.decode(
      one('SELECT payload FROM orders WHERE id=?', [id])['payload'] as String,
    ),
  );
  OrderAllocation allocation(Map<String, dynamic> line) =>
      OrderAllocation.fromJson(database.decode(line['allocation'] as String));
  void capture(
    RescueOrder order, {
    bool legacy = false,
  }) => database.transaction(() {
    if (rows('SELECT id FROM finance_lines WHERE order_id=? LIMIT 1', [
      order.id,
    ]).isNotEmpty) {
      return;
    }
    for (final a in OrderAllocation.forOrder(
      order,
      legacy ? 0 : config.commissionBps,
    )) {
      final m = rows(
        'SELECT m.store_id,s.org_id FROM merchant_offers m JOIN merchant_stores s ON s.id=m.store_id WHERE m.offer_id=?',
        [a.offerId],
      );
      database.db.execute(
        'INSERT INTO finance_lines(id,order_id,offer_id,org_id,store_id,allocation,commission_bps,created_at) VALUES(?,?,?,?,?,?,?,?)',
        [
          hashToken('${order.id}:${a.offerId}'),
          order.id,
          a.offerId,
          m.firstOrNull?['org_id'],
          m.firstOrNull?['store_id'],
          jsonEncode(a.toJson()),
          legacy ? 0 : config.commissionBps,
          order.createdAt.toUtc().toIso8601String(),
        ],
      );
    }
  });
  void syncOrder(RescueOrder order) => database.transaction(() {
    capture(order, legacy: true);
    if (order.status == OrderStatus.awaitingPayment) return;
    for (final l in rows('SELECT * FROM finance_lines WHERE order_id=?', [
      order.id,
    ])) {
      final item = order.items.firstWhere((i) => i.offerId == l['offer_id']);
      // Old cancelled orders have no known paid transition; don't invent journal entries.
      if (order.status != OrderStatus.cancelled) _journal(l, 'sale', 1);
      if (item.collected) {
        database.db.execute(
          'UPDATE finance_lines SET collected_at=COALESCE(collected_at,?) WHERE id=?',
          [now, l['id']],
        );
      }
      if (order.status == OrderStatus.cancelled &&
          rows('SELECT id FROM finance_refunds WHERE order_id=? LIMIT 1', [
            order.id,
          ]).isEmpty) {
        if (rows(
          "SELECT id FROM finance_journal WHERE line_id=? AND kind='sale' LIMIT 1",
          [l['id']],
        ).isNotEmpty) {
          _journal(l, 'refund', -1);
        }
        database.db.execute('UPDATE finance_lines SET refunded=1 WHERE id=?', [
          l['id'],
        ]);
      }
    }
  });
  void backfill() {
    for (final r in rows('SELECT payload FROM orders')) {
      syncOrder(RescueOrder.fromJson(database.decode(r['payload'] as String)));
    }
  }

  void _journal(
    Map<String, dynamic> line,
    String kind,
    int sign, {
    OrderAllocation? part,
  }) {
    final a = part ?? allocation(line);
    final entries = {
      'card_clearing': a.external,
      'customer_credit': a.credit,
      'seller_payable': -a.sellerNet,
      'platform_revenue': -(a.commission + a.fee),
    };
    assert(entries.values.fold(0, (a, b) => a + b) == 0);
    for (final e in entries.entries) {
      if (e.value == 0) continue;
      database.db.execute(
        'INSERT OR IGNORE INTO finance_journal(line_id,kind,account,amount,created_at) VALUES(?,?,?,?,?)',
        [line['id'], kind, e.key, e.value * sign, now],
      );
    }
  }

  void ensureCanCancel(String id) {
    if (rows(
      "SELECT id FROM finance_refunds WHERE order_id=? AND status!='rejected' LIMIT 1",
      [id],
    ).isNotEmpty) {
      throw const ApiFailure(
        409,
        'Objednávka už má refundáciu položiek. Zvyšok vyrieš cez podporu.',
      );
    }
  }

  Map<String, dynamic> summary(String user, String org) {
    final organization = requireOwner(user, org);
    final account = rows('SELECT * FROM finance_accounts WHERE org_id=?', [
      org,
    ]).firstOrNull;
    final lines = rows(
      'SELECT l.* FROM finance_lines l WHERE l.org_id=? ORDER BY l.created_at DESC,l.id LIMIT 500',
      [org],
    );
    final entries = <Map<String, dynamic>>[];
    for (final l in lines) {
      final a = remainingAllocation(l), o = order(l['order_id'] as String);
      final item = o.items.firstWhere((i) => i.offerId == l['offer_id']);
      final jobs = rows('SELECT * FROM finance_transfers WHERE line_id=?', [
        l['id'],
      ]);
      final paid = jobs
          .where((j) => j['status'] == 'transferred')
          .fold(
            0,
            (n, j) => n + (j['amount'] as int) - (j['reversed_amount'] as int),
          );
      final hold = rows('SELECT reason FROM finance_holds WHERE order_id=?', [
        o.id,
      ]).firstOrNull;
      final state =
          o.status == OrderStatus.cancelled &&
              rows(
                "SELECT id FROM finance_journal WHERE line_id=? AND kind='sale' LIMIT 1",
                [l['id']],
              ).isEmpty
          ? 'cancelled'
          : l['refunded'] == 1
          ? 'refunded'
          : l['refund_id'] != null
          ? 'refunding'
          : hold != null
          ? 'review'
          : jobs.any((j) => j['status'] == 'review')
          ? 'review'
          : paid == a.sellerNet
          ? 'transferred'
          : jobs.any((j) => j['status'] == 'failed')
          ? 'failed'
          : jobs.isNotEmpty
          ? 'queued'
          : l['collected_at'] != null
          ? 'eligible'
          : o.status == OrderStatus.awaitingPayment
          ? 'awaitingPayment'
          : 'awaitingPickup';
      entries.add({
        ...a.toJson(),
        'id': l['id'],
        'orderId': o.id,
        'storeId': l['store_id'],
        'store': item.store,
        'title': item.title,
        'image': item.image,
        'quantity': item.quantity,
        'refundedQuantity': item.refundCount,
        'createdAt': l['created_at'],
        'collectedAt': l['collected_at'],
        'state': state,
        'transferred': paid,
        'providerIds': jobs
            .map((j) => j['provider_id'])
            .whereType<String>()
            .toList(),
        'error':
            hold?['reason'] ??
            jobs.map((j) => j['error']).whereType<String>().firstOrNull,
      });
    }
    return {
      'organization': organization['name'],
      'organizationId': org,
      'currency': 'EUR',
      'mode': config.paymentMode,
      'connectEnabled':
          config.paymentMode == 'sandbox' || config.connectEnabled,
      'account': {
        'id': account?['account_id'],
        'ready': account?['ready'] == 1,
        'status': account?['status'] ?? 'notConnected',
        'automatic': account?['auto_enabled'] == 1,
      },
      'commissionBps': config.commissionBps,
      'delayHours': config.settlementDelayHours,
      'totals': _totals(org),
      'entryLimit': 500,
      'entries': entries,
    };
  }

  Map<String, dynamic> _totals(String org) {
    final data = rows(
      '''
      SELECT l.*, COALESCE(t.paid,0) paid,
        EXISTS(SELECT 1 FROM finance_journal j WHERE j.line_id=l.id AND j.kind='sale') posted
      FROM finance_lines l LEFT JOIN (
        SELECT line_id,SUM(amount-reversed_amount) paid FROM finance_transfers WHERE status='transferred' GROUP BY line_id
      ) t ON t.line_id=l.id WHERE l.org_id=?
    ''',
      [org],
    );
    var sales = 0,
        refunded = 0,
        commission = 0,
        seller = 0,
        paid = 0,
        pending = 0;
    for (final l in data) {
      if (l['posted'] != 1) continue;
      final a = remainingAllocation(l), transferred = l['paid'] as int;
      sales += allocation(l).goodsNet;
      paid += transferred;
      refunded += allocation(l).goodsNet - a.goodsNet;
      if (l['refunded'] == 1) {
        continue;
      }
      commission += a.commission;
      seller += a.sellerNet;
      if (l['collected_at'] != null && l['refund_id'] == null) {
        pending += a.sellerNet - transferred;
      }
    }
    return {
      'sales': sales,
      'refunded': refunded,
      'commission': commission,
      'sellerNet': seller,
      'transferred': paid,
      'eligible': math.max(0, pending),
    };
  }

  Future<void> clearHold(String id) async {
    if (!working.add(id)) {
      throw const ApiFailure(409, 'Objednávka sa práve spracúva.');
    }
    try {
      if (rows(
        "SELECT r.lot_id FROM stock_reservations r JOIN stock_lots l ON l.id=r.lot_id WHERE r.order_id=? AND r.state='held' AND (l.quality!='checked' OR l.deadline<=?)",
        [id, now],
      ).isNotEmpty) {
        throw const ApiFailure(
          409,
          'Najprv vyrieš nespôsobilú rezervovanú šaržu.',
        );
      }
      if (rows(
        "SELECT t.id FROM finance_transfers t JOIN finance_lines l ON l.id=t.line_id WHERE l.order_id=? AND t.status='review'",
        [id],
      ).isNotEmpty) {
        throw const ApiFailure(
          409,
          'Najprv spáruj nepotvrdené prevody zo Stripe.',
        );
      }
      final o = order(id);
      if (o.total > 0) {
        final payment = one('SELECT * FROM orders WHERE id=?', [id]);
        final c = await gateway.charge(
          payment['payment_session'] as String,
          payment['payment_intent'] as String?,
          o,
        );
        final expected =
            one(
                  "SELECT COALESCE(SUM(external),0) n FROM finance_refunds WHERE order_id=? AND status='completed'",
                  [id],
                )['n']
                as int;
        if ((c['refunded'] as int) > expected) {
          throw const ApiFailure(
            409,
            'Refundácie v Stripe ešte nie sú zosúladené.',
          );
        }
      }
      database.db.execute('DELETE FROM finance_holds WHERE order_id=?', [id]);
    } finally {
      working.remove(id);
    }
  }

  Future<Map<String, dynamic>> connect(
    String user,
    String org, {
    bool link = false,
  }) async {
    final organization = requireOwner(user, org), lock = 'connect:$org';
    if (!working.add(lock)) {
      throw const ApiFailure(409, 'Pripojenie sa už pripravuje.');
    }
    try {
      var row = rows('SELECT * FROM finance_accounts WHERE org_id=?', [
        org,
      ]).firstOrNull;
      if (row == null) {
        database.db.execute(
          'INSERT INTO finance_accounts(org_id,status,attempted_at,updated_at,auto_enabled) VALUES(?,?,?,?,?)',
          [org, 'creating', now, now, config.automaticSettlements ? 1 : 0],
        );
        row = one('SELECT * FROM finance_accounts WHERE org_id=?', [org]);
      }
      Map<String, dynamic> result;
      if (row['account_id'] == null) {
        if (clock().difference(DateTime.parse(row['attempted_at'] as String)) >
            const Duration(hours: 23)) {
          throw const ApiFailure(
            409,
            'Vytvorenie účtu potrebuje kontrolu podpory pred opakovaním.',
          );
        }
        result = await gateway.createAccount(
          org,
          organization['name'] as String,
          organization['contact_email'] as String,
        );
      } else {
        result = await gateway.account(row['account_id'] as String);
      }
      database.db.execute(
        'UPDATE finance_accounts SET account_id=?,ready=?,status=?,updated_at=? WHERE org_id=?',
        [
          result['id'],
          result['ready'] == true ? 1 : 0,
          result['status'],
          now,
          org,
        ],
      );
      return {
        ...result,
        if (link) 'url': await gateway.onboarding(result['id'] as String),
      };
    } finally {
      working.remove(lock);
    }
  }

  void automatic(String user, String org, bool enabled) {
    requireOwner(user, org);
    if (rows('SELECT org_id FROM finance_accounts WHERE org_id=?', [
      org,
    ]).isEmpty) {
      throw const ApiFailure(409, 'Najprv pripoj účet.');
    }
    database.db.execute(
      'UPDATE finance_accounts SET auto_enabled=? WHERE org_id=?',
      [enabled ? 1 : 0, org],
    );
  }

  void requireTrading(String? org, String? store) {
    if (rows(
          "SELECT org_id FROM platform_organizations WHERE org_id=? AND status='suspended'",
          [org],
        ).isNotEmpty ||
        rows(
          'SELECT store_id FROM platform_stores WHERE store_id=? AND paused=1',
          [store],
        ).isNotEmpty) {
      throw const ApiFailure(
        409,
        'Vyúčtovanie pozastavenej firmy alebo pobočky preveruje podpora.',
      );
    }
  }

  int queue(String user, String org) {
    requireOwner(user, org);
    return _queue(org);
  }

  int _queue(String org) {
    requireTrading(org, null);
    final account = one('SELECT * FROM finance_accounts WHERE org_id=?', [org]);
    if (account['ready'] != 1 || account['account_id'] == null) {
      throw const ApiFailure(
        409,
        'Predajca musí dokončiť overenie Stripe účtu.',
      );
    }
    var queued = 0;
    for (final l in rows(
      'SELECT * FROM finance_lines WHERE org_id=? AND collected_at IS NOT NULL AND refunded=0 AND refund_id IS NULL',
      [org],
    )) {
      if (rows(
        'SELECT store_id FROM platform_stores WHERE store_id=? AND paused=1',
        [l['store_id']],
      ).isNotEmpty) {
        continue;
      }
      final o = order(l['order_id'] as String), a = remainingAllocation(l);
      if (o.status == OrderStatus.awaitingPayment ||
          o.status == OrderStatus.cancelled ||
          clock().isBefore(
            DateTime.parse(
              l['collected_at'] as String,
            ).add(Duration(hours: config.settlementDelayHours)),
          ) ||
          rows('SELECT order_id FROM finance_holds WHERE order_id=?', [
            o.id,
          ]).isNotEmpty) {
        continue;
      }
      final active = rows(
        "SELECT * FROM finance_transfers WHERE line_id=? AND status NOT IN ('reversed','cancelled')",
        [l['id']],
      );
      final committed = active.fold<int>(
        0,
        (n, j) => n + (j['amount'] as int) - (j['reversed_amount'] as int),
      );
      final outstanding = math.max(0, a.sellerNet - committed);
      final charged = active
          .where((j) => (j['part'] as String).startsWith('charge'))
          .fold<int>(
            0,
            (n, j) => n + (j['amount'] as int) - (j['reversed_amount'] as int),
          );
      final source = math.min(outstanding, math.max(0, a.external - charged)),
          balance = outstanding - source;
      final epoch =
          one(
                "SELECT COUNT(*) n FROM finance_refunds WHERE order_id=? AND status='completed'",
                [o.id],
              )['n']
              as int;
      for (final p in {'charge': source, 'balance': balance}.entries) {
        if (p.value == 0) continue;
        final part = '${p.key}${epoch == 0 ? '' : '-$epoch'}';
        final id = hashToken('${l['id']}:$part');
        if (rows('SELECT id FROM finance_transfers WHERE id=?', [
          id,
        ]).isNotEmpty) {
          continue;
        }
        database.db.execute(
          'INSERT INTO finance_transfers(id,line_id,part,amount,destination) VALUES(?,?,?,?,?)',
          [id, l['id'], part, p.value, account['account_id']],
        );
        queued++;
      }
    }
    return queued;
  }

  Future<void> drain() async {
    if (_draining) return;
    _draining = true;
    try {
      {
        for (final a in rows(
          'SELECT org_id FROM finance_accounts WHERE ready=1 AND auto_enabled=1',
        )) {
          try {
            _queue(a['org_id'] as String);
          } catch (_) {
            /* visible through account state */
          }
        }
      }
      for (final h in rows(
        "SELECT order_id FROM finance_holds WHERE reason LIKE '%sporu v Stripe%'",
      )) {
        try {
          await reverseDisputed(h['order_id'] as String);
        } catch (_) {
          /* persistent hold is visible to support */
        }
      }
      for (final job in rows(
        "SELECT t.*,l.order_id,l.refunded,l.refund_id FROM finance_transfers t JOIN finance_lines l ON l.id=t.line_id WHERE t.status IN ('queued','processing','failed') ORDER BY COALESCE(t.last_attempt_at,''),t.rowid LIMIT 20",
      )) {
        final id = job['order_id'] as String;
        if (job['refunded'] == 1 ||
            job['refund_id'] != null ||
            !working.add(id)) {
          continue;
        }
        try {
          await _transfer(job);
        } catch (e) {
          database.db.execute(
            "UPDATE finance_transfers SET status=CASE WHEN status='review' THEN status ELSE 'failed' END,error=? WHERE id=?",
            [_error(e), job['id']],
          );
        } finally {
          working.remove(id);
        }
      }
    } finally {
      _draining = false;
    }
  }

  String _error(Object e) => e is ApiFailure
      ? e.message
      : 'Poskytovateľ nepotvrdil operáciu. Skús obnoviť stav.';
  Future<void> _transfer(Map<String, dynamic> job) async {
    database.db.execute(
      'UPDATE finance_transfers SET last_attempt_at=? WHERE id=?',
      [now, job['id']],
    );
    final l = one('SELECT * FROM finance_lines WHERE id=?', [job['line_id']]),
        o = order(l['order_id'] as String);
    if (rows('SELECT order_id FROM finance_holds WHERE order_id=?', [
      o.id,
    ]).isNotEmpty) {
      throw const ApiFailure(409, 'Vyúčtovanie preveruje podpora.');
    }
    final account = await gateway.account(job['destination'] as String);
    if (account['ready'] != true) {
      database.db.execute(
        'UPDATE finance_accounts SET ready=0,status=?,updated_at=? WHERE account_id=?',
        [account['status'], now, job['destination']],
      );
      throw const ApiFailure(
        409,
        'Stripe účet predajcu potrebuje doplniť údaje.',
      );
    }
    if (job['attempted_at'] != null &&
        clock().difference(DateTime.parse(job['attempted_at'] as String)) >
            const Duration(hours: 23)) {
      database.db.execute(
        "UPDATE finance_transfers SET status='review' WHERE id=?",
        [job['id']],
      );
      throw const ApiFailure(
        409,
        'Nepotvrdený prevod potrebuje kontrolu podpory. Automaticky sa neopakuje.',
      );
    }
    final payment = one('SELECT * FROM orders WHERE id=?', [o.id]);
    String? source = job['source_charge'] as String?;
    if (o.total > 0) {
      final c = await gateway.charge(
        payment['payment_session'] as String,
        payment['payment_intent'] as String?,
        o,
      );
      final refunded =
          one(
                "SELECT COALESCE(SUM(external),0) n FROM finance_refunds WHERE order_id=? AND status='completed'",
                [o.id],
              )['n']
              as int;
      if ((c['refunded'] as int) > refunded) {
        hold(o.id, 'Stripe eviduje refundáciu, ktorá čaká na zosúladenie.');
        throw const ApiFailure(409, 'Platbu preveruje podpora.');
      }
      if ((job['part'] as String).startsWith('charge')) {
        source = c['id'] as String;
      }
    }
    database.db.execute(
      "UPDATE finance_transfers SET status='processing',attempted_at=COALESCE(attempted_at,?),source_charge=?,error=NULL WHERE id=?",
      [now, source, job['id']],
    );
    requireTrading(l['org_id'] as String?, l['store_id'] as String?);
    final provider = await gateway.transfer(
      job['id'] as String,
      job['destination'] as String,
      job['amount'] as int,
      o.id,
      charge: source,
    );
    database.transaction(() {
      database.db.execute(
        "UPDATE finance_transfers SET status='transferred',provider_id=?,error=NULL WHERE id=?",
        [provider, job['id']],
      );
      _transferJournal(job, false);
    });
  }

  void _transferJournal(Map<String, dynamic> job, bool reverse) {
    final kind = '${reverse ? 'reversal' : 'transfer'}:${job['id']}';
    final sign = reverse ? -1 : 1, amount = job['amount'] as int;
    for (final entry in {
      'seller_payable': amount,
      (job['part'] as String).startsWith('charge')
              ? 'card_clearing'
              : 'platform_cash':
          -amount,
    }.entries) {
      database.db.execute(
        'INSERT OR IGNORE INTO finance_journal(line_id,kind,account,amount,created_at) VALUES(?,?,?,?,?)',
        [job['line_id'], kind, entry.key, entry.value * sign, now],
      );
    }
  }

  Future<void> reconcileTransfer(String id, String provider) async {
    final job = one(
      'SELECT t.*,l.order_id FROM finance_transfers t JOIN finance_lines l ON l.id=t.line_id WHERE t.id=?',
      [id],
    );
    final lock = job['order_id'] as String;
    if (!working.add(lock)) {
      throw const ApiFailure(409, 'Objednávka sa práve spracúva.');
    }
    try {
      final actual = await gateway.lookupTransfer(provider);
      final destination = actual['destination'] is Map
          ? (actual['destination'] as Map)['id']
          : actual['destination'];
      if (actual['id'] != provider ||
          actual['amount'] != job['amount'] ||
          actual['currency'] != 'eur' ||
          destination != job['destination'] ||
          (actual['metadata'] as Map?)?['settlement_job'] != id ||
          !{
            job['reversed_amount'],
            job['amount'],
          }.contains(actual['amount_reversed'] ?? 0)) {
        throw const ApiFailure(
          409,
          'Stripe prevod nesúhlasí s položkou vyúčtovania.',
        );
      }
      final reversed = actual['amount_reversed'] == job['amount'];
      database.transaction(() {
        database.db.execute(
          'UPDATE finance_transfers SET provider_id=?,status=?,reversal_id=?,reversed_amount=?,error=NULL WHERE id=?',
          [
            provider,
            reversed ? 'reversed' : 'transferred',
            reversed ? 'verified_in_stripe' : null,
            actual['amount_reversed'] ?? 0,
            id,
          ],
        );
        _transferJournal(job, false);
        final extra =
            (actual['amount_reversed'] as int? ?? 0) -
            (job['reversed_amount'] as int);
        if (extra > 0) {
          _transferJournal({
            ...job,
            'id': '${job['id']}:reconciled:${actual['amount_reversed']}',
            'amount': extra,
          }, true);
        }
      });
    } finally {
      working.remove(lock);
    }
  }

  Future<void> reverseDisputed(String id) async {
    hold(id, 'Platba je predmetom sporu v Stripe. Vyúčtovanie je pozastavené.');
    if (!working.add(id)) return;
    try {
      for (final job in rows(
        "SELECT t.* FROM finance_transfers t JOIN finance_lines l ON l.id=t.line_id WHERE l.order_id=? AND t.status='transferred'",
        [id],
      )) {
        final reversed = await gateway.reverse(
          'dispute-${job['id']}',
          job['provider_id'] as String,
          amount: (job['amount'] as int) - (job['reversed_amount'] as int),
        );
        database.transaction(() {
          database.db.execute(
            "UPDATE finance_transfers SET status='reversed',reversed_amount=amount,reversal_id=? WHERE id=?",
            [reversed, job['id']],
          );
          _transferJournal({
            ...job,
            'id': '${job['id']}:dispute',
            'amount': (job['amount'] as int) - (job['reversed_amount'] as int),
          }, true);
        });
      }
    } finally {
      working.remove(id);
    }
  }

  void hold(String id, String reason) => database.db.execute(
    'INSERT INTO finance_holds VALUES(?,?,?) ON CONFLICT(order_id) DO UPDATE SET reason=excluded.reason',
    [id, reason, now],
  );

  /// Refunds immutable unit allocations with durable provider operations.
  Future<Map<String, dynamic>> refund(
    String actor,
    String id,
    Map<String, dynamic> body,
    void Function(RescueOrder, List<String>, int, int, String) apply,
  ) => refundUnits(actor, id, body, apply);

  Map<String, dynamic> export(
    String user,
    String org,
    String? from,
    String? to,
  ) {
    requireOwner(user, org);
    DateTime parse(String? v, DateTime fallback) {
      if (v == null || v.isEmpty) return fallback;
      if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(v)) {
        throw const ApiFailure(400, 'Použi dátum RRRR-MM-DD.');
      }
      final d = DateTime.tryParse('${v}T00:00:00Z');
      if (d == null || d.toIso8601String().substring(0, 10) != v) {
        throw const ApiFailure(400, 'Neplatný dátum.');
      }
      return d;
    }

    final end = parse(to, clock().toUtc().add(const Duration(days: 1)));
    final start = parse(from, end.subtract(const Duration(days: 31)));
    if (!end.isAfter(start) ||
        end.difference(start) > const Duration(days: 366)) {
      throw const ApiFailure(
        400,
        'Vyber obdobie do 366 dní; koncový dátum sa nezahŕňa.',
      );
    }
    final data = rows(
      'SELECT l.*,j.kind,j.account,j.amount,j.created_at posted_at FROM finance_journal j JOIN finance_lines l ON l.id=j.line_id WHERE l.org_id=? AND j.created_at>=? AND j.created_at<? ORDER BY j.id',
      [org, start.toIso8601String(), end.toIso8601String()],
    );
    String cell(Object? v) {
      var s = v?.toString() ?? '';
      if (RegExp(r'^[=+@\-\t\r]').hasMatch(s)) s = "'$s";
      return '"${s.replaceAll('"', '""')}"';
    }

    final output = <List<Object?>>[
      [
        'document',
        'order_id',
        'offer_id',
        'organization_id',
        'store_id',
        'kind',
        'account',
        'debit_cents',
        'credit_cents',
        'currency',
        'posted_at',
        'vat_status',
      ],
    ];
    for (final r in data) {
      final amount = r['amount'] as int;
      output.add([
        'NVP-${(r['order_id'] as String).substring(0, 8).toUpperCase()}',
        r['order_id'],
        r['offer_id'],
        org,
        r['store_id'],
        r['kind'],
        r['account'],
        amount > 0 ? amount : 0,
        amount < 0 ? -amount : 0,
        'EUR',
        r['posted_at'],
        'not_determined',
      ]);
    }
    final transfers = rows(
      'SELECT t.id,t.provider_id,t.amount,t.status,t.reversal_id,l.order_id,l.offer_id FROM finance_transfers t JOIN finance_lines l ON l.id=t.line_id WHERE l.org_id=? AND l.created_at>=? AND l.created_at<?',
      [org, start.toIso8601String(), end.toIso8601String()],
    );
    return {
      'filename': 'nevyhadzuj-${start.toIso8601String().substring(0, 10)}.csv',
      'contentType': 'text/csv',
      'content':
          '\uFEFF${output.map((r) => r.map(cell).join(';')).join('\r\n')}\r\n',
      'transfers': transfers,
      'note':
          'Účtovný podklad v centoch. Nejde o fiškálny ani daňový doklad; DPH nie je automaticky určená.',
      'from': start.toIso8601String(),
      'toExclusive': end.toIso8601String(),
    };
  }
}

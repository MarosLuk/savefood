part of 'merchant.dart';

extension MerchantWarehouse on MerchantService {
  MerchantStore _transferBranch(String id) => MerchantStore.fromJson(
    database.decode(
      _one('SELECT payload FROM merchant_stores WHERE id=?', [id])['payload']
          as String,
    ),
  );
  void propagateLotQuality(
    String id,
    String quality,
    String actor,
    String reason,
  ) {
    if (quality == 'checked') return;
    final children = _rows(
      '''WITH RECURSIVE descendants(id) AS (
      SELECT destination_lot FROM stock_transfers WHERE source_lot=? AND destination_lot IS NOT NULL
      UNION SELECT t.destination_lot FROM stock_transfers t JOIN descendants d ON t.source_lot=d.id WHERE t.destination_lot IS NOT NULL)
      SELECT l.* FROM stock_lots l JOIN descendants d ON d.id=l.id''',
      [id],
    );
    for (final lot in children) {
      if (lot['quality'] == 'withdrawn' || lot['quality'] == quality) continue;
      database.db.execute(
        'UPDATE stock_lots SET quality=?,version=version+1 WHERE id=?',
        [quality, lot['id']],
      );
      _movement(
        lot['store_id'] as String,
        lot['id'] as String,
        actor,
        'quality',
        0,
        0,
        'Prepojená šarža $id · $reason',
      );
    }
  }

  void initializeWarehouse() => database.db.execute('''
    CREATE TABLE IF NOT EXISTS stock_counts(id TEXT PRIMARY KEY,store_id TEXT NOT NULL REFERENCES merchant_stores(id),
      actor TEXT NOT NULL REFERENCES users(id),status TEXT NOT NULL DEFAULT 'draft',reason TEXT NOT NULL,
      version INTEGER NOT NULL DEFAULT 1,created_at TEXT NOT NULL,posted_at TEXT);
    CREATE TABLE IF NOT EXISTS stock_count_lines(count_id TEXT NOT NULL REFERENCES stock_counts(id),lot_id TEXT NOT NULL REFERENCES stock_lots(id),
      expected INTEGER NOT NULL,lot_version INTEGER NOT NULL,counted INTEGER,PRIMARY KEY(count_id,lot_id));
    CREATE TABLE IF NOT EXISTS stock_transfers(id TEXT PRIMARY KEY,source_store TEXT NOT NULL REFERENCES merchant_stores(id),
      destination_store TEXT NOT NULL REFERENCES merchant_stores(id),source_lot TEXT NOT NULL REFERENCES stock_lots(id),
      quantity INTEGER NOT NULL,status TEXT NOT NULL DEFAULT 'draft',reason TEXT NOT NULL,version INTEGER NOT NULL DEFAULT 1,
      created_at TEXT NOT NULL,dispatched_at TEXT,received_at TEXT,destination_lot TEXT REFERENCES stock_lots(id));
    CREATE TABLE IF NOT EXISTS warehouse_audit(id TEXT PRIMARY KEY,operation_id TEXT NOT NULL,actor TEXT NOT NULL,
      event TEXT NOT NULL,detail TEXT NOT NULL,created_at TEXT NOT NULL);
    CREATE INDEX IF NOT EXISTS stock_counts_store ON stock_counts(store_id,created_at);
    CREATE INDEX IF NOT EXISTS stock_transfers_stores ON stock_transfers(source_store,destination_store);
  ''');

  void _warehouseAudit(String id, String user, String event, String detail) =>
      database.db.execute('INSERT INTO warehouse_audit VALUES(?,?,?,?,?,?)', [
        _id(),
        id,
        user,
        event,
        detail,
        _now,
      ]);
  List<Map<String, dynamic>> _warehouseHistory(String id) => _rows(
    'SELECT a.event,a.detail,a.created_at,u.name actor FROM warehouse_audit a LEFT JOIN users u ON u.id=a.actor WHERE operation_id=? ORDER BY a.rowid DESC LIMIT 100',
    [id],
  );

  Map<String, dynamic> warehouse(
    String user,
    String store, {
    int? beforeCounts,
    int? beforeTransfers,
  }) {
    final branch = requireStore(user, store);
    final counts = _rows(
      'SELECT *,rowid cursor FROM stock_counts WHERE store_id=? AND (? IS NULL OR rowid<?) ORDER BY rowid DESC LIMIT 101',
      [store, beforeCounts, beforeCounts],
    );
    final transfers = _rows(
      'SELECT t.*,t.rowid cursor,p.payload product,s.payload source,d.payload destination FROM stock_transfers t JOIN stock_lots l ON l.id=t.source_lot JOIN stock_products p ON p.id=l.product_id JOIN merchant_stores s ON s.id=t.source_store JOIN merchant_stores d ON d.id=t.destination_store WHERE (source_store=? OR destination_store=?) AND (? IS NULL OR t.rowid<?) ORDER BY t.rowid DESC LIMIT 101',
      [store, store, beforeTransfers, beforeTransfers],
    );
    return {
      'destinations': _rows(
        'SELECT payload FROM merchant_stores WHERE org_id=? AND id!=?',
        [branch.organizationId, store],
      ).map((r) => database.decode(r['payload'] as String)).toList(),
      'counts': counts.take(100).toList(),
      'countsNext': counts.length > 100 ? counts[99]['cursor'] : null,
      'transfersNext': transfers.length > 100 ? transfers[99]['cursor'] : null,
      'transfers': transfers
          .take(100)
          .map(
            (r) => {
              ...r,
              'product': database.decode(r['product'] as String),
              'source': database.decode(r['source'] as String),
              'destination': database.decode(r['destination'] as String),
            },
          )
          .toList(),
    };
  }

  Map<String, dynamic> countDetail(
    String user,
    String id, {
    int? before,
    String search = '',
  }) {
    if (search.length > 150 || before != null && before < 1) {
      throw const ApiFailure(400, 'Neplatné vyhľadávanie alebo stránka.');
    }
    final c = _one('SELECT * FROM stock_counts WHERE id=?', [id]);
    final store = requireStore(user, c['store_id'] as String);
    final lines = _rows(
      "SELECT c.*,c.rowid cursor,l.on_hand,l.version current_version,l.lot_code,l.deadline,l.quality,p.payload product FROM stock_count_lines c JOIN stock_lots l ON l.id=c.lot_id JOIN stock_products p ON p.id=l.product_id WHERE count_id=? AND (? IS NULL OR c.rowid>?) AND (?='' OR instr(normalized(l.lot_code||' '||p.payload),normalized(?))>0) ORDER BY c.rowid LIMIT 101",
      [id, before, before, search, search],
    );
    final stats = _one(
      'SELECT COUNT(*) total,COALESCE(SUM(c.counted IS NOT NULL),0) counted,COALESCE(SUM(c.counted IS NULL),0) missing,COALESCE(SUM(c.counted!=c.expected),0) changed,COALESCE(SUM(c.lot_version!=l.version OR c.expected!=l.on_hand),0) stale FROM stock_count_lines c JOIN stock_lots l ON l.id=c.lot_id WHERE c.count_id=?',
      [id],
    );
    return {
      ...c,
      'store': store.toJson(),
      'audit': _warehouseHistory(id),
      'lineStats': stats,
      'linesNext': lines.length > 100 ? lines[99]['cursor'].toString() : null,
      'lines': lines
          .take(100)
          .map(
            (l) => {
              ...l,
              'product': database.decode(l['product'] as String),
              'reserved': _held(l['lot_id'] as String),
              'stale':
                  l['lot_version'] != l['current_version'] ||
                  l['expected'] != l['on_hand'],
            },
          )
          .toList(),
    };
  }

  Map<String, dynamic> createCount(
    String user,
    Map<String, dynamic> b,
  ) => database.transaction(() {
    final store = requireStore(user, _text(b, 'storeId'));
    final reason = _text(b, 'reason', min: 3, max: 300);
    if (_rows(
      "SELECT id FROM stock_counts WHERE store_id=? AND status='draft'",
      [store.id],
    ).isNotEmpty) {
      throw const ApiFailure(
        409,
        'Prevádzka už má rozpracovanú inventúru. Najprv ju dokonči alebo zruš.',
      );
    }
    final id = _id();
    database.db.execute(
      'INSERT INTO stock_counts(id,store_id,actor,reason,created_at) VALUES(?,?,?,?,?)',
      [id, store.id, user, reason, _now],
    );
    _rebaseCount(id, store.id);
    _warehouseAudit(id, user, 'created', reason);
    return countDetail(user, id);
  });
  void _rebaseCount(String id, String store) {
    for (final lot in _rows('SELECT * FROM stock_lots WHERE store_id=?', [
      store,
    ])) {
      database.db.execute(
        '''INSERT INTO stock_count_lines VALUES(?,?,?,?,NULL)
        ON CONFLICT(count_id,lot_id) DO UPDATE SET counted=CASE WHEN expected!=excluded.expected OR lot_version!=excluded.lot_version THEN NULL ELSE counted END,
          expected=excluded.expected,lot_version=excluded.lot_version''',
        [id, lot['id'], lot['on_hand'], lot['version']],
      );
    }
  }

  Map<String, dynamic> updateCount(
    String user,
    String id,
    Map<String, dynamic> b,
  ) => database.transaction(() {
    final c = _one('SELECT * FROM stock_counts WHERE id=?', [id]);
    requireStore(user, c['store_id'] as String);
    if (c['status'] != 'draft' || b['version'] != c['version']) {
      throw const ApiFailure(
        409,
        'Inventúra sa zmenila alebo je ukončená. Obnov údaje.',
      );
    }
    final action = _text(b, 'action');
    if (action == 'save') {
      final lines = (b['lines'] as List).map(merchantMap).toList();
      if (lines.isEmpty ||
          lines.length > 200 ||
          lines.map((l) => l['lotId']).toSet().length != lines.length) {
        throw const ApiFailure(400, 'Ulož 1 až 200 rôznych šarží naraz.');
      }
      for (final line in lines) {
        final lot = _text(line, 'lotId'),
            qty = _integer(line, 'counted', 0, 1000000);
        _one('SELECT * FROM stock_count_lines WHERE count_id=? AND lot_id=?', [
          id,
          lot,
        ]);
        database.db.execute(
          'UPDATE stock_count_lines SET counted=? WHERE count_id=? AND lot_id=?',
          [qty, id, lot],
        );
      }
      _warehouseAudit(id, user, 'counted', 'Uložené počty: ${lines.length}');
    } else if (action == 'rebase') {
      _rebaseCount(id, c['store_id'] as String);
      _warehouseAudit(
        id,
        user,
        'rebased',
        'Zmenené šarže vyžadujú nové prepočítanie.',
      );
    } else if (action == 'post') {
      requireStore(user, c['store_id'] as String, manage: true);
      final lines = _rows(
        'SELECT c.*,l.on_hand,l.version FROM stock_count_lines c JOIN stock_lots l ON l.id=c.lot_id WHERE count_id=?',
        [id],
      );
      final added = _rows(
        'SELECT id FROM stock_lots WHERE store_id=? AND id NOT IN (SELECT lot_id FROM stock_count_lines WHERE count_id=?)',
        [c['store_id'], id],
      );
      if (added.isNotEmpty ||
          lines.any(
            (l) =>
                l['counted'] == null ||
                l['expected'] != l['on_hand'] ||
                l['lot_version'] != l['version'],
          )) {
        throw const ApiFailure(
          409,
          'Doplň všetky počty. Zmenené alebo nové šarže najprv obnov a znovu prepočítaj.',
        );
      }
      for (final line in lines) {
        final next = line['counted'] as int, lot = line['lot_id'] as String;
        if (next < _held(lot)) {
          throw const ApiFailure(
            409,
            'Skutočný počet nekryje rezervácie. Najprv vyrieš dotknuté objednávky.',
          );
        }
        final delta = next - (line['on_hand'] as int);
        if (delta != 0) {
          database.db.execute(
            'UPDATE stock_lots SET on_hand=?,version=version+1 WHERE id=?',
            [next, lot],
          );
          _movement(
            c['store_id'] as String,
            lot,
            user,
            'inventory',
            delta,
            0,
            'Inventúra $id · ${c['reason']}',
          );
        }
      }
      database.db.execute(
        "UPDATE stock_counts SET status='posted',posted_at=? WHERE id=?",
        [_now, id],
      );
      _warehouseAudit(
        id,
        user,
        'posted',
        'Inventúra bola zaúčtovaná do skladu.',
      );
    } else if (action == 'cancel') {
      requireStore(user, c['store_id'] as String, manage: true);
      database.db.execute(
        "UPDATE stock_counts SET status='cancelled' WHERE id=?",
        [id],
      );
      _warehouseAudit(
        id,
        user,
        'cancelled',
        _text(b, 'reason', min: 3, max: 300),
      );
    } else {
      throw const ApiFailure(400, 'Neplatná akcia inventúry.');
    }
    database.db.execute(
      'UPDATE stock_counts SET version=version+1 WHERE id=?',
      [id],
    );
    return countDetail(user, id);
  });

  Map<String, dynamic> transferDetail(String user, String id) {
    final t = _one('SELECT * FROM stock_transfers WHERE id=?', [id]);
    final source = _transferBranch(t['source_store'] as String),
        destination = _transferBranch(t['destination_store'] as String);
    final from = canAccessStore(user, source.id),
        to = canAccessStore(user, destination.id);
    if (!from && !to) {
      throw const ApiFailure(403, 'Presun nepatrí tvojej pobočke.');
    }
    final lot = _lot(t['source_lot'] as String);
    return {
      ...t,
      'source': source.toJson(),
      'destination': destination.toJson(),
      'lot': {
        ..._lotJson(lot),
        if (!from) 'onHand': 0,
        if (!from) 'reserved': 0,
      },
      'sourceAvailable': from
          ? (lot['on_hand'] as int) - _held(lot['id'] as String)
          : null,
      'canDispatch': from,
      'canReceive': to,
      'product': _product(lot['product_id'] as String).toJson(),
      'audit': _warehouseHistory(id),
    };
  }

  Map<String, dynamic> createTransfer(
    String user,
    Map<String, dynamic> b,
  ) => database.transaction(() {
    final lot = _lot(_text(b, 'lotId'));
    final from = requireStore(user, lot['store_id'] as String, manage: true),
        to = _transferBranch(_text(b, 'destinationStoreId'));
    if (from.organizationId != to.organizationId || from.id == to.id) {
      throw const ApiFailure(400, 'Vyber inú pobočku tej istej firmy.');
    }
    final qty = _amount(
          b,
          'quantity',
          _product(lot['product_id'] as String).unit,
          1,
          1000000,
        ),
        reason = _text(b, 'reason', min: 3, max: 300);
    if (qty > (lot['on_hand'] as int) - _held(lot['id'] as String)) {
      throw const ApiFailure(409, 'Na presun nie je dostatok voľných kusov.');
    }
    final id = _id();
    database.db.execute(
      'INSERT INTO stock_transfers(id,source_store,destination_store,source_lot,quantity,reason,created_at) VALUES(?,?,?,?,?,?,?)',
      [id, from.id, to.id, lot['id'], qty, reason, _now],
    );
    _warehouseAudit(id, user, 'created', reason);
    return transferDetail(user, id);
  });
  Map<String, dynamic> updateTransfer(
    String user,
    String id,
    Map<String, dynamic> b,
  ) => database.transaction(() {
    final t = _one('SELECT * FROM stock_transfers WHERE id=?', [id]);
    final source = _transferBranch(t['source_store'] as String),
        destination = _transferBranch(t['destination_store'] as String);
    if (!canAccessStore(user, source.id) &&
        !canAccessStore(user, destination.id)) {
      throw const ApiFailure(403, 'Presun nepatrí tvojej pobočke.');
    }
    if (b['version'] != t['version']) {
      throw const ApiFailure(
        409,
        'Presun medzitým zmenil kolega. Obnov údaje.',
      );
    }
    final action = _text(b, 'action'),
        reason = _text(b, 'reason', min: 3, max: 300),
        qty = t['quantity'] as int;
    final lot = _lot(t['source_lot'] as String);
    if (action == 'dispatch') {
      requireStore(user, source.id, manage: true);
      if (t['status'] != 'draft') {
        throw const ApiFailure(409, 'Odoslať možno iba koncept presunu.');
      }
      if (b['lotVersion'] != lot['version']) {
        throw const ApiFailure(409, 'Zdrojová šarža sa zmenila. Obnov údaje.');
      }
      if (lot['quality'] != 'checked' ||
          !DateTime.parse(lot['deadline'] as String).isAfter(clock())) {
        throw const ApiFailure(
          409,
          'Presúvať možno iba skontrolované zásoby pred termínom.',
        );
      }
      if (qty > (lot['on_hand'] as int) - _held(lot['id'] as String)) {
        throw const ApiFailure(
          409,
          'Kusy kryjú rezervácie alebo už nie sú na sklade.',
        );
      }
      database.db.execute(
        'UPDATE stock_lots SET on_hand=on_hand-?,version=version+1 WHERE id=?',
        [qty, lot['id']],
      );
      database.db.execute(
        "UPDATE stock_transfers SET status='inTransit',dispatched_at=? WHERE id=?",
        [_now, id],
      );
      _movement(
        source.id,
        lot['id'] as String,
        user,
        'transfer_out',
        -qty,
        0,
        'Presun $id · $reason',
      );
    } else if (action == 'receive') {
      requireStore(user, destination.id);
      if (t['status'] != 'inTransit') {
        throw const ApiFailure(409, 'Prijať možno iba tovar na ceste.');
      }
      final checked = b['checked'] == true;
      if (checked) requireStore(user, destination.id, manage: true);
      if (checked &&
          (lot['quality'] != 'checked' ||
              !DateTime.parse(lot['deadline'] as String).isAfter(clock()))) {
        throw const ApiFailure(
          409,
          'Zadržaný tovar alebo tovar po termíne nemožno prijať do predaja.',
        );
      }
      final target = _id(),
          code =
              '${(lot['lot_code'] as String).substring(0, math.min(60, (lot['lot_code'] as String).length))} · P$id';
      database.db.execute(
        'INSERT INTO stock_lots(id,store_id,product_id,lot_code,on_hand,deadline,date_type,quality) VALUES(?,?,?,?,?,?,?,?)',
        [
          target,
          destination.id,
          lot['product_id'],
          code,
          qty,
          lot['deadline'],
          lot['date_type'],
          lot['quality'] == 'withdrawn'
              ? 'withdrawn'
              : checked
              ? 'checked'
              : 'quarantine',
        ],
      );
      database.db.execute(
        "UPDATE stock_transfers SET status='received',received_at=?,destination_lot=? WHERE id=?",
        [_now, target, id],
      );
      _movement(
        destination.id,
        target,
        user,
        'transfer_in',
        qty,
        0,
        'Presun $id · $reason',
      );
    } else if (action == 'return') {
      requireStore(user, source.id, manage: true);
      if (t['status'] != 'inTransit' || b['physicallyReturned'] != true) {
        throw const ApiFailure(409, 'Potvrď fyzický návrat tovaru na ceste.');
      }
      // Separate quarantine lot: returning goods must not quarantine already held stock.
      final target = _id();
      database.db.execute(
        'INSERT INTO stock_lots(id,store_id,product_id,lot_code,on_hand,deadline,date_type,quality) VALUES(?,?,?,?,?,?,?,?)',
        [
          target,
          source.id,
          lot['product_id'],
          'Návrat $id',
          qty,
          lot['deadline'],
          lot['date_type'],
          lot['quality'] == 'withdrawn' ? 'withdrawn' : 'quarantine',
        ],
      );
      database.db.execute(
        "UPDATE stock_transfers SET status='returned',received_at=?,destination_lot=? WHERE id=?",
        [_now, target, id],
      );
      _movement(
        source.id,
        target,
        user,
        'transfer_return',
        qty,
        0,
        'Presun $id · $reason',
      );
    } else if (action == 'cancel') {
      requireStore(user, source.id, manage: true);
      if (t['status'] != 'draft') {
        throw const ApiFailure(
          409,
          'Tovar na ceste treba fyzicky prijať alebo vrátiť.',
        );
      }
      database.db.execute(
        "UPDATE stock_transfers SET status='cancelled' WHERE id=?",
        [id],
      );
    } else {
      throw const ApiFailure(400, 'Neplatná akcia presunu.');
    }
    database.db.execute(
      'UPDATE stock_transfers SET version=version+1 WHERE id=?',
      [id],
    );
    _warehouseAudit(id, user, action, reason);
    return transferDetail(user, id);
  });
}

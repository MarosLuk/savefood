part of 'merchant.dart';

extension StockConnector on MerchantService {
  void initializeConnector() {
    database.db.execute(
      '''CREATE TABLE IF NOT EXISTS stock_changes(sequence INTEGER PRIMARY KEY AUTOINCREMENT,movement TEXT UNIQUE,store_id TEXT NOT NULL,lot_id TEXT NOT NULL,origin TEXT NOT NULL,payload TEXT NOT NULL,created_at TEXT NOT NULL);
      CREATE INDEX IF NOT EXISTS stock_changes_store ON stock_changes(store_id,sequence);
      CREATE TABLE IF NOT EXISTS stock_delivery(integration_id TEXT PRIMARY KEY REFERENCES stock_integrations(id),acknowledged INTEGER NOT NULL DEFAULT 0,delivered INTEGER NOT NULL DEFAULT 0,updated_at TEXT NOT NULL);''',
    );
    for (final row in _rows(
      'SELECT i.id,i.store_id FROM stock_integrations i LEFT JOIN stock_delivery d ON d.integration_id=i.id WHERE d.integration_id IS NULL',
    )) {
      initializeDelivery(row['id'] as String, row['store_id'] as String);
    }
  }

  void initializeDelivery(String id, String store) {
    final after = _one(
      'SELECT COALESCE(MAX(sequence),0) n FROM stock_changes',
      [],
    )['n'];
    database.db.execute(
      'INSERT OR IGNORE INTO stock_delivery VALUES(?,?,?,?)',
      [id, after, after, _now],
    );
    for (final lot in _rows('SELECT id FROM stock_lots WHERE store_id=?', [
      store,
    ])) {
      recordChange(
        store,
        lot['id'] as String,
        'bootstrap',
        'snapshot',
        0,
        0,
        'Úvodné zosúladenie',
        null,
      );
    }
  }

  void recordChange(
    String store,
    String lot,
    String actor,
    String kind,
    int physical,
    int reserved,
    String reason,
    String? movement,
  ) {
    final l = _lot(lot), p = _product(l['product_id'] as String);
    final payload = {
      'schema': 'nevyhadzuj.stock.v1',
      'storeId': store,
      'sku': p.sku,
      'productId': p.id,
      'unit': p.unit.name,
      'scale': p.unit.scale,
      'kind': kind,
      'physicalDelta': physical,
      'reservedDelta': reserved,
      'reason': reason,
      'state': {
        ..._lotJson(l),
        'onHandDisplay': p.unit.formatAmount(l['on_hand'] as int),
      },
    };
    database.db.execute(
      'INSERT INTO stock_changes(movement,store_id,lot_id,origin,payload,created_at) VALUES(?,?,?,?,?,?)',
      [movement, store, lot, actor, jsonEncode(payload), _now],
    );
  }

  Map<String, dynamic> changes(
    String? authorization, {
    int? after,
  }) => database.transaction(() {
    final i = _integration(authorization),
        delivery = _one('SELECT * FROM stock_delivery WHERE integration_id=?', [
          i['id'],
        ]);
    final cursor = after ?? delivery['acknowledged'] as int;
    if (cursor < 0 || cursor > (delivery['delivered'] as int)) {
      throw const ApiFailure(
        409,
        'Kurzor musí nadväzovať na už doručenú stránku.',
      );
    }
    final rows = _rows(
      'SELECT * FROM stock_changes WHERE store_id=? AND sequence>? ORDER BY sequence LIMIT 201',
      [i['store_id'], cursor],
    );
    final page = rows.take(200).toList(),
        through = page.lastOrNull?['sequence'] ?? cursor;
    database.db.execute(
      'UPDATE stock_delivery SET delivered=MAX(delivered,?),updated_at=? WHERE integration_id=?',
      [through, _now, i['id']],
    );
    return {
      'schema': 'nevyhadzuj.stock.v1',
      'integrationId': i['id'],
      'storeId': i['store_id'],
      'acknowledged': delivery['acknowledged'],
      'through': through,
      'hasMore': rows.length > 200,
      'events': page
          .map(
            (r) => {
              'id': r['sequence'].toString(),
              'sequence': r['sequence'],
              'createdAt': r['created_at'],
              'echo': r['origin'] == 'integration:${i['id']}',
              ...database.decode(r['payload'] as String),
            },
          )
          .toList(),
    };
  });
  Map<String, dynamic> acknowledge(
    String? authorization,
    Map<String, dynamic> b,
  ) => database.transaction(() {
    final i = _integration(authorization),
        d = _one('SELECT * FROM stock_delivery WHERE integration_id=?', [
          i['id'],
        ]);
    final through = _integer(b, 'through', 0, 9007199254740991);
    if (through > (d['delivered'] as int)) {
      throw const ApiFailure(
        409,
        'Najprv načítaj všetky potvrdzované udalosti.',
      );
    }
    database.db.execute(
      'UPDATE stock_delivery SET acknowledged=MAX(acknowledged,?),updated_at=? WHERE integration_id=?',
      [through, _now, i['id']],
    );
    database.db.execute(
      'UPDATE stock_integrations SET last_seen=? WHERE id=?',
      [_now, i['id']],
    );
    return {'acknowledged': math.max(through, d['acknowledged'] as int)};
  });
}

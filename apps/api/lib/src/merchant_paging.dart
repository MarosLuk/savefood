part of 'merchant.dart';

extension MerchantPaging on MerchantService {
  void initializePaging() => database.db.execute('''
    CREATE TABLE IF NOT EXISTS stock_product_search(product_id TEXT PRIMARY KEY REFERENCES stock_products(id) ON DELETE CASCADE,search TEXT NOT NULL);
    CREATE TABLE IF NOT EXISTS stock_lot_search(lot_id TEXT PRIMARY KEY REFERENCES stock_lots(id) ON DELETE CASCADE,search TEXT NOT NULL);
    CREATE TRIGGER IF NOT EXISTS stock_product_search_insert AFTER INSERT ON stock_products BEGIN
      INSERT OR REPLACE INTO stock_product_search VALUES(NEW.id,normalized(json_extract(NEW.payload,'\$.name')||' '||NEW.sku)); END;
    CREATE TRIGGER IF NOT EXISTS stock_product_search_update AFTER UPDATE OF payload,sku ON stock_products BEGIN
      INSERT OR REPLACE INTO stock_product_search VALUES(NEW.id,normalized(json_extract(NEW.payload,'\$.name')||' '||NEW.sku)); END;
    CREATE TRIGGER IF NOT EXISTS stock_lot_search_insert AFTER INSERT ON stock_lots BEGIN
      INSERT OR REPLACE INTO stock_lot_search VALUES(NEW.id,normalized(NEW.lot_code)); END;
    CREATE TRIGGER IF NOT EXISTS stock_lot_search_update AFTER UPDATE OF lot_code ON stock_lots BEGIN
      INSERT OR REPLACE INTO stock_lot_search VALUES(NEW.id,normalized(NEW.lot_code)); END;
    INSERT OR IGNORE INTO stock_product_search SELECT id,normalized(json_extract(payload,'\$.name')||' '||sku) FROM stock_products WHERE id NOT IN (SELECT product_id FROM stock_product_search);
    INSERT OR IGNORE INTO stock_lot_search SELECT id,normalized(lot_code) FROM stock_lots WHERE id NOT IN (SELECT lot_id FROM stock_lot_search);
  ''');

  Map<String, dynamic> pagedWorkspace(String user, Map<String, String> query) {
    final organizations = _rows(
      'SELECT o.*,m.role FROM merchant_organizations o JOIN merchant_members m ON m.org_id=o.id WHERE m.user_id=?',
      [user],
    );
    final allowed = storeIds(user).toSet();
    final stores = _rows(
      'SELECT s.* FROM merchant_stores s JOIN merchant_members m ON m.org_id=s.org_id WHERE m.user_id=? ORDER BY s.rowid',
      [user],
    ).where((s) => allowed.contains(s['id'])).toList();
    final store = query['storeId'] ?? (stores.firstOrNull?['id'] as String?);
    if (store != null && !allowed.contains(store)) {
      throw const ApiFailure(403, 'Pobočka nie je prístupná.');
    }
    final org = store == null
        ? null
        : stores.firstWhere((s) => s['id'] == store)['org_id'] as String;
    if (org != null) _org(user, org);
    final section = query['section'];
    const sections = {
      'products',
      'lots',
      'offers',
      'orders',
      'rules',
      'movements',
    };
    if (section != null && !sections.contains(section)) {
      throw const ApiFailure(400, 'Neplatná časť prehľadu.');
    }
    final before = query['before'] == null
        ? null
        : int.tryParse(query['before']!);
    if (query['before'] != null && (before == null || before < 1)) {
      throw const ApiFailure(400, 'Neplatný kurzor.');
    }
    final search = normalizeSearch(query['query'] ?? '');
    if (search.length > 150) {
      throw const ApiFailure(400, 'Príliš dlhé vyhľadávanie.');
    }
    final output = <String, dynamic>{
      'paged': true,
      'activeStoreId': store,
      'organizations': organizations
          .map(
            (o) => {
              'id': o['id'],
              'name': o['name'],
              'companyId': o['company_id'],
              'contactEmail': o['contact_email'],
              'role': o['role'],
            },
          )
          .toList(),
      'stores': stores.map(storePresentation).toList(),
      'pages': <String, dynamic>{},
      'stockSummary': <String, dynamic>{},
    };
    if (store == null) return output;
    final products = <String, Map<String, dynamic>>{};
    void product(String id) {
      products.putIfAbsent(id, () => _product(id).toJson());
    }

    for (final kind in section == null ? sections : {section}) {
      final term = section == kind ? search : '';
      final cursor = section == kind ? before : null;
      late List<Map<String, dynamic>> rows;
      final args = <Object?>[
        kind == 'products' ? org : store,
        cursor,
        cursor,
        term,
        '%$term%',
      ];
      rows = switch (kind) {
        'products' => _rows(
          "SELECT p.*,p.rowid cursor FROM stock_products p JOIN stock_product_search ps ON ps.product_id=p.id WHERE p.org_id=? AND (? IS NULL OR p.rowid<?) AND (?='' OR instr(ps.search,?)>0) ORDER BY p.rowid DESC LIMIT 51",
          [...args.take(4), term],
        ),
        'lots' => _rows(
          "SELECT l.*,l.rowid cursor FROM stock_lots l JOIN stock_products p ON p.id=l.product_id JOIN stock_product_search ps ON ps.product_id=p.id JOIN stock_lot_search ls ON ls.lot_id=l.id WHERE l.store_id=? AND (? IS NULL OR l.rowid<?) AND (?='' OR instr(ls.search||' '||ps.search,?)>0) AND (?=0 OR (l.quality='checked' AND l.deadline>? AND l.on_hand>(SELECT COALESCE(SUM(quantity),0) FROM stock_reservations r WHERE r.lot_id=l.id AND r.state='held'))) ORDER BY l.rowid DESC LIMIT 51",
          [
            ...args.take(4),
            term,
            query['availableOnly'] == 'true' ? 1 : 0,
            _now,
          ],
        ),
        'offers' => _rows(
          "SELECT m.*,m.rowid cursor,o.payload FROM merchant_offers m JOIN offers o ON o.id=m.offer_id WHERE m.store_id=? AND (? IS NULL OR m.rowid<?) AND (?='' OR normalized(o.payload) LIKE ?) ORDER BY m.rowid DESC LIMIT 51",
          args,
        ),
        'orders' => _rows(
          "SELECT o.*,o.rowid cursor FROM orders o WHERE EXISTS(SELECT 1 FROM merchant_order_lines l WHERE l.order_id=o.id AND l.store_id=?) AND (? IS NULL OR o.rowid<?) AND (?='' OR normalized(o.id) LIKE ?) ORDER BY o.rowid DESC LIMIT 51",
          args,
        ),
        'rules' => _rows(
          "SELECT r.*,r.rowid cursor FROM bundle_rules r WHERE r.store_id=? AND (? IS NULL OR r.rowid<?) AND (?='' OR normalized(r.payload) LIKE ?) ORDER BY r.rowid DESC LIMIT 51",
          args,
        ),
        _ => _rows(
          "SELECT m.*,m.rowid cursor FROM stock_movements m WHERE m.store_id=? AND (? IS NULL OR m.rowid<?) AND (?='' OR normalized(m.reason||' '||m.kind) LIKE ?) ORDER BY m.rowid DESC LIMIT 51",
          args,
        ),
      };
      (output['pages'] as Map)[kind] = rows.length > 50
          ? rows[49]['cursor'].toString()
          : null;
      output[kind] = rows.take(50).map((r) {
        if (kind == 'products') {
          final p = database.decode(r['payload'] as String);
          products[p['id'] as String] = p;
          return p;
        }
        if (kind == 'lots') {
          product(r['product_id'] as String);
          return _lotJson(r);
        }
        if (kind == 'rules') return database.decode(r['payload'] as String);
        if (kind == 'offers') {
          final offer = database.decode(r['payload'] as String),
              recipe = jsonDecode(r['recipe'] as String) as Map;
          for (final id in recipe.keys) {
            product(id as String);
          }
          return {
            'offer': offer,
            'storeId': r['store_id'],
            'state': r['state'],
            'recipe': recipe,
            'ruleId': r['rule_id'],
            'available': remaining(
              r['offer_id'] as String,
              math.max(
                0,
                (offer['stock'] as int) - committed(r['offer_id'] as String),
              ),
              includeDraft: true,
            ),
          };
        }
        if (kind == 'orders') {
          final order = RescueOrder.fromJson(
            database.decode(r['payload'] as String),
          );
          final items = order.items
              .where((i) => managed(i.offerId)?['store_id'] == store)
              .toList();
          final risk = _rows(
            "SELECT l.id FROM stock_reservations r JOIN stock_lots l ON l.id=r.lot_id WHERE r.order_id=? AND l.store_id=? AND r.state='held' AND (l.quality!='checked' OR l.deadline<=?) LIMIT 1",
            [order.id, store, _now],
          ).isNotEmpty;
          final orderStores = _rows(
            'SELECT DISTINCT store_id FROM merchant_order_lines WHERE order_id=?',
            [order.id],
          );
          return {
            'id': order.id,
            'status': r['status'],
            'createdAt': order.createdAt.toIso8601String(),
            'items': items.map((i) => i.toJson()).toList(),
            'atRisk': risk,
            'cancellableStoreId': orderStores.length == 1 ? store : null,
          };
        }
        if (kind == 'movements') {
          final lot = _lot(r['lot_id'] as String),
              p = _product(lot['product_id'] as String);
          return {...r, 'unit': p.unit.name};
        }
        return r;
      }).toList();
    }
    output['products'] = products.values.toList();
    final units = _rows(
      '''WITH held AS(SELECT r.lot_id,SUM(r.quantity) n FROM stock_reservations r JOIN stock_lots x ON x.id=r.lot_id WHERE x.store_id=? AND r.state='held' GROUP BY r.lot_id)
      SELECT json_extract(p.payload,'\$.unit') unit,COUNT(*) lots,
      COALESCE(SUM(CASE WHEN l.quality='checked' AND l.deadline>? THEN l.on_hand-COALESCE(h.n,0) ELSE 0 END),0) available,
      COALESCE(SUM(h.n),0) reserved,
      COALESCE(SUM(CASE WHEN l.quality='checked' AND l.deadline>? AND l.deadline<? THEN 1 ELSE 0 END),0) soon
      FROM stock_lots l JOIN stock_products p ON p.id=l.product_id LEFT JOIN held h ON h.lot_id=l.id WHERE l.store_id=? GROUP BY json_extract(p.payload,'\$.unit')''',
      [
        store,
        _now,
        _now,
        clock().toUtc().add(const Duration(days: 2)).toIso8601String(),
        store,
      ],
    );
    output['stockSummary'] = {
      for (final key in ['lots', 'available', 'reserved', 'soon'])
        key: units.fold<int>(0, (n, r) => n + (r[key] as int)),
      'units': [
        for (final row in units)
          {
            'unit': row['unit'],
            'available': row['available'],
            'reserved': row['reserved'],
          },
      ],
      'drafts': _one(
        "SELECT COUNT(*) n FROM merchant_offers WHERE store_id=? AND state='draft'",
        [store],
      )['n'],
    };
    final owner = organizations.any(
      (o) => o['id'] == org && o['role'] == 'owner',
    );
    output['members'] = owner
        ? _rows(
            'SELECT m.org_id,m.role,u.email,u.name FROM merchant_members m JOIN users u ON u.id=m.user_id WHERE m.org_id=?',
            [org],
          )
        : [];
    output['integrations'] = owner
        ? _rows(
            'SELECT i.id,i.store_id,i.name,i.revoked,i.created_at,i.last_seen,d.acknowledged,d.delivered,(SELECT COUNT(*) FROM stock_changes c WHERE c.store_id=i.store_id AND c.sequence>d.acknowledged) pending FROM stock_integrations i LEFT JOIN stock_delivery d ON d.integration_id=i.id WHERE i.store_id=?',
            [store],
          )
        : [];
    return output;
  }
}

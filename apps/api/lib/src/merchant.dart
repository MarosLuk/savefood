import 'dart:convert';
import 'dart:math' as math;
import 'package:csv/csv.dart';
import 'package:marketplace_domain/marketplace_domain.dart';
import 'package:marketplace_fixtures/marketplace_fixtures.dart'
    show demoImageNames;
import 'package:timezone/timezone.dart' as tz;
import 'package:uuid/uuid.dart';
import 'auth.dart';
import 'database.dart';
import 'mail.dart';

part 'warehouse.dart';
part 'merchant_access.dart';
part 'merchant_paging.dart';
part 'stock_connector.dart';
part 'partial_stock.dart';

/// All stock mutations are synchronous and run inside BEGIN IMMEDIATE.
/// Availability is shared by every offer that refers to the same physical lot.
class MerchantService {
  MerchantService(
    this.database, {
    DateTime Function()? clock,
    this.allowDemoImages = false,
    this.mediaBaseUrl = '',
    this.appUrl = 'http://localhost:7358',
    this.mail,
    this.requireVerifiedEmails = false,
  }) : clock = clock ?? DateTime.now {
    initializeWarehouse();
    initializeAccess();
    initializePartialStock();
    initializeConnector();
    initializePaging();
    database.transaction(() {
      for (final row in _rows(
        'SELECT DISTINCT o.payload FROM orders o JOIN stock_reservations r ON r.order_id=o.id LEFT JOIN merchant_order_lines l ON l.order_id=r.order_id AND l.offer_id=r.offer_id WHERE l.order_id IS NULL',
      )) {
        final order = RescueOrder.fromJson(
          database.decode(row['payload'] as String),
        );
        for (final item in order.items) {
          final offer = managed(item.offerId);
          if (offer != null) {
            database.db.execute(
              'INSERT OR IGNORE INTO merchant_order_lines(order_id,offer_id,store_id,quantity) VALUES(?,?,?,?)',
              [order.id, item.offerId, offer['store_id'], item.quantity],
            );
          }
        }
      }
    });
  }
  final MarketplaceDatabase database;
  final DateTime Function() clock;
  final bool allowDemoImages;
  final String mediaBaseUrl;
  final String appUrl;
  final MailService? mail;
  final bool requireVerifiedEmails;
  String get _now => clock().toUtc().toIso8601String();
  String _id() => const Uuid().v4();
  Object? _canonical(Object? value) {
    if (value is Map) {
      final keys = value.keys.cast<String>().toList()..sort();
      return {for (final key in keys) key: _canonical(value[key])};
    }
    if (value is List) return value.map(_canonical).toList();
    return value;
  }

  List<Map<String, dynamic>> _rows(
    String sql, [
    List<Object?> args = const [],
  ]) => database.db
      .select(sql, args)
      .map((r) => Map<String, dynamic>.from(r))
      .toList();
  Map<String, dynamic> _one(String sql, List<Object?> args) {
    final rows = _rows(sql, args);
    if (rows.isEmpty) throw const ApiFailure(404, 'Záznam sa nenašiel.');
    return rows.first;
  }

  Map<String, dynamic> mutate(
    String user,
    String path,
    Map<String, dynamic> body,
    Map<String, dynamic> Function() action,
  ) => database.transaction(() {
    final key = _text(body, 'idempotencyKey', min: 16, max: 100);
    final hash = hashToken(
      jsonEncode(_canonical({'path': path, 'body': body})),
    );
    final previous = _rows(
      'SELECT request_hash,response FROM merchant_requests WHERE user_id=? AND idempotency=?',
      [user, key],
    );
    if (previous.isNotEmpty) {
      if (previous.first['request_hash'] != hash) {
        throw const ApiFailure(
          409,
          'Identifikátor zmeny už patrí inej požiadavke.',
        );
      }
      return database.decode(previous.first['response'] as String);
    }
    final result = action();
    database.db.execute('INSERT INTO merchant_requests VALUES(?,?,?,?)', [
      user,
      key,
      hash,
      jsonEncode(
        result.containsKey('token') ? {...result, 'token': null} : result,
      ),
    ]);
    return result;
  });
  int _integer(Map<String, dynamic> b, String key, int min, int max) {
    final v = b[key];
    if (v is! int || v < min || v > max) {
      throw ApiFailure(400, 'Neplatné množstvo alebo hodnota: $key.');
    }
    return v;
  }

  String _text(
    Map<String, dynamic> b,
    String key, {
    int min = 1,
    int max = 250,
  }) {
    final v = stringField(b, key, max: max);
    if (v.length < min) throw ApiFailure(400, 'Vyplň pole: $key.');
    return v;
  }

  int _amount(
    Map<String, dynamic> body,
    String key,
    StockUnit unit,
    int min,
    int max,
  ) {
    if (body['${key}Display'] == null) return _integer(body, key, min, max);
    final value = body['${key}Display'];
    if (value is! String || value.length > 30) {
      throw const ApiFailure(400, 'Neplatné množstvo.');
    }
    final amount = unit.parseAmount(value);
    if (amount < min || amount > max) {
      throw const ApiFailure(400, 'Množstvo je mimo povoleného rozsahu.');
    }
    return amount;
  }

  DateTime _date(Object? v) {
    if (v is! String || !RegExp(r'(Z|[+-]\d\d:\d\d)$').hasMatch(v)) {
      throw const ApiFailure(400, 'Čas musí obsahovať časové pásmo.');
    }
    final result = DateTime.tryParse(v);
    if (result == null) throw const ApiFailure(400, 'Neplatný dátum.');
    final fields = RegExp(
      r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})(?::(\d{2})(?:\.\d{1,6})?)?(Z|[+-]\d{2}:\d{2})$',
    ).firstMatch(v);
    if (fields == null) {
      throw const ApiFailure(400, 'Neplatný dátum alebo čas.');
    }
    final year = int.parse(fields[1]!),
        month = int.parse(fields[2]!),
        day = int.parse(fields[3]!);
    final date = DateTime.utc(year, month, day);
    if (date.year != year ||
        date.month != month ||
        date.day != day ||
        int.parse(fields[4]!) > 23 ||
        int.parse(fields[5]!) > 59 ||
        int.parse(fields[6] ?? '0') > 59) {
      throw const ApiFailure(400, 'Dátum alebo čas neexistuje.');
    }
    final offset = fields[7]!;
    if (offset != 'Z' &&
        (int.parse(offset.substring(1, 3)) > 14 ||
            int.parse(offset.substring(4)) > 59 ||
            int.parse(offset.substring(1, 3)) == 14 &&
                int.parse(offset.substring(4)) != 0)) {
      throw const ApiFailure(400, 'Neplatné časové pásmo.');
    }
    return result.toUtc();
  }

  Map<String, dynamic> _org(
    String user,
    String org, {
    bool owner = false,
    bool manage = false,
  }) {
    if (requireVerifiedEmails &&
        _one('SELECT email_verified FROM users WHERE id=?', [
              user,
            ])['email_verified'] !=
            1) {
      throw const ApiFailure(403, 'Najprv over e-mail účtu.');
    }
    final row = _one(
      'SELECT o.*,m.role FROM merchant_organizations o JOIN merchant_members m ON m.org_id=o.id WHERE o.id=? AND m.user_id=?',
      [org, user],
    );
    if (owner && row['role'] != 'owner' || manage && row['role'] == 'staff') {
      throw const ApiFailure(403, 'Na túto akciu nemáš oprávnenie.');
    }
    if (_rows(
      "SELECT org_id FROM platform_organizations WHERE org_id=? AND status='suspended'",
      [org],
    ).isNotEmpty) {
      throw const ApiFailure(
        403,
        'Prevádzkovateľ firmy je dočasne pozastavený. Kontaktuj podporu.',
      );
    }
    return row;
  }

  MerchantStore requireStore(
    String user,
    String store, {
    bool owner = false,
    bool manage = false,
  }) {
    final row = _one('SELECT * FROM merchant_stores WHERE id=?', [store]);
    _org(user, row['org_id'] as String, owner: owner, manage: manage);
    if (!canAccessStore(user, store)) {
      throw const ApiFailure(403, 'K tejto pobočke nemáš pridelený prístup.');
    }
    return MerchantStore.fromJson(database.decode(row['payload'] as String));
  }

  List<String> storeIds(String user) => _rows(
    '''SELECT s.id FROM merchant_stores s JOIN merchant_members m ON m.org_id=s.org_id
    LEFT JOIN merchant_member_scopes p ON p.org_id=m.org_id AND p.user_id=m.user_id
    WHERE m.user_id=? AND (m.role='owner' OR COALESCE(p.all_stores,1)=1 OR EXISTS(SELECT 1 FROM merchant_member_stores a WHERE a.org_id=m.org_id AND a.user_id=m.user_id AND a.store_id=s.id))''',
    [user],
  ).map((r) => r['id'] as String).toList();
  StockProduct _product(String id) => StockProduct.fromJson(
    database.decode(
      _one('SELECT payload FROM stock_products WHERE id=?', [id])['payload']
          as String,
    ),
  );
  Map<String, dynamic> _lot(String id) =>
      _one('SELECT * FROM stock_lots WHERE id=?', [id]);
  int _held(String lot) =>
      _one(
            "SELECT COALESCE(SUM(quantity),0) AS n FROM stock_reservations WHERE lot_id=? AND state='held'",
            [lot],
          )['n']
          as int;
  int _available(Map<String, dynamic> lot) =>
      (lot['on_hand'] as int) - _held(lot['id'] as String);
  Map<String, dynamic> _lotJson(Map<String, dynamic> row) => {
    'id': row['id'],
    'storeId': row['store_id'],
    'productId': row['product_id'],
    'lotCode': row['lot_code'],
    'onHand': row['on_hand'],
    'reserved': _held(row['id'] as String),
    'deadline': row['deadline'],
    'dateType': row['date_type'],
    'quality': row['quality'],
    'version': row['version'],
  };

  Map<String, dynamic> storePresentation(Map<String, dynamic> row) => {
    ...database.decode(row['payload'] as String),
    'platformPaused': _rows(
      'SELECT store_id FROM platform_stores WHERE store_id=? AND paused=1',
      [row['id']],
    ).isNotEmpty,
  };
  Map<String, dynamic> createOrganization(
    String user,
    Map<String, dynamic> b,
  ) => database.transaction(() {
    if (requireVerifiedEmails &&
        _one('SELECT email_verified FROM users WHERE id=?', [
              user,
            ])['email_verified'] !=
            1) {
      throw const ApiFailure(403, 'Pred vytvorením firmy over svoj e-mail.');
    }
    final name = _text(b, 'name', min: 2, max: 100),
        company = _text(b, 'companyId', max: 20),
        email = _text(b, 'contactEmail');
    if (!RegExp(r'^\d{8}$').hasMatch(company) ||
        !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
      throw const ApiFailure(400, 'Zadaj 8-miestne IČO a kontaktný e-mail.');
    }
    final id = _id();
    database.db.execute(
      'INSERT INTO merchant_organizations VALUES(?,?,?,?,?)',
      [id, name, company, email, _now],
    );
    database.db.execute('INSERT INTO merchant_members VALUES(?,?,?)', [
      id,
      user,
      'owner',
    ]);
    final store = _createStore(id, merchantMap(b['store']));
    return {'organizationId': id, 'storeId': store.id};
  });
  MerchantStore _createStore(String org, Map<String, dynamic> b) {
    final name = _text(b, 'name', min: 2, max: 100),
        address = _text(b, 'address', min: 5);
    final point = GeoPoint.fromJson(merchantMap(b['point']));
    if (!point.latitude.isFinite ||
        !point.longitude.isFinite ||
        point.latitude.abs() > 90 ||
        point.longitude.abs() > 180) {
      throw const ApiFailure(400, 'Neplatná poloha prevádzky.');
    }
    final store = MerchantStore(
      id: _id(),
      organizationId: org,
      name: name,
      kind: StoreKind.values.byName(_text(b, 'kind')),
      address: address,
      point: point,
    );
    database.db.execute('INSERT INTO merchant_stores VALUES(?,?,?)', [
      store.id,
      org,
      jsonEncode(store.toJson()),
    ]);
    return store;
  }

  Map<String, dynamic> createStore(String user, Map<String, dynamic> b) =>
      database.transaction(() {
        final org = _text(b, 'organizationId');
        _org(user, org, owner: true);
        return _createStore(org, b).toJson();
      });
  Map<String, dynamic> createProduct(String user, Map<String, dynamic> b) =>
      database.transaction(() {
        final org = _text(b, 'organizationId');
        _org(user, org, manage: true);
        final sku = _text(b, 'sku', max: 80);
        if (_rows('SELECT id FROM stock_products WHERE org_id=? AND sku=?', [
          org,
          sku,
        ]).isNotEmpty) {
          throw const ApiFailure(409, 'Toto SKU už existuje.');
        }
        final category = FoodCategory.values.byName(_text(b, 'category'));
        if (category == FoodCategory.flowers) {
          throw const ApiFailure(
            400,
            'Skladové potravinové balíčky nemôžu obsahovať kvety.',
          );
        }
        final image = _text(b, 'image', max: 2000);
        _image(image, org: org);
        final product = StockProduct(
          id: _id(),
          organizationId: org,
          sku: sku,
          name: _text(b, 'name', min: 2, max: 120),
          category: category,
          unit: StockUnit.values.byName(_text(b, 'unit')),
          unitValue: _integer(b, 'unitValue', 1, 100000),
          allergens: _text(b, 'allergens', max: 1000),
          storage: StorageZone.values.byName(_text(b, 'storage')),
          image: image,
        );
        database.db.execute('INSERT INTO stock_products VALUES(?,?,?,?)', [
          product.id,
          org,
          sku,
          jsonEncode(product.toJson()),
        ]);
        return product.toJson();
      });
  void _image(String value, {String? org}) {
    if (allowDemoImages && demoImageNames.contains(value)) return;
    if (mediaBaseUrl.isNotEmpty &&
        value.startsWith('$mediaBaseUrl/v1/media/')) {
      if (!value.endsWith('.jpg')) {
        throw const ApiFailure(400, 'Použi adresu nahratej fotografie.');
      }
      final id = value
          .substring('$mediaBaseUrl/v1/media/'.length)
          .replaceFirst(RegExp(r'\.jpg$'), '');
      if (_rows(
        "SELECT id FROM media_assets WHERE id=? AND org_id=? AND kind='product' AND deleted_at IS NULL",
        [id, org],
      ).isNotEmpty) {
        return;
      }
      throw const ApiFailure(400, 'Nahratá fotografia už nie je dostupná.');
    }
    final uri = Uri.tryParse(value);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      throw const ApiFailure(400, 'Fotografia musí mať platnú HTTPS adresu.');
    }
  }

  Map<String, dynamic> receive(String user, Map<String, dynamic> b) =>
      database.transaction(() {
        final store = requireStore(user, _text(b, 'storeId'));
        if (b['quality'] == 'checked') {
          requireStore(user, store.id, manage: true);
        }
        return _receive(store, b, user);
      });
  Map<String, dynamic> _receive(
    MerchantStore store,
    Map<String, dynamic> b,
    String actor,
  ) {
    final product = _product(_text(b, 'productId'));
    if (product.organizationId != store.organizationId) {
      throw const ApiFailure(404, 'Položka sa nenašla.');
    }
    final code = _text(b, 'lotCode', max: 100),
        quantity = _amount(b, 'quantity', product.unit, 1, 1000000);
    final deadline = _date(b['deadline']);
    final dateType = DateMark.values.byName(_text(b, 'dateType'));
    final quality = StockQuality.values.byName(_text(b, 'quality'));
    if (!deadline.isAfter(clock())) {
      throw const ApiFailure(
        400,
        'Prijímaná šarža musí mať budúci termín vyradenia.',
      );
    }
    final rows = _rows(
      'SELECT * FROM stock_lots WHERE store_id=? AND product_id=? AND lot_code=?',
      [store.id, product.id, code],
    );
    String id;
    if (rows.isEmpty) {
      id = _id();
      database.db.execute(
        'INSERT INTO stock_lots(id,store_id,product_id,lot_code,on_hand,deadline,date_type,quality) VALUES(?,?,?,?,?,?,?,?)',
        [
          id,
          store.id,
          product.id,
          code,
          quantity,
          deadline.toIso8601String(),
          dateType.name,
          quality.name,
        ],
      );
    } else {
      final row = rows.first;
      id = row['id'] as String;
      if (row['deadline'] != deadline.toIso8601String() ||
          row['date_type'] != dateType.name ||
          row['quality'] != quality.name) {
        throw const ApiFailure(
          409,
          'Existujúca šarža má iný dátum alebo stav. Použi samostatnú šaržu.',
        );
      }
      if ((row['on_hand'] as int) + quantity > 1000000) {
        throw const ApiFailure(400, 'Príliš vysoký stav šarže.');
      }
      database.db.execute(
        'UPDATE stock_lots SET on_hand=on_hand+?,version=version+1 WHERE id=?',
        [quantity, id],
      );
    }
    _movement(store.id, id, actor, 'receive', quantity, 0, 'Príjem šarže');
    return _lotJson(_lot(id));
  }

  Map<String, dynamic> adjust(String user, String id, Map<String, dynamic> b) =>
      database.transaction(() {
        final lot = _lot(id);
        requireStore(user, lot['store_id'] as String);
        if (b['version'] != lot['version']) {
          throw const ApiFailure(
            409,
            'Sklad medzitým zmenil niekto iný. Obnov údaje.',
          );
        }
        return _adjust(lot, b, user);
      });
  Map<String, dynamic> _adjust(
    Map<String, dynamic> lot,
    Map<String, dynamic> b,
    String actor,
  ) {
    final delta = _amount(
          b,
          'delta',
          _product(lot['product_id'] as String).unit,
          -1000000,
          1000000,
        ),
        reason = _text(b, 'reason', min: 3, max: 300);
    final next = (lot['on_hand'] as int) + delta;
    if (delta == 0 || next < 0 || next > 1000000) {
      throw const ApiFailure(400, 'Neplatná zmena skladu.');
    }
    if (next < _held(lot['id'] as String)) {
      throw const ApiFailure(
        409,
        'Zásoba kryje rezervácie. Najprv vyrieš rezervované objednávky.',
      );
    }
    database.db.execute(
      'UPDATE stock_lots SET on_hand=?,version=version+1 WHERE id=?',
      [next, lot['id']],
    );
    _movement(
      lot['store_id'] as String,
      lot['id'] as String,
      actor,
      'adjust',
      delta,
      0,
      reason,
    );
    return _lotJson(_lot(lot['id'] as String));
  }

  Map<String, dynamic> quality(
    String user,
    String id,
    Map<String, dynamic> b,
  ) => database.transaction(() {
    final lot = _lot(id);
    requireStore(user, lot['store_id'] as String, manage: true);
    if (b['version'] != lot['version']) {
      throw const ApiFailure(409, 'Šarža sa zmenila. Obnov údaje.');
    }
    final quality = StockQuality.values.byName(_text(b, 'quality'));
    final reason = _text(b, 'reason', min: 3, max: 300);
    if (lot['quality'] == 'withdrawn' && quality != StockQuality.withdrawn) {
      throw const ApiFailure(409, 'Vyradenú šaržu nemožno vrátiť do predaja.');
    }
    database.db.execute(
      'UPDATE stock_lots SET quality=?,version=version+1 WHERE id=?',
      [quality.name, id],
    );
    _movement(lot['store_id'] as String, id, user, 'quality', 0, 0, reason);
    propagateLotQuality(id, quality.name, user, reason);
    return _lotJson(_lot(id));
  });
  void _movement(
    String store,
    String lot,
    String actor,
    String kind,
    int physical,
    int reserved,
    String reason,
  ) => database.transaction(() {
    final id = _id();
    database.db.execute(
      'INSERT INTO stock_movements VALUES(?,?,?,?,?,?,?,?,?)',
      [id, store, lot, actor, kind, physical, reserved, reason, _now],
    );
    recordChange(store, lot, actor, kind, physical, reserved, reason, id);
  });
  void _event(String store, String actor, String kind, String detail) =>
      database.db.execute('INSERT INTO merchant_events VALUES(?,?,?,?,?,?)', [
        _id(),
        store,
        actor,
        kind,
        detail,
        _now,
      ]);

  List<Map<String, dynamic>> _eligible(
    String store,
    String product,
    DateTime through, {
    DateTime? until,
  }) => _rows(
    "SELECT * FROM stock_lots WHERE store_id=? AND product_id=? AND quality='checked' AND deadline>? AND (? IS NULL OR deadline<=?) ORDER BY deadline,id",
    [
      store,
      product,
      (through.isAfter(clock()) ? through : clock()).toUtc().toIso8601String(),
      until?.toUtc().toIso8601String(),
      until?.toUtc().toIso8601String(),
    ],
  );
  int _productAvailable(
    String store,
    String product,
    DateTime through, {
    DateTime? until,
  }) => _eligible(
    store,
    product,
    through,
    until: until,
  ).fold(0, (n, l) => n + _available(l));
  Map<String, int> _recipe(Object? raw) {
    final map = merchantMap(raw);
    if (map.isEmpty || map.length > 30) {
      throw const ApiFailure(
        400,
        'Balíček potrebuje 1 až 30 položiek receptúry.',
      );
    }
    return map.map(
      (k, v) => MapEntry(
        k,
        _integer({'quantity': v}, 'quantity', 1, 1000 * _product(k).unit.scale),
      ),
    );
  }

  int _recipeAvailable(
    String store,
    Map<String, int> recipe,
    DateTime through, {
    DateTime? until,
  }) => recipe.entries
      .map(
        (e) =>
            _productAvailable(store, e.key, through, until: until) ~/ e.value,
      )
      .reduce(math.min);
  Map<String, dynamic>? managed(String offer) {
    final r = _rows('SELECT * FROM merchant_offers WHERE offer_id=?', [offer]);
    return r.isEmpty ? null : r.first;
  }

  bool visible(String offer) {
    if (_rows(
      'SELECT offer_id FROM platform_offers WHERE offer_id=? AND hidden=1',
      [offer],
    ).isNotEmpty) {
      return false;
    }
    final row = managed(offer);
    if (row == null) return true;
    if (_rows(
      'SELECT store_id FROM platform_stores WHERE store_id=? AND paused=1',
      [row['store_id']],
    ).isNotEmpty) {
      return false;
    }
    if (_rows(
      "SELECT s.id FROM merchant_stores s JOIN platform_organizations p ON p.org_id=s.org_id WHERE s.id=? AND p.status='suspended'",
      [row['store_id']],
    ).isNotEmpty) {
      return false;
    }
    return row['state'] == 'published';
  }

  int remaining(String offer, int capacity, {bool includeDraft = false}) {
    if (!includeDraft && !visible(offer)) return 0;
    final row = managed(offer);
    if (row == null) return capacity;
    if (!includeDraft && row['state'] != 'published') return 0;
    final food = FoodOffer.fromJson(
      database.decode(
        _one('SELECT payload FROM offers WHERE id=?', [offer])['payload']
            as String,
      ),
    );
    if (!food.pickupEnd.isAfter(clock())) return 0;
    return math.min(
      capacity,
      _recipeAvailable(
        row['store_id'] as String,
        _recipe(jsonDecode(row['recipe'] as String)),
        food.pickupEnd,
        until: DateTime.tryParse(row['eligible_until'] as String? ?? ''),
      ),
    );
  }

  Map<String, dynamic> createOffer(String user, Map<String, dynamic> b) =>
      database.transaction(() {
        final store = requireStore(user, _text(b, 'storeId'), manage: true);
        return _createOffer(store, b, user);
      });
  Map<String, dynamic> _createOffer(
    MerchantStore store,
    Map<String, dynamic> b,
    String actor, {
    String? ruleId,
    String? day,
    DateTime? eligibleUntil,
  }) {
    final recipe = _recipe(b['recipe']);
    final start = _date(b['pickupStart']), end = _date(b['pickupEnd']);
    if (!end.isAfter(start) ||
        !end.isAfter(clock()) ||
        end.difference(start) > const Duration(hours: 12)) {
      throw const ApiFailure(400, 'Zadaj budúce výdajové okno do 12 hodín.');
    }
    final products = recipe.keys.map(_product).toList();
    if (products.any((p) => p.organizationId != store.organizationId)) {
      throw const ApiFailure(404, 'Položka sa nenašla.');
    }
    if (products.map((p) => p.storage).toSet().length != 1) {
      throw const ApiFailure(
        400,
        'Jeden balíček musí mať rovnakú skladovaciu zónu.',
      );
    }
    final original =
        (products.fold<int>(0, (n, p) => n + p.valueMilliCents(recipe[p.id]!)) +
            500) ~/
        1000;
    final price = _integer(b, 'price', 50, 1000000),
        stock = _integer(b, 'stock', 1, 1000);
    if (price > original) {
      throw const ApiFailure(400, 'Predajná cena prevyšuje hodnotu obsahu.');
    }
    final state = b['state'] as String? ?? 'draft';
    if (!{'draft', 'published'}.contains(state)) {
      throw const ApiFailure(400, 'Neplatný stav ponuky.');
    }
    if (_recipeAvailable(store.id, recipe, end, until: eligibleUntil) < 1) {
      throw const ApiFailure(
        409,
        'Receptúra nemá dostatočný skontrolovaný sklad do konca výdaja.',
      );
    }
    final image = _text(b, 'image', max: 2000);
    _image(image, org: store.organizationId);
    final category = FoodCategory.values.byName(_text(b, 'category'));
    if (products.any((p) => p.category != category)) {
      throw const ApiFailure(
        400,
        'Položky balíčka musia patriť do vybranej kategórie.',
      );
    }
    final offer = FoodOffer(
      id: _id(),
      store: store.name,
      title: _text(b, 'title', min: 3, max: 100),
      category: category,
      image: image,
      price: price,
      originalPrice: original,
      stock: stock,
      rating: 0,
      reviews: 0,
      address: store.address,
      point: store.point,
      pickupStart: start,
      pickupEnd: end,
      description: _text(b, 'description', min: 10, max: 3000),
      allergens: products.map((p) => p.allergens).toSet().join('; '),
    );
    database.db.execute('INSERT INTO offers(id,payload) VALUES(?,?)', [
      offer.id,
      jsonEncode(offer.toJson()),
    ]);
    database.db.execute(
      'INSERT INTO merchant_offers(offer_id,store_id,state,recipe,rule_id,business_day,created_at,eligible_until) VALUES(?,?,?,?,?,?,?,?)',
      [
        offer.id,
        store.id,
        state,
        jsonEncode(recipe),
        ruleId,
        day,
        _now,
        eligibleUntil?.toUtc().toIso8601String(),
      ],
    );
    _event(store.id, actor, 'offer_created', offer.id);
    return {'id': offer.id, 'state': state};
  }

  int committed(String id) {
    return _one(
          "SELECT COALESCE(SUM(l.quantity-l.refunded_quantity),0) AS n FROM merchant_order_lines l JOIN orders o ON o.id=l.order_id WHERE l.offer_id=? AND o.status IN ('awaitingPayment','reserved','collected','cancelling')",
          [id],
        )['n']
        as int;
  }

  Map<String, dynamic> editOffer(
    String user,
    String id,
    Map<String, dynamic> b,
  ) => database.transaction(() {
    final row = managed(id);
    if (row == null) throw const ApiFailure(404, 'Ponuka sa nenašla.');
    final store = requireStore(user, row['store_id'] as String, manage: true);
    final food = database.decode(
      _one('SELECT payload FROM offers WHERE id=?', [id])['payload'] as String,
    );
    final price = _integer(b, 'price', 50, food['originalPrice'] as int),
        stock = _integer(b, 'stock', 1, 1000);
    if (stock < committed(id)) {
      throw const ApiFailure(
        409,
        'Limit nemôže byť nižší než už rezervované a vydané balíčky.',
      );
    }
    final image = _text(b, 'image', max: 2000);
    _image(image, org: store.organizationId);
    food.addAll({
      'title': _text(b, 'title', min: 3, max: 100),
      'description': _text(b, 'description', min: 10, max: 3000),
      'image': image,
      'price': price,
      'stock': stock,
    });
    database.db.execute('UPDATE offers SET payload=? WHERE id=?', [
      jsonEncode(food),
      id,
    ]);
    _event(store.id, user, 'offer_edited', id);
    return {'id': id};
  });
  Map<String, dynamic> offerState(
    String user,
    String id,
    Map<String, dynamic> b,
  ) => database.transaction(() {
    final row = managed(id);
    if (row == null) throw const ApiFailure(404, 'Ponuka sa nenašla.');
    final store = requireStore(user, row['store_id'] as String, manage: true),
        state = _text(b, 'state');
    if (!{'published', 'paused'}.contains(state)) {
      throw const ApiFailure(400, 'Neplatný stav ponuky.');
    }
    if (state == 'published' && remaining(id, 1000, includeDraft: true) < 1) {
      throw const ApiFailure(
        409,
        'Na zverejnenie nie je dostatočný platný sklad.',
      );
    }
    database.db.execute('UPDATE merchant_offers SET state=? WHERE offer_id=?', [
      state,
      id,
    ]);
    _event(store.id, user, 'offer_$state', id);
    return {'id': id, 'state': state};
  });

  /// Called from the order transaction after the durable order has been inserted.
  void hold(RescueOrder order) {
    for (final item in order.items) {
      final row = managed(item.offerId);
      if (row == null) continue;
      database.db.execute(
        'INSERT INTO merchant_order_lines(order_id,offer_id,store_id,quantity) VALUES(?,?,?,?)',
        [order.id, item.offerId, row['store_id'], item.quantity],
      );
      if (row['state'] != 'published') {
        throw const ApiFailure(409, 'Ponuka bola pozastavená.');
      }
      final recipe = _recipe(jsonDecode(row['recipe'] as String));
      for (final component in recipe.entries) {
        var needed = component.value * item.quantity;
        for (final lot in _eligible(
          row['store_id'] as String,
          component.key,
          item.pickupEnd,
          until: DateTime.tryParse(row['eligible_until'] as String? ?? ''),
        )) {
          final quantity = math.min(needed, _available(lot));
          if (quantity <= 0) continue;
          database.db.execute(
            "INSERT INTO stock_reservations VALUES(?,?,?,?,'held')",
            [order.id, item.offerId, lot['id'], quantity],
          );
          _movement(
            row['store_id'] as String,
            lot['id'] as String,
            order.id,
            'reserve',
            0,
            quantity,
            'Rezervácia balíčka',
          );
          needed -= quantity;
          if (needed == 0) break;
        }
        if (needed > 0) {
          throw const ApiFailure(
            409,
            'Sklad sa medzitým zmenil. Obnov ponuky.',
          );
        }
      }
    }
  }

  void release(RescueOrder order, {Set<String>? offerIds}) {
    for (final row in _rows(
      "SELECT r.*,l.store_id FROM stock_reservations r JOIN stock_lots l ON l.id=r.lot_id WHERE r.order_id=? AND r.state='held'",
      [order.id],
    )) {
      if (offerIds != null && !offerIds.contains(row['offer_id'])) continue;
      database.db.execute(
        "UPDATE stock_reservations SET state='released' WHERE order_id=? AND offer_id=? AND lot_id=?",
        [order.id, row['offer_id'], row['lot_id']],
      );
      _movement(
        row['store_id'] as String,
        row['lot_id'] as String,
        order.id,
        'release',
        0,
        -(row['quantity'] as int),
        'Uvoľnenie po stornovaní',
      );
    }
  }

  void consume(RescueOrder order, List<OrderItem> selected) {
    final ids = selected.map((i) => i.offerId).toSet();
    for (final row in _rows(
      "SELECT r.*,l.store_id,l.deadline,l.quality FROM stock_reservations r JOIN stock_lots l ON l.id=r.lot_id WHERE r.order_id=? AND r.state='held'",
      [order.id],
    )) {
      if (!ids.contains(row['offer_id'])) continue;
      if (row['quality'] != 'checked' ||
          !DateTime.parse(row['deadline'] as String).isAfter(clock())) {
        throw const ApiFailure(
          409,
          'Šarža nie je spôsobilá na výdaj. Vyrieš objednávku s prevádzkovateľom.',
        );
      }
      final count = row['quantity'] as int;
      database.db.execute(
        'UPDATE stock_lots SET on_hand=on_hand-?,version=version+1 WHERE id=?',
        [count, row['lot_id']],
      );
      database.db.execute(
        "UPDATE stock_reservations SET state='consumed' WHERE order_id=? AND offer_id=? AND lot_id=?",
        [order.id, row['offer_id'], row['lot_id']],
      );
      _movement(
        row['store_id'] as String,
        row['lot_id'] as String,
        order.id,
        'collect',
        -count,
        -count,
        'Výdaj balíčka',
      );
    }
  }

  String cancellationTarget(String user, String store, String id) {
    requireStore(user, store, manage: true);
    final row = _one('SELECT user_id,payload FROM orders WHERE id=?', [id]);
    final order = RescueOrder.fromJson(
      database.decode(row['payload'] as String),
    );
    if (!order.items.any((i) => managed(i.offerId)?['store_id'] == store)) {
      throw const ApiFailure(404, 'Objednávka sa nenašla.');
    }
    if (order.items.any((i) => managed(i.offerId)?['store_id'] != store)) {
      throw const ApiFailure(
        409,
        'Objednávka obsahuje viac prevádzok. Storno musí vyriešiť správca platformy.',
      );
    }
    return row['user_id'] as String;
  }

  void auditCancellation(String user, String store, String id, String reason) {
    _event(store, user, 'order_cancelled', '$id: $reason');
  }

  Map<String, dynamic> pickupTarget(
    String user,
    String store,
    String id,
    String code,
  ) {
    requireStore(user, store);
    final row = _one('SELECT user_id,payload FROM orders WHERE id=?', [id]);
    final order = RescueOrder.fromJson(
      database.decode(row['payload'] as String),
    );
    if (!constantPickupCode(code, order.pickupCode)) {
      throw const ApiFailure(403, 'Kód vyzdvihnutia nie je správny.');
    }
    final ids = order.items
        .where((i) => managed(i.offerId)?['store_id'] == store)
        .map((i) => i.offerId)
        .toList();
    if (ids.isEmpty) throw const ApiFailure(404, 'Objednávka sa nenašla.');
    return {'userId': row['user_id'], 'offerIds': ids};
  }

  bool constantPickupCode(String actual, String? expected) =>
      hashToken(actual.trim().toUpperCase()) == hashToken(expected ?? '');

  Map<String, dynamic> saveRule(
    String user,
    Map<String, dynamic> b, {
    String? id,
  }) => database.transaction(() {
    final store = requireStore(user, _text(b, 'storeId'), manage: true);
    if (id != null) {
      final previous = _one('SELECT store_id FROM bundle_rules WHERE id=?', [
        id,
      ]);
      if (previous['store_id'] != store.id) {
        throw const ApiFailure(404, 'Pravidlo sa nenašlo.');
      }
    }
    final start = _integer(b, 'startMinutes', 0, 1438),
        end = _integer(b, 'endMinutes', 1, 1439);
    if (end <= start || end - start > 720) {
      throw const ApiFailure(400, 'Neplatné výdajové okno.');
    }
    final category = FoodCategory.values.byName(_text(b, 'category'));
    if (category == FoodCategory.flowers) {
      throw const ApiFailure(400, 'Vyber potravinovú kategóriu.');
    }
    final rule = BundleRule(
      id: id ?? _id(),
      storeId: store.id,
      name: _text(b, 'name', min: 3, max: 100),
      category: category,
      storage: StorageZone.values.byName(_text(b, 'storage')),
      daysBefore: _integer(b, 'daysBefore', 0, 14),
      targetValue: _integer(b, 'targetValue', 100, 100000),
      discountPercent: _integer(b, 'discountPercent', 1, 90),
      maxPacks: _integer(b, 'maxPacks', 1, 1000),
      startMinutes: start,
      endMinutes: end,
      autoPublish: b['autoPublish'] == true,
      enabled: b['enabled'] != false,
    );
    database.db.execute(
      'INSERT INTO bundle_rules VALUES(?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET payload=excluded.payload,enabled=excluded.enabled',
      [
        rule.id,
        store.id,
        jsonEncode(rule.toJson()),
        rule.enabled ? 1 : 0,
        _now,
      ],
    );
    _event(store.id, user, 'rule_saved', rule.id);
    return rule.toJson();
  });
  Map<String, dynamic> runRules(String user, String store) {
    requireStore(user, store, manage: true);
    return _runRules(store, actor: user);
  }

  Map<String, dynamic> _runRules(
    String store, {
    required String actor,
  }) => database.transaction(() {
    final date = tz.TZDateTime.from(
      clock(),
      tz.getLocation('Europe/Bratislava'),
    );
    final day =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    final results = <Map<String, dynamic>>[];
    for (final row in _rows(
      'SELECT payload FROM bundle_rules WHERE store_id=? AND enabled=1 ORDER BY created_at,id',
      [store],
    )) {
      final rule = BundleRule.fromJson(
        database.decode(row['payload'] as String),
      );
      final existing = _rows(
        'SELECT offer_id,state FROM merchant_offers WHERE rule_id=? AND business_day=?',
        [rule.id, day],
      );
      if (existing.isNotEmpty) {
        results.add({
          'ruleId': rule.id,
          'status': 'existing',
          'offerId': existing.first['offer_id'],
        });
        continue;
      }
      final start = tz.TZDateTime(
        date.location,
        date.year,
        date.month,
        date.day,
        rule.startMinutes ~/ 60,
        rule.startMinutes % 60,
      );
      final end = tz.TZDateTime(
        date.location,
        date.year,
        date.month,
        date.day,
        rule.endMinutes ~/ 60,
        rule.endMinutes % 60,
      );
      if (!end.isAfter(clock())) {
        results.add({'ruleId': rule.id, 'status': 'window_ended'});
        continue;
      }
      final horizon = tz.TZDateTime(
        date.location,
        date.year,
        date.month,
        date.day + rule.daysBefore + 1,
      );
      final lots = _rows(
        "SELECT l.* FROM stock_lots l WHERE l.store_id=? AND l.quality='checked' AND l.deadline>? AND l.deadline<=? ORDER BY l.deadline,l.id",
        [
          store,
          end.toUtc().toIso8601String(),
          horizon.toUtc().toIso8601String(),
        ],
      );
      final recipe = <String, int>{};
      var value = 0;
      for (final lot in lots) {
        final product = _product(lot['product_id'] as String);
        if (product.category != rule.category ||
            product.storage != rule.storage) {
          continue;
        }
        final free = _available(lot);
        if (free <= 0) continue;
        final take = math.min(
          free,
          (rule.targetValue * 1000 - value + product.valueMilliCents(1) - 1) ~/
              product.valueMilliCents(1),
        );
        if (take <= 0) break;
        recipe.update(product.id, (n) => n + take, ifAbsent: () => take);
        value += product.valueMilliCents(take);
        if (value >= rule.targetValue * 1000) break;
      }
      if (value < rule.targetValue * 1000 ||
          recipe.length > 30 ||
          recipe.entries.any(
            (e) => e.value > 1000 * _product(e.key).unit.scale,
          )) {
        results.add({'ruleId': rule.id, 'status': 'insufficient_stock'});
        continue;
      }
      final merchant = MerchantStore.fromJson(
        database.decode(
          _one('SELECT payload FROM merchant_stores WHERE id=?', [
                store,
              ])['payload']
              as String,
        ),
      );
      final offer = _createOffer(
        merchant,
        {
          'recipe': recipe,
          'title': rule.name,
          'description':
              'Balíček zostavený z prebytkov podľa aktuálnych zásob. Obsah určuje receptúra prevádzky. Skladovanie: ${rule.storage.label}.',
          'category': rule.category.name,
          'image': _product(recipe.keys.first).image,
          'price': math.max(
            50,
            (((value + 500) ~/ 1000) * (100 - rule.discountPercent) + 50) ~/
                100,
          ),
          'stock': rule.maxPacks,
          'pickupStart': start.toUtc().toIso8601String(),
          'pickupEnd': end.toUtc().toIso8601String(),
          'state': rule.autoPublish ? 'published' : 'draft',
        },
        actor,
        ruleId: rule.id,
        day: day,
        eligibleUntil: horizon,
      );
      results.add({
        'ruleId': rule.id,
        'status': offer['state'],
        'offerId': offer['id'],
      });
    }
    return {'results': results};
  });
  void runScheduled() {
    for (final row in _rows(
      "SELECT DISTINCT r.store_id FROM bundle_rules r JOIN merchant_stores s ON s.id=r.store_id LEFT JOIN platform_organizations p ON p.org_id=s.org_id LEFT JOIN platform_stores b ON b.store_id=s.id WHERE r.enabled=1 AND COALESCE(p.status,'active')='active' AND COALESCE(b.paused,0)=0",
    )) {
      _runRules(row['store_id'] as String, actor: 'automation');
    }
  }

  Map<String, dynamic> createIntegration(
    String user,
    Map<String, dynamic> b,
  ) => database.transaction(() {
    final store = requireStore(user, _text(b, 'storeId'), owner: true),
        name = _text(b, 'name', min: 2, max: 100);
    final id = _id(), token = 'nvp_stock_${randomSecret()}';
    database.db.execute(
      'INSERT INTO stock_integrations(id,store_id,name,token_hash,created_at) VALUES(?,?,?,?,?)',
      [id, store.id, name, hashToken(token), _now],
    );
    initializeDelivery(id, store.id);
    _event(store.id, user, 'integration_created', id);
    return {'id': id, 'token': token, 'storeId': store.id};
  });
  void revokeIntegration(String user, String id) => database.transaction(() {
    final row = _one('SELECT * FROM stock_integrations WHERE id=?', [id]);
    requireStore(user, row['store_id'] as String, owner: true);
    database.db.execute('UPDATE stock_integrations SET revoked=1 WHERE id=?', [
      id,
    ]);
    _event(row['store_id'] as String, user, 'integration_revoked', id);
  });
  Map<String, dynamic> _integration(String? authorization) {
    if (authorization == null ||
        !authorization.startsWith('Bearer nvp_stock_')) {
      throw const ApiFailure(401, 'Chýba skladový token.');
    }
    final rows = _rows(
      'SELECT * FROM stock_integrations WHERE token_hash=? AND revoked=0',
      [hashToken(authorization.substring(7))],
    );
    if (rows.isEmpty) throw const ApiFailure(401, 'Skladový token neplatí.');
    if (_rows(
      "SELECT s.id FROM merchant_stores s JOIN platform_organizations p ON p.org_id=s.org_id WHERE s.id=? AND p.status='suspended'",
      [rows.first['store_id']],
    ).isNotEmpty) {
      throw const ApiFailure(403, 'Firma je pozastavená.');
    }
    return rows.first;
  }

  Map<String, dynamic> integrationStock(String? authorization, {int? after}) {
    final integration = _integration(authorization);
    final lots = _rows(
      'SELECT *,rowid cursor FROM stock_lots WHERE store_id=? AND (? IS NULL OR rowid>?) ORDER BY rowid LIMIT 201',
      [integration['store_id'], after, after],
    );
    return {
      'storeId': integration['store_id'],
      'nextCursor': lots.length > 200 ? lots[199]['cursor'].toString() : null,
      'lots': lots
          .take(200)
          .map(
            (l) => {
              ..._lotJson(l),
              'sku': _product(l['product_id'] as String).sku,
            },
          )
          .toList(),
    };
  }

  Map<String, dynamic> integrationEvent(
    String? authorization,
    Map<String, dynamic> b,
  ) => database.transaction(() {
    final integration = _integration(authorization),
        event = _text(b, 'eventId', min: 8, max: 100),
        requestHash = hashToken(jsonEncode(_canonical(b)));
    final previous = _rows(
      'SELECT request_hash,response FROM stock_events WHERE integration_id=? AND event_id=?',
      [integration['id'], event],
    );
    if (previous.isNotEmpty) {
      if (previous.first['request_hash'] != requestHash) {
        throw const ApiFailure(409, 'Identifikátor udalosti už má iný obsah.');
      }
      return database.decode(previous.first['response'] as String);
    }
    final store = MerchantStore.fromJson(
      database.decode(
        _one('SELECT payload FROM merchant_stores WHERE id=?', [
              integration['store_id'],
            ])['payload']
            as String,
      ),
    );
    final productId =
        _one('SELECT id FROM stock_products WHERE org_id=? AND sku=?', [
              store.organizationId,
              _text(b, 'sku', max: 80),
            ])['id']
            as String;
    final unit = _product(productId).unit;
    if (b['unit'] != null && b['unit'] != unit.name) {
      throw const ApiFailure(
        409,
        'Jednotka externej položky nesúhlasí s katalógom.',
      );
    }
    final operation = _text(b, 'operation'),
        actor = 'integration:${integration['id']}';
    Map<String, dynamic> result;
    if (operation == 'receive') {
      // External receipts always wait for a local quality check.
      result = _receive(store, {
        ...b,
        'productId': productId,
        'quality': 'quarantine',
      }, actor);
    } else if (operation == 'adjust' || operation == 'set') {
      final lot = _one(
        'SELECT * FROM stock_lots WHERE store_id=? AND product_id=? AND lot_code=?',
        [store.id, productId, _text(b, 'lotCode', max: 100)],
      );
      if (operation == 'set') {
        final sequence = _integer(b, 'sequence', 1, 2147483647);
        final previous = _rows(
          'SELECT sequence FROM stock_sync_versions WHERE integration_id=? AND lot_id=?',
          [integration['id'], lot['id']],
        );
        if (b['expectedVersion'] != lot['version'] ||
            previous.isNotEmpty &&
                sequence <= (previous.first['sequence'] as int)) {
          throw const ApiFailure(
            409,
            'Stav skladu alebo poradie udalostí sa zmenilo. Najprv zosúlaď sklad.',
          );
        }
        database.db.execute(
          'INSERT INTO stock_sync_versions VALUES(?,?,?) ON CONFLICT(integration_id,lot_id) DO UPDATE SET sequence=excluded.sequence',
          [integration['id'], lot['id'], sequence],
        );
      }
      final delta = operation == 'set'
          ? _amount(b, 'onHand', unit, 0, 1000000) - (lot['on_hand'] as int)
          : _amount(b, 'delta', unit, -1000000, 1000000);
      result = delta == 0
          ? _lotJson(lot)
          : _adjust(lot, {
              'delta': delta,
              'reason': _text(b, 'reason', min: 3, max: 300),
            }, actor);
    } else {
      throw const ApiFailure(400, 'Neplatná skladová operácia.');
    }
    database.db.execute('INSERT INTO stock_events VALUES(?,?,?,?,?)', [
      integration['id'],
      event,
      requestHash,
      jsonEncode(result),
      _now,
    ]);
    database.db.execute(
      'UPDATE stock_integrations SET last_seen=? WHERE id=?',
      [_now, integration['id']],
    );
    return result;
  });
  Map<String, dynamic> importCsv(
    String user,
    String store,
    Map<String, dynamic> b,
  ) => database.transaction(() {
    final branch = requireStore(user, store);
    final content = _text(b, 'csv', min: 1, max: 55000),
        delimiter = b['delimiter'] as String? ?? ',';
    if (!{',', ';'}.contains(delimiter)) {
      throw const ApiFailure(
        400,
        'Oddeľovač musí byť čiarka alebo bodkočiarka.',
      );
    }
    final rows = CsvToListConverter(
      fieldDelimiter: delimiter,
      shouldParseNumbers: false,
      eol: '\n',
      allowInvalid: false,
    ).convert(content.replaceFirst('\uFEFF', '').replaceAll('\r\n', '\n'));
    const columns = ['sku', 'lotCode', 'quantity', 'deadline', 'dateType'];
    if (rows.length < 2 ||
        rows.length > 201 ||
        rows.first.length != columns.length ||
        rows.first.map((v) => v.toString().trim()).join(',') !=
            columns.join(',')) {
      throw const ApiFailure(
        400,
        'CSV potrebuje hlavičku sku,lotCode,quantity,deadline,dateType a najviac 200 riadkov.',
      );
    }
    final results = <Map<String, dynamic>>[];
    for (var i = 1; i < rows.length; i++) {
      final row = rows[i];
      if (row.length != columns.length) {
        throw ApiFailure(
          400,
          'CSV riadok ${i + 1} má nesprávny počet stĺpcov.',
        );
      }
      final fields = Map<String, dynamic>.fromIterables(
        columns,
        row.map((v) => v.toString().trim()),
      );
      final product = _one(
        'SELECT id FROM stock_products WHERE org_id=? AND sku=?',
        [branch.organizationId, fields['sku']],
      );
      results.add(
        _receive(branch, {
          ...fields,
          'productId': product['id'],
          'quantityDisplay': fields['quantity'],
          'quality': 'quarantine',
        }, user),
      );
    }
    return {'imported': results.length, 'lots': results};
  });
  void setMember(
    String user,
    Map<String, dynamic> b,
  ) => database.transaction(() {
    final org = _text(b, 'organizationId');
    _org(user, org, owner: true);
    final role = _text(b, 'role');
    if (!{'manager', 'staff', 'remove'}.contains(role)) {
      throw const ApiFailure(400, 'Vyber rolu manažér alebo personál.');
    }
    final member =
        _one('SELECT id FROM users WHERE email=?', [
              _text(b, 'email').toLowerCase(),
            ])['id']
            as String;
    final previous = _rows(
      'SELECT role FROM merchant_members WHERE org_id=? AND user_id=?',
      [org, member],
    );
    if (previous.isNotEmpty && previous.first['role'] == 'owner') {
      throw const ApiFailure(409, 'Vlastníka nemožno takto zmeniť.');
    }
    if (role == 'remove') {
      database.db.execute(
        'DELETE FROM merchant_members WHERE org_id=? AND user_id=?',
        [org, member],
      );
    } else {
      database.db.execute(
        'INSERT INTO merchant_members VALUES(?,?,?) ON CONFLICT(org_id,user_id) DO UPDATE SET role=excluded.role',
        [org, member, role],
      );
      setMemberScope(org, member, b);
    }
  });

  Map<String, dynamic> workspace(String user) {
    final organizations = _rows(
      'SELECT o.*,m.role FROM merchant_organizations o JOIN merchant_members m ON m.org_id=o.id WHERE m.user_id=?',
      [user],
    );
    final stores = storeIds(user),
        orgIds = organizations.map((o) => o['id']).toSet();
    final products =
        _rows(
              'SELECT p.* FROM stock_products p JOIN merchant_members m ON m.org_id=p.org_id WHERE m.user_id=?',
              [user],
            )
            .where((p) => orgIds.contains(p['org_id']))
            .map((p) => database.decode(p['payload'] as String))
            .toList();
    final lots = _rows(
      'SELECT l.* FROM stock_lots l JOIN merchant_stores s ON s.id=l.store_id JOIN merchant_members m ON m.org_id=s.org_id WHERE m.user_id=? ORDER BY l.deadline,l.id',
      [user],
    ).where((l) => stores.contains(l['store_id'])).map(_lotJson).toList();
    final offers =
        _rows(
          'SELECT m.*,o.payload FROM merchant_offers m JOIN offers o ON o.id=m.offer_id JOIN merchant_stores s ON s.id=m.store_id JOIN merchant_members a ON a.org_id=s.org_id WHERE a.user_id=? ORDER BY m.created_at DESC',
          [user],
        ).where((o) => stores.contains(o['store_id'])).map((r) {
          final offer = database.decode(r['payload'] as String);
          return {
            'offer': offer,
            'storeId': r['store_id'],
            'state': r['state'],
            'recipe': jsonDecode(r['recipe'] as String),
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
        }).toList();
    final orders = <Map<String, dynamic>>[];
    for (final row in _rows(
      'SELECT DISTINCT o.id,o.payload,o.status,o.rowid FROM orders o JOIN merchant_order_lines l ON l.order_id=o.id JOIN merchant_stores s ON s.id=l.store_id JOIN merchant_members m ON m.org_id=s.org_id WHERE m.user_id=? ORDER BY o.rowid DESC',
      [user],
    )) {
      final order = RescueOrder.fromJson(
        database.decode(row['payload'] as String),
      );
      final items = order.items
          .where((i) => stores.contains(managed(i.offerId)?['store_id']))
          .toList();
      if (items.isEmpty) continue;
      final risk =
          _rows(
            "SELECT r.offer_id,l.quality,l.deadline FROM stock_reservations r JOIN stock_lots l ON l.id=r.lot_id WHERE r.order_id=? AND r.state='held'",
            [order.id],
          ).any(
            (r) =>
                items.any((i) => i.offerId == r['offer_id']) &&
                (r['quality'] != 'checked' ||
                    !DateTime.parse(r['deadline'] as String).isAfter(clock())),
          );
      final orderStores = order.items
          .map((i) => managed(i.offerId)?['store_id'])
          .toSet();
      orders.add({
        'id': order.id,
        'status': row['status'],
        'items': items.map((i) => i.toJson()).toList(),
        'createdAt': order.createdAt.toIso8601String(),
        'atRisk': risk,
        'cancellableStoreId': orderStores.length == 1
            ? orderStores.single
            : null,
      });
    }
    final ownerOrgs = organizations
        .where((o) => o['role'] == 'owner')
        .map((o) => o['id'])
        .toSet();
    final ownerStores = _rows(
      'SELECT id,org_id FROM merchant_stores',
    ).where((s) => ownerOrgs.contains(s['org_id'])).map((s) => s['id']).toSet();
    return {
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
      'stores': _rows(
        'SELECT s.* FROM merchant_stores s JOIN merchant_members m ON m.org_id=s.org_id WHERE m.user_id=?',
        [user],
      ).where((s) => stores.contains(s['id'])).map(storePresentation).toList(),
      'products': products,
      'lots': lots,
      'offers': offers,
      'orders': orders,
      'rules':
          _rows(
                'SELECT r.* FROM bundle_rules r JOIN merchant_stores s ON s.id=r.store_id JOIN merchant_members m ON m.org_id=s.org_id WHERE m.user_id=?',
                [user],
              )
              .where((r) => stores.contains(r['store_id']))
              .map((r) => database.decode(r['payload'] as String))
              .toList(),
      'movements': _rows(
        'SELECT v.* FROM stock_movements v JOIN merchant_stores s ON s.id=v.store_id JOIN merchant_members m ON m.org_id=s.org_id WHERE m.user_id=? ORDER BY v.rowid DESC LIMIT 300',
        [user],
      ).where((m) => stores.contains(m['store_id'])).take(300).toList(),
      'integrations': _rows(
        'SELECT id,store_id,name,revoked,created_at,last_seen FROM stock_integrations',
      ).where((r) => ownerStores.contains(r['store_id'])).toList(),
      'members': _rows(
        'SELECT m.org_id,m.role,u.email,u.name FROM merchant_members m JOIN users u ON u.id=m.user_id',
      ).where((m) => ownerOrgs.contains(m['org_id'])).toList(),
    };
  }
}

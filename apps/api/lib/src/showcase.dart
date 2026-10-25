import 'dart:convert';
import 'package:marketplace_domain/marketplace_domain.dart';
import 'package:timezone/timezone.dart' as tz;
import 'auth.dart';
import 'database.dart';
import 'merchant.dart';

/// Opt-in fictional data, inserted with the same stock service as normal writes.
/// No passwords, external providers, real card numbers or live payments.
class DemoShowcase {
  DemoShowcase(this.database, this.merchants, this.clock);
  final MarketplaceDatabase database;
  final MerchantService merchants;
  final DateTime Function() clock;
  static const userPrefix = 'showcase-';
  static const customer = '${userPrefix}customer';
  final _zone = tz.getLocation('Europe/Bratislava');
  String get _now => clock().toUtc().toIso8601String();

  void ensure() => database.transaction(() {
    database.db.execute(
      'CREATE TABLE IF NOT EXISTS demo_showcase(key TEXT PRIMARY KEY,payload TEXT NOT NULL)',
    );
    _user('customer', 'Sofia Nováková');
    _user('bakery', 'Lucia · Pekáreň Maslo');
    _user('restaurant', 'Martin · Bistro Záhrada');
    _user('grocery', 'Adam · Dobrý obchod');
    _user('visitor', 'Alex · demo zákazník');
    final local = tz.TZDateTime.from(clock(), _zone);
    final day = '${local.year}-${local.month}-${local.day}';
    if (_read('day:$day') != null) return;
    final bakery = _business(
      'bakery',
      'Pekáreň Maslo',
      'Čerstvo upečené dobro',
      'Štefánikova 12, Bratislava',
      'bakery',
      'ambient',
      [
        ('Kváskový chlieb', 'bread', 400, 'Lepok'),
        ('Maslový croissant', 'bakery', 250, 'Lepok, mlieko, vajcia'),
        ('Škoricový slimák', 'bakery', 350, 'Lepok, mlieko, vajcia'),
      ],
    );
    final restaurant = _business(
      'restaurant',
      'Bistro Záhrada',
      'Dobré menu do krabičky',
      'Dunajská 8, Bratislava',
      'meals',
      'chilled',
      [
        ('Zeleninová miska s kuskusom', 'meal', 650, 'Lepok, sezam'),
        ('Sezónny šalát', 'salad', 450, 'Horčica'),
        ('Pečená zelenina s ryžou', 'meal', 750, 'Bez deklarovaných alergénov'),
      ],
    );
    final grocery = _business(
      'grocery',
      'Dobrý obchod',
      'Malý nákup, veľká záchrana',
      'Záhradnícka 21, Bratislava',
      'groceries',
      'chilled',
      [
        ('Biely jogurt · balenie', 'vegetables', 350, 'Mlieko'),
        ('Čerstvý tvaroh · balenie', 'vegetables', 250, 'Mlieko'),
        (
          'Zeleninový mix · balenie',
          'salad',
          400,
          'Bez deklarovaných alergénov',
        ),
      ],
    );
    for (final b in [bakery, restaurant, grocery]) {
      _day(b, local, day);
    }
    // A second bakery branch demonstrates organization-wide stock and branch selection.
    final branch = Map<String, dynamic>.from(bakery);
    branch['storeId'] = bakery['branchId'];
    branch['name'] = 'Pekáreň Maslo · Ružinov';
    _day(branch, local, '$day-branch', history: false);
    final favoriteIds = database.db
        .select(
          "SELECT o.offer_id FROM merchant_offers o JOIN merchant_stores s ON s.id=o.store_id WHERE o.state='published' ORDER BY o.rowid DESC LIMIT 4",
        )
        .map((r) => r['offer_id'] as String)
        .toList();
    final profile = database.decode(
      database.db.select('SELECT profile FROM users WHERE id=?', [
            customer,
          ]).first['profile']
          as String,
    );
    profile['favorites'] = favoriteIds;
    profile['invoice'] = _invoice.toJson();
    database.db.execute(
      'UPDATE users SET profile=?,member_until=?,trial_used=1 WHERE id=?',
      [
        jsonEncode(profile),
        clock().add(const Duration(days: 30)).toUtc().toIso8601String(),
        customer,
      ],
    );
    _write('day:$day', {'createdAt': _now});
  });

  void _user(String persona, String name) {
    database.db.execute(
      'INSERT OR IGNORE INTO users(id,email,name,credit) VALUES(?,?,?,?)',
      [
        '$userPrefix$persona',
        '$persona@demo.nevyhadzuj.test',
        name,
        persona == 'customer' ? 650 : 0,
      ],
    );
  }

  Map<String, dynamic>? _read(String key) {
    final rows = database.db.select(
      'SELECT payload FROM demo_showcase WHERE key=?',
      [key],
    );
    return rows.isEmpty
        ? null
        : database.decode(rows.first['payload'] as String);
  }

  void _write(String key, Map<String, dynamic> value) => database.db.execute(
    'INSERT INTO demo_showcase VALUES(?,?)',
    [key, jsonEncode(value)],
  );

  Map<String, dynamic> _business(
    String persona,
    String name,
    String title,
    String address,
    String category,
    String storage,
    List<(String, String, int, String)> products,
  ) {
    final previous = _read('business:$persona');
    if (previous != null) return previous;
    final user = '$userPrefix$persona';
    final kind = switch (persona) {
      'restaurant' => 'restaurant',
      'grocery' => 'grocery',
      _ => 'bakery',
    };
    final result = merchants.createOrganization(user, {
      'name': '$name · demo s.r.o.',
      'companyId': '00000001',
      'contactEmail': '$persona@demo.nevyhadzuj.test',
      'store': {
        'name': name,
        'kind': kind,
        'address': address,
        'point': {
          'lat': 48.1487 + (persona == 'bakery' ? .004 : .0),
          'lng': 17.1077 + (persona == 'grocery' ? .02 : .0),
        },
      },
    });
    final org = result['organizationId'] as String;
    final ids = <String>[];
    for (var i = 0; i < products.length; i++) {
      final p = products[i];
      final product = merchants.createProduct(user, {
        'organizationId': org,
        'sku': '000${i + 101}',
        'name': p.$1,
        'category': category,
        'unit': persona == 'restaurant' ? 'portion' : 'piece',
        'unitValue': p.$3,
        'allergens': p.$4,
        'storage': storage,
        'image': p.$2,
      });
      ids.add(product['id'] as String);
    }
    String? branch;
    if (persona == 'bakery') {
      branch =
          merchants.createStore(user, {
                'organizationId': org,
                'name': 'Pekáreň Maslo · Ružinov',
                'kind': kind,
                'address': 'Ružová dolina 6, Bratislava',
                'point': {'lat': 48.1519, 'lng': 17.1424},
              })['id']
              as String;
    }
    final b = {
      ...result,
      'persona': persona,
      'name': name,
      'title': title,
      'category': category,
      'storage': storage,
      'products': ids,
      'branchId': branch,
      'image': products.first.$2,
      'secondImage': products.last.$2,
      'value': products[0].$3 + products[1].$3 * 2,
      'secondValue': products[2].$3 * 2,
    };
    _write('business:$persona', b);
    return b;
  }

  void _day(
    Map<String, dynamic> b,
    tz.TZDateTime today,
    String day, {
    bool history = true,
  }) {
    final user = '$userPrefix${b['persona']}', store = b['storeId'] as String;
    final products = (b['products'] as List).cast<String>();
    final deadline = tz.TZDateTime(
      _zone,
      today.year,
      today.month,
      today.day + 1,
      20,
    );
    for (var i = 0; i < products.length; i++) {
      merchants.receive(user, {
        'storeId': store,
        'productId': products[i],
        'lotCode': 'DEMO-$day-${i + 1}',
        'quantity': [48, 72, 36][i],
        'deadline': deadline.toUtc().toIso8601String(),
        'dateType': b['persona'] == 'bakery' ? 'bestBefore' : 'useBy',
        'quality': 'checked',
      });
    }
    merchants.receive(user, {
      'storeId': store,
      'productId': products[1],
      'lotCode': 'KONTROLA-$day',
      'quantity': 12,
      'deadline': deadline.toUtc().toIso8601String(),
      'dateType': 'useBy',
      'quality': 'quarantine',
    });
    merchants.receive(user, {
      'storeId': store,
      'productId': products[2],
      'lotCode': 'VYRADENE-$day',
      'quantity': 4,
      'deadline': deadline.toUtc().toIso8601String(),
      'dateType': 'useBy',
      'quality': 'withdrawn',
    });
    final past = today.subtract(const Duration(days: 1));
    final pastClock = tz.TZDateTime(
      _zone,
      past.year,
      past.month,
      past.day,
      10,
    ).toUtc();
    final historical = MerchantService(
      database,
      clock: () => pastClock,
      allowDemoImages: true,
    );
    historical.receive(user, {
      'storeId': store,
      'productId': products[0],
      'lotCode': 'PO-TERMINE-$day',
      'quantity': 3,
      'deadline': tz.TZDateTime(
        _zone,
        past.year,
        past.month,
        past.day,
        23,
      ).toUtc().toIso8601String(),
      'dateType': 'useBy',
      'quality': 'checked',
    });
    final start = clock().subtract(const Duration(minutes: 15));
    final end = clock().add(const Duration(hours: 3));
    final main = _offer(
      merchants,
      user,
      b,
      '${b['title']}',
      'published',
      start,
      end,
    );
    _offer(
      merchants,
      user,
      b,
      'Malá radosť so zľavou',
      'published',
      start,
      end,
      second: true,
    );
    final paused = _offer(
      merchants,
      user,
      b,
      'Balíček na ďalšiu vlnu',
      'published',
      start,
      end,
      second: true,
    );
    merchants.offerState(user, paused, {'state': 'paused'});
    _offer(
      merchants,
      user,
      b,
      'Zajtrajší výber na schválenie',
      'draft',
      tz.TZDateTime(_zone, today.year, today.month, today.day + 1, 16),
      tz.TZDateTime(_zone, today.year, today.month, today.day + 1, 19),
    );
    // Generated drafts use the real rule engine, including expiry and quality filters.
    final ruleKey = 'rule:$store';
    if (_read(ruleKey) == null) {
      final rule = merchants.saveRule(user, {
        'storeId': store,
        'name': 'Druhá šanca · denný výber',
        'category': b['category'],
        'storage': b['storage'],
        'daysBefore': 2,
        'targetValue': b['value'],
        'discountPercent': 60,
        'maxPacks': 12,
        'startMinutes': (today.hour * 60 + today.minute - 30).clamp(0, 1438),
        'endMinutes': (today.hour * 60 + today.minute + 180).clamp(1, 1439),
        'autoPublish': false,
        'enabled': true,
      });
      _write(ruleKey, {'id': rule['id']});
    }
    merchants.runRules(user, store);
    _order(
      merchants,
      customer,
      main,
      '$day-${b['persona']}-ready',
      1,
      OrderStatus.reserved,
      clock(),
    );
    _order(
      merchants,
      '${userPrefix}visitor',
      main,
      '$day-${b['persona']}-visitor',
      2,
      OrderStatus.reserved,
      clock(),
    );
    if (history) {
      final old = _offer(
        historical,
        user,
        b,
        'Včerajšia dobrá záchrana',
        'published',
        tz.TZDateTime(_zone, past.year, past.month, past.day, 17),
        tz.TZDateTime(_zone, past.year, past.month, past.day, 19),
      );
      _order(
        historical,
        customer,
        old,
        '$day-${b['persona']}-collected',
        2,
        OrderStatus.collected,
        pastClock,
      );
      _order(
        historical,
        customer,
        old,
        '$day-${b['persona']}-cancelled',
        1,
        OrderStatus.cancelled,
        pastClock,
      );
      database.db.execute(
        'INSERT OR IGNORE INTO reviews(user_id,offer_id,rating,comment,created_at) VALUES(?,?,?,?,?)',
        [
          customer,
          old,
          5,
          'Milý personál, chutný balíček a jednoduché vyzdvihnutie. Demo hodnotenie.',
          pastClock.toIso8601String(),
        ],
      );
    }
  }

  String _offer(
    MerchantService service,
    String user,
    Map<String, dynamic> b,
    String title,
    String state,
    DateTime start,
    DateTime end, {
    bool second = false,
  }) {
    final p = (b['products'] as List).cast<String>();
    final value = b[second ? 'secondValue' : 'value'] as int;
    return service.createOffer(user, {
          'storeId': b['storeId'],
          'title': title,
          'description':
              'Poctivé dobroty z prevádzky ${b['name']}, ktoré si zaslúžia druhú šancu. '
              'Obsah sa riadi uvedenou receptúrou a označenými alergénmi. Vyzdvihni si balíček vo výdajovom okne. '
              'Fiktívna demo prevádzka s ilustračnou fotografiou.',
          'category': b['category'],
          'image': b[second ? 'secondImage' : 'image'],
          'price': (value * .4).round(),
          'stock': 18,
          'state': state,
          'pickupStart': start.toUtc().toIso8601String(),
          'pickupEnd': end.toUtc().toIso8601String(),
          'recipe': second ? {p[2]: 2} : {p[0]: 1, p[1]: 2},
        })['id']
        as String;
  }

  static const _invoice = InvoiceDetails(
    name: 'Sofia Nováková',
    email: 'customer@demo.nevyhadzuj.test',
    street: 'Ukážková 12',
    city: 'Bratislava',
    postcode: '81101',
  );

  void _order(
    MerchantService service,
    String user,
    String offerId,
    String key,
    int quantity,
    OrderStatus status,
    DateTime created,
  ) {
    final food = FoodOffer.fromJson(
      database.decode(
        database.db.select('SELECT payload FROM offers WHERE id=?', [
              offerId,
            ]).first['payload']
            as String,
      ),
    );
    final quote = CheckoutQuote.calculate(
      subtotal: food.price * quantity,
      clubMember: user == customer,
      credit: 0,
      useCredit: false,
    );
    final order = RescueOrder(
      id: '${hashToken('showcase:$key').substring(0, 16)}-demo',
      createdAt: created.toUtc(),
      items: [
        OrderItem(
          offerId: food.id,
          store: food.store,
          title: food.title,
          image: food.image,
          quantity: quantity,
          unitPrice: food.price,
          pickupStart: food.pickupStart,
          pickupEnd: food.pickupEnd,
          address: food.address,
        ),
      ],
      total: quote.total,
      discount: quote.discount,
      serviceFee: quote.serviceFee,
      creditUsed: 0,
      cashback: quote.cashback,
      invoice: _invoice,
      pickupCode:
          'D${key.hashCode.abs().toString().padLeft(7, '0').substring(0, 7)}',
    );
    database.db.execute(
      'INSERT INTO orders(id,user_id,idempotency,request_hash,payload,status,payment_session) VALUES(?,?,?,?,?,?,?)',
      [
        order.id,
        user,
        'showcase-$key',
        hashToken(key),
        jsonEncode(order.toJson()),
        'reserved',
        'sandbox_${order.id}',
      ],
    );
    service.hold(order);
    if (status == OrderStatus.collected) {
      service.consume(order, order.items);
      if (order.cashback > 0) {
        database.db.execute('UPDATE users SET credit=credit+? WHERE id=?', [
          order.cashback,
          user,
        ]);
        database.db.execute('INSERT INTO ledger VALUES(?,?,?,?,?,?)', [
          'demo-cashback-$key',
          user,
          order.id,
          'cashback',
          order.cashback,
          created.toUtc().toIso8601String(),
        ]);
      }
    } else if (status == OrderStatus.cancelled) {
      service.release(order);
    }
    final updated = order.withStatus(
      status,
      updatedItems: status == OrderStatus.collected
          ? order.items.map((i) => i.withCollected()).toList()
          : null,
    );
    database.db.execute('UPDATE orders SET payload=?,status=? WHERE id=?', [
      jsonEncode(updated.toJson()),
      status.name,
      order.id,
    ]);
  }
}

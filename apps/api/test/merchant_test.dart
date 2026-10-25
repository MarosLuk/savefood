import 'dart:convert';
import 'package:marketplace_domain/marketplace_domain.dart';
import 'package:marketplace_server/marketplace_server.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

void main() {
  late MarketplaceServer app;
  late DateTime now;
  late String org, store, product;
  final sessions = <String, String>{};
  Future<Response> call(
    String method,
    String path, {
    Map<String, dynamic>? body,
    String actor = 'owner',
    String? token,
  }) async => app.handler(
    Request(
      method,
      Uri.parse('http://localhost$path'),
      headers: {
        'content-type': 'application/json',
        'authorization': 'Bearer ${token ?? sessions[actor]}',
      },
      body: body == null ? null : jsonEncode(body),
    ),
  );
  Future<Map<String, dynamic>> json(Response r) async =>
      merchantMap(jsonDecode(await r.readAsString()));
  Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> b, {
    String actor = 'owner',
    int status = 201,
  }) async {
    final r = await call(
      'POST',
      path,
      body: {
        ...b,
        'idempotencyKey':
            b['idempotencyKey'] ??
            'mutation-${DateTime.now().microsecondsSinceEpoch}-${b.hashCode}',
      },
      actor: actor,
    );
    final result = await json(r);
    expect(r.statusCode, status, reason: result['error'] as String?);
    return result;
  }

  Future<Map<String, dynamic>> workspace({String actor = 'owner'}) async =>
      json(await call('GET', '/v1/merchant/workspace', actor: actor));
  Future<Map<String, dynamic>> receive(
    String code,
    int count, {
    String? deadline,
    String quality = 'checked',
  }) => post('/v1/merchant/stock/receive', {
    'storeId': store,
    'productId': product,
    'lotCode': code,
    'quantity': count,
    'deadline': deadline ?? '2026-10-24T20:00:00Z',
    'dateType': 'useBy',
    'quality': quality,
  });
  Map<String, dynamic> offerBody({String state = 'published'}) => {
    'storeId': store,
    'title': 'Voňavý balíček',
    'description': 'Čerstvé pečivo z našej prevádzky.',
    'category': 'bakery',
    'image': 'https://images.example.test/bread.jpg',
    'price': 150,
    'stock': 10,
    'pickupStart': '2026-10-24T12:00:00Z',
    'pickupEnd': '2026-10-24T13:00:00Z',
    'recipe': {product: 2},
    'state': state,
  };
  Future<String> offer({String state = 'published'}) async =>
      (await post('/v1/merchant/offers', offerBody(state: state)))['id']
          as String;
  Future<Response> reserve(
    String id, {
    int count = 1,
    String key = 'merchant-order-idempotency-1',
    List<Map<String, dynamic>>? items,
  }) => call(
    'POST',
    '/v1/orders',
    actor: 'buyer',
    body: {
      'idempotencyKey': key,
      'items':
          items ??
          [
            {'offerId': id, 'quantity': count},
          ],
      'invoice': {
        'name': 'Jana Nová',
        'email': 'buyer@example.test',
        'street': 'Ulica 1',
        'city': 'Bratislava',
        'postcode': '81101',
      },
    },
  );
  Map<String, dynamic> rule({bool auto = false}) => {
    'storeId': store,
    'name': 'Denný pekársky balíček',
    'category': 'bakery',
    'storage': 'ambient',
    'daysBefore': 1,
    'targetValue': 600,
    'discountPercent': 60,
    'maxPacks': 10,
    'startMinutes': 14 * 60,
    'endMinutes': 15 * 60,
    'autoPublish': auto,
    'enabled': true,
  };
  setUp(() async {
    now = DateTime.utc(2026, 10, 24, 10);
    app = MarketplaceServer(
      const ServerConfig(databasePath: ':memory:', seedDemo: false),
      clock: () => now,
    );
    for (final user in ['owner', 'buyer', 'other', 'staff']) {
      app.database.db.execute(
        'INSERT INTO users(id,email,name) VALUES(?,?,?)',
        [user, '$user@example.test', user],
      );
      sessions[user] = app.auth.createSession(user)['token'] as String;
    }
    final result = await post('/v1/merchant/organizations', {
      'name': 'Dobrá pekáreň s.r.o.',
      'companyId': '12345678',
      'contactEmail': 'owner@example.test',
      'store': {
        'name': 'Dobrá pekáreň',
        'kind': 'bakery',
        'address': 'Hlavná 1, Bratislava',
        'point': {'lat': 48.15, 'lng': 17.1},
      },
    });
    org = result['organizationId'] as String;
    store = result['storeId'] as String;
    product =
        (await post('/v1/merchant/products', {
              'organizationId': org,
              'sku': '000123',
              'name': 'Croissant',
              'category': 'bakery',
              'unit': 'piece',
              'unitValue': 300,
              'allergens': 'Lepok, mlieko',
              'storage': 'ambient',
              'image': 'https://images.example.test/bread.jpg',
            }))['id']
            as String;
  });
  tearDown(() => app.close());
  test(
    'FEFO reservations across competing offers are atomic and idempotent',
    () async {
      final early = await receive('first', 4),
          late = await receive('second', 6, deadline: '2026-10-25T20:00:00Z');
      final a = await offer(), b = await offer();
      final responses = await Future.wait([
        reserve(a, count: 3, key: 'merchant-order-idempotency-a'),
        reserve(b, count: 3, key: 'merchant-order-idempotency-b'),
      ]);
      expect(responses.map((r) => r.statusCode), containsAll([201, 409]));
      final index = responses.indexWhere((r) => r.statusCode == 201),
          order = await json(responses.firstWhere((r) => r.statusCode == 201));
      final retry = await reserve(
        index == 0 ? a : b,
        count: 3,
        key: index == 0
            ? 'merchant-order-idempotency-a'
            : 'merchant-order-idempotency-b',
      );
      expect((await json(retry))['id'], order['id']);
      final lots = (await workspace())['lots'] as List;
      expect(lots.singleWhere((l) => l['id'] == early['id'])['reserved'], 4);
      expect(lots.singleWhere((l) => l['id'] == late['id'])['reserved'], 2);
      expect(app.database.db.select('SELECT id FROM orders'), hasLength(1));
    },
  );
  test(
    'cancel restores availability once and collection consumes physical stock once',
    () async {
      await receive('batch', 10);
      final id = await offer();
      final first = await json(await reserve(id, count: 2));
      await post(
        '/v1/orders/${first['id']}/cancel',
        {},
        actor: 'buyer',
        status: 200,
      );
      await post(
        '/v1/orders/${first['id']}/cancel',
        {},
        actor: 'buyer',
        status: 200,
      );
      expect(((await workspace())['lots'] as List).first['reserved'], 0);
      final second = await json(
        await reserve(id, count: 3, key: 'merchant-second-order-key'),
      );
      final path = '/v1/merchant/stores/$store/orders/${second['id']}/collect';
      await post(path, {'pickupCode': second['pickupCode']}, status: 200);
      await post(path, {'pickupCode': second['pickupCode']}, status: 200);
      final lot = ((await workspace())['lots'] as List).first;
      expect(lot['onHand'], 4);
      expect(lot['reserved'], 0);
      expect(
        app.database.db.select(
          "SELECT * FROM stock_movements WHERE kind='collect'",
        ),
        hasLength(1),
      );
    },
  );
  test(
    'rollback releases earlier components when a later basket line exhausts shared stock',
    () async {
      await receive('batch', 6);
      final a = await offer(), b = await offer();
      expect(
        (await reserve(
          a,
          items: [
            {'offerId': a, 'quantity': 2},
            {'offerId': b, 'quantity': 2},
          ],
        )).statusCode,
        409,
      );
      expect(app.database.db.select('SELECT * FROM orders'), isEmpty);
      expect(
        app.database.db.select('SELECT * FROM stock_reservations'),
        isEmpty,
      );
    },
  );
  test(
    'adjustments respect holds and version, quarantined stock blocks pickup',
    () async {
      final lot = await receive('batch', 10);
      final id = await offer();
      final order = await json(await reserve(id, count: 3));
      await post('/v1/merchant/lots/${lot['id']}/adjust', {
        'version': 1,
        'delta': -5,
        'reason': 'Predaj na pokladni',
      }, status: 409);
      await post('/v1/merchant/lots/${lot['id']}/adjust', {
        'version': 1,
        'delta': -2,
        'reason': 'Predaj na pokladni',
      }, status: 200);
      await post('/v1/merchant/lots/${lot['id']}/adjust', {
        'version': 1,
        'delta': 1,
        'reason': 'Inventúra',
      }, status: 409);
      await post('/v1/merchant/lots/${lot['id']}/quality', {
        'version': 2,
        'quality': 'quarantine',
        'reason': 'Kontrola teploty',
      }, status: 200);
      await post('/v1/merchant/stores/$store/orders/${order['id']}/collect', {
        'pickupCode': order['pickupCode'],
      }, status: 409);
      final ws = await workspace();
      expect((ws['orders'] as List).first['atRisk'], true);
      expect((ws['lots'] as List).first['onHand'], 8);
      expect(
        ((await json(await call('GET', '/v1/catalog')))['offers'] as List)
            .first['stock'],
        0,
      );
    },
  );
  test(
    'uninspected and short-dated lots cannot cover whole pickup window',
    () async {
      await receive('too-soon', 10, deadline: '2026-10-24T12:30:00Z');
      await receive('unchecked', 10, quality: 'quarantine');
      await post('/v1/merchant/offers', offerBody(), status: 409);
      await receive('valid', 4);
      final id = await offer();
      now = DateTime.utc(2026, 10, 24, 21);
      expect((await reserve(id)).statusCode, 409);
    },
  );
  test(
    'organization isolation, staff capabilities and revocation are enforced',
    () async {
      final lot = await receive('batch', 10);
      expect((await workspace(actor: 'other'))['products'], isEmpty);
      await post(
        '/v1/merchant/lots/${lot['id']}/adjust',
        {'version': 1, 'delta': 1, 'reason': 'Cudzie údaje'},
        actor: 'other',
        status: 404,
      );
      await post('/v1/merchant/members', {
        'organizationId': org,
        'email': 'staff@example.test',
        'role': 'staff',
      }, status: 200);
      await post('/v1/merchant/rules', rule(), actor: 'staff', status: 403);
      await post(
        '/v1/merchant/integrations',
        {'storeId': store, 'name': 'POS'},
        actor: 'staff',
        status: 403,
      );
      await post(
        '/v1/merchant/lots/${lot['id']}/adjust',
        {'version': 1, 'delta': 1, 'reason': 'Príjem navyše'},
        actor: 'staff',
        status: 200,
      );
      await post('/v1/merchant/members', {
        'organizationId': org,
        'email': 'staff@example.test',
        'role': 'remove',
      }, status: 200);
      expect((await workspace(actor: 'staff'))['stores'], isEmpty);
    },
  );
  test(
    'seller order view omits buyer invoice, contacts and pickup secret',
    () async {
      await receive('batch', 10);
      final id = await offer();
      await reserve(id);
      final ws = await workspace();
      final order = (ws['orders'] as List).first as Map;
      expect(
        order.keys,
        unorderedEquals([
          'id',
          'status',
          'items',
          'createdAt',
          'atRisk',
          'cancellableStoreId',
        ]),
      );
      expect(jsonEncode(ws), isNot(contains('buyer@example.test')));
    },
  );
  test(
    'automation makes one daily draft, derives price, approval rechecks stock',
    () async {
      final lot = await receive('batch', 10);
      await post('/v1/merchant/rules', rule());
      final path = '/v1/merchant/stores/$store/automation';
      final first = await post(path, {}, status: 200);
      await post(path, {}, status: 200);
      app.merchants.runScheduled();
      final ws = await workspace();
      expect(ws['offers'], hasLength(1));
      final draft = (ws['offers'] as List).first;
      expect(draft['state'], 'draft');
      expect(draft['offer']['price'], 240);
      expect(draft['offer']['originalPrice'], 600);
      expect(draft['offer']['allergens'], 'Lepok, mlieko');
      expect((await json(await call('GET', '/v1/catalog')))['offers'], isEmpty);
      final id = (first['results'] as List).first['offerId'];
      await post('/v1/merchant/lots/${lot['id']}/adjust', {
        'version': 1,
        'delta': -10,
        'reason': 'Inventúra skladu',
      }, status: 200);
      await post('/v1/merchant/offers/$id/state', {
        'state': 'published',
      }, status: 409);
    },
  );
  test(
    'explicit automatic publication and pause control catalog and new reservations',
    () async {
      await receive('batch', 10);
      await post('/v1/merchant/rules', rule(auto: true));
      await post('/v1/merchant/stores/$store/automation', {}, status: 200);
      final catalog =
          (await json(await call('GET', '/v1/catalog')))['offers'] as List;
      expect(catalog, hasLength(1));
      final id = catalog.first['id'] as String;
      await post('/v1/merchant/offers/$id/state', {
        'state': 'paused',
      }, status: 200);
      expect((await reserve(id)).statusCode, 409);
      expect((await json(await call('GET', '/v1/catalog')))['offers'], isEmpty);
    },
  );
  test(
    'stock integration is scoped, idempotent, revocable and requires inspection',
    () async {
      final integration = await post('/v1/merchant/integrations', {
            'storeId': store,
            'name': 'Pokladňa',
          }),
          token = integration['token'] as String;
      final event = {
        'eventId': 'external-receipt-1',
        'operation': 'receive',
        'sku': '000123',
        'lotCode': 'pos-batch',
        'quantity': 6,
        'deadline': '2026-10-24T20:00:00Z',
        'dateType': 'useBy',
        'quality': 'checked',
      };
      expect(
        (await call(
          'POST',
          '/v1/integrations/stock',
          body: event,
          token: token,
        )).statusCode,
        200,
      );
      expect(
        (await call(
          'POST',
          '/v1/integrations/stock',
          body: event,
          token: token,
        )).statusCode,
        200,
      );
      expect(
        (await call(
          'POST',
          '/v1/integrations/stock',
          body: {...event, 'quantity': 9},
          token: token,
        )).statusCode,
        409,
      );
      final ws = await workspace();
      expect(ws['lots'], hasLength(1));
      expect((ws['lots'] as List).first['onHand'], 6);
      expect((ws['lots'] as List).first['quality'], 'quarantine');
      expect(jsonEncode(ws), isNot(contains(token)));
      expect(
        (await call('GET', '/v1/merchant/workspace', token: token)).statusCode,
        401,
      );
      await post(
        '/v1/merchant/integrations/${integration['id']}/revoke',
        {},
        status: 200,
      );
      expect(
        (await call(
          'POST',
          '/v1/integrations/stock',
          body: {...event, 'eventId': 'external-receipt-2'},
          token: token,
        )).statusCode,
        401,
      );
    },
  );
  test(
    'CSV preserves SKU and quotes and rolls back the whole invalid import',
    () async {
      const header = 'sku,lotCode,quantity,deadline,dateType\n';
      final path = '/v1/merchant/stores/$store/import';
      await post(path, {
        'csv': '${header}000123,"batch,one",3,2026-10-24T20:00:00Z,useBy',
      }, status: 200);
      expect(
        ((await workspace())['lots'] as List).first['lotCode'],
        'batch,one',
      );
      await post(path, {
        'csv':
            '${header}000123,second,2,2026-10-24T20:00:00Z,useBy\nunknown,third,2,2026-10-24T20:00:00Z,useBy',
      }, status: 404);
      expect((await workspace())['lots'], hasLength(1));
    },
  );
  test('paused offers keep order backing for existing pickups', () async {
    await receive('batch', 10);
    final id = await offer(), order = await json(await reserve(id));
    await post('/v1/merchant/offers/$id/state', {
      'state': 'paused',
    }, status: 200);
    await post('/v1/merchant/stores/$store/orders/${order['id']}/collect', {
      'pickupCode': order['pickupCode'],
    }, status: 200);
    expect(((await workspace())['lots'] as List).first['onHand'], 8);
  });
  test(
    'manual receipts and imports are idempotent even when the response is retried',
    () async {
      final receipt = {
        'idempotencyKey': 'durable-stock-receipt-key',
        'storeId': store,
        'productId': product,
        'lotCode': 'same',
        'quantity': 8,
        'deadline': '2026-10-24T20:00:00Z',
        'dateType': 'useBy',
        'quality': 'checked',
      };
      await post('/v1/merchant/stock/receive', receipt);
      await post('/v1/merchant/stock/receive', receipt);
      await post('/v1/merchant/stock/receive', {
        ...receipt,
        'quantity': 7,
      }, status: 409);
      const csv = {
        'idempotencyKey': 'durable-stock-csv-import-key',
        'csv':
            'sku,lotCode,quantity,deadline,dateType\n000123,import,3,2026-10-24T20:00:00Z,useBy',
      };
      await post('/v1/merchant/stores/$store/import', csv, status: 200);
      await post('/v1/merchant/stores/$store/import', csv, status: 200);
      final lots = (await workspace())['lots'] as List;
      expect(lots.map((l) => l['onHand']), unorderedEquals([8, 3]));
    },
  );
  test(
    'integration secrets are stored as hashes and are not replayed from idempotency storage',
    () async {
      const body = {
        'storeId': 'unused',
        'name': 'POS',
        'idempotencyKey': 'one-time-integration-token-key',
      };
      final actual = {...body, 'storeId': store};
      final first = await post('/v1/merchant/integrations', actual),
          second = await post('/v1/merchant/integrations', actual);
      expect(first['token'], isNotNull);
      expect(second['token'], isNull);
      expect(second['id'], first['id']);
      final raw = first['token'] as String;
      expect(
        app.database.db
            .select('SELECT response FROM merchant_requests')
            .any((r) => (r['response'] as String).contains(raw)),
        false,
      );
      expect(
        app.database.db
            .select('SELECT token_hash FROM stock_integrations')
            .first['token_hash'],
        isNot(raw),
      );
    },
  );
  test(
    'branch pickup only consumes that branch in a multi-store order',
    () async {
      final second =
          (await post('/v1/merchant/stores', {
                'organizationId': org,
                'name': 'Druhá pobočka',
                'kind': 'bakery',
                'address': 'Ružová 2, Bratislava',
                'point': {'lat': 48.16, 'lng': 17.16},
              }))['id']
              as String;
      await receive('first', 10);
      await post('/v1/merchant/stock/receive', {
        'storeId': second,
        'productId': product,
        'lotCode': 'second',
        'quantity': 8,
        'deadline': '2026-10-24T20:00:00Z',
        'dateType': 'useBy',
        'quality': 'checked',
      });
      final a = await offer(),
          b =
              (await post('/v1/merchant/offers', {
                    ...offerBody(),
                    'storeId': second,
                  }))['id']
                  as String;
      final order = await json(
        await reserve(
          a,
          items: [
            {'offerId': a, 'quantity': 1},
            {'offerId': b, 'quantity': 1},
          ],
        ),
      );
      await post('/v1/merchant/stores/$store/orders/${order['id']}/collect', {
        'pickupCode': order['pickupCode'],
      }, status: 200);
      final ws = await workspace(),
          items = ((ws['orders'] as List).first['items'] as List);
      expect(items.singleWhere((i) => i['offerId'] == a)['collected'], true);
      expect(items.singleWhere((i) => i['offerId'] == b)['collected'], false);
      expect(
        (ws['lots'] as List).singleWhere(
          (l) => l['storeId'] == second,
        )['onHand'],
        8,
      );
      expect((ws['orders'] as List).first['status'], 'reserved');
    },
  );
  test(
    'editing a discount preserves earlier order price and prevents capacity below commitments',
    () async {
      await receive('batch', 20);
      final id = await offer(), old = await json(await reserve(id, count: 2));
      final body = {
        ...offerBody(),
        'price': 200,
        'stock': 1,
        'idempotencyKey': 'edit-capacity-too-low-key',
      };
      expect(
        (await call('PATCH', '/v1/merchant/offers/$id', body: body)).statusCode,
        409,
      );
      expect(
        (await call(
          'PATCH',
          '/v1/merchant/offers/$id',
          body: {
            ...body,
            'stock': 10,
            'idempotencyKey': 'edit-price-new-discount-key',
          },
        )).statusCode,
        200,
      );
      final next = await json(
        await reserve(id, key: 'order-after-discount-edit-key'),
      );
      expect((old['items'] as List).first['unitPrice'], 150);
      expect((next['items'] as List).first['unitPrice'], 200);
    },
  );
  test(
    'automatic offer never substitutes long-dated stock outside its rescue horizon',
    () async {
      await receive('near', 2);
      await receive('far', 20, deadline: '2026-11-20T20:00:00Z');
      await post('/v1/merchant/rules', rule(auto: true));
      await post('/v1/merchant/stores/$store/automation', {}, status: 200);
      final id =
          ((await workspace())['offers'] as List).first['offer']['id']
              as String;
      expect((await reserve(id)).statusCode, 201);
      expect(
        (await reserve(id, key: 'second-auto-order-after-near')).statusCode,
        409,
      );
    },
  );
  test(
    'absolute stock synchronization rejects stale versions and out-of-order snapshots',
    () async {
      await receive('batch', 10);
      final integration = await post('/v1/merchant/integrations', {
        'storeId': store,
        'name': 'ERP',
      });
      final token = integration['token'] as String;
      final snapshot = await json(
        await call('GET', '/v1/integrations/stock', token: token),
      );
      expect(snapshot['lots'], hasLength(1));
      final event = {
        'eventId': 'absolute-sync-0001',
        'operation': 'set',
        'sku': '000123',
        'lotCode': 'batch',
        'onHand': 8,
        'reason': 'ERP inventúra',
        'expectedVersion': 1,
        'sequence': 3,
      };
      expect(
        (await call(
          'POST',
          '/v1/integrations/stock',
          body: event,
          token: token,
        )).statusCode,
        200,
      );
      expect(
        (await call(
          'POST',
          '/v1/integrations/stock',
          body: {...event, 'eventId': 'absolute-sync-0002', 'sequence': 4},
          token: token,
        )).statusCode,
        409,
      );
      expect(
        (await call(
          'POST',
          '/v1/integrations/stock',
          body: {
            ...event,
            'eventId': 'absolute-sync-0003',
            'expectedVersion': 2,
            'sequence': 2,
          },
          token: token,
        )).statusCode,
        409,
      );
      expect(((await workspace())['lots'] as List).first['onHand'], 8);
    },
  );
  test(
    'nested transaction rollback includes reservations, movements and idempotency record',
    () async {
      expect(
        () => app.database.transaction(() {
          app.database.transaction(
            () => app.database.db.execute(
              "INSERT INTO merchant_requests VALUES('owner','nested-test-key','h','{}')",
            ),
          );
          throw StateError('rollback outer');
        }),
        throwsStateError,
      );
      expect(
        app.database.db.select(
          "SELECT * FROM merchant_requests WHERE idempotency='nested-test-key'",
        ),
        isEmpty,
      );
      await receive('still-works', 1);
    },
  );
  test(
    'seller can cancel a blocked single-store order and release its held inventory',
    () async {
      final lot = await receive('batch', 10);
      final id = await offer(), order = await json(await reserve(id, count: 2));
      await post('/v1/merchant/lots/${lot['id']}/quality', {
        'version': 1,
        'quality': 'quarantine',
        'reason': 'Porušené skladovanie',
      }, status: 200);
      final path = '/v1/merchant/stores/$store/orders/${order['id']}/cancel';
      await post(path, {'reason': 'Nevyhovujúca šarža'}, status: 200);
      await post(path, {'reason': 'Nevyhovujúca šarža'}, status: 200);
      final ws = await workspace();
      expect((ws['orders'] as List).first['status'], 'cancelled');
      expect((ws['lots'] as List).first['reserved'], 0);
      expect((ws['lots'] as List).first['onHand'], 10);
    },
  );
  test(
    'invalid calendar dates are rejected instead of normalizing to another day',
    () async {
      final response = await call(
        'POST',
        '/v1/merchant/stock/receive',
        body: {
          'idempotencyKey': 'invalid-calendar-date-key',
          'storeId': store,
          'productId': product,
          'lotCode': 'bad',
          'quantity': 1,
          'deadline': '2027-02-31T20:00:00Z',
          'dateType': 'useBy',
          'quality': 'checked',
        },
      );
      expect(response.statusCode, 400);
      expect((await workspace())['lots'], isEmpty);
    },
  );
  test(
    'stock event replay accepts reordered JSON keys without applying the receipt again',
    () async {
      final integration = await post('/v1/merchant/integrations', {
        'storeId': store,
        'name': 'POS',
      });
      final token = integration['token'] as String;
      final event = {
        'eventId': 'canonical-receipt-1',
        'operation': 'receive',
        'sku': '000123',
        'lotCode': 'canonical',
        'quantity': 4,
        'deadline': '2026-10-24T20:00:00Z',
        'dateType': 'useBy',
      };
      expect(
        (await call(
          'POST',
          '/v1/integrations/stock',
          body: event,
          token: token,
        )).statusCode,
        200,
      );
      expect(
        (await call(
          'POST',
          '/v1/integrations/stock',
          body: Map.fromEntries(event.entries.toList().reversed),
          token: token,
        )).statusCode,
        200,
      );
      expect(((await workspace())['lots'] as List).single['onHand'], 4);
    },
  );
}

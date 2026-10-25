import 'dart:convert';
import 'package:marketplace_server/marketplace_server.dart';
import 'package:marketplace_server/src/auth.dart';
import 'package:marketplace_server/src/merchant.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

void main() {
  late MarketplaceServer app;
  late String source, destination, org;
  late Map<String, dynamic> lot;
  setUp(() {
    app = MarketplaceServer(
      const ServerConfig(databasePath: ':memory:', demoShowcase: true),
      clock: () => DateTime.utc(2026, 10, 25, 12),
    );
    final w = app.merchants.workspace('showcase-bakery');
    final stores = w['stores'] as List;
    source = stores[0]['id'] as String;
    destination = stores[1]['id'] as String;
    org = stores[0]['organizationId'] as String;
    lot = Map<String, dynamic>.from(
      (w['lots'] as List).firstWhere(
        (l) =>
            l['storeId'] == source &&
            l['quality'] == 'checked' &&
            (l['reserved'] as int) > 0 &&
            (l['onHand'] as int) - (l['reserved'] as int) > 5,
      ),
    );
  });
  tearDown(() => app.close());
  Map<String, dynamic> transfer() =>
      app.merchants.createTransfer('showcase-bakery', {
        'lotId': lot['id'],
        'destinationStoreId': destination,
        'quantity': 3,
        'reason': 'Zásobenie druhej pobočky',
      });
  Map<String, dynamic> move(
    Map<String, dynamic> t,
    String action, {
    Map<String, dynamic> extra = const {},
  }) => app.merchants.updateTransfer('showcase-bakery', t['id'] as String, {
    'action': action,
    'reason': 'Potvrdený pohyb tovaru',
    'version': t['version'],
    'lotVersion': (t['lot'] as Map)['version'],
    ...extra,
  });
  int physical() =>
      app.database.db.select('SELECT SUM(on_hand) n FROM stock_lots').first['n']
          as int;
  List<Map<String, dynamic>> quantities(Map<String, dynamic> c) =>
      (c['lines'] as List)
          .map(
            (l) => <String, dynamic>{
              'lotId': l['lot_id'],
              'counted': l['on_hand'],
            },
          )
          .toList();
  Map<String, dynamic> save(
    Map<String, dynamic> c,
    List<Map<String, dynamic>> lines, {
    String user = 'showcase-bakery',
  }) => app.merchants.updateCount(user, c['id'] as String, {
    'version': c['version'],
    'action': 'save',
    'lines': lines,
  });
  test(
    'older transfer history remains reachable beyond the first hundred records',
    () {
      for (var i = 0; i < 105; i++) {
        transfer();
      }
      final first = app.merchants.warehouse('showcase-bakery', source);
      final second = app.merchants.warehouse(
        'showcase-bakery',
        source,
        beforeTransfers: first['transfersNext'] as int,
      );
      final ids = {
        ...(first['transfers'] as List).map((t) => t['id']),
        ...(second['transfers'] as List).map((t) => t['id']),
      };
      expect((first['transfers'] as List).length, 100);
      expect(ids, hasLength(105));
      expect(second['transfersNext'], isNull);
    },
  );
  test(
    'in-transit stock is conserved, receive is quarantined and repeated actions cannot duplicate goods',
    () {
      final before = physical(), t = transfer();
      final sent = move(t, 'dispatch');
      expect(physical() + 3, before);
      final received = move(sent, 'receive');
      expect(physical(), before);
      final target = app.database.db.select(
        'SELECT * FROM stock_lots WHERE id=?',
        [received['destination_lot']],
      ).first;
      expect(target['quality'], 'quarantine');
      expect(target['deadline'], lot['deadline']);
      expect(target['on_hand'], 3);
      expect(() => move(received, 'receive'), throwsA(isA<ApiFailure>()));
      expect(physical(), before);
    },
  );
  test(
    'reserved goods cannot be moved and cross-company destinations are blocked',
    () {
      expect(
        () => app.merchants.createTransfer('showcase-bakery', {
          'lotId': lot['id'],
          'destinationStoreId': destination,
          'quantity': lot['onHand'],
          'reason': 'Presun všetkých kusov',
        }),
        throwsA(isA<ApiFailure>()),
      );
      final foreign =
          (app.merchants.workspace('showcase-grocery')['stores'] as List)
              .first['id'];
      expect(
        () => app.merchants.createTransfer('showcase-bakery', {
          'lotId': lot['id'],
          'destinationStoreId': foreign,
          'quantity': 1,
          'reason': 'Nepovolený presun',
        }),
        throwsA(isA<ApiFailure>()),
      );
    },
  );
  test(
    'withdrawing a batch propagates to received branches and blocks saleable in-transit receipt',
    () {
      final first = move(
        move(transfer(), 'dispatch'),
        'receive',
        extra: {'checked': true},
      );
      final second = move(transfer(), 'dispatch');
      final latest = app.merchants.transferDetail(
        'showcase-bakery',
        second['id'] as String,
      );
      app.merchants.quality('showcase-bakery', lot['id'] as String, {
        'version': latest['lot']['version'],
        'quality': 'withdrawn',
        'reason': 'Stiahnutie prepojenej šarže',
      });
      expect(
        app.database.db.select('SELECT quality FROM stock_lots WHERE id=?', [
          first['destination_lot'],
        ]).first['quality'],
        'withdrawn',
      );
      expect(
        () => move(second, 'receive', extra: {'checked': true}),
        throwsA(isA<ApiFailure>()),
      );
      final isolated = move(second, 'receive');
      expect(
        app.database.db.select('SELECT quality FROM stock_lots WHERE id=?', [
          isolated['destination_lot'],
        ]).first['quality'],
        'withdrawn',
      );
    },
  );
  test(
    'physical return creates separate quarantine stock without changing quality of held source goods',
    () {
      final before = physical(), sent = move(transfer(), 'dispatch');
      expect(() => move(sent, 'return'), throwsA(isA<ApiFailure>()));
      final returned = move(
        sent,
        'return',
        extra: {'physicallyReturned': true},
      );
      expect(physical(), before);
      expect(returned['status'], 'returned');
      expect(
        app.database.db.select('SELECT quality FROM stock_lots WHERE id=?', [
          lot['id'],
        ]).first['quality'],
        'checked',
      );
      expect(
        app.database.db.select('SELECT quality FROM stock_lots WHERE id=?', [
          returned['destination_lot'],
        ]).first['quality'],
        'quarantine',
      );
    },
  );
  test(
    'inventory posts all differences once and cannot reduce stock below reservations',
    () {
      final before = physical();
      var c = app.merchants.createCount('showcase-bakery', {
        'storeId': source,
        'reason': 'Pravidelná inventúra',
      });
      var lines = quantities(c);
      lines.firstWhere((l) => l['lotId'] == lot['id'])['counted'] =
          (lot['onHand'] as int) - 1;
      c = save(c, lines);
      c = app.merchants.updateCount('showcase-bakery', c['id'] as String, {
        'version': c['version'],
        'action': 'post',
      });
      expect(c['status'], 'posted');
      expect(physical(), before - 1);
      expect(
        () => app.merchants.updateCount('showcase-bakery', c['id'] as String, {
          'version': c['version'],
          'action': 'post',
        }),
        throwsA(isA<ApiFailure>()),
      );
      c = app.merchants.createCount('showcase-bakery', {
        'storeId': source,
        'reason': 'Kontrola rezervácií',
      });
      lines = quantities(c);
      lines.firstWhere((l) => l['lotId'] == lot['id'])['counted'] = 0;
      c = save(c, lines);
      expect(
        () => app.merchants.updateCount('showcase-bakery', c['id'] as String, {
          'version': c['version'],
          'action': 'post',
        }),
        throwsA(isA<ApiFailure>()),
      );
      expect(physical(), before - 1);
    },
  );
  test(
    'concurrent movements invalidate counts and rebase preserves only unchanged counts',
    () {
      var c = app.merchants.createCount('showcase-bakery', {
        'storeId': source,
        'reason': 'Denná kontrola skladu',
      });
      c = save(c, quantities(c));
      app.merchants.adjust('showcase-bakery', lot['id'] as String, {
        'delta': 1,
        'reason': 'Nový kus na sklade',
        'version': lot['version'],
      });
      final before = physical();
      expect(
        () => app.merchants.updateCount('showcase-bakery', c['id'] as String, {
          'version': c['version'],
          'action': 'post',
        }),
        throwsA(isA<ApiFailure>()),
      );
      expect(physical(), before);
      c = app.merchants.updateCount('showcase-bakery', c['id'] as String, {
        'version': c['version'],
        'action': 'rebase',
      });
      expect((c['lines'] as List).where((l) => l['counted'] == null).length, 1);
    },
  );
  test(
    'staff can count but only managers can approve; HTTP mutation replay stays idempotent',
    () async {
      app.database.db.execute(
        "INSERT INTO merchant_members VALUES(?,?,'staff')",
        [org, 'showcase-customer'],
      );
      var c = app.merchants.createCount('showcase-customer', {
        'storeId': source,
        'reason': 'Počítanie pracovníkom',
      });
      c = save(c, quantities(c), user: 'showcase-customer');
      expect(
        () => app.merchants.updateCount(
          'showcase-customer',
          c['id'] as String,
          {'version': c['version'], 'action': 'post'},
        ),
        throwsA(isA<ApiFailure>()),
      );
      final token = app.auth.createSession('showcase-bakery')['token'];
      final t = transfer(),
          body = jsonEncode({
            'idempotencyKey': 'dispatch-test-idempotent-key',
            'action': 'dispatch',
            'version': t['version'],
            'lotVersion': lot['version'],
            'reason': 'Odoslané obsluhou',
          });
      final before = physical();
      for (var i = 0; i < 2; i++) {
        final response = await app.handler(
          Request(
            'POST',
            Uri.parse(
              'http://localhost/v1/merchant/stock/transfers/${t['id']}',
            ),
            headers: {
              'Authorization': 'Bearer $token',
              'content-type': 'application/json',
            },
            body: body,
          ),
        );
        expect(response.statusCode, 200, reason: await response.readAsString());
      }
      expect(physical(), before - 3);
    },
  );
}

import 'dart:typed_data';
import 'package:image/image.dart' as image;
import 'package:marketplace_server/marketplace_server.dart';
import 'package:marketplace_server/src/auth.dart';
import 'package:marketplace_server/src/merchant.dart';
import 'package:test/test.dart';

void main() {
  late MarketplaceServer app;
  late String org, source, destination;
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
  });
  tearDown(() => app.close());
  Uint8List photo() =>
      Uint8List.fromList(image.encodePng(image.Image(width: 8, height: 9)));
  void member(String user, String role, List<String>? stores) =>
      app.merchants.setMember('showcase-bakery', {
        'organizationId': org,
        'email': app.auth.user(user)['email'],
        'role': role,
        'storeIds': stores,
      });
  test(
    'merchant media is sanitized, deduplicated and scoped to its organization',
    () async {
      final p = await app.media.add('showcase-bakery', photo(), org: org);
      expect(p['width'], 8);
      expect(image.decodeJpg(app.media.photo(p['id'] as String))!.height, 9);
      expect(
        (await app.media.add('showcase-bakery', photo(), org: org))['id'],
        p['id'],
      );
      expect(
        () => app.media.list('showcase-restaurant', org),
        throwsA(isA<ApiFailure>()),
      );
      expect(
        () => app.media.remove('showcase-restaurant', p['id'] as String),
        throwsA(isA<ApiFailure>()),
      );
      app.media.remove('showcase-bakery', p['id'] as String);
      expect(
        () => app.media.photo(p['id'] as String),
        throwsA(isA<ApiFailure>()),
      );
    },
  );
  test('invalid bytes and foreign access are rejected', () async {
    await expectLater(
      app.media.add('showcase-bakery', Uint8List.fromList([1, 2, 3]), org: org),
      throwsA(isA<ApiFailure>()),
    );
    await expectLater(
      app.media.add('showcase-restaurant', photo(), org: org),
      throwsA(isA<ApiFailure>()),
    );
  });
  test('review drafts are private until attached to a review', () async {
    final p = await app.media.add('showcase-customer', photo(), kind: 'review');
    expect(
      () => app.media.photo(p['id'] as String),
      throwsA(isA<ApiFailure>()),
    );
    expect(
      app.media.photo(p['id'] as String, user: 'showcase-customer'),
      isNotEmpty,
    );
  });
  test('branch scope protects stock, operations and workspace data', () {
    member('showcase-customer', 'staff', [destination]);
    expect(app.merchants.storeIds('showcase-customer'), [destination]);
    expect(
      () => app.merchants.requireStore('showcase-customer', source),
      throwsA(isA<ApiFailure>()),
    );
    expect(
      () => app.merchants.createCount('showcase-customer', {
        'storeId': source,
        'reason': 'Unauthorized inventory',
      }),
      throwsA(isA<ApiFailure>()),
    );
    final w = app.merchants.workspace('showcase-customer');
    expect((w['stores'] as List).every((s) => s['id'] == destination), true);
    expect((w['lots'] as List).every((s) => s['storeId'] == destination), true);
  });
  test('recipient can accept a transfer without access to source stock', () {
    member('showcase-customer', 'staff', [destination]);
    final lot =
        (app.merchants.workspace('showcase-bakery')['lots'] as List).firstWhere(
              (l) =>
                  l['storeId'] == source &&
                  l['quality'] == 'checked' &&
                  (l['onHand'] as int) - (l['reserved'] as int) > 3,
            )
            as Map;
    var t = app.merchants.createTransfer('showcase-bakery', {
      'lotId': lot['id'],
      'destinationStoreId': destination,
      'quantity': 2,
      'reason': 'Branch transfer',
    });
    t = app.merchants.updateTransfer('showcase-bakery', t['id'] as String, {
      'version': t['version'],
      'action': 'dispatch',
      'lotVersion': lot['version'],
      'reason': 'Dispatched physically',
    });
    final view = app.merchants.transferDetail(
      'showcase-customer',
      t['id'] as String,
    );
    expect(view['sourceAvailable'], isNull);
    expect(view['canDispatch'], false);
    expect(view['canReceive'], true);
    expect(
      () =>
          app.merchants.updateTransfer('showcase-customer', t['id'] as String, {
            'version': t['version'],
            'action': 'return',
            'reason': 'Not my branch',
            'physicallyReturned': true,
          }),
      throwsA(isA<ApiFailure>()),
    );
    final received = app.merchants
        .updateTransfer('showcase-customer', t['id'] as String, {
          'version': t['version'],
          'action': 'receive',
          'checked': false,
          'reason': 'Received physically',
        });
    expect(received['status'], 'received');
  });
  test(
    'invites require the verified target email and cannot be accepted twice',
    () {
      final invite = app.merchants.invite('showcase-bakery', {
        'organizationId': org,
        'email': app.auth.user('showcase-customer')['email'],
        'role': 'staff',
        'storeIds': [destination],
      });
      final body =
          app.database.db
                  .select(
                    'SELECT body FROM mail_outbox ORDER BY rowid DESC LIMIT 1',
                  )
                  .first['body']
              as String;
      final token = RegExp(r'Kód pozvánky: (\S+)').firstMatch(body)!.group(1);
      final payload = {'inviteId': invite['id'], 'token': token};
      expect(
        () => app.merchants.acceptInvite('showcase-customer', payload),
        throwsA(isA<ApiFailure>()),
      );
      app.database.db.execute(
        "UPDATE users SET email_verified=1 WHERE id='showcase-customer'",
      );
      expect(
        app.merchants.acceptInvite('showcase-customer', payload)['accepted'],
        true,
      );
      expect(app.merchants.storeIds('showcase-customer'), [destination]);
      expect(
        () => app.merchants.acceptInvite('showcase-customer', payload),
        throwsA(isA<ApiFailure>()),
      );
    },
  );
  test(
    'ownership transfer preserves a single owner and grants every branch',
    () {
      member('showcase-customer', 'manager', [destination]);
      app.database.db.execute(
        "UPDATE users SET email_verified=1 WHERE id='showcase-customer'",
      );
      app.merchants.transferOwnership('showcase-bakery', {
        'organizationId': org,
        'email': app.auth.user('showcase-customer')['email'],
      });
      expect(
        app.database.db.select(
          "SELECT user_id FROM merchant_members WHERE org_id=? AND role='owner'",
          [org],
        ).single['user_id'],
        'showcase-customer',
      );
      expect(app.merchants.storeIds('showcase-customer').toSet(), {
        source,
        destination,
      });
      expect(
        () => app.merchants.setMember('showcase-bakery', {
          'organizationId': org,
          'email': app.auth.user('showcase-customer')['email'],
          'role': 'remove',
        }),
        throwsA(isA<ApiFailure>()),
      );
    },
  );
}

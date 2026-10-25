import 'package:marketplace_server/marketplace_server.dart';
import 'package:marketplace_server/src/auth.dart';
import 'package:marketplace_server/src/merchant.dart';
import 'package:test/test.dart';

void main() {
  late MarketplaceServer app;
  setUp(
    () => app = MarketplaceServer(
      const ServerConfig(databasePath: ':memory:', demoShowcase: true),
      clock: () => DateTime.utc(2026, 10, 25, 12),
    ),
  );
  tearDown(() => app.close());
  Map<String, dynamic> change(
    String kind,
    String id,
    String action, {
    int version = 0,
    Map<String, dynamic> extra = const {},
  }) => app.platform.change('showcase-support', kind, id, {
    'action': action,
    'version': version,
    'reason': 'Overenie administrátorskej zmeny',
    ...extra,
  });
  test(
    'administration checks roles, redacts credentials and prevents last-admin removal',
    () {
      expect(
        () => app.platform.list('showcase-customer', 'users', {}),
        throwsA(isA<ApiFailure>()),
      );
      final users =
          app.platform.list('showcase-support', 'users', {})['rows'] as List;
      expect(
        users.every(
          (u) => !u.containsKey('password_hash') && !u.containsKey('profile'),
        ),
        true,
      );
      expect(
        () => change(
          'users',
          'showcase-support',
          'role',
          extra: {'role': 'none'},
        ),
        throwsA(isA<ApiFailure>()),
      );
      app.database.db.execute(
        "UPDATE users SET email_verified=1 WHERE id='showcase-customer'",
      );
      change(
        'users',
        'showcase-customer',
        'role',
        extra: {'role': 'moderator'},
      );
      expect(
        () => app.platform.list('showcase-customer', 'users', {}),
        throwsA(isA<ApiFailure>()),
      );
      expect(
        app.platform.list('showcase-customer', 'offers', {})['rows'],
        isNotEmpty,
      );
    },
  );
  test(
    'suspension hides company offers, blocks stock mutations and creates support cases',
    () {
      final w = app.merchants.workspace('showcase-bakery'),
          org = (w['stores'] as List).first['organizationId'] as String;
      final offers = (w['offers'] as List)
          .map((o) => (o['offer'] as Map)['id'])
          .toSet();
      expect(app.catalog().any((o) => offers.contains(o.id)), true);
      change('organizations', org, 'suspend');
      expect(app.catalog().any((o) => offers.contains(o.id)), false);
      expect(
        () => app.merchants.createCount('showcase-bakery', {
          'storeId': (w['stores'] as List).first['id'],
          'reason': 'Blocked operation',
        }),
        throwsA(isA<ApiFailure>()),
      );
      expect(
        app.database.db.select(
          "SELECT id FROM support_tickets WHERE source_key LIKE 'org-hold:%'",
        ),
        isNotEmpty,
      );
      change('organizations', org, 'activate', version: 1);
      expect(app.catalog().any((o) => offers.contains(o.id)), true);
    },
  );
  test('versioned moderation cannot be bypassed by seller publication', () {
    final offer = app.catalog().first;
    change('offers', offer.id, 'hide');
    expect(app.catalog().any((o) => o.id == offer.id), false);
    expect(
      () => change('offers', offer.id, 'show'),
      throwsA(isA<ApiFailure>()),
    );
    change('offers', offer.id, 'show', version: 1);
    expect(app.catalog().any((o) => o.id == offer.id), true);
    expect(
      app.platform.list('showcase-support', 'audit', {})['rows'],
      hasLength(2),
    );
  });
  test(
    'pausing one branch hides its offers, preserves other branches and stops settlement',
    () {
      final w = app.merchants.workspace('showcase-bakery'),
          store = (w['stores'] as List).first['id'] as String;
      final offers = (w['offers'] as List)
          .where((o) => o['storeId'] == store && o['state'] == 'published')
          .toList();
      expect(offers, isNotEmpty);
      change('stores', store, 'suspend');
      expect(
        offers.every((o) => !app.merchants.visible(o['offer']['id'] as String)),
        true,
      );
      final page = app.merchants.pagedWorkspace('showcase-bakery', {
        'storeId': store,
      });
      expect(
        (page['stores'] as List).firstWhere(
          (s) => s['id'] == store,
        )['platformPaused'],
        true,
      );
      expect(
        () => app.finance.requireTrading(
          (w['organizations'] as List).first['id'] as String,
          store,
        ),
        throwsA(isA<ApiFailure>()),
      );
      change('stores', store, 'activate', version: 1);
      expect(
        offers.every((o) => app.merchants.visible(o['offer']['id'] as String)),
        true,
      );
    },
  );
}

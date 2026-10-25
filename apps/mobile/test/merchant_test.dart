import 'package:nevyhadzuj/app.dart';
import 'dart:async';
import 'dart:convert';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:marketplace_data/marketplace_data.dart';
import 'package:nevyhadzuj/features/merchant/controller.dart';
import 'package:nevyhadzuj/features/merchant/editor.dart';
import 'package:nevyhadzuj/features/merchant/portal.dart';
import 'package:nevyhadzuj/state/app_store.dart';
import 'support/merchant_fixture.dart';

void main() {
  Future<MerchantController> controller({String role = 'owner'}) async {
    final api = MarketplaceApi(
      'https://api.example.test',
      vault: MemoryTokenVault(),
      client: MockClient(
        (r) async => http.Response(
          jsonEncode(merchantFixture(role: role)),
          200,
          headers: {'content-type': 'application/json'},
        ),
      ),
    );
    final c = MerchantController(api);
    await c.load();
    expect(c.error, isNull);
    addTearDown(c.dispose);
    return c;
  }

  Future<void> mount(
    WidgetTester tester,
    MerchantController c, {
    Size size = const Size(390, 844),
    Brightness brightness = Brightness.light,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = AppStore(
      MemoryMarketplaceRepository(),
      clock: () => DateTime(2026, 10, 24, 12),
    );
    addTearDown(store.dispose);
    await tester.pumpWidget(
      StoreScope(
        store: store,
        child: MaterialApp(
          theme: appTheme(brightness),
          home: MerchantPortalScreen(controller: c),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final size in [
    const Size(375, 812),
    const Size(768, 1024),
    const Size(1440, 1000),
  ]) {
    testWidgets('seller dashboard and each section fit $size', (tester) async {
      final c = await controller();
      await mount(tester, c, size: size);
      for (final name in ['Sklad', 'Ponuky', 'Pravidlá', 'Výdaj']) {
        await tester.tap(find.text(name).last);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
      await tester.tap(find.byTooltip('Nastavenia predajcu'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
    'dark stock view searches SKU and keeps available, reserved and physical distinct',
    (tester) async {
      final c = await controller();
      await mount(tester, c, brightness: Brightness.dark);
      await tester.tap(find.text('Sklad').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('merchant-stock-search')),
        '000123',
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Fyzicky 24 · rezervované 6 · voľné 18 ks'),
        findsOneWidget,
      );
      expect(find.textContaining('PEK-2410-B'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'staff sees stock and pickup but cannot create rules or connection tokens',
    (tester) async {
      final c = await controller(role: 'staff');
      await mount(tester, c);
      await tester.tap(find.text('Pravidlá').last);
      await tester.pumpAndSettle();
      expect(find.text('Nové pravidlo'), findsNothing);
      await tester.tap(find.byTooltip('Nastavenia predajcu'));
      await tester.pumpAndSettle();
      expect(find.text('Vytvoriť skladové pripojenie'), findsNothing);
    },
  );
  testWidgets(
    'editor retains fields and mutation key after a failed request; dropdown default is submitted',
    (tester) async {
      final requests = <Map<String, dynamic>>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(Brightness.light),
          home: Scaffold(
            body: MerchantEditor(
              title: 'Príjem',
              fields: const [
                MerchantField('name', 'Názov'),
                MerchantField(
                  'kind',
                  'Typ',
                  options: {'first': 'Prvá', 'second': 'Druhá'},
                ),
              ],
              submit: (b) async {
                requests.add(b);
                throw StateError('Dočasný výpadok');
              },
            ),
          ),
        ),
      );
      await tester.enterText(
        find.byKey(const ValueKey('merchant-name')),
        'Test šarže',
      );
      await tester.tap(find.text('Uložiť'));
      await tester.pumpAndSettle();
      expect(find.text('Dočasný výpadok'), findsOneWidget);
      expect(find.text('Test šarže'), findsOneWidget);
      await tester.tap(find.text('Uložiť'));
      await tester.pumpAndSettle();
      expect(requests, hasLength(2));
      expect(requests[0]['idempotencyKey'], requests[1]['idempotencyKey']);
      expect(requests[0]['kind'], 'first');
    },
  );
  test(
    'after mutation, refresh failure is surfaced as saved and retry keeps the same key',
    () async {
      var gets = 0;
      final keys = <String>[];
      final api = MarketplaceApi(
        'https://api.example.test',
        vault: MemoryTokenVault(),
        client: MockClient((r) async {
          if (r.method == 'GET') {
            gets++;
            return gets == 1
                ? http.Response(
                    jsonEncode(merchantFixture()),
                    200,
                    headers: {'content-type': 'application/json'},
                  )
                : http.Response('{"error":"offline"}', 503);
          }
          keys.add((jsonDecode(r.body) as Map)['idempotencyKey'] as String);
          return http.Response('{"id":"saved"}', 201);
        }),
      );
      final c = MerchantController(api);
      addTearDown(c.dispose);
      await c.load();
      const body = {
        'idempotencyKey': 'stable-form-idempotency-key',
        'storeId': 'store',
      };
      await expectLater(c.mutate('stock/receive', body), throwsStateError);
      expect(c.busy, false);
      await expectLater(c.mutate('stock/receive', body), throwsStateError);
      expect(keys[0], keys[1]);
      expect(c.error, contains('Zmena je uložená'));
    },
  );
  test(
    'mutation waits for an in-flight stale refresh and then loads authoritative stock',
    () async {
      final gate = Completer<http.Response>(), started = Completer<void>();
      var gets = 0;
      final api = MarketplaceApi(
        'https://api.example.test',
        vault: MemoryTokenVault(),
        client: MockClient((r) async {
          if (r.method != 'GET') return http.Response('{"id":"saved"}', 201);
          gets++;
          if (gets == 2) {
            started.complete();
            return gate.future;
          }
          final fixture = merchantFixture();
          if (gets >= 3) {
            (fixture['lots'] as List).first['onHand'] = 8;
          }
          return http.Response(
            jsonEncode(fixture),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      final c = MerchantController(api);
      addTearDown(c.dispose);
      await c.load();
      final refresh = c.load();
      await started.future;
      final mutation = c.mutate('stock/receive', const {'storeId': 'store'});
      gate.complete(
        http.Response(
          jsonEncode(merchantFixture()),
          200,
          headers: {'content-type': 'application/json'},
        ),
      );
      await refresh;
      await mutation;
      expect(c.lots.first.onHand, 8);
      expect(gets, 3);
    },
  );
  testWidgets(
    'restaurant can create a stock product in mobile with defaults and exact cents',
    (tester) async {
      Map<String, dynamic>? submitted;
      final api = MarketplaceApi(
        'https://api.example.test',
        vault: MemoryTokenVault(),
        client: MockClient((r) async {
          if (r.method == 'GET') {
            return http.Response(
              jsonEncode(merchantFixture()),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          submitted = Map<String, dynamic>.from(jsonDecode(r.body) as Map);
          return http.Response('{"id":"new-product"}', 201);
        }),
      );
      final c = MerchantController(api);
      addTearDown(c.dispose);
      await c.load();
      await mount(tester, c);
      await tester.tap(find.text('Sklad').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Nová položka'));
      await tester.pumpAndSettle();
      for (final field in {
        'name': 'Jogurt',
        'sku': '000789',
        'unitValue': '2,50',
        'allergens': 'Mlieko',
        'image': 'https://example.test/yogurt.jpg',
      }.entries) {
        final finder = find.byKey(ValueKey('merchant-${field.key}'));
        await tester.ensureVisible(finder);
        await tester.enterText(finder, field.value);
      }
      await tester.ensureVisible(find.text('Uložiť'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Uložiť'));
      await tester.pumpAndSettle();
      expect(submitted?['sku'], '000789');
      expect(submitted?['unitValue'], 250);
      expect(submitted?['unit'], 'piece');
      expect(submitted?['storage'], 'ambient');
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'dedicated merchant entry opens business setup without buyer onboarding',
    (tester) async {
      final store = AppStore(MemoryMarketplaceRepository());
      addTearDown(store.dispose);
      await tester.pumpWidget(
        NevyhadzujApp(store: store, startInMerchantPortal: true),
      );
      await tester.pumpAndSettle();
      expect(find.byType(MerchantPortalScreen), findsOneWidget);
      expect(find.text('Pripoj aplikáciu k serveru'), findsOneWidget);
      await tester.tap(find.byTooltip('Späť'));
      await tester.pumpAndSettle();
      expect(find.byType(MerchantPortalScreen), findsNothing);
      expect(find.byType(Scaffold), findsOneWidget);
    },
  );
  testWidgets('changing signed-in account clears previous seller workspace', (
    tester,
  ) async {
    var other = false;
    final vault = MemoryTokenVault()..token = 'session-one';
    final api = MarketplaceApi(
      'https://api.example.test',
      vault: vault,
      client: MockClient((r) async {
        if (r.url.path == '/v1/auth/login') {
          return http.Response('{"token":"session-two"}', 200);
        }
        if (r.url.path == '/v1/auth/logout') return http.Response('{}', 200);
        return http.Response(
          jsonEncode(other ? {} : merchantFixture()),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    await api.restoreSession();
    final store = AppStore(MemoryMarketplaceRepository(), api: api)
      ..email = 'owner@example.test';
    addTearDown(store.dispose);
    await tester.pumpWidget(
      NevyhadzujApp(store: store, startInMerchantPortal: true),
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining('živý prehľad tvojej prevádzky'),
      findsOneWidget,
    );
    await store.signOut();
    await tester.pumpAndSettle();
    expect(find.text('Prihlás sa do svojho účtu'), findsOneWidget);
    other = true;
    await api.login('other@example.test', 'test-password');
    store.email = 'other@example.test';
    store.setTheme(ThemeMode.dark);
    await tester.pumpAndSettle();
    expect(find.text('Založiť účet prevádzky'), findsOneWidget);
    expect(find.textContaining('živý prehľad tvojej prevádzky'), findsNothing);
  });
}

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:design_system/design_system.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:marketplace_data/marketplace_data.dart';
import 'package:nevyhadzuj/features/merchant/controller.dart';
import 'package:nevyhadzuj/features/merchant/warehouse.dart';
import 'package:nevyhadzuj/state/app_store.dart';
import 'support/merchant_fixture.dart';

Map<String, dynamic> countFixture() => {
  'id': 'count',
  'store_id': 'store',
  'status': 'draft',
  'reason': 'Denná inventúra',
  'version': 1,
  'created_at': '2026-10-25T10:00:00Z',
  'store': (merchantFixture()['stores'] as List).first,
  'audit': [],
  'lines': [
    {
      'lot_id': 'lot',
      'expected': 10,
      'on_hand': 10,
      'reserved': 2,
      'counted': null,
      'stale': false,
      'lot_code': 'CHLIEB-01',
      'product': (merchantFixture()['products'] as List).first,
    },
  ],
};
void main() {
  Future<(AppStore, MerchantController)> setup({
    void Function(http.Request)? observe,
  }) async {
    var count = countFixture();
    final vault = MemoryTokenVault();
    await vault.write('test-session');
    final api = MarketplaceApi(
      'https://api.example.test',
      vault: vault,
      client: MockClient((r) async {
        observe?.call(r);
        Object result;
        if (r.url.path == '/v1/merchant/workspace') {
          result = merchantFixture();
        } else if (r.url.path.endsWith('/operations')) {
          result = {
            'counts': [count],
            'transfers': [],
          };
        } else if (r.url.path.endsWith('/counts/count')) {
          if (r.method == 'POST') {
            final b = jsonDecode(r.body) as Map;
            count = {
              ...count,
              'version': (count['version'] as int) + 1,
              if (b['action'] == 'save')
                'lines': [
                  {
                    ...(count['lines'] as List).first as Map,
                    'counted': b['lines'][0]['counted'],
                  },
                ],
              if (b['action'] == 'post') 'status': 'posted',
            };
          }
          result = count;
        } else {
          result = {'ok': true};
        }
        return http.Response(
          jsonEncode(result),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    await api.restoreSession();
    final store = AppStore(MemoryMarketplaceRepository(), api: api)
      ..email = 'owner@example.test';
    final controller = MerchantController(api);
    await controller.load();
    addTearDown(() => store.dispose());
    addTearDown(() => controller.dispose());
    addTearDown(api.close);
    return (store, controller);
  }

  Future<void> mount(
    WidgetTester t,
    AppStore store,
    Widget screen,
    Size size,
    Brightness brightness,
  ) async {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    addTearDown(() => t.pumpWidget(const SizedBox.shrink()));
    await t.pumpWidget(
      StoreScope(
        store: store,
        child: MaterialApp(theme: appTheme(brightness), home: screen),
      ),
    );
    await t.pumpAndSettle();
  }

  for (final size in [const Size(375, 812), const Size(1440, 1000)]) {
    for (final theme in Brightness.values) {
      testWidgets('warehouse workflow fits $size $theme', (t) async {
        final (store, c) = await setup();
        await mount(t, store, WarehouseScreen(controller: c), size, theme);
        expect(find.text('Nová inventúra'), findsOneWidget);
        expect(t.takeException(), isNull);
        await mount(
          t,
          store,
          WarehouseDetailScreen(controller: c, kind: 'counts', id: 'count'),
          size,
          theme,
        );
        expect(find.text('Denná inventúra'), findsOneWidget);
        expect(t.takeException(), isNull);
      });
    }
  }
  testWidgets(
    'owner counts, saves and explicitly approves inventory with the new version',
    (t) async {
      final writes = <http.Request>[];
      final (store, c) = await setup(
        observe: (r) {
          if (r.method == 'POST') writes.add(r);
        },
      );
      await mount(
        t,
        store,
        WarehouseDetailScreen(controller: c, kind: 'counts', id: 'count'),
        const Size(390, 844),
        Brightness.light,
      );
      final field = find.byKey(const ValueKey('count-1-lot'));
      await t.ensureVisible(field);
      await t.pumpAndSettle();
      await t.enterText(field, '9');
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('Uložiť počty'));
      await t.pumpAndSettle();
      await t.tap(find.text('Uložiť počty'));
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('Schváliť inventúru'));
      await t.pumpAndSettle();
      await t.tap(find.text('Schváliť inventúru'));
      await t.pumpAndSettle();
      expect(find.text('Schváliť inventúru?'), findsOneWidget);
      await t.tap(find.text('Potvrdiť'));
      await t.pumpAndSettle();
      expect(find.text('Zaúčtované'), findsOneWidget);
      expect(writes, hasLength(2));
      expect((jsonDecode(writes.last.body) as Map)['version'], 2);
      expect(t.takeException(), isNull);
    },
  );
}

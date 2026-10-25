import 'dart:convert';
import 'package:marketplace_server/marketplace_server.dart';
import 'package:marketplace_server/src/merchant.dart';
import 'package:test/test.dart';

void main() {
  late MarketplaceServer app;
  late String store, org;
  late Map<String, dynamic> product;
  setUp(() {
    app = MarketplaceServer(
      const ServerConfig(databasePath: ':memory:', demoShowcase: true),
      clock: () => DateTime.utc(2026, 10, 25, 12),
    );
    final w = app.merchants.workspace('showcase-bakery');
    store = (w['stores'] as List).first['id'] as String;
    org = (w['stores'] as List).first['organizationId'] as String;
    product = Map<String, dynamic>.from((w['products'] as List).first);
    app.database.transaction(() {
      for (var i = 0; i < 125; i++) {
        final p = {
          ...product,
          'id': 'paging-$i',
          'sku': 'LONG-$i',
          'name': 'Čerstvá zelenina $i',
        };
        app.database.db.execute('INSERT INTO stock_products VALUES(?,?,?,?)', [
          p['id'],
          org,
          p['sku'],
          jsonEncode(p),
        ]);
        app.merchants.receive('showcase-bakery', {
          'storeId': store,
          'productId': p['id'],
          'lotCode': 'LOT-$i',
          'quantity': 10,
          'deadline': '2026-10-27T20:00:00Z',
          'dateType': 'useBy',
          'quality': 'checked',
        });
      }
    });
  });
  tearDown(() => app.close());
  test(
    'catalog and stock pages are bounded, searchable and traversed without gaps',
    () {
      final seen = <String>{};
      String? cursor;
      do {
        final page = app.merchants.pagedWorkspace('showcase-bakery', {
          'storeId': store,
          'section': 'products',
          'query': 'cerstva zelenina',
          'before': ?cursor,
        });
        final items = page['products'] as List;
        expect(items.length, lessThanOrEqualTo(50));
        for (final p in items) {
          expect(seen.add(p['id'] as String), true);
        }
        cursor = (page['pages'] as Map)['products'] as String?;
      } while (cursor != null);
      expect(seen, hasLength(125));
      final lots = app.merchants.pagedWorkspace('showcase-bakery', {
        'storeId': store,
        'section': 'lots',
        'query': 'LOT-124',
      });
      expect(lots['lots'], hasLength(1));
      expect((lots['products'] as List).single['id'], 'paging-124');
    },
  );
  test(
    'dashboard summary counts every lot rather than just the first page',
    () {
      final page = app.merchants.pagedWorkspace('showcase-bakery', {
        'storeId': store,
      });
      expect((page['lots'] as List).length, 50);
      final all = (app.merchants.workspace('showcase-bakery')['lots'] as List)
          .where((l) => l['storeId'] == store)
          .toList();
      expect((page['stockSummary'] as Map)['lots'], all.length);
      expect(
        (page['stockSummary'] as Map)['reserved'],
        all.fold<int>(0, (n, l) => n + (l['reserved'] as int)),
      );
    },
  );
  test(
    'large inventory counts expose all lines through bounded search and pages while summaries cover the whole count',
    () {
      final created = app.merchants.createCount('showcase-bakery', {
            'storeId': store,
            'reason': 'Veľká pravidelná inventúra',
          }),
          id = created['id'] as String;
      final ids = <String>{};
      String? cursor;
      do {
        final page = app.merchants.countDetail(
          'showcase-bakery',
          id,
          before: int.tryParse(cursor ?? ''),
        );
        expect((page['lines'] as List).length, lessThanOrEqualTo(100));
        for (final line in page['lines'] as List) {
          expect(ids.add(line['lot_id'] as String), true);
        }
        cursor = page['linesNext'] as String?;
      } while (cursor != null);
      expect(ids.length, (created['lineStats'] as Map)['total']);
      expect(ids.length, greaterThan(125));
      final searched = app.merchants.countDetail(
        'showcase-bakery',
        id,
        search: 'LOT-124',
      );
      expect(searched['lines'], hasLength(1));
      expect((searched['lineStats'] as Map)['total'], ids.length);
    },
  );
}

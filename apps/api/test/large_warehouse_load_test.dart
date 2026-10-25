import 'dart:convert';
import 'dart:io';
import 'package:marketplace_server/marketplace_server.dart';
import 'package:marketplace_server/src/merchant.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

void main() {
  test(
    'large warehouse workload: 5000 SKUs, paged lookups and acknowledged ERP feed',
    () async {
      final app = MarketplaceServer(
        const ServerConfig(databasePath: ':memory:', demoShowcase: true),
        clock: () => DateTime.utc(2026, 10, 25, 12),
      );
      addTearDown(app.close);
      final w = app.merchants.workspace('showcase-bakery'),
          store = (w['stores'] as List).first as Map,
          p = Map<String, dynamic>.from((w['products'] as List).first);
      app.database.transaction(() {
        for (var i = 0; i < 5000; i++) {
          final row = {
            ...p,
            'id': 'load-$i',
            'sku': 'LOAD-$i',
            'name': 'Veľký sklad položka $i',
          };
          app.database.db.execute(
            'INSERT INTO stock_products VALUES(?,?,?,?)',
            [row['id'], store['organizationId'], row['sku'], jsonEncode(row)],
          );
          app.database.db.execute(
            'INSERT INTO stock_lots(id,store_id,product_id,lot_code,on_hand,deadline,date_type,quality) VALUES(?,?,?,?,?,?,?,?)',
            [
              'load-lot-$i',
              store['id'],
              row['id'],
              'LOAD-LOT-$i',
              10,
              '2026-10-28T22:00:00Z',
              'useBy',
              'checked',
            ],
          );
        }
      });
      final token = app.auth.createSession('showcase-bakery')['token'],
          times = <double>[];
      final watch = Stopwatch()..start();
      for (var batch = 0; batch < 5; batch++) {
        await Future.wait(
          List.generate(20, (i) async {
            final timing = Stopwatch()..start();
            final r = await app.handler(
              Request(
                'GET',
                Uri.parse(
                  'http://localhost/v1/merchant/workspace?paged=true&storeId=${store['id']}&section=lots&query=LOAD-LOT-${batch * 20 + i}',
                ),
                headers: {'authorization': 'Bearer $token'},
              ),
            );
            final result = jsonDecode(await r.readAsString()) as Map;
            expect(r.statusCode, 200);
            expect((result['lots'] as List).length, lessThanOrEqualTo(50));
            expect(
              (result['stockSummary'] as Map)['lots'],
              greaterThanOrEqualTo(5000),
            );
            times.add(timing.elapsedMicroseconds / 1000);
          }),
        );
      }
      watch.stop();
      times.sort();
      final integration = app.merchants.createIntegration('showcase-bakery', {
            'storeId': store['id'],
            'name': 'Záťažový ERP test',
          }),
          authorization = 'Bearer ${integration['token']}';
      var events = 0, pages = 0;
      final feed = Stopwatch()..start();
      while (true) {
        final page = app.merchants.changes(authorization);
        expect((page['events'] as List).length, lessThanOrEqualTo(200));
        events += (page['events'] as List).length;
        pages++;
        app.merchants.acknowledge(authorization, {'through': page['through']});
        if (page['hasMore'] != true) break;
      }
      feed.stop();
      expect(events, greaterThanOrEqualTo(5000));
      expect(app.merchants.changes(authorization)['events'], isEmpty);
      final result = {
        'scope':
            'in-process HTTP handler; synthetic data; not a deployed internet benchmark',
        'skus': 5000,
        'requests': 100,
        'concurrency': 20,
        'totalMs': watch.elapsedMilliseconds,
        'p50Ms': times[49],
        'p95Ms': times[94],
        'maxMs': times.last,
        'erpEvents': events,
        'erpPages': pages,
        'erpReadAndAckMs': feed.elapsedMilliseconds,
      };
      await Directory('../../artifacts').create(recursive: true);
      await File(
        '../../artifacts/warehouse-load.json',
      ).writeAsString(const JsonEncoder.withIndent('  ').convert(result));
    },
    skip: Platform.environment['RUN_LOAD'] != '1'
        ? 'Explicit load run: RUN_LOAD=1 dart test test/large_warehouse_load_test.dart'
        : false,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

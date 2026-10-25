import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:marketplace_server/marketplace_server.dart';
import 'package:marketplace_server/src/auth.dart';
import 'package:marketplace_server/src/erp_bridge.dart';
import 'package:marketplace_server/src/merchant.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

void main() {
  late MarketplaceServer app;
  late String store, token, id;
  late MarketplaceDatabase state;
  setUp(() {
    app = MarketplaceServer(
      const ServerConfig(databasePath: ':memory:', demoShowcase: true),
      clock: () => DateTime.utc(2026, 10, 25, 12),
    );
    state = MarketplaceDatabase(':memory:');
    final w = app.merchants.workspace('showcase-bakery');
    store = (w['stores'] as List).first['id'] as String;
    final i = app.merchants.createIntegration('showcase-bakery', {
      'storeId': store,
      'name': 'Testovací ERP sklad',
    });
    id = i['id'] as String;
    token = 'Bearer ${i['token']}';
  });
  tearDown(() {
    app.close();
    state.close();
  });
  test(
    'stock feed is durable, bounded and acknowledged only through delivered events',
    () {
      final first = app.merchants.changes(token);
      expect(first['events'], isNotEmpty);
      expect(app.merchants.changes(token)['events'], first['events']);
      expect(
        () => app.merchants.acknowledge(token, {
          'through': (first['through'] as int) + 100000,
        }),
        throwsA(isA<ApiFailure>()),
      );
      app.merchants.acknowledge(token, {'through': first['through']});
      expect(app.merchants.changes(token)['events'], isEmpty);
      app.merchants.revokeIntegration('showcase-bakery', id);
      expect(() => app.merchants.changes(token), throwsA(isA<ApiFailure>()));
    },
  );
  test(
    'incoming ERP changes are echo-marked and cannot overwrite reservations or wrong units',
    () {
      final initial = app.merchants.changes(token);
      app.merchants.acknowledge(token, {'through': initial['through']});
      final w = app.merchants.workspace('showcase-bakery');
      final p = (w['products'] as List).first;
      final receipt = {
        'eventId': 'erp-receipt-one',
        'operation': 'receive',
        'sku': p['sku'],
        'lotCode': 'ERP-TEST',
        'quantityDisplay': '12',
        'unit': p['unit'],
        'deadline': '2026-10-27T22:00:00Z',
        'dateType': 'useBy',
      };
      final lot = app.merchants.integrationEvent(token, receipt);
      expect(lot['quality'], 'quarantine');
      app.merchants.integrationEvent(token, receipt);
      final changes = app.merchants.changes(token);
      expect(changes['events'], hasLength(1));
      expect((changes['events'] as List).single['echo'], true);
      expect(
        () => app.merchants.integrationEvent(token, {
          ...receipt,
          'eventId': 'erp-wrong-unit',
          'unit': 'liter',
        }),
        throwsA(isA<ApiFailure>()),
      );
    },
  );
  test(
    'bridge retries the same event after lost ERP response and commits inbound cursor after acceptance',
    () async {
      final accepted = <String, Map>{};
      var lose = true;
      final p = (app.merchants.workspace('showcase-bakery')['products'] as List)
          .first;
      final client = MockClient((r) async {
        if (r.url.host == 'marketplace.test') {
          final response = await app.handler(
            Request(r.method, r.url, headers: r.headers, body: r.bodyBytes),
          );
          return http.Response.bytes(
            await response.read().expand((c) => c).toList(),
            response.statusCode,
            headers: response.headers,
          );
        }
        if (r.url.path == '/stock/events') {
          final e = jsonDecode(r.body) as Map;
          accepted.putIfAbsent(r.headers['idempotency-key']!, () => e);
          if (lose) {
            lose = false;
            throw StateError('Simulated lost response');
          }
          return http.Response(
            jsonEncode({'eventId': e['id'], 'acceptedSequence': e['sequence']}),
            200,
          );
        }
        if (r.url.path == '/stock/inbound') {
          return http.Response(
            jsonEncode({
              'events': r.url.queryParameters['after'] == null
                  ? [
                      {
                        'eventId': 'erp-bridge-receipt',
                        'operation': 'receive',
                        'sku': p['sku'],
                        'lotCode': 'BRIDGE',
                        'quantityDisplay': '5',
                        'unit': p['unit'],
                        'deadline': '2026-10-27T22:00:00Z',
                        'dateType': 'useBy',
                      },
                    ]
                  : [],
              'nextCursor': 'erp-page-1',
              'hasMore': false,
            }),
            200,
          );
        }
        return http.Response('{}', 404);
      });
      final bridge = ErpBridge(
        marketplace: Uri.parse('https://marketplace.test'),
        stockToken: token.substring(7),
        erp: Uri.parse('https://erp.test'),
        erpToken: 'test-token',
        state: state,
        pullIncoming: true,
        client: client,
      );
      await expectLater(bridge.once(), throwsStateError);
      expect(
        app.database.db.select(
          'SELECT acknowledged,delivered FROM stock_delivery WHERE integration_id=?',
          [id],
        ).first['acknowledged'],
        lessThan(
          app.database.db.select(
                'SELECT delivered FROM stock_delivery WHERE integration_id=?',
                [id],
              ).first['delivered']
              as int,
        ),
      );
      final result = await bridge.once();
      expect(result['received'], 1);
      final total = accepted.length;
      await bridge.once();
      expect(accepted, hasLength(total));
      expect(
        app.database.db.select(
          "SELECT id FROM stock_lots WHERE lot_code='BRIDGE'",
        ),
        hasLength(1),
      );
      bridge.close();
    },
  );
  test(
    'connector endpoint validation rejects cleartext and credential-bearing URLs',
    () {
      for (final url in [
        'http://erp.test',
        'https://key:secret@erp.test',
        'https://erp.test?key=secret',
      ]) {
        expect(
          () => ErpBridge(
            marketplace: Uri.parse('https://marketplace.test'),
            stockToken: 'token',
            erp: Uri.parse(url),
            erpToken: 'secret',
            state: state,
          ),
          throwsArgumentError,
        );
      }
    },
  );
}

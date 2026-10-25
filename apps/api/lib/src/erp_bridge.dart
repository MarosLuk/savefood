import 'dart:convert';
import 'package:http/http.dart' as http;
import 'database.dart';

/// Generic ERP HTTP contract. Provider-specific mappings belong at the ERP edge.
/// Acknowledgements advance only after durable acceptance by the receiver.
class ErpBridge {
  ErpBridge({
    required this.marketplace,
    required this.stockToken,
    required this.erp,
    required this.erpToken,
    required this.state,
    this.pullIncoming = false,
    this.allowLoopback = false,
    http.Client? client,
  }) : client = client ?? http.Client() {
    for (final uri in [marketplace, erp]) {
      if (uri.userInfo.isNotEmpty ||
          uri.hasQuery ||
          uri.hasFragment ||
          uri.scheme != 'https' &&
              !(allowLoopback &&
                  uri.scheme == 'http' &&
                  {'127.0.0.1', 'localhost', '::1'}.contains(uri.host))) {
        throw ArgumentError(
          'ERP endpoints require HTTPS (or explicit local test loopback).',
        );
      }
    }
    if (stockToken.isEmpty || erpToken.isEmpty) {
      throw ArgumentError('Both connector tokens are required.');
    }
    state.db.execute(
      'CREATE TABLE IF NOT EXISTS bridge_state(name TEXT PRIMARY KEY,value TEXT NOT NULL)',
    );
  }
  final Uri marketplace, erp;
  final String stockToken, erpToken;
  final MarketplaceDatabase state;
  final bool pullIncoming, allowLoopback;
  final http.Client client;
  Uri uri(Uri base, String path) =>
      Uri.parse('${base.toString().replaceAll(RegExp(r'/+$'), '')}$path');
  Future<Map<String, dynamic>> request(
    String method,
    Uri url,
    String token, {
    Map<String, dynamic>? body,
    String? key,
  }) async {
    final r = http.Request(method, url)..followRedirects = false;
    r.headers.addAll({
      'authorization': 'Bearer $token',
      'accept': 'application/json',
      if (body != null) 'content-type': 'application/json',
      'idempotency-key': ?key,
    });
    if (body != null) r.body = jsonEncode(body);
    final response = await client.send(r).timeout(const Duration(seconds: 25));
    final bytes = <int>[];
    await for (final chunk in response.stream.timeout(
      const Duration(seconds: 25),
    )) {
      if (bytes.length + chunk.length > 2 * 1024 * 1024) {
        throw StateError('ERP response exceeds 2 MB.');
      }
      bytes.addAll(chunk);
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        'Connector request failed (${response.statusCode}); cursor preserved.',
      );
    }
    final result = jsonDecode(utf8.decode(bytes));
    if (result is! Map) {
      throw StateError('Connector returned an invalid envelope.');
    }
    return Map<String, dynamic>.from(result);
  }

  Future<Map<String, int>> once({int maxPages = 5}) async {
    if (maxPages < 1 || maxPages > 100) {
      throw ArgumentError('Invalid page budget.');
    }
    var sent = 0, received = 0;
    for (var page = 0; page < maxPages; page++) {
      final batch = await request(
        'GET',
        uri(marketplace, '/v1/integrations/changes'),
        stockToken,
      );
      if (batch['schema'] != 'nevyhadzuj.stock.v1' ||
          batch['through'] is! int ||
          batch['events'] is! List) {
        throw StateError('Unsupported stock feed.');
      }
      for (final raw in batch['events'] as List) {
        final event = Map<String, dynamic>.from(raw as Map);
        if (event['echo'] == true) continue;
        final result = await request(
          'POST',
          uri(erp, '/stock/events'),
          erpToken,
          body: event,
          key: 'nevyhadzuj/${batch['integrationId']}/${event['sequence']}',
        );
        if (result['acceptedSequence'] != event['sequence'] ||
            result['eventId'] != event['id']) {
          throw StateError(
            'ERP did not confirm this exact event; cursor preserved.',
          );
        }
        sent++;
      }
      await request(
        'POST',
        uri(marketplace, '/v1/integrations/changes/ack'),
        stockToken,
        body: {'through': batch['through']},
      );
      if (batch['hasMore'] != true) break;
    }
    if (pullIncoming) {
      final name = 'inbound:${erp.toString()}:${marketplace.toString()}';
      for (var page = 0; page < maxPages; page++) {
        final cursor =
            state.db.select('SELECT value FROM bridge_state WHERE name=?', [
                  name,
                ]).firstOrNull?['value']
                as String?;
        final path =
            '/stock/inbound${cursor == null ? '' : '?after=${Uri.encodeQueryComponent(cursor)}'}';
        final batch = await request('GET', uri(erp, path), erpToken);
        if (batch['events'] is! List ||
            (batch['events'] as List).length > 200 ||
            batch['nextCursor'] is! String) {
          throw StateError('ERP inbound page is invalid.');
        }
        for (final raw in batch['events'] as List) {
          final event = Map<String, dynamic>.from(raw as Map);
          if (event['eventId'] is! String ||
              !(event['eventId'] as String).startsWith('erp-')) {
            throw StateError(
              'ERP events require stable erp-prefixed event IDs.',
            );
          }
          await request(
            'POST',
            uri(marketplace, '/v1/integrations/stock'),
            stockToken,
            body: event,
          );
          received++;
        }
        state.db.execute(
          'INSERT INTO bridge_state VALUES(?,?) ON CONFLICT(name) DO UPDATE SET value=excluded.value',
          [name, batch['nextCursor']],
        );
        if (batch['hasMore'] != true) break;
        if (batch['nextCursor'] == cursor) {
          throw StateError('ERP cursor did not advance.');
        }
      }
    }
    return {'sent': sent, 'received': received};
  }

  Future<Map<String, int>> accountingOnce({int maxPages = 5}) async {
    if (maxPages < 1 || maxPages > 100) {
      throw ArgumentError('Invalid page budget.');
    }
    var sent = 0;
    for (var page = 0; page < maxPages; page++) {
      final batch = await request(
        'GET',
        uri(marketplace, '/v1/integrations/accounting'),
        stockToken,
      );
      if (batch['schema'] != 'nevyhadzuj.billing.v1' ||
          batch['through'] is! int ||
          batch['documents'] is! List) {
        throw StateError('Unsupported accounting feed.');
      }
      for (final raw in batch['documents'] as List) {
        final doc = Map<String, dynamic>.from(raw as Map);
        final result = await request(
          'POST',
          uri(erp, '/accounting/documents'),
          erpToken,
          body: doc,
          key: 'nevyhadzuj/document/${doc['id']}',
        );
        if (result['documentId'] != doc['id'] ||
            result['hash'] != doc['hash']) {
          throw StateError(
            'Accounting system did not confirm the immutable document.',
          );
        }
        sent++;
      }
      await request(
        'POST',
        uri(marketplace, '/v1/integrations/accounting/ack'),
        stockToken,
        body: {'through': batch['through']},
      );
      if (batch['hasMore'] != true) break;
    }
    return {'sent': sent, 'received': 0};
  }

  void close() => client.close();
}

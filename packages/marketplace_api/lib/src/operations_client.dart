import 'package:marketplace_domain/marketplace_domain.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'client.dart';

extension OperationsApi on MarketplaceApi {
  Future<Map<String, dynamic>> supportTickets({
    bool inbox = false,
    String? status,
    int? before,
    String? search,
    String? priority,
    String assignment = 'all',
    bool unread = false,
  }) => request(
    'GET',
    '/v1/support/tickets?${Uri(queryParameters: {'inbox': '$inbox', 'status': ?status, 'search': ?search, 'priority': ?priority, 'assignment': assignment, 'unread': '$unread', if (before != null) 'before': '$before'}).query}',
  );
  Future<SupportTicket> supportTicket(
    String id, {
    int? before,
    int? after,
  }) async => SupportTicket.fromJson(
    await request(
      'GET',
      '/v1/support/tickets/${Uri.encodeComponent(id)}?${Uri(queryParameters: {if (before != null) 'before': '$before', if (after != null) 'after': '$after'}).query}',
    ),
  );
  Future<SupportPhoto> uploadSupportPhoto(
    String ticket,
    Uint8List bytes,
  ) async => SupportPhoto.fromJson(
    Map<String, dynamic>.from(
      jsonDecode(
            utf8.decode(
              (await binary(
                'POST',
                '/v1/support/tickets/${Uri.encodeComponent(ticket)}/photos',
                bytes: bytes,
              )).bodyBytes,
            ),
          )
          as Map,
    ),
  );
  Future<Uint8List> supportPhoto(String id) async => (await binary(
    'GET',
    '/v1/support/photos/${Uri.encodeComponent(id)}',
  )).bodyBytes;
  Future<Map<String, dynamic>> supportAction(
    String path,
    Map<String, dynamic> body,
  ) => request(
    'POST',
    '/v1/support/$path',
    body: {
      ...body,
      'idempotencyKey':
          body['idempotencyKey'] ?? MarketplaceApi.newIdempotencyKey(),
    },
  );
  Future<Map<String, dynamic>> supportOrder(String ticket) => request(
    'GET',
    '/v1/support/tickets/${Uri.encodeComponent(ticket)}/order',
  );
  Future<Map<String, dynamic>> merchantFinance(String org) =>
      request('GET', '/v1/merchant/finance/${Uri.encodeComponent(org)}');
  Future<Map<String, dynamic>> financeAction(
    String org,
    String action,
    Map<String, dynamic> body,
  ) => request(
    'POST',
    '/v1/merchant/finance/${Uri.encodeComponent(org)}/$action',
    body: {
      ...body,
      'idempotencyKey':
          body['idempotencyKey'] ?? MarketplaceApi.newIdempotencyKey(),
    },
  );
  Future<Map<String, dynamic>> accountingExport(
    String org, {
    String? from,
    String? to,
  }) => request(
    'GET',
    '/v1/merchant/finance/${Uri.encodeComponent(org)}/export?${Uri(queryParameters: {'from': ?from, 'to': ?to}).query}',
  );
}

import 'package:marketplace_domain/marketplace_domain.dart';
import 'client.dart';

extension MerchantApi on MarketplaceApi {
  Future<MerchantWorkspace> merchantWorkspace({
    String? storeId,
    String? section,
    String? before,
    String? query,
  }) async => MerchantWorkspace.fromJson(
    await request(
      'GET',
      '/v1/merchant/workspace?${Uri(queryParameters: {'paged': 'true', 'storeId': ?storeId, 'section': ?section, 'before': ?before, 'query': ?query}).query}',
    ),
  );
  Future<Map<String, dynamic>> merchantAction(
    String path,
    Map<String, dynamic> body, {
    String method = 'POST',
  }) => request(
    method,
    '/v1/merchant/$path',
    body: {
      ...body,
      'idempotencyKey':
          body['idempotencyKey'] ?? MarketplaceApi.newIdempotencyKey(),
    },
  );
}

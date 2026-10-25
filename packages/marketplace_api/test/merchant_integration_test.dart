import 'dart:io';
import 'package:marketplace_api/marketplace_api.dart';
import 'package:marketplace_domain/marketplace_domain.dart';
import 'package:marketplace_server/marketplace_server.dart';
import 'package:shelf/shelf_io.dart' as shelf;
import 'package:test/test.dart';

void main() {
  test(
    'seller web and customer mobile share stock through the actual HTTP API',
    () async {
      final now = DateTime.utc(2026, 10, 24, 10);
      final app = MarketplaceServer(
        const ServerConfig(databasePath: ':memory:', seedDemo: false),
        clock: () => now,
      );
      final server = await shelf.serve(
        app.handler,
        InternetAddress.loopbackIPv4,
        0,
      );
      final base = 'http://127.0.0.1:${server.port}';
      final seller = MarketplaceApi(base, vault: MemoryTokenVault()),
          buyer = MarketplaceApi(base, vault: MemoryTokenVault());
      addTearDown(() async {
        seller.close();
        buyer.close();
        await server.close(force: true);
        app.close();
      });
      await seller.register(
        'Predajca',
        'seller@example.test',
        'long-test-password-123',
      );
      await buyer.register(
        'Zákazník',
        'buyer@example.test',
        'long-buyer-password-123',
      );
      await seller.merchantAction('organizations', {
        'name': 'Malá reštaurácia s.r.o.',
        'companyId': '12345678',
        'contactEmail': 'seller@example.test',
        'store': {
          'name': 'Malá reštaurácia',
          'kind': 'restaurant',
          'address': 'Hlavná 1, Bratislava',
          'point': {'lat': 48.15, 'lng': 17.1},
        },
      });
      var ws = await seller.merchantWorkspace();
      final store = ws.stores.single;
      final product = await seller.merchantAction('products', {
        'organizationId': store.organizationId,
        'sku': 'MEAL-01',
        'name': 'Denné menu',
        'category': 'meals',
        'unit': 'portion',
        'unitValue': 900,
        'allergens': 'Lepok, zeler',
        'storage': 'chilled',
        'image': 'https://example.test/menu.jpg',
      });
      await seller.merchantAction('stock/receive', {
        'storeId': store.id,
        'productId': product['id'],
        'lotCode': 'KUCHYNA-2410',
        'quantity': 5,
        'deadline': '2026-10-24T15:00:00Z',
        'dateType': 'useBy',
        'quality': 'checked',
      });
      final offer = await seller.merchantAction('offers', {
        'storeId': store.id,
        'title': 'Denné menu so sebou',
        'category': 'meals',
        'image': 'https://example.test/menu.jpg',
        'price': 350,
        'stock': 5,
        'pickupStart': '2026-10-24T12:00:00Z',
        'pickupEnd': '2026-10-24T13:00:00Z',
        'description': 'Čerstvé porcie z dnešného obedového menu.',
        'recipe': {product['id']: 1},
        'state': 'draft',
      });
      expect(await buyer.catalog(), isEmpty);
      await seller.merchantAction('offers/${offer['id']}/state', {
        'state': 'published',
      });
      expect((await buyer.catalog()).single.stock, 5);
      final order = await buyer.reserve(
        cart: {offer['id'] as String: 2},
        invoice: const InvoiceDetails(
          name: 'Jana Nová',
          email: 'buyer@example.test',
          street: 'Ulica 1',
          city: 'Bratislava',
          postcode: '81101',
        ),
        coupon: '',
        useCredit: false,
        key: MarketplaceApi.newIdempotencyKey(),
      );
      ws = await seller.merchantWorkspace();
      expect(ws.lots.single.reserved, 2);
      expect(ws.lots.single.onHand, 5);
      expect((await buyer.catalog()).single.stock, 3);
      await seller.merchantAction(
        'stores/${store.id}/orders/${order.id}/collect',
        {'pickupCode': order.pickupCode},
      );
      ws = await seller.merchantWorkspace();
      expect(ws.lots.single.onHand, 3);
      expect(ws.lots.single.reserved, 0);
      expect((await buyer.me())['orders'].single['status'], 'collected');
    },
  );
}

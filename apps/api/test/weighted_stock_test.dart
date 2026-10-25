import 'package:marketplace_domain/marketplace_domain.dart';
import 'package:marketplace_server/marketplace_server.dart';
import 'package:marketplace_server/src/merchant.dart';
import 'package:test/test.dart';

void main() {
  test(
    'fixed units parse exact kg and litres without binary floating point',
    () {
      expect(StockUnit.kilogram.parseAmount('0,125'), 125);
      expect(StockUnit.liter.parseAmount('1.001'), 1001);
      expect(StockUnit.kilogram.formatAmount(1501, withUnit: true), '1,501 kg');
      expect(StockUnit.piece.parseAmount('3'), 3);
      expect(() => StockUnit.piece.parseAmount('0,5'), throwsFormatException);
      expect(
        () => StockUnit.kilogram.parseAmount('0.0001'),
        throwsFormatException,
      );
    },
  );
  test(
    'weighted receipt, recipe valuation, reservation and expiry automation preserve base units',
    () {
      final app = MarketplaceServer(
        const ServerConfig(databasePath: ':memory:', demoShowcase: true),
        clock: () => DateTime.utc(2026, 10, 25, 12),
      );
      addTearDown(app.close);
      final w = app.merchants.workspace('showcase-bakery'),
          s = (w['stores'] as List).first as Map;
      final p = app.merchants.createProduct('showcase-bakery', {
        'organizationId': s['organizationId'],
        'sku': 'KG-APPLE',
        'name': 'Jablká na váhu',
        'category': 'groceries',
        'unit': 'kilogram',
        'unitValue': 199,
        'allergens': 'Bez alergénov',
        'storage': 'ambient',
        'image': 'vegetables',
      });
      final lot = app.merchants.receive('showcase-bakery', {
        'storeId': s['id'],
        'productId': p['id'],
        'lotCode': 'KG-1',
        'quantityDisplay': '10,125',
        'deadline': '2026-10-27T20:00:00Z',
        'dateType': 'useBy',
        'quality': 'checked',
      });
      expect(lot['onHand'], 10125);
      final offer = app.merchants.createOffer('showcase-bakery', {
        'storeId': s['id'],
        'title': 'Jablkový balíček',
        'description': 'Voňavé jablká s blížiacim sa termínom.',
        'category': 'groceries',
        'image': 'vegetables',
        'recipe': {p['id']: 1500},
        'price': 150,
        'stock': 5,
        'pickupStart': '2026-10-26T14:00:00Z',
        'pickupEnd': '2026-10-26T15:00:00Z',
        'state': 'published',
      });
      // 1.5 kg × 1.99 EUR = 2.985 EUR, rounded once to 2.99 EUR.
      final published = app.database.decode(
        app.database.db.select('SELECT payload FROM offers WHERE id=?', [
              offer['id'],
            ]).first['payload']
            as String,
      );
      expect(published['originalPrice'], 299);
      final adjusted = app.merchants
          .adjust('showcase-bakery', lot['id'] as String, {
            'version': lot['version'],
            'deltaDisplay': '-0,125',
            'reason': 'Presné odváženie',
          });
      expect(adjusted['onHand'], 10000);
      final summary = app.merchants.pagedWorkspace('showcase-bakery', {
        'storeId': s['id'] as String,
      });
      expect(
        ((summary['stockSummary'] as Map)['units'] as List).singleWhere(
          (u) => u['unit'] == 'kilogram',
        )['available'],
        10000,
      );
    },
  );
}

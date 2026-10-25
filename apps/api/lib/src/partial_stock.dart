part of 'merchant.dart';

extension PartialStock on MerchantService {
  void initializePartialStock() {
    if (!_rows(
      'PRAGMA table_info(merchant_order_lines)',
    ).any((r) => r['name'] == 'refunded_quantity')) {
      database.db.execute(
        'ALTER TABLE merchant_order_lines ADD COLUMN refunded_quantity INTEGER NOT NULL DEFAULT 0',
      );
      for (final row in _rows(
        'SELECT l.order_id,l.offer_id,o.payload FROM merchant_order_lines l JOIN orders o ON o.id=l.order_id',
      )) {
        final order = RescueOrder.fromJson(
          database.decode(row['payload'] as String),
        );
        final item = order.items
            .where((i) => i.offerId == row['offer_id'])
            .firstOrNull;
        if (item != null) {
          database.db.execute(
            'UPDATE merchant_order_lines SET refunded_quantity=? WHERE order_id=? AND offer_id=?',
            [item.refundCount, row['order_id'], row['offer_id']],
          );
        }
      }
    }
  }

  void releaseUnits(RescueOrder order, Map<String, int> units, String refund) {
    for (final entry in units.entries) {
      final item = order.items.firstWhere((i) => i.offerId == entry.key);
      if (entry.value < 1 || entry.value > item.remainingQuantity) {
        throw const ApiFailure(409, 'Neplatný počet uvoľnených balíčkov.');
      }
      database.db.execute(
        'UPDATE merchant_order_lines SET refunded_quantity=refunded_quantity+? WHERE order_id=? AND offer_id=?',
        [entry.value, order.id, entry.key],
      );
      final offer = managed(entry.key);
      if (offer == null || item.collected) continue;
      final recipe = _recipe(jsonDecode(offer['recipe'] as String));
      for (final component in recipe.entries) {
        var needed = component.value * entry.value;
        for (final row in _rows(
          "SELECT r.*,l.store_id FROM stock_reservations r JOIN stock_lots l ON l.id=r.lot_id WHERE r.order_id=? AND r.offer_id=? AND l.product_id=? AND r.state='held' ORDER BY l.deadline DESC,l.id DESC",
          [order.id, entry.key, component.key],
        )) {
          if (needed == 0) break;
          final take = math.min(needed, row['quantity'] as int),
              left = (row['quantity'] as int) - take;
          if (left == 0) {
            database.db.execute(
              "UPDATE stock_reservations SET state='released' WHERE order_id=? AND offer_id=? AND lot_id=?",
              [order.id, entry.key, row['lot_id']],
            );
          } else {
            database.db.execute(
              'UPDATE stock_reservations SET quantity=? WHERE order_id=? AND offer_id=? AND lot_id=?',
              [left, order.id, entry.key, row['lot_id']],
            );
          }
          _movement(
            row['store_id'] as String,
            row['lot_id'] as String,
            order.id,
            'release',
            0,
            -take,
            'Refundácia $refund · ${entry.value} balíčkov',
          );
          needed -= take;
        }
        if (needed != 0) {
          throw const ApiFailure(
            409,
            'Rezervácia nesúhlasí s počtom. Najprv zosúlaď sklad.',
          );
        }
      }
    }
  }
}

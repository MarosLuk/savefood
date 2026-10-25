import 'package:marketplace_domain/marketplace_domain.dart';
import 'package:test/test.dart';

void main() {
  test('allocation conserves every cent, including ties and zero weights', () {
    expect(allocateCents(2, [1, 1, 1]), [1, 1, 0]);
    for (var amount = 0; amount < 200; amount++) {
      for (final weights in [
        [1, 3, 7],
        [0, 4, 0],
        [1, 1, 1],
        [333, 999, 27, 501],
      ]) {
        final shares = allocateCents(amount, weights);
        expect(shares.fold(0, (a, b) => a + b), amount);
        expect(shares.every((s) => s >= 0), true);
        for (var i = 0; i < weights.length; i++) {
          if (weights[i] == 0) expect(shares[i], 0);
        }
      }
    }
  });
  test(
    'seller, credit, external payment and fees reconcile across a mixed basket',
    () {
      final order = RescueOrder(
        id: 'order',
        createdAt: DateTime.utc(2026),
        items: [
          for (final v in [101, 203, 507])
            OrderItem(
              offerId: 'offer-$v',
              store: 'Store',
              title: 'Food',
              image: 'bread',
              quantity: 1,
              unitPrice: v,
              pickupStart: DateTime.utc(2026),
              pickupEnd: DateTime.utc(2026, 1, 2),
              address: 'Address',
            ),
        ],
        total: 255,
        discount: 81,
        serviceFee: 16,
        creditUsed: 491,
        cashback: 0,
        invoice: const InvoiceDetails(),
      );
      final a = OrderAllocation.forOrder(order, 1000);
      int sum(int Function(OrderAllocation) f) => a.fold(0, (n, l) => n + f(l));
      expect(sum((l) => l.external), order.total);
      expect(sum((l) => l.credit), order.creditUsed);
      expect(sum((l) => l.discount), 81);
      expect(sum((l) => l.commission), 73);
      expect(
        sum((l) => l.sellerNet + l.commission + l.fee),
        order.total + order.creditUsed,
      );
    },
  );
}

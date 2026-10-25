import 'package:marketplace_domain/marketplace_domain.dart';
import 'package:test/test.dart';

void main() {
  test(
    'credit leaves a valid external minimum or covers the complete amount',
    () {
      final partial = CheckoutQuote.calculate(
        subtotal: 390,
        credit: 397,
        useCredit: true,
        minimumExternalPayment: 50,
      );
      expect(partial.total, 50);
      expect(partial.creditUsed, 348);
      final full = CheckoutQuote.calculate(
        subtotal: 390,
        credit: 398,
        useCredit: true,
        minimumExternalPayment: 50,
      );
      expect(full.total, 0);
      expect(full.creditUsed, 398);
    },
  );
  test(
    'legacy orders remain hosted and native flow survives state changes',
    () {
      final native = RescueOrder(
        id: 'order',
        createdAt: DateTime.utc(2026),
        items: [],
        total: 398,
        discount: 0,
        serviceFee: 8,
        creditUsed: 0,
        cashback: 0,
        invoice: const InvoiceDetails(),
        paymentFlow: PaymentFlow.native,
      );
      expect(
        RescueOrder.fromJson(
          native.withStatus(OrderStatus.collected).toJson(),
        ).paymentFlow,
        PaymentFlow.native,
      );
      final legacy = native.toJson()..remove('paymentFlow');
      expect(RescueOrder.fromJson(legacy).paymentFlow, PaymentFlow.hosted);
    },
  );
}

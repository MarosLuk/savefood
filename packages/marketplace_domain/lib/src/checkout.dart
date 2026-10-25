import 'dart:math' as math;

class CheckoutQuote {
  const CheckoutQuote({
    required this.subtotal,
    required this.discount,
    required this.serviceFee,
    required this.creditUsed,
    required this.total,
    required this.cashback,
  });
  final int subtotal, discount, serviceFee, creditUsed, total, cashback;
  static const validCoupons = {'VITAJ10', 'DOBREJEDLO'};

  factory CheckoutQuote.calculate({
    required int subtotal,
    String coupon = '',
    int credit = 0,
    bool useCredit = false,
    bool clubMember = false,
    int minimumExternalPayment = 0,
  }) {
    if (subtotal < 0 || credit < 0 || minimumExternalPayment < 0) {
      throw ArgumentError('Záporná suma.');
    }
    final normalized = coupon.trim().toUpperCase();
    if (normalized.isNotEmpty && !validCoupons.contains(normalized)) {
      throw ArgumentError('Tento kupón nepoznáme. V deme skús VITAJ10.');
    }
    final discount = normalized.isEmpty ? 0 : (subtotal * .10).round();
    final fee = subtotal == 0 ? 0 : (subtotal * .02).round();
    final beforeCredit = subtotal - discount + fee;
    // Cover everything, or leave a charge the card processor can accept.
    final creditLimit = credit >= beforeCredit
        ? beforeCredit
        : math.max(0, beforeCredit - minimumExternalPayment);
    final used = useCredit ? math.min(credit, creditLimit) : 0;
    final total = beforeCredit - used;
    return CheckoutQuote(
      subtotal: subtotal,
      discount: discount,
      serviceFee: fee,
      creditUsed: used,
      total: total,
      cashback: clubMember ? ((subtotal - discount) * .10).round() : 0,
    );
  }
}

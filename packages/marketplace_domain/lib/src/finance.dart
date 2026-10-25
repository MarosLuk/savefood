import 'models.dart';

/// Largest-remainder allocation. Integers only, stable tie-breaking by input order.
List<int> allocateCents(int amount, List<int> weights) {
  if (amount < 0 || weights.any((w) => w < 0)) {
    throw ArgumentError('Záporná suma.');
  }
  final sum = weights.fold(0, (a, b) => a + b);
  if (sum == 0) {
    if (amount != 0) throw ArgumentError('Chýba základ rozdelenia.');
    return List.filled(weights.length, 0);
  }
  final result = weights.map((w) => amount * w ~/ sum).toList();
  final ranks = List.generate(weights.length, (i) => i)
    ..sort((a, b) {
      final diff = (amount * weights[b] % sum).compareTo(
        amount * weights[a] % sum,
      );
      return diff == 0 ? a.compareTo(b) : diff;
    });
  var remainder = amount - result.fold(0, (a, b) => a + b);
  for (final i in ranks) {
    if (remainder-- <= 0) break;
    result[i]++;
  }
  return result;
}

class OrderAllocation {
  const OrderAllocation({
    required this.offerId,
    required this.gross,
    required this.discount,
    required this.fee,
    required this.credit,
    required this.external,
    required this.commission,
    required this.sellerNet,
  });
  final String offerId;
  final int gross, discount, fee, credit, external, commission, sellerNet;
  int get goodsNet => gross - discount;
  int get refundable => external + credit;
  OrderAllocation unitSlice(int quantity, int start, int count) {
    if (quantity < 1 ||
        start < 0 ||
        count < 0 ||
        start + count > quantity ||
        gross % quantity != 0) {
      throw ArgumentError('Neplatný rozsah kusov.');
    }
    final net = allocateCents(goodsNet, List.filled(quantity, 1));
    final fees = allocateCents(fee, net),
        commissions = allocateCents(commission, net);
    final charge = List.generate(quantity, (i) => net[i] + fees[i]);
    final credits = allocateCents(credit, charge);
    int sum(List<int> values) =>
        values.skip(start).take(count).fold(0, (a, b) => a + b);
    final g = gross ~/ quantity * count,
        n = sum(net),
        f = sum(fees),
        c = sum(credits),
        m = sum(commissions);
    return OrderAllocation(
      offerId: offerId,
      gross: g,
      discount: g - n,
      fee: f,
      credit: c,
      external: n + f - c,
      commission: m,
      sellerNet: n - m,
    );
  }

  Map<String, dynamic> toJson() => {
    'offerId': offerId,
    'gross': gross,
    'discount': discount,
    'fee': fee,
    'credit': credit,
    'external': external,
    'commission': commission,
    'sellerNet': sellerNet,
  };
  factory OrderAllocation.fromJson(Map<String, dynamic> j) => OrderAllocation(
    offerId: j['offerId'] as String,
    gross: j['gross'] as int,
    discount: j['discount'] as int,
    fee: j['fee'] as int,
    credit: j['credit'] as int,
    external: j['external'] as int,
    commission: j['commission'] as int,
    sellerNet: j['sellerNet'] as int,
  );
  static List<OrderAllocation> forOrder(RescueOrder order, int commissionBps) {
    if (commissionBps < 0 || commissionBps > 5000 || order.items.isEmpty) {
      throw ArgumentError('Neplatná provízia alebo objednávka.');
    }
    final gross = order.items.map((i) => i.total).toList();
    final discounts = allocateCents(order.discount, gross);
    final net = List.generate(gross.length, (i) => gross[i] - discounts[i]);
    if (net.any((n) => n < 0)) throw ArgumentError('Zľava prevyšuje predaj.');
    final fees = allocateCents(order.serviceFee, net);
    final charge = List.generate(net.length, (i) => net[i] + fees[i]);
    final credits = allocateCents(order.creditUsed, charge);
    if (charge.fold(0, (a, b) => a + b) != order.total + order.creditUsed) {
      throw ArgumentError('Nesúhlasí súčet objednávky.');
    }
    final commissionTotal =
        (net.fold(0, (a, b) => a + b) * commissionBps + 5000) ~/ 10000;
    final commissions = allocateCents(commissionTotal, net);
    return List.generate(
      gross.length,
      (i) => OrderAllocation(
        offerId: order.items[i].offerId,
        gross: gross[i],
        discount: discounts[i],
        fee: fees[i],
        credit: credits[i],
        external: charge[i] - credits[i],
        commission: commissions[i],
        sellerNet: net[i] - commissions[i],
      ),
    );
  }
}

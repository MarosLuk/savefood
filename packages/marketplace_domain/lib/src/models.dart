import 'dart:math' as math;

/// All arithmetic uses integer cents. Formatting is deliberately at the edge.
String euro(int cents) =>
    '${(cents / 100).toStringAsFixed(2).replaceAll('.', ',')} €';

enum FoodCategory {
  bakery('Pečivo', 'bread'),
  meals('Jedlá', 'meal'),
  desserts('Sladké', 'dessert'),
  groceries('Potraviny', 'vegetables'),
  cafe('Kaviarne', 'coffee'),
  produce('Ovocie a zelenina', 'salad'),
  flowers('Kvety', 'flowers');

  const FoodCategory(this.label, this.image);
  final String label;
  final String image;
}

enum Diet {
  vegetarian('Vegetariánske'),
  vegan('Vegánske'),
  glutenFree('Bez lepku'),
  lactoseFree('Bez laktózy');

  const Diet(this.label);
  final String label;
}

enum OfferFeature {
  localFavorite('Miestny favorit'),
  fresh('Novinka'),
  sellingFast('Mizne rýchlo');

  const OfferFeature(this.label);
  final String label;
}

enum OfferType { surprise, club }

class GeoPoint {
  const GeoPoint(this.latitude, this.longitude);
  final double latitude;
  final double longitude;

  double distanceTo(GeoPoint other) {
    const radius = 6371.0;
    double rad(double d) => d * math.pi / 180;
    final dLat = rad(other.latitude - latitude);
    final dLon = rad(other.longitude - longitude);
    final a =
        math.pow(math.sin(dLat / 2), 2) +
        math.cos(rad(latitude)) *
            math.cos(rad(other.latitude)) *
            math.pow(math.sin(dLon / 2), 2);
    return radius * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  Map<String, dynamic> toJson() => {'lat': latitude, 'lng': longitude};
  factory GeoPoint.fromJson(Map<String, dynamic> json) => GeoPoint(
    (json['lat'] as num).toDouble(),
    (json['lng'] as num).toDouble(),
  );
}

class FoodOffer {
  const FoodOffer({
    required this.id,
    required this.store,
    required this.title,
    required this.category,
    required this.image,
    required this.price,
    required this.originalPrice,
    required this.stock,
    required this.rating,
    required this.reviews,
    required this.address,
    required this.point,
    required this.pickupStart,
    required this.pickupEnd,
    required this.description,
    this.diets = const {},
    this.features = const {},
    this.type = OfferType.surprise,
    this.allergens =
        'Obsah sa mení. Na alergény sa vždy opýtaj priamo v prevádzke.',
    this.dineIn = false,
  });

  final String id, store, title, image, address, description, allergens;
  final FoodCategory category;
  final int price, originalPrice, stock, reviews;
  final double rating;
  final GeoPoint point;
  final DateTime pickupStart, pickupEnd;
  final Set<Diet> diets;
  final Set<OfferFeature> features;
  final OfferType type;
  final bool dineIn;

  int get discountPercent => ((1 - price / originalPrice) * 100).round();
  String get timeLabel => '${_time(pickupStart)} – ${_time(pickupEnd)}';
  static String _time(DateTime time) =>
      '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  bool availableAt(DateTime now) => stock > 0 && pickupEnd.isAfter(now);

  Map<String, dynamic> toJson() => {
    'id': id,
    'store': store,
    'title': title,
    'category': category.name,
    'image': image,
    'price': price,
    'originalPrice': originalPrice,
    'stock': stock,
    'rating': rating,
    'reviews': reviews,
    'address': address,
    'point': point.toJson(),
    'pickupStart': pickupStart.toUtc().toIso8601String(),
    'pickupEnd': pickupEnd.toUtc().toIso8601String(),
    'description': description,
    'diets': diets.map((v) => v.name).toList(),
    'features': features.map((v) => v.name).toList(),
    'type': type.name,
    'allergens': allergens,
    'dineIn': dineIn,
  };
  factory FoodOffer.fromJson(Map<String, dynamic> json) => FoodOffer(
    id: json['id'] as String,
    store: json['store'] as String,
    title: json['title'] as String,
    category: FoodCategory.values.byName(json['category'] as String),
    image: json['image'] as String,
    price: json['price'] as int,
    originalPrice: json['originalPrice'] as int,
    stock: json['stock'] as int,
    rating: (json['rating'] as num).toDouble(),
    reviews: json['reviews'] as int,
    address: json['address'] as String,
    point: GeoPoint.fromJson(Map<String, dynamic>.from(json['point'] as Map)),
    pickupStart: DateTime.parse(json['pickupStart'] as String).toLocal(),
    pickupEnd: DateTime.parse(json['pickupEnd'] as String).toLocal(),
    description: json['description'] as String,
    diets: (json['diets'] as List? ?? [])
        .map((v) => Diet.values.byName(v as String))
        .toSet(),
    features: (json['features'] as List? ?? [])
        .map((v) => OfferFeature.values.byName(v as String))
        .toSet(),
    type: OfferType.values.byName(json['type'] as String? ?? 'surprise'),
    allergens: json['allergens'] as String? ?? '',
    dineIn: json['dineIn'] as bool? ?? false,
  );
}

class InvoiceDetails {
  const InvoiceDetails({
    this.name = '',
    this.email = '',
    this.street = '',
    this.city = '',
    this.postcode = '',
    this.company = '',
    this.companyId = '',
    this.country = 'SK',
    this.taxId = '',
    this.vatId = '',
  });
  final String name,
      email,
      street,
      city,
      postcode,
      company,
      companyId,
      country,
      taxId,
      vatId;
  bool get isValid =>
      name.trim().length >= 2 &&
      RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email.trim()) &&
      street.trim().isNotEmpty &&
      city.trim().isNotEmpty &&
      RegExp(r'^\d{3}\s?\d{2}$').hasMatch(postcode.trim()) &&
      (company.isEmpty || RegExp(r'^\d{8}$').hasMatch(companyId));
  Map<String, dynamic> toJson() => {
    'name': name,
    'email': email,
    'street': street,
    'city': city,
    'postcode': postcode,
    'company': company,
    'companyId': companyId,
    'country': country,
    'taxId': taxId,
    'vatId': vatId,
  };
  factory InvoiceDetails.fromJson(Map<String, dynamic> json) => InvoiceDetails(
    name: json['name'] as String? ?? '',
    email: json['email'] as String? ?? '',
    street: json['street'] as String? ?? '',
    city: json['city'] as String? ?? '',
    postcode: json['postcode'] as String? ?? '',
    company: json['company'] as String? ?? '',
    companyId: json['companyId'] as String? ?? '',
    country: json['country'] as String? ?? 'SK',
    taxId: json['taxId'] as String? ?? '',
    vatId: json['vatId'] as String? ?? '',
  );
}

enum OrderStatus { awaitingPayment, reserved, collected, cancelled }

class OrderItem {
  const OrderItem({
    required this.offerId,
    required this.store,
    required this.title,
    required this.image,
    required this.quantity,
    required this.unitPrice,
    required this.pickupStart,
    required this.pickupEnd,
    required this.address,
    this.collected = false,
    this.refunded = false,
    this.refundedQuantity = 0,
    this.category,
  });
  final String offerId, store, title, image, address;
  final int quantity, unitPrice;
  final DateTime pickupStart, pickupEnd;
  final bool collected, refunded;
  final int refundedQuantity;
  final FoodCategory? category;
  int get refundCount => refunded ? quantity : refundedQuantity;
  int get remainingQuantity => quantity - refundCount;
  OrderItem withCollected() => OrderItem(
    offerId: offerId,
    store: store,
    title: title,
    image: image,
    quantity: quantity,
    unitPrice: unitPrice,
    pickupStart: pickupStart,
    pickupEnd: pickupEnd,
    address: address,
    collected: true,
    refunded: refunded,
    refundedQuantity: refundCount,
    category: category,
  );
  OrderItem withRefunded([int? count]) => OrderItem(
    offerId: offerId,
    store: store,
    title: title,
    image: image,
    quantity: quantity,
    unitPrice: unitPrice,
    pickupStart: pickupStart,
    pickupEnd: pickupEnd,
    address: address,
    collected: collected,
    refunded: refundCount + (count ?? remainingQuantity) == quantity,
    refundedQuantity: refundCount + (count ?? remainingQuantity),
    category: category,
  );
  int get total => quantity * unitPrice;
  Map<String, dynamic> toJson() => {
    'offerId': offerId,
    'store': store,
    'title': title,
    'image': image,
    'quantity': quantity,
    'unitPrice': unitPrice,
    'pickupStart': pickupStart.toIso8601String(),
    'pickupEnd': pickupEnd.toIso8601String(),
    'address': address,
    'collected': collected,
    'refunded': refunded,
    'refundedQuantity': refundCount,
    'category': category?.name,
  };
  factory OrderItem.fromJson(Map<String, dynamic> json) => OrderItem(
    offerId: json['offerId'] as String,
    store: json['store'] as String,
    title: json['title'] as String,
    image: json['image'] as String,
    quantity: json['quantity'] as int,
    unitPrice: json['unitPrice'] as int,
    pickupStart: DateTime.parse(json['pickupStart'] as String).toLocal(),
    pickupEnd: DateTime.parse(json['pickupEnd'] as String).toLocal(),
    address: json['address'] as String,
    collected: json['collected'] as bool? ?? false,
    refunded: json['refunded'] as bool? ?? false,
    refundedQuantity: json['refundedQuantity'] as int? ?? 0,
    category: FoodCategory.values
        .where((v) => v.name == json['category'])
        .firstOrNull,
  );
}

enum PaymentFlow { hosted, native }

class RescueOrder {
  const RescueOrder({
    required this.id,
    required this.createdAt,
    required this.items,
    required this.total,
    required this.discount,
    required this.serviceFee,
    required this.creditUsed,
    required this.cashback,
    required this.invoice,
    this.status = OrderStatus.reserved,
    this.paymentUrl,
    this.pickupCode,
    this.paymentFlow = PaymentFlow.hosted,
    this.refundedAmount = 0,
  });
  final String id;
  final DateTime createdAt;
  final List<OrderItem> items;
  final int total, discount, serviceFee, creditUsed, cashback;
  final InvoiceDetails invoice;
  final OrderStatus status;
  final String? paymentUrl, pickupCode;
  final PaymentFlow paymentFlow;
  final int refundedAmount;
  int get count => items.fold(0, (n, item) => n + item.quantity);
  RescueOrder withStatus(OrderStatus status, {List<OrderItem>? updatedItems}) =>
      RescueOrder(
        id: id,
        createdAt: createdAt,
        items: updatedItems ?? items,
        total: total,
        discount: discount,
        serviceFee: serviceFee,
        creditUsed: creditUsed,
        cashback: cashback,
        invoice: invoice,
        status: status,
        paymentUrl: paymentUrl,
        pickupCode: pickupCode,
        paymentFlow: paymentFlow,
        refundedAmount: refundedAmount,
      );
  Map<String, dynamic> toJson() => {
    'id': id,
    'createdAt': createdAt.toIso8601String(),
    'items': items.map((i) => i.toJson()).toList(),
    'total': total,
    'discount': discount,
    'serviceFee': serviceFee,
    'creditUsed': creditUsed,
    'cashback': cashback,
    'invoice': invoice.toJson(),
    'status': status.name,
    'paymentUrl': paymentUrl,
    'pickupCode': pickupCode,
    'paymentFlow': paymentFlow.name,
    'refundedAmount': refundedAmount,
  };
  factory RescueOrder.fromJson(Map<String, dynamic> json) => RescueOrder(
    id: json['id'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String),
    items: (json['items'] as List)
        .map((i) => OrderItem.fromJson(Map<String, dynamic>.from(i as Map)))
        .toList(),
    total: json['total'] as int,
    discount: json['discount'] as int,
    serviceFee: json['serviceFee'] as int,
    creditUsed: json['creditUsed'] as int,
    cashback: json['cashback'] as int,
    invoice: InvoiceDetails.fromJson(
      Map<String, dynamic>.from(json['invoice'] as Map),
    ),
    status: OrderStatus.values.byName(json['status'] as String),
    paymentUrl: json['paymentUrl'] as String?,
    pickupCode: json['pickupCode'] as String?,
    refundedAmount: json['refundedAmount'] as int? ?? 0,
    paymentFlow: PaymentFlow.values.byName(
      json['paymentFlow'] as String? ?? 'hosted',
    ),
  );
}

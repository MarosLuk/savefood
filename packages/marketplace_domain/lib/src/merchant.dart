import 'models.dart';

Map<String, dynamic> merchantMap(Object? value) =>
    Map<String, dynamic>.from(value as Map);
List<T> merchantList<T>(Object? value, T Function(Map<String, dynamic>) read) =>
    (value as List? ?? []).map((v) => read(merchantMap(v))).toList();

enum MerchantRole { owner, manager, staff }

enum StoreKind {
  grocery('Potraviny'),
  restaurant('Reštaurácia'),
  bakery('Pekáreň'),
  cafe('Kaviareň');

  const StoreKind(this.label);
  final String label;
}

enum StockUnit {
  piece('ks'),
  pack('balenie'),
  portion('porcia'),
  kilogram('kg', 1000),
  liter('l', 1000);

  const StockUnit(this.label, [this.scale = 1]);
  final String label;
  final int scale;
  int parseAmount(String value) {
    final text = value.trim().replaceAll(',', '.');
    if (!RegExp(r'^-?\d{1,9}(\.\d{1,3})?$').hasMatch(text)) {
      throw const FormatException(
        'Zadaj množstvo s najviac 3 desatinnými miestami.',
      );
    }
    final negative = text.startsWith('-'),
        parts = text.replaceFirst('-', '').split('.');
    final fraction = parts.length == 1
        ? 0
        : int.parse(parts[1].padRight(3, '0'));
    if (fraction * scale % 1000 != 0) {
      throw const FormatException('Táto jednotka vyžaduje celé množstvo.');
    }
    final amount = int.parse(parts[0]) * scale + fraction * scale ~/ 1000;
    return negative ? -amount : amount;
  }

  String formatAmount(int amount, {bool withUnit = false}) {
    final absolute = amount.abs(), whole = absolute ~/ scale;
    final fraction = scale == 1
        ? ''
        : (absolute % scale)
              .toString()
              .padLeft(3, '0')
              .replaceFirst(RegExp(r'0+$'), '');
    return '${amount < 0 ? '-' : ''}$whole${fraction.isEmpty ? '' : ',$fraction'}${withUnit ? ' $label' : ''}';
  }
}

enum StorageZone {
  ambient('Suchý sklad'),
  chilled('Chladené'),
  frozen('Mrazené');

  const StorageZone(this.label);
  final String label;
}

enum DateMark {
  useBy('Spotrebujte do'),
  bestBefore('Minimálna trvanlivosť');

  const DateMark(this.label);
  final String label;
}

enum StockQuality {
  checked('Skontrolované'),
  quarantine('Na kontrolu'),
  withdrawn('Vyradené');

  const StockQuality(this.label);
  final String label;
}

class MerchantOrganization {
  const MerchantOrganization({
    required this.id,
    required this.name,
    required this.companyId,
    required this.contactEmail,
    required this.role,
  });
  final String id, name, companyId, contactEmail;
  final MerchantRole role;
  bool get canManage => role != MerchantRole.staff;
  factory MerchantOrganization.fromJson(Map<String, dynamic> j) =>
      MerchantOrganization(
        id: j['id'] as String,
        name: j['name'] as String,
        companyId: j['companyId'] as String,
        contactEmail: j['contactEmail'] as String,
        role: MerchantRole.values.byName(j['role'] as String),
      );
}

class MerchantStore {
  const MerchantStore({
    required this.id,
    required this.organizationId,
    required this.name,
    required this.kind,
    required this.address,
    required this.point,
    this.platformPaused = false,
  });
  final String id, organizationId, name, address;
  final StoreKind kind;
  final GeoPoint point;
  final bool platformPaused;
  Map<String, dynamic> toJson() => {
    'id': id,
    'organizationId': organizationId,
    'name': name,
    'kind': kind.name,
    'address': address,
    'point': point.toJson(),
    'platformPaused': platformPaused,
  };
  factory MerchantStore.fromJson(Map<String, dynamic> j) => MerchantStore(
    id: j['id'] as String,
    organizationId: j['organizationId'] as String,
    name: j['name'] as String,
    kind: StoreKind.values.byName(j['kind'] as String),
    address: j['address'] as String,
    point: GeoPoint.fromJson(merchantMap(j['point'])),
    platformPaused: j['platformPaused'] == true,
  );
}

class StockProduct {
  const StockProduct({
    required this.id,
    required this.organizationId,
    required this.sku,
    required this.name,
    required this.category,
    required this.unit,
    required this.unitValue,
    required this.allergens,
    required this.storage,
    required this.image,
  });
  final String id, organizationId, sku, name, allergens, image;
  final FoodCategory category;
  final StockUnit unit;
  final int unitValue;
  int valueMilliCents(int baseQuantity) =>
      unitValue * baseQuantity * (1000 ~/ unit.scale);
  final StorageZone storage;
  Map<String, dynamic> toJson() => {
    'id': id,
    'organizationId': organizationId,
    'sku': sku,
    'name': name,
    'category': category.name,
    'unit': unit.name,
    'unitValue': unitValue,
    'allergens': allergens,
    'storage': storage.name,
    'image': image,
  };
  factory StockProduct.fromJson(Map<String, dynamic> j) => StockProduct(
    id: j['id'] as String,
    organizationId: j['organizationId'] as String,
    sku: j['sku'] as String,
    name: j['name'] as String,
    category: FoodCategory.values.byName(j['category'] as String),
    unit: StockUnit.values.byName(j['unit'] as String),
    unitValue: j['unitValue'] as int,
    allergens: j['allergens'] as String,
    storage: StorageZone.values.byName(j['storage'] as String),
    image: j['image'] as String,
  );
}

class StockLot {
  const StockLot({
    required this.id,
    required this.storeId,
    required this.productId,
    required this.code,
    required this.onHand,
    required this.reserved,
    required this.deadline,
    required this.dateMark,
    required this.quality,
    required this.version,
  });
  final String id, storeId, productId, code;
  final int onHand, reserved, version;
  final DateTime deadline;
  final DateMark dateMark;
  final StockQuality quality;
  int get available => onHand - reserved;
  bool sellableAt(DateTime when) =>
      quality == StockQuality.checked && deadline.isAfter(when);
  factory StockLot.fromJson(Map<String, dynamic> j) => StockLot(
    id: j['id'] as String,
    storeId: j['storeId'] as String,
    productId: j['productId'] as String,
    code: j['lotCode'] as String,
    onHand: j['onHand'] as int,
    reserved: j['reserved'] as int,
    deadline: DateTime.parse(j['deadline'] as String).toLocal(),
    dateMark: DateMark.values.byName(j['dateType'] as String),
    quality: StockQuality.values.byName(j['quality'] as String),
    version: j['version'] as int,
  );
}

class MerchantOffer {
  const MerchantOffer({
    required this.offer,
    required this.storeId,
    required this.state,
    required this.recipe,
    required this.available,
    this.ruleId,
  });
  final FoodOffer offer;
  final String storeId, state;
  final String? ruleId;
  final Map<String, int> recipe;
  final int available;
  factory MerchantOffer.fromJson(Map<String, dynamic> j) => MerchantOffer(
    offer: FoodOffer.fromJson(merchantMap(j['offer'])),
    storeId: j['storeId'] as String,
    state: j['state'] as String,
    recipe: merchantMap(j['recipe']).map((k, v) => MapEntry(k, v as int)),
    available: j['available'] as int,
    ruleId: j['ruleId'] as String?,
  );
}

class BundleRule {
  const BundleRule({
    required this.id,
    required this.storeId,
    required this.name,
    required this.category,
    required this.storage,
    required this.daysBefore,
    required this.targetValue,
    required this.discountPercent,
    required this.maxPacks,
    required this.startMinutes,
    required this.endMinutes,
    required this.autoPublish,
    required this.enabled,
  });
  final String id, storeId, name;
  final FoodCategory category;
  final StorageZone storage;
  final int daysBefore,
      targetValue,
      discountPercent,
      maxPacks,
      startMinutes,
      endMinutes;
  final bool autoPublish, enabled;
  Map<String, dynamic> toJson() => {
    'id': id,
    'storeId': storeId,
    'name': name,
    'category': category.name,
    'storage': storage.name,
    'daysBefore': daysBefore,
    'targetValue': targetValue,
    'discountPercent': discountPercent,
    'maxPacks': maxPacks,
    'startMinutes': startMinutes,
    'endMinutes': endMinutes,
    'autoPublish': autoPublish,
    'enabled': enabled,
  };
  factory BundleRule.fromJson(Map<String, dynamic> j) => BundleRule(
    id: j['id'] as String,
    storeId: j['storeId'] as String,
    name: j['name'] as String,
    category: FoodCategory.values.byName(j['category'] as String),
    storage: StorageZone.values.byName(j['storage'] as String),
    daysBefore: j['daysBefore'] as int,
    targetValue: j['targetValue'] as int,
    discountPercent: j['discountPercent'] as int,
    maxPacks: j['maxPacks'] as int,
    startMinutes: j['startMinutes'] as int,
    endMinutes: j['endMinutes'] as int,
    autoPublish: j['autoPublish'] as bool,
    enabled: j['enabled'] as bool,
  );
}

/// Seller view intentionally contains only the branch's lines, never the buyer's invoice.
class MerchantOrder {
  const MerchantOrder({
    required this.id,
    required this.status,
    required this.items,
    required this.createdAt,
    required this.atRisk,
    this.cancellableStoreId,
  });
  final String id, status;
  final List<OrderItem> items;
  final DateTime createdAt;
  final bool atRisk;
  final String? cancellableStoreId;
  factory MerchantOrder.fromJson(Map<String, dynamic> j) => MerchantOrder(
    id: j['id'] as String,
    status: j['status'] as String,
    items: merchantList(j['items'], OrderItem.fromJson),
    createdAt: DateTime.parse(j['createdAt'] as String),
    atRisk: j['atRisk'] as bool,
    cancellableStoreId: j['cancellableStoreId'] as String?,
  );
}

class MerchantWorkspace {
  const MerchantWorkspace({
    this.organizations = const [],
    this.stores = const [],
    this.products = const [],
    this.lots = const [],
    this.offers = const [],
    this.rules = const [],
    this.orders = const [],
    this.movements = const [],
    this.integrations = const [],
    this.members = const [],
    this.paged = false,
    this.activeStoreId,
    this.pages = const {},
    this.stockSummary = const {},
  });
  final List<MerchantOrganization> organizations;
  final List<MerchantStore> stores;
  final List<StockProduct> products;
  final List<StockLot> lots;
  final List<MerchantOffer> offers;
  final List<BundleRule> rules;
  final List<MerchantOrder> orders;
  final List<Map<String, dynamic>> movements, integrations, members;
  final bool paged;
  final String? activeStoreId;
  final Map<String, dynamic> pages, stockSummary;
  factory MerchantWorkspace.fromJson(Map<String, dynamic> j) =>
      MerchantWorkspace(
        paged: j['paged'] as bool? ?? false,
        activeStoreId: j['activeStoreId'] as String?,
        pages: Map<String, dynamic>.from(j['pages'] as Map? ?? {}),
        stockSummary: Map<String, dynamic>.from(
          j['stockSummary'] as Map? ?? {},
        ),
        organizations: merchantList(
          j['organizations'],
          MerchantOrganization.fromJson,
        ),
        stores: merchantList(j['stores'], MerchantStore.fromJson),
        products: merchantList(j['products'], StockProduct.fromJson),
        lots: merchantList(j['lots'], StockLot.fromJson),
        offers: merchantList(j['offers'], MerchantOffer.fromJson),
        rules: merchantList(j['rules'], BundleRule.fromJson),
        orders: merchantList(j['orders'], MerchantOrder.fromJson),
        movements: merchantList(j['movements'], (v) => v),
        integrations: merchantList(j['integrations'], (v) => v),
        members: merchantList(j['members'], (v) => v),
      );
}

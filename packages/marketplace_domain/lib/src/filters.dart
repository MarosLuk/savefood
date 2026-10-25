import 'models.dart';

enum OfferSort { distance, rating, price }

enum PickupFilter { any, now, today, tomorrow, custom }

String normalizeSearch(String value) {
  // Explicit map avoids locale-sensitive casing and supports Slovak/Czech.
  const replacements = {
    'á': 'a',
    'ä': 'a',
    'č': 'c',
    'ď': 'd',
    'é': 'e',
    'í': 'i',
    'ľ': 'l',
    'ĺ': 'l',
    'ň': 'n',
    'ó': 'o',
    'ô': 'o',
    'ŕ': 'r',
    'ř': 'r',
    'š': 's',
    'ť': 't',
    'ú': 'u',
    'ý': 'y',
    'ž': 'z',
    'ě': 'e',
    'ů': 'u',
  };
  return value
      .toLowerCase()
      .split('')
      .map((c) => replacements[c] ?? c)
      .join('')
      .trim();
}

class OfferFilters {
  const OfferFilters({
    this.query = '',
    this.categories = const {},
    this.diets = const {},
    this.features = const {},
    this.stores = const {},
    this.type,
    this.pickup = PickupFilter.any,
    this.customDate,
    this.sort = OfferSort.distance,
    this.availableFirst = true,
    this.radiusKm = 10,
  });
  final String query;
  final Set<FoodCategory> categories;
  final Set<Diet> diets;
  final Set<OfferFeature> features;
  final Set<String> stores;
  final OfferType? type;
  final PickupFilter pickup;
  final DateTime? customDate;
  final OfferSort sort;
  final bool availableFirst;
  final double radiusKm;
  int get activeCount =>
      categories.length +
      diets.length +
      features.length +
      stores.length +
      (type == null ? 0 : 1) +
      (pickup == PickupFilter.any ? 0 : 1);

  OfferFilters copyWith({
    String? query,
    Set<FoodCategory>? categories,
    Set<Diet>? diets,
    Set<OfferFeature>? features,
    Set<String>? stores,
    OfferType? type,
    bool clearType = false,
    PickupFilter? pickup,
    DateTime? customDate,
    OfferSort? sort,
    bool? availableFirst,
    double? radiusKm,
  }) => OfferFilters(
    query: query ?? this.query,
    categories: categories ?? this.categories,
    diets: diets ?? this.diets,
    features: features ?? this.features,
    stores: stores ?? this.stores,
    type: clearType ? null : type ?? this.type,
    pickup: pickup ?? this.pickup,
    customDate: customDate ?? this.customDate,
    sort: sort ?? this.sort,
    availableFirst: availableFirst ?? this.availableFirst,
    radiusKm: radiusKm ?? this.radiusKm,
  );

  List<FoodOffer> apply(
    Iterable<FoodOffer> source,
    GeoPoint origin,
    DateTime now, {
    int Function(FoodOffer)? remaining,
  }) {
    bool sameDay(DateTime a, DateTime b) =>
        a.year == b.year && a.month == b.month && a.day == b.day;
    final words = normalizeSearch(
      query,
    ).split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    final result = source.where((offer) {
      final search = normalizeSearch(
        '${offer.title} ${offer.store} ${offer.category.label} ${offer.address}',
      );
      if (!words.every(search.contains)) return false;
      if (categories.isNotEmpty && !categories.contains(offer.category)) {
        return false;
      }
      if (!diets.every(offer.diets.contains)) return false;
      if (!features.every(offer.features.contains)) return false;
      if (stores.isNotEmpty && !stores.contains(offer.store)) return false;
      if (type != null && offer.type != type) return false;
      if (origin.distanceTo(offer.point) > radiusKm) return false;
      return switch (pickup) {
        PickupFilter.any => true,
        PickupFilter.now =>
          !offer.pickupStart.isAfter(now) && offer.pickupEnd.isAfter(now),
        PickupFilter.today => sameDay(offer.pickupStart, now),
        PickupFilter.tomorrow => sameDay(
          offer.pickupStart,
          now.add(const Duration(days: 1)),
        ),
        PickupFilter.custom =>
          customDate != null && sameDay(offer.pickupStart, customDate!),
      };
    }).toList();
    bool available(FoodOffer o) =>
        (remaining?.call(o) ?? o.stock) > 0 && o.pickupEnd.isAfter(now);
    result.sort((a, b) {
      if (availableFirst && available(a) != available(b)) {
        return available(a) ? -1 : 1;
      }
      final comparison = switch (sort) {
        OfferSort.distance =>
          origin.distanceTo(a.point).compareTo(origin.distanceTo(b.point)),
        OfferSort.rating => b.rating.compareTo(a.rating),
        OfferSort.price => a.price.compareTo(b.price),
      };
      return comparison == 0 ? a.id.compareTo(b.id) : comparison;
    });
    return result;
  }
}

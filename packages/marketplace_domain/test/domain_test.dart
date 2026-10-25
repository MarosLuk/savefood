import 'package:marketplace_domain/marketplace_domain.dart';
import 'package:test/test.dart';

final now = DateTime(2026, 10, 23, 14);
FoodOffer fixture({
  String id = 'one',
  int price = 390,
  int stock = 4,
  DateTime? start,
  DateTime? end,
  Set<Diet> diets = const {},
  Set<OfferFeature> features = const {},
  GeoPoint point = const GeoPoint(48.149, 17.108),
  OfferType type = OfferType.surprise,
}) => FoodOffer(
  id: id,
  store: 'Pekáreň Šťastná',
  title: 'Čerstvé pečivo',
  category: FoodCategory.bakery,
  image: 'bread',
  price: price,
  originalPrice: 1200,
  stock: stock,
  rating: id == 'two' ? 4.9 : 4.7,
  reviews: 25,
  address: 'Bratislava',
  point: point,
  pickupStart: start ?? DateTime(2026, 10, 23, 13),
  pickupEnd: end ?? DateTime(2026, 10, 23, 18),
  description: 'Test',
  diets: diets,
  features: features,
  type: type,
);
const origin = GeoPoint(48.1486, 17.1077);

void main() {
  group('Money and quotes', () {
    test('Slovak EUR formatting', () {
      expect(euro(390), '3,90 €');
      expect(euro(0), '0,00 €');
    });
    test('fee uses integer cent rounding', () {
      final q = CheckoutQuote.calculate(subtotal: 399);
      expect(q.serviceFee, 8);
      expect(q.total, 407);
    });
    test('empty cart has no fee', () {
      expect(CheckoutQuote.calculate(subtotal: 0).total, 0);
    });
    test('coupon is normalized and discount is deterministic', () {
      final q = CheckoutQuote.calculate(subtotal: 399, coupon: ' vitaj10 ');
      expect(q.discount, 40);
      expect(q.total, 367);
    });
    test('unknown coupon rejected', () {
      expect(
        () => CheckoutQuote.calculate(subtotal: 100, coupon: 'BAD'),
        throwsArgumentError,
      );
    });
    test('credit never makes the total negative', () {
      final q = CheckoutQuote.calculate(
        subtotal: 399,
        credit: 5000,
        useCredit: true,
      );
      expect(q.creditUsed, 407);
      expect(q.total, 0);
    });
    test('credit is opt in', () {
      expect(
        CheckoutQuote.calculate(subtotal: 399, credit: 5000).creditUsed,
        0,
      );
    });
    test('cashback excludes fee and coupon discount', () {
      final q = CheckoutQuote.calculate(
        subtotal: 1000,
        coupon: 'VITAJ10',
        clubMember: true,
      );
      expect(q.cashback, 90);
      expect(q.serviceFee, 20);
    });
    test('cashback applies to rescued value even when credit pays', () {
      expect(
        CheckoutQuote.calculate(
          subtotal: 1000,
          credit: 5000,
          useCredit: true,
          clubMember: true,
        ).cashback,
        100,
      );
    });
    test('negative inputs are invalid', () {
      expect(() => CheckoutQuote.calculate(subtotal: -1), throwsArgumentError);
      expect(
        () => CheckoutQuote.calculate(subtotal: 100, credit: -1),
        throwsArgumentError,
      );
    });
  });
  group('Catalog filters', () {
    test('search is case and diacritic insensitive', () {
      expect(
        const OfferFilters(
          query: 'PEKAREN stastna',
        ).apply([fixture()], origin, now),
        hasLength(1),
      );
    });
    test('every query word must match', () {
      expect(
        const OfferFilters(
          query: 'pekaren sushi',
        ).apply([fixture()], origin, now),
        isEmpty,
      );
    });
    test('all selected diets must match', () {
      expect(
        const OfferFilters(diets: {Diet.vegan, Diet.glutenFree}).apply(
          [
            fixture(diets: {Diet.vegan}),
          ],
          origin,
          now,
        ),
        isEmpty,
      );
    });
    test('category is constrained', () {
      expect(
        const OfferFilters(
          categories: {FoodCategory.meals},
        ).apply([fixture()], origin, now),
        isEmpty,
      );
    });
    test('distance excludes another city', () {
      expect(
        const OfferFilters().apply(
          [fixture(point: const GeoPoint(48.72, 21.26))],
          origin,
          now,
        ),
        isEmpty,
      );
    });
    test('pickup now respects both interval boundaries', () {
      final f = const OfferFilters(pickup: PickupFilter.now);
      expect(f.apply([fixture()], origin, now), hasLength(1));
      expect(
        f.apply(
          [fixture(start: now.add(const Duration(minutes: 1)))],
          origin,
          now,
        ),
        isEmpty,
      );
      expect(f.apply([fixture(end: now)], origin, now), isEmpty);
    });
    test('tomorrow is a calendar date', () {
      final f = const OfferFilters(pickup: PickupFilter.tomorrow);
      expect(
        f.apply(
          [
            fixture(
              start: DateTime(2026, 10, 24, 16),
              end: DateTime(2026, 10, 24, 18),
            ),
          ],
          origin,
          now,
        ),
        hasLength(1),
      );
    });
    test('custom date requires a selected day', () {
      expect(
        const OfferFilters(
          pickup: PickupFilter.custom,
        ).apply([fixture()], origin, now),
        isEmpty,
      );
    });
    test('available first respects reserved stock callback', () {
      final list = const OfferFilters().apply(
        [fixture(id: 'one'), fixture(id: 'two')],
        origin,
        now,
        remaining: (o) => o.id == 'one' ? 0 : 1,
      );
      expect(list.first.id, 'two');
    });
    test('expired offers sort after available offers', () {
      final list = const OfferFilters().apply(
        [fixture(id: 'one', end: now), fixture(id: 'two')],
        origin,
        now,
      );
      expect(list.first.id, 'two');
    });
    test('price ordering', () {
      final list = const OfferFilters(sort: OfferSort.price).apply(
        [fixture(price: 700), fixture(id: 'two', price: 200)],
        origin,
        now,
      );
      expect(list.first.price, 200);
    });
    test('rating ordering', () {
      final list = const OfferFilters(
        sort: OfferSort.rating,
      ).apply([fixture(), fixture(id: 'two')], origin, now);
      expect(list.first.id, 'two');
    });
    test('type selection can be cleared', () {
      const f = OfferFilters(type: OfferType.club);
      expect(f.copyWith(clearType: true).type, isNull);
    });
    test('feature and store filters compose', () {
      final f = const OfferFilters(
        features: {OfferFeature.fresh},
        stores: {'Pekáreň Šťastná'},
      );
      expect(
        f.apply(
          [
            fixture(features: {OfferFeature.fresh}),
          ],
          origin,
          now,
        ),
        hasLength(1),
      );
    });
  });
  test('invoice validates email, postal code and company ID', () {
    const valid = InvoiceDetails(
      name: 'Jana Nová',
      email: 'jana@example.test',
      street: 'Ulica 1',
      city: 'Bratislava',
      postcode: '811 01',
    );
    expect(valid.isValid, isTrue);
    expect(
      const InvoiceDetails(
        name: 'Jana',
        email: 'bad',
        street: 'Ulica',
        city: 'BA',
        postcode: '81101',
      ).isValid,
      isFalse,
    );
    expect(
      const InvoiceDetails(
        name: 'Jana',
        email: 'a@b.sk',
        street: 'Ulica',
        city: 'BA',
        postcode: '81101',
        company: 'Firma',
        companyId: '123',
      ).isValid,
      isFalse,
    );
  });
  test('Haversine distance is symmetric and zero for identical points', () {
    expect(origin.distanceTo(origin), 0);
    const b = GeoPoint(48.72, 21.26);
    expect(origin.distanceTo(b), closeTo(b.distanceTo(origin), .0001));
  });
}

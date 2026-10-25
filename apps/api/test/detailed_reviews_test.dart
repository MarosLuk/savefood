import 'dart:typed_data';
import 'package:image/image.dart' as image;
import 'package:marketplace_server/marketplace_server.dart';
import 'package:marketplace_server/src/auth.dart';
import 'package:test/test.dart';

void main() {
  late MarketplaceServer app;
  late String offer;
  setUp(() {
    app = MarketplaceServer(
      const ServerConfig(databasePath: ':memory:', demoShowcase: true),
      clock: () => DateTime.utc(2026, 10, 25, 12),
    );
    final orders = app.profile('showcase-customer')['orders'] as List;
    offer =
        ((orders.firstWhere((o) => o['status'] == 'collected') as Map)['items']
                    as List)
                .first['offerId']
            as String;
  });
  tearDown(() => app.close());
  test(
    'verified buyer can publish four dimensions and photos; aggregates cover all reviews',
    () async {
      final p = await app.media.add(
        'showcase-customer',
        Uint8List.fromList(image.encodePng(image.Image(width: 10, height: 8))),
        kind: 'review',
      );
      expect(
        () => app.media.photo(p['id'] as String),
        throwsA(isA<ApiFailure>()),
      );
      app.reviews.save('showcase-customer', offer, {
        'rating': 4,
        'comment': 'Dobrá porcia',
        'dimensions': {'quality': 5, 'value': 4, 'quantity': 3, 'pickup': 5},
        'attachments': [p['id']],
      });
      final result = app.reviews.list(offer, user: 'showcase-customer');
      expect((result['ownReview'] as Map)['quality'], 5);
      expect((result['ownReview'] as Map)['attachments'], hasLength(1));
      expect((result['summary'] as Map)['quantity'], 3.0);
      expect(app.media.photo(p['id'] as String), isNotEmpty);
      app.database.db.execute(
        "UPDATE reviews SET moderation='hidden' WHERE user_id=? AND offer_id=?",
        ['showcase-customer', offer],
      );
      expect(
        () => app.media.photo(p['id'] as String),
        throwsA(isA<ApiFailure>()),
      );
      app.reviews.save('showcase-customer', offer, {
        'rating': 5,
        'comment': 'Upravená recenzia',
        'attachments': [p['id']],
      });
      expect(
        (app.reviews.list(offer, user: 'showcase-customer')['ownReview']
            as Map)['moderation'],
        'hidden',
      );
      app.reviews.remove('showcase-customer', offer);
      expect(
        () => app.media.photo(p['id'] as String, user: 'showcase-customer'),
        throwsA(isA<ApiFailure>()),
      );
    },
  );
  test(
    'uncollected orders and foreign photos cannot be used to create reviews',
    () async {
      expect(
        () => app.reviews.save('showcase-bakery', offer, {
          'rating': 5,
          'comment': 'Fake review',
        }),
        throwsA(isA<ApiFailure>()),
      );
      final p = await app.media.add(
        'showcase-bakery',
        Uint8List.fromList(image.encodePng(image.Image(width: 2, height: 2))),
        kind: 'review',
      );
      expect(
        () => app.reviews.save('showcase-customer', offer, {
          'rating': 5,
          'comment': 'Foreign photo',
          'attachments': [p['id']],
        }),
        throwsA(isA<ApiFailure>()),
      );
    },
  );
}

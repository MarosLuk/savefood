import 'package:marketplace_domain/marketplace_domain.dart';
import 'auth.dart';
import 'database.dart';
import 'media.dart';

class ReviewService {
  ReviewService(this.database, this.media, {DateTime Function()? clock})
    : clock = clock ?? DateTime.now {
    final columns = database.db
        .select('PRAGMA table_info(reviews)')
        .map((r) => r['name'])
        .toSet();
    for (final c in {
      'quality': 'INTEGER',
      'value': 'INTEGER',
      'quantity': 'INTEGER',
      'pickup': 'INTEGER',
      'moderation': "TEXT NOT NULL DEFAULT 'visible'",
      'version': 'INTEGER NOT NULL DEFAULT 1',
    }.entries) {
      if (!columns.contains(c.key)) {
        database.db.execute(
          'ALTER TABLE reviews ADD COLUMN ${c.key} ${c.value}',
        );
      }
    }
  }
  final MarketplaceDatabase database;
  final MediaService media;
  final DateTime Function() clock;
  static const dimensions = ['quality', 'value', 'quantity', 'pickup'];
  bool eligible(String user, String offer) => database.db
      .select(
        "SELECT payload FROM orders WHERE user_id=? AND status IN ('collected','reserved','cancelled')",
        [user],
      )
      .any((r) {
        final order = RescueOrder.fromJson(
          database.decode(r['payload'] as String),
        );
        return order.items.any(
          (i) =>
              i.offerId == offer &&
              (i.collected ||
                  order.status == OrderStatus.collected && !i.refunded),
        );
      });
  void requireEligible(String user, String offer) {
    if (!eligible(user, offer)) {
      throw const ApiFailure(403, 'Hodnotiť možno až po vyzdvihnutí balíčka.');
    }
  }

  Map<String, dynamic> list(String offer, {String? user, String? before}) {
    final cursor = before == null ? null : int.tryParse(before);
    if (before != null && (cursor == null || cursor < 1)) {
      throw const ApiFailure(400, 'Neplatná stránka recenzií.');
    }
    final rows = database.db.select(
      "SELECT *,rowid cursor FROM reviews WHERE offer_id=? AND moderation='visible' AND (? IS NULL OR rowid<?) ORDER BY rowid DESC LIMIT 51",
      [offer, cursor, cursor],
    );
    Map<String, dynamic> record(Map r) => {
      'id': hashToken('${r['user_id']}:$offer'),
      for (final k in [
        'rating',
        'comment',
        'created_at',
        'quality',
        'value',
        'quantity',
        'pickup',
        'version',
      ])
        k: r[k],
      'own': r['user_id'] == user,
      'attachments': database.db
          .select(
            'SELECT a.id,a.width,a.height,a.created_at FROM review_media m JOIN media_assets a ON a.id=m.media_id WHERE m.user_id=? AND m.offer_id=? AND a.deleted_at IS NULL',
            [r['user_id'], offer],
          )
          .map(media.metadata)
          .toList(),
    };
    final summary = database.db.select(
      "SELECT COUNT(*) count,COALESCE(AVG(rating),0) average,AVG(quality) quality,AVG(value) value,AVG(quantity) quantity,AVG(pickup) pickup FROM reviews WHERE offer_id=? AND moderation='visible'",
      [offer],
    ).first;
    final own = user == null
        ? []
        : database.db.select(
            'SELECT * FROM reviews WHERE offer_id=? AND user_id=?',
            [offer, user],
          );
    return {
      'reviews': rows.take(50).map(record).toList(),
      'nextCursor': rows.length > 50 ? rows[49]['cursor'].toString() : null,
      'summary': {
        ...summary,
        'stars': {
          for (final stars in [1, 2, 3, 4, 5])
            stars.toString(): database.db.select(
              "SELECT COUNT(*) n FROM reviews WHERE offer_id=? AND moderation='visible' AND rating=?",
              [offer, stars],
            ).first['n'],
        },
      },
      'ownReview': own.isEmpty
          ? null
          : {...record(own.first), 'moderation': own.first['moderation']},
      'eligible': user != null && eligible(user, offer),
    };
  }

  void save(
    String user,
    String offer,
    Map<String, dynamic> body,
  ) => database.transaction(() {
    requireEligible(user, offer);
    final rating = body['rating'];
    if (rating is! int || rating < 1 || rating > 5) {
      throw const ApiFailure(400, 'Vyber hodnotenie od 1 do 5.');
    }
    final comment = stringField(body, 'comment', max: 1000);
    final detail = body['dimensions'] as Map? ?? {};
    for (final key in dimensions) {
      final value = detail[key];
      if (value != null && (value is! int || value < 1 || value > 5)) {
        throw const ApiFailure(400, 'Každé podhodnotenie musí byť od 1 do 5.');
      }
    }
    final previous = database.db.select(
      'SELECT * FROM reviews WHERE user_id=? AND offer_id=?',
      [user, offer],
    );
    if (previous.isNotEmpty &&
        body['version'] != null &&
        body['version'] != previous.first['version']) {
      throw const ApiFailure(409, 'Recenzia sa zmenila. Obnov ju.');
    }
    final attachments = (body['attachments'] as List? ?? []).cast<String>();
    if (attachments.length > 3 ||
        attachments.toSet().length != attachments.length) {
      throw const ApiFailure(400, 'Prilož najviac tri rôzne fotografie.');
    }
    for (final id in attachments) {
      if (database.db.select(
        "SELECT id FROM media_assets WHERE id=? AND user_id=? AND kind='review' AND deleted_at IS NULL",
        [id, user],
      ).isEmpty) {
        throw const ApiFailure(403, 'Fotografia nepatrí tvojmu účtu.');
      }
      if (database.db.select(
        'SELECT media_id FROM review_media WHERE media_id=? AND (user_id!=? OR offer_id!=?)',
        [id, user, offer],
      ).isNotEmpty) {
        throw const ApiFailure(409, 'Fotografia patrí inej recenzii.');
      }
    }
    database.db.execute(
      '''INSERT INTO reviews(user_id,offer_id,rating,comment,created_at,quality,value,quantity,pickup)
      VALUES(?,?,?,?,?,?,?,?,?) ON CONFLICT(user_id,offer_id) DO UPDATE SET rating=excluded.rating,comment=excluded.comment,
      quality=excluded.quality,value=excluded.value,quantity=excluded.quantity,pickup=excluded.pickup,version=reviews.version+1''',
      [
        user,
        offer,
        rating,
        comment,
        clock().toUtc().toIso8601String(),
        for (final key in dimensions) detail[key],
      ],
    );
    // An edit cannot bypass moderation of a hidden review.
    database.db.execute(
      'DELETE FROM review_media WHERE user_id=? AND offer_id=?',
      [user, offer],
    );
    for (final id in attachments) {
      database.db.execute('INSERT INTO review_media VALUES(?,?,?)', [
        user,
        offer,
        id,
      ]);
    }
  });
  void remove(String user, String offer) => database.transaction(() {
    final photos = database.db.select(
      'SELECT media_id FROM review_media WHERE user_id=? AND offer_id=?',
      [user, offer],
    );
    database.db.execute(
      'DELETE FROM review_media WHERE user_id=? AND offer_id=?',
      [user, offer],
    );
    database.db.execute('DELETE FROM reviews WHERE user_id=? AND offer_id=?', [
      user,
      offer,
    ]);
    for (final p in photos) {
      media.remove(user, p['media_id'] as String);
    }
  });
}

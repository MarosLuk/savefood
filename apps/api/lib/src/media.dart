import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';
import 'auth.dart';
import 'config.dart';
import 'database.dart';
import 'image_codec.dart';

class MediaService {
  MediaService(this.database, this.config, {DateTime Function()? clock})
    : clock = clock ?? DateTime.now {
    database.db.execute(
      '''CREATE TABLE IF NOT EXISTS media_assets(id TEXT PRIMARY KEY,user_id TEXT NOT NULL REFERENCES users(id),
      org_id TEXT REFERENCES merchant_organizations(id),kind TEXT NOT NULL,hash TEXT NOT NULL,width INTEGER NOT NULL,height INTEGER NOT NULL,
      content BLOB NOT NULL,created_at TEXT NOT NULL,deleted_at TEXT);
      CREATE INDEX IF NOT EXISTS media_org ON media_assets(org_id,created_at);
      CREATE TABLE IF NOT EXISTS review_media(user_id TEXT NOT NULL,offer_id TEXT NOT NULL,media_id TEXT NOT NULL UNIQUE REFERENCES media_assets(id),
      PRIMARY KEY(user_id,offer_id,media_id));''',
    );
  }
  final MarketplaceDatabase database;
  final ServerConfig config;
  final DateTime Function() clock;
  int processing = 0;
  String url(String id) => '${config.publicUrl}/v1/media/$id.jpg';
  void requireOrganization(String user, String org, {bool manage = false}) {
    if (config.production &&
        database.db.select(
          'SELECT id FROM users WHERE id=? AND email_verified=1 AND disabled=0 AND deleted_at IS NULL',
          [user],
        ).isEmpty) {
      throw const ApiFailure(403, 'Najprv over svoj e-mail.');
    }
    if (database.db.select(
      "SELECT org_id FROM platform_organizations WHERE org_id=? AND status='suspended'",
      [org],
    ).isNotEmpty) {
      throw const ApiFailure(403, 'Firma je pozastavená.');
    }
    final rows = database.db.select(
      'SELECT role FROM merchant_members WHERE user_id=? AND org_id=?',
      [user, org],
    );
    if (rows.isEmpty || manage && rows.first['role'] == 'staff') {
      throw const ApiFailure(
        403,
        'Fotografie môže spravovať vlastník alebo manažér firmy.',
      );
    }
  }

  Map<String, dynamic> metadata(Map r) => {
    'id': r['id'],
    'url': url(r['id'] as String),
    'width': r['width'],
    'height': r['height'],
    'createdAt': r['created_at'],
  };
  Future<Map<String, dynamic>> add(
    String user,
    Uint8List bytes, {
    String? org,
    String kind = 'product',
  }) async {
    if (kind == 'product') {
      if (org == null) throw const ApiFailure(400, 'Vyber firmu.');
      requireOrganization(user, org, manage: true);
    }
    if (!{'product', 'review'}.contains(kind) ||
        bytes.isEmpty ||
        bytes.length > 5 * 1024 * 1024) {
      throw const ApiFailure(400, 'Použi fotografiu JPEG/PNG do 5 MB.');
    }
    if (processing >= 2) {
      throw const ApiFailure(
        429,
        'Práve spracúvame fotografie. Skús to o chvíľu.',
      );
    }
    processing++;
    late (Uint8List, int, int) result;
    try {
      result = await sanitizeMarketplacePhoto(bytes);
    } catch (_) {
      throw const ApiFailure(
        400,
        'Fotografia musí byť statické JPEG/PNG do 20 megapixelov.',
      );
    } finally {
      processing--;
    }
    if (org != null) requireOrganization(user, org, manage: true);
    return database.transaction(() {
      final quota = database.db.select(
        'SELECT COUNT(*) n,COALESCE(SUM(length(content)),0) size FROM media_assets WHERE deleted_at IS NULL AND (org_id=? OR org_id IS NULL AND user_id=?)',
        [org, user],
      ).first;
      if ((quota['n'] as int) >= 500 ||
          (quota['size'] as int) + result.$1.length > 250 * 1024 * 1024) {
        throw const ApiFailure(
          409,
          'Knižnica dosiahla limit 500 fotografií alebo 250 MB. Odstráň nepoužívané fotografie.',
        );
      }
      final hash = sha256.convert(result.$1).toString();
      final old = database.db.select(
        'SELECT id,width,height,created_at FROM media_assets WHERE user_id=? AND org_id IS ? AND kind=? AND hash=? AND deleted_at IS NULL',
        [user, org, kind, hash],
      );
      if (old.isNotEmpty) return metadata(old.first);
      final id = const Uuid().v4(), now = clock().toUtc().toIso8601String();
      database.db.execute(
        'INSERT INTO media_assets(id,user_id,org_id,kind,hash,width,height,content,created_at) VALUES(?,?,?,?,?,?,?,?,?)',
        [id, user, org, kind, hash, result.$2, result.$3, result.$1, now],
      );
      return metadata({
        'id': id,
        'width': result.$2,
        'height': result.$3,
        'created_at': now,
      });
    });
  }

  Map<String, dynamic> list(String user, String org, {String? before}) {
    requireOrganization(user, org);
    final cursor = before == null ? null : int.tryParse(before);
    if (before != null && cursor == null) {
      throw const ApiFailure(400, 'Neplatná stránka.');
    }
    final rows = database.db.select(
      "SELECT rowid n,id,width,height,created_at FROM media_assets WHERE org_id=? AND deleted_at IS NULL AND kind='product' AND (? IS NULL OR rowid<?) ORDER BY rowid DESC LIMIT 51",
      [org, cursor, cursor],
    );
    return {
      'photos': rows.take(50).map(metadata).toList(),
      'nextCursor': rows.length > 50 ? rows[49]['n'].toString() : null,
    };
  }

  Uint8List photo(String id, {String? user}) {
    final rows = database.db.select(
      'SELECT * FROM media_assets WHERE id=? AND deleted_at IS NULL',
      [id],
    );
    if (rows.isEmpty) throw const ApiFailure(404, 'Fotografia neexistuje.');
    final r = rows.first;
    if (r['kind'] == 'review' &&
        r['user_id'] != user &&
        database.db.select(
          "SELECT m.media_id FROM review_media m JOIN reviews r ON r.user_id=m.user_id AND r.offer_id=m.offer_id WHERE m.media_id=? AND r.moderation='visible'",
          [id],
        ).isEmpty) {
      throw const ApiFailure(404, 'Fotografia ešte nie je zverejnená.');
    }
    return r['content'] as Uint8List;
  }

  void remove(String user, String id) {
    final rows = database.db.select(
      'SELECT * FROM media_assets WHERE id=? AND deleted_at IS NULL',
      [id],
    );
    if (rows.isEmpty) throw const ApiFailure(404, 'Fotografia neexistuje.');
    final r = rows.first;
    if (r['org_id'] != null) {
      requireOrganization(user, r['org_id'] as String, manage: true);
    } else if (r['user_id'] != user) {
      throw const ApiFailure(403, 'Fotografia patrí inému účtu.');
    }
    final image = url(id);
    if (database.db.select(
      "SELECT id FROM stock_products WHERE json_extract(payload,'\$.image')=? UNION ALL SELECT id FROM offers WHERE json_extract(payload,'\$.image')=? UNION ALL SELECT id FROM orders WHERE EXISTS(SELECT 1 FROM json_each(orders.payload,'\$.items') i WHERE json_extract(i.value,'\$.image')=?) LIMIT 1",
      [image, image, image],
    ).isNotEmpty) {
      throw const ApiFailure(
        409,
        'Fotografia sa používa pri produkte alebo ponuke. Najprv ju tam nahraď.',
      );
    }
    database.transaction(() {
      database.db.execute('DELETE FROM review_media WHERE media_id=?', [id]);
      database.db.execute(
        "UPDATE media_assets SET content=X'',deleted_at=? WHERE id=?",
        [clock().toUtc().toIso8601String(), id],
      );
    });
  }
}

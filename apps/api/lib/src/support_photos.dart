part of 'support.dart';

extension SupportPhotos on SupportService {
  void initializePhotos() => database.db.execute('''
  CREATE TABLE IF NOT EXISTS support_photos(id TEXT PRIMARY KEY,ticket_id TEXT NOT NULL REFERENCES support_tickets(id),user_id TEXT NOT NULL REFERENCES users(id),
   message_id TEXT REFERENCES support_messages(id),hash TEXT NOT NULL,width INTEGER NOT NULL,height INTEGER NOT NULL,content BLOB NOT NULL,created_at TEXT NOT NULL);
  CREATE INDEX IF NOT EXISTS support_photos_ticket ON support_photos(ticket_id,message_id);
 ''');
  Map<String, dynamic> _photoInfo(Map<String, dynamic> p) => {
    'id': p['id'],
    'width': p['width'],
    'height': p['height'],
    'size': p['size'] ?? (p['content'] as Uint8List).length,
    'mimeType': 'image/jpeg',
  };
  List<Map<String, dynamic>> photoMetadata(String message) => rows(
    'SELECT id,width,height,length(content) size FROM support_photos WHERE message_id=? ORDER BY rowid',
    [message],
  ).map(_photoInfo).toList();
  Future<Map<String, dynamic>> addPhoto(
    String user,
    String id,
    Uint8List bytes,
  ) async {
    _owned(user, id);
    if (bytes.isEmpty || bytes.length > 5 * 1024 * 1024) {
      throw const ApiFailure(413, 'Fotografia môže mať najviac 5 MB.');
    }
    (Uint8List, int, int) result;
    if (photoDecodes >= 2) {
      throw const ApiFailure(
        429,
        'Práve spracúvame viac fotografií. Skús to o chvíľu.',
      );
    }
    photoDecodes++;
    try {
      result = await sanitizeMarketplacePhoto(bytes);
    } catch (_) {
      throw const ApiFailure(
        400,
        'Vyber platnú statickú fotografiu JPEG alebo PNG do 20 megapixelov.',
      );
    } finally {
      photoDecodes--;
    }
    return database.transaction(() {
      _owned(user, id);
      final hash = sha256.convert(result.$1).toString();
      final duplicate = rows(
        'SELECT * FROM support_photos WHERE ticket_id=? AND user_id=? AND hash=? AND message_id IS NULL',
        [id, user, hash],
      ).firstOrNull;
      if (duplicate != null) return _photoInfo(duplicate);
      if ((rows(
                'SELECT COUNT(*) n FROM support_photos WHERE ticket_id=? AND user_id=? AND message_id IS NULL',
                [id, user],
              ).first['n']
              as int) >=
          3) {
        throw const ApiFailure(
          409,
          'Najprv odošli alebo odstráň tri rozpracované fotografie.',
        );
      }
      final quota = rows(
        'SELECT COUNT(*) n,COALESCE(SUM(length(content)),0) bytes FROM support_photos WHERE ticket_id=?',
        [id],
      ).first;
      if ((quota['n'] as int) >= 50 ||
          (quota['bytes'] as int) + result.$1.length > 25 * 1024 * 1024) {
        throw const ApiFailure(413, 'Požiadavka dosiahla limit fotografií.');
      }
      final photo = _id();
      database.db.execute(
        'INSERT INTO support_photos VALUES(?,?,?,NULL,?,?,?,?,?)',
        [photo, id, user, hash, result.$2, result.$3, result.$1, now],
      );
      return _photoInfo(
        rows('SELECT * FROM support_photos WHERE id=?', [photo]).first,
      );
    });
  }

  void validatePhotos(String user, String ticket, List<String> ids) {
    if (ids.length > 3 || ids.toSet().length != ids.length) {
      throw const ApiFailure(
        400,
        'K jednej správe prilož najviac tri rôzne fotografie.',
      );
    }
    for (final id in ids) {
      if (rows(
        'SELECT id FROM support_photos WHERE id=? AND ticket_id=? AND user_id=? AND message_id IS NULL',
        [id, ticket, user],
      ).isEmpty) {
        throw const ApiFailure(
          404,
          'Fotografia už bola odoslaná alebo nepatrí tejto správe.',
        );
      }
    }
  }

  void linkPhotos(String message, List<String> ids) {
    for (final id in ids) {
      database.db.execute('UPDATE support_photos SET message_id=? WHERE id=?', [
        message,
        id,
      ]);
    }
  }

  Uint8List photo(String user, String id) {
    final p = rows(
      'SELECT p.*,m.internal FROM support_photos p LEFT JOIN support_messages m ON m.id=p.message_id WHERE p.id=?',
      [id],
    ).firstOrNull;
    if (p == null) throw const ApiFailure(404, 'Fotografia sa nenašla.');
    _owned(user, p['ticket_id'] as String);
    if (p['message_id'] == null && p['user_id'] != user ||
        p['internal'] == 1 && !isAgent(user)) {
      throw const ApiFailure(404, 'Fotografia sa nenašla.');
    }
    return p['content'] as Uint8List;
  }

  void cleanPhotos() => database.db.execute(
    'DELETE FROM support_photos WHERE message_id IS NULL AND created_at<?',
    [clock().toUtc().subtract(const Duration(hours: 24)).toIso8601String()],
  );
  void discardPhoto(String user, String id) {
    final p = rows(
      'SELECT id,ticket_id FROM support_photos WHERE id=? AND user_id=? AND message_id IS NULL',
      [id, user],
    ).firstOrNull;
    if (p == null) {
      throw const ApiFailure(404, 'Rozpracovaná fotografia sa nenašla.');
    }
    _owned(user, p['ticket_id'] as String);
    database.db.execute('DELETE FROM support_photos WHERE id=?', [id]);
  }
}

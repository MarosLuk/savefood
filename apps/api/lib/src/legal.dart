import 'dart:convert';
import 'package:marketplace_domain/marketplace_domain.dart';
import 'auth.dart';
import 'database.dart';

/// Published policy versions are immutable. Drafts never replace accepted text.
class LegalService {
  LegalService(
    this.database, {
    required this.production,
    required this.demo,
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now {
    database.db.execute(
      '''CREATE TABLE IF NOT EXISTS legal_documents(version INTEGER PRIMARY KEY,payload TEXT NOT NULL,published_at TEXT NOT NULL);
      CREATE TABLE IF NOT EXISTS legal_state(id INTEGER PRIMARY KEY CHECK(id=1),draft TEXT NOT NULL,revision INTEGER NOT NULL DEFAULT 0);''',
    );
    final columns = database.db
        .select('PRAGMA table_info(legal_acceptances)')
        .map((r) => r['name']);
    if (!columns.contains('electronic_invoice')) {
      database.db.execute(
        'ALTER TABLE legal_acceptances ADD COLUMN electronic_invoice INTEGER NOT NULL DEFAULT 0',
      );
    }
    if (demo && current()['configured'] != true) {
      save({
        'revision': 0,
        'operator': 'DEMO · Fiktívny prevádzkovateľ',
        'registration': '00000000',
        'address': 'DEMO · Bratislava',
        'contact': 'privacy@demo.nevyhadzuj.test',
        'terms':
            'DEMO podmienky. Ide o nezáväzné ukážkové rezervácie. Skutočné platby sa nevykonávajú. Čas a obsah balíčka sú uvedené pri ponuke. Tieto údaje nie sú produkčné obchodné podmienky.',
        'privacy':
            'DEMO súkromie. Ukážkové účty obsahujú fiktívne údaje. Aplikácia synchronizuje profil, objednávky, zásoby a komunikáciu s podporou. Produkčné právne základy, spracovatelia a retenčné pravidlá musia byť schválené pred spustením.',
        'retention': {
          'orders': 3650,
          'support': 365,
          'accountAudit': 365,
          'mail': 30,
          'mediaDraftHours': 24,
        },
      }, publish: true);
    }
  }
  final MarketplaceDatabase database;
  final bool production, demo;
  final DateTime Function() clock;
  String get now => clock().toUtc().toIso8601String();
  Map<String, dynamic> current({int? version}) {
    final r = database.db.select(
      'SELECT * FROM legal_documents WHERE (? IS NULL OR version=?) ORDER BY version DESC LIMIT 1',
      [version, version],
    ).firstOrNull;
    return r == null
        ? {'configured': false, 'version': 0}
        : {
            ...database.decode(r['payload'] as String),
            'configured': true,
            'version': r['version'],
            'publishedAt': r['published_at'],
          };
  }

  Map<String, dynamic> draft() {
    final r = database.db
        .select('SELECT * FROM legal_state WHERE id=1')
        .firstOrNull;
    return {
      ...(r == null ? current() : database.decode(r['draft'] as String)),
      'revision': r?['revision'] ?? 0,
      'publishedVersion': current()['version'],
    };
  }

  Map<String, dynamic> save(
    Map<String, dynamic> body, {
    bool publish = false,
  }) => database.transaction(() {
    final previous = draft();
    if (previous['revision'] != body['revision']) {
      throw const ApiFailure(409, 'Text už zmenil iný správca. Obnov ho.');
    }
    final p = <String, dynamic>{};
    for (final key in [
      'operator',
      'registration',
      'address',
      'contact',
      'terms',
      'privacy',
    ]) {
      p[key] = stringField(
        body,
        key,
        max: key == 'terms' || key == 'privacy' ? 100000 : 1000,
      );
      if (publish &&
          (p[key] as String).trim().length <
              (key == 'terms' || key == 'privacy' ? 100 : 3)) {
        throw ApiFailure(400, 'Pred publikovaním doplň pole $key.');
      }
    }
    if (publish &&
        !RegExp(
          r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
        ).hasMatch(p['contact'] as String)) {
      throw const ApiFailure(400, 'Doplň platný kontakt prevádzkovateľa.');
    }
    final retention = Map<String, dynamic>.from(
      body['retention'] as Map? ?? {},
    );
    for (final key in [
      'orders',
      'support',
      'accountAudit',
      'mail',
      'mediaDraftHours',
    ]) {
      final n = retention[key];
      if (n is! int || n < 1 || n > (key == 'mediaDraftHours' ? 720 : 36500)) {
        throw const ApiFailure(400, 'Doplň schválené lehoty uchovávania.');
      }
    }
    p['retention'] = retention;
    p['demo'] = demo;
    database.db.execute(
      'INSERT INTO legal_state(id,draft,revision) VALUES(1,?,1) ON CONFLICT(id) DO UPDATE SET draft=excluded.draft,revision=revision+1',
      [jsonEncode(p)],
    );
    if (publish) {
      final v = (current()['version'] as int) + 1;
      database.db.execute('INSERT INTO legal_documents VALUES(?,?,?)', [
        v,
        jsonEncode(p),
        now,
      ]);
    }
    return draft();
  });
  void validateAcceptance(Map<String, dynamic> body) {
    final c = current();
    if (c['configured'] != true) {
      if (production) {
        throw const ApiFailure(
          503,
          'Podmienky prevádzkovateľa zatiaľ nie sú zverejnené.',
        );
      }
      return;
    }
    if (body['version'] != c['version'] || body['accepted'] != true) {
      throw const ApiFailure(
        409,
        'Oboznám sa s aktuálnymi podmienkami a potvrď súhlas.',
      );
    }
  }

  void accept(String user, Map<String, dynamic> body) {
    validateAcceptance(body);
    final c = current();
    if (c['configured'] != true) return;
    database.db.execute(
      'INSERT INTO legal_acceptances(user_id,version,accepted_at,electronic_invoice) VALUES(?,?,?,?) ON CONFLICT(user_id,version) DO UPDATE SET electronic_invoice=MAX(electronic_invoice,excluded.electronic_invoice)',
      [user, c['version'], now, body['electronicInvoice'] == true ? 1 : 0],
    );
  }

  void requireAccepted(String user) {
    if (!production) return;
    final c = current();
    if (c['configured'] != true) {
      throw const ApiFailure(
        503,
        'Prevádzkovateľ ešte nedokončil obchodné podmienky.',
      );
    }
    if (database.db.select(
      'SELECT version FROM legal_acceptances WHERE user_id=? AND version=? AND electronic_invoice=1',
      [user, c['version']],
    ).isEmpty) {
      throw const ApiFailure(
        409,
        'Potvrď aktuálne podmienky a elektronické doklady.',
      );
    }
  }

  /// Scrub personal data only after the operator's configured retention expires.
  /// Stock/financial amounts and document snapshots retain their audit purpose.
  void clean() {
    final p = current();
    if (p['configured'] != true) return;
    final r = p['retention'] as Map;
    String before(int days) =>
        clock().toUtc().subtract(Duration(days: days)).toIso8601String();
    database.transaction(() {
      database.db.execute('DELETE FROM account_audit WHERE created_at<?', [
        before(r['accountAudit'] as int),
      ]);
      database.db.execute(
        "DELETE FROM mail_outbox WHERE status!='pending' AND created_at<?",
        [before(r['mail'] as int)],
      );
      database.db.execute(
        "UPDATE media_assets SET content=X'',deleted_at=? WHERE kind='review' AND deleted_at IS NULL AND created_at<? AND NOT EXISTS(SELECT 1 FROM review_media m WHERE m.media_id=media_assets.id)",
        [
          now,
          clock()
              .toUtc()
              .subtract(Duration(hours: r['mediaDraftHours'] as int))
              .toIso8601String(),
        ],
      );
      for (final row in database.db.select(
        "SELECT id,payload FROM orders WHERE status IN ('collected','cancelled') AND json_extract(payload,'\$.createdAt')<? AND NOT EXISTS(SELECT 1 FROM finance_holds h WHERE h.order_id=orders.id)",
        [before(r['orders'] as int)],
      )) {
        final order = RescueOrder.fromJson(
          database.decode(row['payload'] as String),
        );
        if (order.invoice.email.isEmpty) continue;
        final payload = order.toJson();
        payload['invoice'] = const InvoiceDetails().toJson();
        database.db.execute('UPDATE orders SET payload=? WHERE id=?', [
          jsonEncode(payload),
          row['id'],
        ]);
      }
      // Retain ticket metadata; erase conversation/attachments after closure.
      for (final t in database.db.select(
        "SELECT id FROM support_tickets WHERE status IN ('closed','resolved') AND updated_at<?",
        [before(r['support'] as int)],
      )) {
        database.db.execute(
          "UPDATE support_messages SET body='[Uplynula lehota uchovávania]' WHERE ticket_id=?",
          [t['id']],
        );
        database.db.execute('DELETE FROM support_photos WHERE ticket_id=?', [
          t['id'],
        ]);
      }
    });
  }
}

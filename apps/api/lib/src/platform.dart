import 'dart:convert';
import 'package:uuid/uuid.dart';
import 'package:marketplace_domain/marketplace_domain.dart';
import 'auth.dart';
import 'database.dart';
import 'support.dart';

class PlatformService {
  PlatformService(this.database, this.support, {DateTime Function()? clock})
    : clock = clock ?? DateTime.now {
    database.db.execute(
      '''CREATE TABLE IF NOT EXISTS platform_roles(user_id TEXT PRIMARY KEY REFERENCES users(id),role TEXT NOT NULL);
      CREATE TABLE IF NOT EXISTS platform_organizations(org_id TEXT PRIMARY KEY REFERENCES merchant_organizations(id),status TEXT NOT NULL,reason TEXT NOT NULL,updated_at TEXT NOT NULL);
      CREATE TABLE IF NOT EXISTS platform_stores(store_id TEXT PRIMARY KEY REFERENCES merchant_stores(id),paused INTEGER NOT NULL DEFAULT 0,reason TEXT NOT NULL);
      CREATE TABLE IF NOT EXISTS platform_offers(offer_id TEXT PRIMARY KEY REFERENCES offers(id),hidden INTEGER NOT NULL DEFAULT 0,reason TEXT NOT NULL);
      CREATE TABLE IF NOT EXISTS platform_versions(kind TEXT NOT NULL,entity TEXT NOT NULL,version INTEGER NOT NULL,PRIMARY KEY(kind,entity));
      CREATE TABLE IF NOT EXISTS platform_audit(id TEXT PRIMARY KEY,actor TEXT NOT NULL,event TEXT NOT NULL,kind TEXT NOT NULL,entity TEXT NOT NULL,detail TEXT NOT NULL,created_at TEXT NOT NULL);
      CREATE TABLE IF NOT EXISTS platform_settings(name TEXT PRIMARY KEY,payload TEXT NOT NULL,version INTEGER NOT NULL DEFAULT 1);
      CREATE TABLE IF NOT EXISTS legal_acceptances(user_id TEXT NOT NULL REFERENCES users(id),version INTEGER NOT NULL,accepted_at TEXT NOT NULL,PRIMARY KEY(user_id,version));''',
    );
  }
  final MarketplaceDatabase database;
  final SupportService support;
  final DateTime Function() clock;
  String? role(String user) =>
      database.db.select('SELECT role FROM platform_roles WHERE user_id=?', [
            user,
          ]).firstOrNull?['role']
          as String?;
  void require(String user, {bool write = false, bool content = false}) {
    final r = role(user);
    if (r == null || write && r == 'auditor' || !content && r == 'moderator') {
      throw const ApiFailure(
        403,
        'Táto časť je dostupná iba správcom platformy.',
      );
    }
  }

  void bootstrap(List<String> emails) {
    for (final email in emails) {
      final found = database.db.select(
        'SELECT id FROM users WHERE email=? AND email_verified=1 AND disabled=0',
        [email.trim().toLowerCase()],
      );
      if (found.isEmpty) {
        throw ArgumentError(
          'Bootstrap admin must be an existing verified account.',
        );
      }
      database.db.execute(
        "INSERT OR IGNORE INTO platform_roles VALUES(?,'admin')",
        [found.first['id']],
      );
    }
  }

  Map<String, dynamic> overview(String user) {
    require(user, content: true);
    int count(String table) =>
        database.db.select('SELECT COUNT(*) n FROM $table').first['n'] as int;
    return {
      'role': role(user),
      'users': count('users'),
      'organizations': count('merchant_organizations'),
      'stores': count('merchant_stores'),
      'offers': count('offers'),
      'reviews': count('reviews'),
      'openTickets': database.db
          .select(
            "SELECT COUNT(*) n FROM support_tickets WHERE status NOT IN ('closed','resolved')",
          )
          .first['n'],
      'mail': database.db
          .select(
            'SELECT status,COUNT(*) count FROM mail_outbox GROUP BY status',
          )
          .map((r) => Map<String, dynamic>.from(r))
          .toList(),
    };
  }

  Map<String, dynamic> list(
    String user,
    String kind,
    Map<String, String> query,
  ) {
    require(user, content: {'offers', 'reviews'}.contains(kind));
    final before = query['before'] == null
        ? null
        : int.tryParse(query['before']!);
    if (query['before'] != null && before == null) {
      throw const ApiFailure(400, 'Neplatná stránka.');
    }
    final search = query['query'] ?? '';
    if (search.length > 150) {
      throw const ApiFailure(400, 'Príliš dlhé vyhľadávanie.');
    }
    const sources = {
      'users':
          'SELECT u.rowid cursor,u.id,u.name,u.email,u.email_verified,u.disabled,u.deleted_at,p.role FROM users u LEFT JOIN platform_roles p ON p.user_id=u.id',
      'organizations':
          "SELECT o.rowid cursor,o.id,o.name,o.company_id,o.contact_email,COALESCE(p.status,'active') status FROM merchant_organizations o LEFT JOIN platform_organizations p ON p.org_id=o.id",
      'stores':
          'SELECT s.rowid cursor,s.id,s.org_id,s.payload,COALESCE(p.paused,0) paused FROM merchant_stores s LEFT JOIN platform_stores p ON p.store_id=s.id',
      'offers':
          'SELECT o.rowid cursor,o.id,o.payload,COALESCE(p.hidden,0) hidden FROM offers o LEFT JOIN platform_offers p ON p.offer_id=o.id',
      'reviews':
          'SELECT r.rowid cursor,CAST(r.rowid AS TEXT) id,r.offer_id,r.rating,r.comment,r.moderation,r.created_at FROM reviews r',
      'agents':
          'SELECT a.rowid cursor,a.user_id id,u.name,u.email,a.active FROM support_agents a JOIN users u ON u.id=a.user_id',
      'audit':
          'SELECT a.rowid cursor,a.id,a.actor,a.event,a.kind,a.entity,a.detail,a.created_at FROM platform_audit a',
      'mail':
          'SELECT m.rowid cursor,m.id,m.subject,m.status,m.attempts,m.error,m.created_at FROM mail_outbox m',
    };
    final source = sources[kind];
    if (source == null) {
      throw const ApiFailure(404, 'Neznáma časť administrácie.');
    }
    final field = switch (kind) {
      'users' || 'agents' => "name||' '||email",
      'organizations' => "name||' '||company_id",
      'stores' || 'offers' => 'payload',
      'reviews' => 'comment',
      'audit' => "event||' '||entity",
      _ => 'subject',
    };
    final rows = database.db.select(
      'SELECT * FROM ($source) WHERE (? IS NULL OR cursor<?) AND (?=\'\' OR instr(normalized($field),normalized(?))>0) ORDER BY cursor DESC LIMIT 51',
      [before, before, search, search],
    );
    return {
      'rows': rows.take(50).map((r) {
        final result = Map<String, dynamic>.from(r);
        if (result['payload'] is String) {
          result['payload'] = database.decode(result['payload'] as String);
        }
        result['version'] =
            database.db.select(
              'SELECT version FROM platform_versions WHERE kind=? AND entity=?',
              [kind, result['id']],
            ).firstOrNull?['version'] ??
            0;
        return result;
      }).toList(),
      'nextCursor': rows.length > 50 ? rows[49]['cursor'].toString() : null,
    };
  }

  Map<String, dynamic> change(
    String user,
    String kind,
    String id,
    Map<String, dynamic> body,
  ) => database.transaction(() {
    require(user, write: true, content: {'offers', 'reviews'}.contains(kind));
    final action = stringField(body, 'action'),
        reason = stringField(body, 'reason', max: 500);
    if (reason.length < 5) {
      throw const ApiFailure(400, 'Uveď konkrétny dôvod zmeny.');
    }
    final version =
        database.db.select(
          'SELECT version FROM platform_versions WHERE kind=? AND entity=?',
          [kind, id],
        ).firstOrNull?['version'] ??
        0;
    if (body['version'] != version) {
      throw const ApiFailure(409, 'Záznam zmenil iný správca. Obnov údaje.');
    }
    if (kind == 'users') {
      final target = database.db.select(
        'SELECT id,email_verified,deleted_at FROM users WHERE id=?',
        [id],
      );
      if (target.isEmpty || target.first['deleted_at'] != null) {
        throw const ApiFailure(404, 'Aktívny účet neexistuje.');
      }
      if ({'disable', 'enable'}.contains(action)) {
        if (action == 'disable' && id == user) {
          throw const ApiFailure(
            409,
            'Vlastný administrátorský účet nemožno zablokovať.',
          );
        }
        if (action == 'disable') _protectLastAdmin(id);
        database.db.execute('UPDATE users SET disabled=? WHERE id=?', [
          action == 'disable' ? 1 : 0,
          id,
        ]);
        if (action == 'disable') {
          database.db.execute('DELETE FROM sessions WHERE user_id=?', [id]);
          database.db.execute('DELETE FROM devices WHERE user_id=?', [id]);
        }
      } else if (action == 'role') {
        final next = stringField(body, 'role');
        if (!{'admin', 'moderator', 'auditor', 'none'}.contains(next)) {
          throw const ApiFailure(400, 'Vyber platnú rolu.');
        }
        if (target.first['email_verified'] != 1) {
          throw const ApiFailure(409, 'Správca musí mať overený e-mail.');
        }
        if (next != 'admin') _protectLastAdmin(id);
        if (next == 'none') {
          database.db.execute('DELETE FROM platform_roles WHERE user_id=?', [
            id,
          ]);
        } else {
          database.db.execute(
            'INSERT INTO platform_roles VALUES(?,?) ON CONFLICT(user_id) DO UPDATE SET role=excluded.role',
            [id, next],
          );
        }
      } else if (action == 'support-on' || action == 'support-off') {
        final email =
            database.db.select('SELECT email FROM users WHERE id=?', [
                  id,
                ]).first['email']
                as String;
        support.setAgent(email, action == 'support-on');
      } else {
        throw const ApiFailure(400, 'Neplatná akcia účtu.');
      }
    } else if (kind == 'organizations' &&
        {'suspend', 'activate'}.contains(action)) {
      if (database.db.select(
        'SELECT id FROM merchant_organizations WHERE id=?',
        [id],
      ).isEmpty) {
        throw const ApiFailure(404, 'Firma neexistuje.');
      }
      database.db.execute(
        'INSERT INTO platform_organizations VALUES(?,?,?,?) ON CONFLICT(org_id) DO UPDATE SET status=excluded.status,reason=excluded.reason,updated_at=excluded.updated_at',
        [
          id,
          action == 'suspend' ? 'suspended' : 'active',
          reason,
          clock().toUtc().toIso8601String(),
        ],
      );
      if (action == 'suspend') {
        for (final order in database.db.select(
          "SELECT DISTINCT o.id,o.user_id FROM orders o JOIN merchant_order_lines l ON l.order_id=o.id JOIN merchant_stores s ON s.id=l.store_id WHERE s.org_id=? AND o.status IN ('reserved','awaitingPayment')",
          [id],
        )) {
          support.systemTicket(
            order['user_id'] as String,
            order['id'] as String,
            TicketCategory.pickup,
            'org-hold:${order['id']}:$id',
            'Preverenie výdaja objednávky',
            'Prevádzkovateľ bol dočasne pozastavený. Podpora preverí výdaj alebo vrátenie platby.',
          );
        }
      }
    } else if (kind == 'stores' && {'suspend', 'activate'}.contains(action)) {
      if (database.db.select('SELECT id FROM merchant_stores WHERE id=?', [
        id,
      ]).isEmpty) {
        throw const ApiFailure(404, 'Pobočka neexistuje.');
      }
      database.db.execute(
        'INSERT INTO platform_stores VALUES(?,?,?) ON CONFLICT(store_id) DO UPDATE SET paused=excluded.paused,reason=excluded.reason',
        [id, action == 'suspend' ? 1 : 0, reason],
      );
      if (action == 'suspend') {
        for (final o in database.db.select(
          "SELECT DISTINCT o.id,o.user_id FROM orders o JOIN merchant_order_lines l ON l.order_id=o.id WHERE l.store_id=? AND o.status IN ('reserved','awaitingPayment')",
          [id],
        )) {
          support.systemTicket(
            o['user_id'] as String,
            o['id'] as String,
            TicketCategory.pickup,
            'branch-hold:${o['id']}:$id',
            'Preverenie výdaja v pobočke',
            'Predaj v pobočke bol dočasne pozastavený. Podpora preverí už rezervované výdaje.',
          );
        }
      }
    } else if (kind == 'offers' && {'hide', 'show'}.contains(action)) {
      if (database.db.select('SELECT id FROM offers WHERE id=?', [
        id,
      ]).isEmpty) {
        throw const ApiFailure(404, 'Ponuka neexistuje.');
      }
      database.db.execute(
        'INSERT INTO platform_offers VALUES(?,?,?) ON CONFLICT(offer_id) DO UPDATE SET hidden=excluded.hidden,reason=excluded.reason',
        [id, action == 'hide' ? 1 : 0, reason],
      );
    } else if (kind == 'reviews' && {'hide', 'show'}.contains(action)) {
      if (database.db.select('SELECT rowid FROM reviews WHERE rowid=?', [
        id,
      ]).isEmpty) {
        throw const ApiFailure(404, 'Recenzia neexistuje.');
      }
      database.db.execute(
        'UPDATE reviews SET moderation=?,version=version+1 WHERE rowid=?',
        [action == 'hide' ? 'hidden' : 'visible', id],
      );
    } else {
      throw const ApiFailure(400, 'Akcia nie je dostupná pre tento záznam.');
    }
    database.db.execute(
      'INSERT INTO platform_versions VALUES(?,?,?) ON CONFLICT(kind,entity) DO UPDATE SET version=excluded.version',
      [kind, id, (version as int) + 1],
    );
    database.db.execute('INSERT INTO platform_audit VALUES(?,?,?,?,?,?,?)', [
      const Uuid().v4(),
      user,
      action,
      kind,
      id,
      jsonEncode({
        'reason': reason,
        if (action == 'role') 'role': body['role'],
      }),
      clock().toUtc().toIso8601String(),
    ]);
    return {'updated': true, 'version': version + 1};
  });
  void _protectLastAdmin(String id) {
    final active =
        database.db.select('SELECT disabled FROM users WHERE id=?', [
          id,
        ]).firstOrNull?['disabled'] ==
        0;
    if (active &&
        role(id) == 'admin' &&
        (database.db
                    .select(
                      "SELECT COUNT(*) n FROM platform_roles p JOIN users u ON u.id=p.user_id WHERE p.role='admin' AND u.disabled=0",
                    )
                    .first['n']
                as int) <
            2) {
      throw const ApiFailure(
        409,
        'Platforma musí mať aspoň jedného aktívneho správcu.',
      );
    }
  }
}

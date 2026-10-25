import 'dart:convert';
import 'dart:math';
import 'package:uuid/uuid.dart';
import 'auth.dart';
import 'database.dart';
import 'mail.dart';

class AccountService {
  AccountService(this.database, this.auth, this.mail) {
    final columns = database.db
        .select('PRAGMA table_info(users)')
        .map((r) => r['name'])
        .toSet();
    for (final entry in {
      'email_verified': 'INTEGER NOT NULL DEFAULT 0',
      'disabled': 'INTEGER NOT NULL DEFAULT 0',
      'deleted_at': 'TEXT',
    }.entries) {
      if (!columns.contains(entry.key)) {
        database.db.execute(
          'ALTER TABLE users ADD COLUMN ${entry.key} ${entry.value}',
        );
      }
    }
    database.db.execute(
      '''CREATE TABLE IF NOT EXISTS account_challenges(
      id TEXT PRIMARY KEY,user_id TEXT NOT NULL REFERENCES users(id),purpose TEXT NOT NULL,
      target TEXT NOT NULL,token_hash TEXT NOT NULL,expires TEXT NOT NULL,used INTEGER NOT NULL DEFAULT 0,
      attempts INTEGER NOT NULL DEFAULT 0,credential_hash TEXT,session_hash TEXT);
      CREATE TABLE IF NOT EXISTS account_grants(id TEXT PRIMARY KEY,user_id TEXT NOT NULL,
      session_hash TEXT NOT NULL,expires TEXT NOT NULL,used INTEGER NOT NULL DEFAULT 0);
      CREATE TABLE IF NOT EXISTS account_audit(id TEXT PRIMARY KEY,user_id TEXT NOT NULL,event TEXT NOT NULL,created_at TEXT NOT NULL);''',
    );
  }
  final MarketplaceDatabase database;
  final AuthService auth;
  final MailService mail;
  String get now => auth.clock().toUtc().toIso8601String();
  Map<String, dynamic> row(String id) => auth.user(id);
  void audit(String user, String event) => database.db.execute(
    'INSERT INTO account_audit VALUES(?,?,?,?)',
    [const Uuid().v4(), user, event, now],
  );
  String email(String value) {
    final result = value.trim().toLowerCase();
    if (result.length > 250 ||
        !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(result)) {
      throw const ApiFailure(400, 'Zadaj platný e-mail.');
    }
    return result;
  }

  Future<Map<String, dynamic>> request(
    Map<String, dynamic> body, {
    String? user,
    String session = '',
  }) async {
    final purpose = stringField(body, 'purpose');
    if (!{'reset', 'verify', 'authorize', 'email'}.contains(purpose)) {
      throw const ApiFailure(400, 'Neplatný účel overenia.');
    }
    String target;
    if (purpose == 'reset') {
      target = email(stringField(body, 'email'));
      auth.rateLimit('reset:$target');
      final found = database.db.select(
        'SELECT id FROM users WHERE email=? AND disabled=0 AND deleted_at IS NULL',
        [target],
      );
      // Uniform response, including unknown identities. No user enumeration.
      if (found.isEmpty) {
        return {'requested': true, 'challengeId': const Uuid().v4()};
      }
      user = found.first['id'] as String;
    } else {
      if (user == null) throw const ApiFailure(401, 'Prihlás sa.');
      auth.rateLimit('account:$user:$purpose');
      target = purpose == 'email'
          ? email(stringField(body, 'email'))
          : row(user)['email'] as String;
      if (purpose == 'email') await authorize(user, body, session);
    }
    final current = row(user);
    final id = const Uuid().v4();
    final code = List.generate(8, (_) => Random.secure().nextInt(10)).join();
    final expires = auth
        .clock()
        .toUtc()
        .add(const Duration(minutes: 15))
        .toIso8601String();
    database.transaction(() {
      database.db.execute(
        "UPDATE mail_outbox SET status='cancelled',body='' WHERE dedupe IN (SELECT 'account:'||id FROM account_challenges WHERE user_id=? AND purpose=?) AND status='pending'",
        [user, purpose],
      );
      database.db.execute(
        'UPDATE account_challenges SET used=1 WHERE user_id=? AND purpose=?',
        [user, purpose],
      );
      database.db.execute(
        'INSERT INTO account_challenges(id,user_id,purpose,target,token_hash,expires,credential_hash,session_hash) VALUES(?,?,?,?,?,?,?,?)',
        [
          id,
          user,
          purpose,
          target,
          hashToken('$id:$code'),
          expires,
          current['password_hash'],
          purpose == 'reset' ? null : hashToken(session),
        ],
      );
      final subject = switch (purpose) {
        'reset' => 'Obnova hesla',
        'verify' => 'Overenie e-mailu',
        'email' => 'Potvrdenie novej adresy',
        _ => 'Overenie citlivej zmeny účtu',
      };
      final link = Uri.parse(auth.config.appUrl).replace(
        fragment: Uri(
          queryParameters: {
            'accountAction': purpose,
            'challenge': id,
            'code': code,
          },
        ).query,
      );
      mail.enqueue(
        user!,
        target,
        'Save Food · $subject',
        '$subject\n\nTvoj jednorazový kód: $code\nPlatí 15 minút.\n\nOtvoriť aplikáciu: $link\n\nAk si o túto zmenu nežiadal/a, kód nikomu neposkytuj.',
        lifetime: const Duration(minutes: 15),
        dedupe: 'account:$id',
      );
      audit(user, 'requested:$purpose');
    });
    return {'requested': true, 'challengeId': id};
  }

  Map<String, dynamic> _challenge(
    Map<String, dynamic> body, {
    String? user,
    String session = '',
    bool countAttempt = true,
  }) {
    final id = stringField(body, 'challengeId'),
        code = stringField(body, 'code', max: 100);
    final found = database.db.select(
      'SELECT * FROM account_challenges WHERE id=?',
      [id],
    );
    if (found.isEmpty) {
      throw const ApiFailure(400, 'Kód je neplatný alebo vypršal.');
    }
    final r = Map<String, dynamic>.from(found.first);
    if (r['used'] == 1 ||
        (countAttempt ? r['attempts'] as int >= 5 : r['attempts'] as int > 5) ||
        (r['expires'] as String).compareTo(now) <= 0) {
      throw const ApiFailure(400, 'Kód je neplatný alebo vypršal.');
    }
    if (countAttempt) {
      database.db.execute(
        'UPDATE account_challenges SET attempts=attempts+1 WHERE id=?',
        [id],
      );
    }
    if (hashToken('$id:$code') != r['token_hash']) {
      throw const ApiFailure(400, 'Kód je neplatný alebo vypršal.');
    }
    if (r['purpose'] != 'reset' &&
        (user != r['user_id'] || r['session_hash'] != hashToken(session))) {
      throw const ApiFailure(403, 'Overenie patrí inej relácii.');
    }
    final current = row(r['user_id'] as String);
    if (current['disabled'] == 1 ||
        current['deleted_at'] != null ||
        current['password_hash'] != r['credential_hash']) {
      throw const ApiFailure(
        400,
        'Účet sa medzičasom zmenil. Vyžiadaj nový kód.',
      );
    }
    return r;
  }

  Future<Map<String, dynamic>> confirm(
    Map<String, dynamic> body, {
    String? user,
    String session = '',
  }) async {
    final r = _challenge(body, user: user, session: session),
        purpose = r['purpose'] as String;
    final id = r['user_id'] as String;
    if (purpose == 'reset') {
      final password = stringField(body, 'password', max: 128);
      final credential = await auth.encodePassword(password);
      return database.transaction(() {
        final latest = _challenge(
          body,
          user: user,
          session: session,
          countAttempt: false,
        );
        if (latest['token_hash'] != r['token_hash']) {
          throw const ApiFailure(409, 'Vyžiadaj nový kód.');
        }
        database.db.execute(
          'UPDATE users SET password_hash=?,salt=?,email_verified=1 WHERE id=?',
          [credential.$1, credential.$2, id],
        );
        _revoke(id);
        audit(id, 'password-reset');
        return {'confirmed': true};
      });
    }
    return database.transaction(() {
      database.db.execute('UPDATE account_challenges SET used=1 WHERE id=?', [
        r['id'],
      ]);
      if (purpose == 'authorize') {
        final grant = randomSecret();
        database.db.execute(
          'INSERT INTO account_grants(id,user_id,session_hash,expires) VALUES(?,?,?,?)',
          [
            hashToken(grant),
            id,
            hashToken(session),
            auth
                .clock()
                .toUtc()
                .add(const Duration(minutes: 5))
                .toIso8601String(),
          ],
        );
        return {'confirmed': true, 'grant': grant};
      }
      if (purpose == 'email') {
        if (database.db.select('SELECT id FROM users WHERE email=? AND id!=?', [
          r['target'],
          id,
        ]).isNotEmpty) {
          throw const ApiFailure(409, 'Táto adresa je už použitá.');
        }
        final old = row(id)['email'] as String;
        database.db.execute(
          'UPDATE users SET email=?,email_verified=1 WHERE id=?',
          [r['target'], id],
        );
        _revoke(id);
        mail.enqueue(
          id,
          old,
          'Save Food · E-mail bol zmenený',
          'E-mail tvojho účtu bol zmenený. Ak si zmenu nevykonal/a, kontaktuj podporu.',
        );
      } else if (purpose == 'verify') {
        if (row(id)['email'] != r['target']) {
          throw const ApiFailure(409, 'E-mail účtu sa zmenil.');
        }
        database.db.execute('UPDATE users SET email_verified=1 WHERE id=?', [
          id,
        ]);
      }
      audit(id, 'confirmed:$purpose');
      return {'confirmed': true, 'signInRequired': purpose == 'email'};
    });
  }

  Future<void> authorize(
    String user,
    Map<String, dynamic> body,
    String session,
  ) async {
    if (body['grant'] is String) {
      final found = database.db.select(
        'SELECT id FROM account_grants WHERE id=? AND user_id=? AND session_hash=? AND expires>? AND used=0',
        [hashToken(body['grant'] as String), user, hashToken(session), now],
      );
      if (found.isEmpty) {
        throw const ApiFailure(403, 'Overenie vypršalo. Vyžiadaj nový kód.');
      }
      database.db.execute('UPDATE account_grants SET used=1 WHERE id=?', [
        found.first['id'],
      ]);
    } else {
      await auth.checkPassword(user, body['currentPassword']);
    }
  }

  void _revoke(String user) {
    database.db.execute(
      "UPDATE mail_outbox SET status='cancelled',body='' WHERE dedupe LIKE 'account:%' AND user_id=? AND status='pending'",
      [user],
    );
    database.db.execute('DELETE FROM sessions WHERE user_id=?', [user]);
    database.db.execute('DELETE FROM devices WHERE user_id=?', [user]);
    database.db.execute(
      'UPDATE account_challenges SET used=1 WHERE user_id=?',
      [user],
    );
    database.db.execute('UPDATE account_grants SET used=1 WHERE user_id=?', [
      user,
    ]);
  }

  Future<void> password(
    String user,
    Map<String, dynamic> body,
    String session,
  ) async {
    final previous = row(user)['password_hash'];
    await authorize(user, body, session);
    final encoded = await auth.encodePassword(
      stringField(body, 'password', max: 128),
    );
    database.transaction(() {
      if (row(user)['password_hash'] != previous) {
        throw const ApiFailure(409, 'Účet sa zmenil. Prihlás sa znova.');
      }
      database.db.execute(
        'UPDATE users SET password_hash=?,salt=? WHERE id=?',
        [encoded.$1, encoded.$2, user],
      );
      _revoke(user);
      audit(user, 'password-changed');
      mail.enqueue(
        user,
        row(user)['email'] as String,
        'Save Food · Heslo bolo zmenené',
        'Heslo tvojho účtu bolo zmenené a všetky relácie boli odhlásené.',
      );
    });
  }

  Map<String, dynamic> export(String user) {
    List<Map<String, dynamic>> select(String sql) => database.db
        .select(sql, [user])
        .map((r) => Map<String, dynamic>.from(r))
        .toList();
    final current = row(user);
    return {
      'exportedAt': now,
      'account': {
        for (final k in [
          'id',
          'email',
          'name',
          'profile',
          'credit',
          'member_until',
          'email_verified',
        ])
          k: current[k],
      },
      'orders': select('SELECT id,payload,status FROM orders WHERE user_id=?'),
      'creditLedger': select(
        'SELECT order_id,kind,amount,created_at FROM ledger WHERE user_id=?',
      ),
      'reviews': select(
        'SELECT offer_id,rating,comment,quality,value,quantity,pickup,moderation,created_at FROM reviews WHERE user_id=?',
      ),
      'reviewPhotos': select(
        "SELECT a.id,a.width,a.height,a.created_at FROM media_assets a WHERE a.user_id=? AND a.kind='review' AND a.deleted_at IS NULL",
      ),
      'legalAcceptances': select(
        'SELECT version,accepted_at FROM legal_acceptances WHERE user_id=?',
      ),
      'documents': select(
        'SELECT d.id,d.payload,d.hash FROM billing_documents d JOIN orders o ON o.id=d.order_id WHERE o.user_id=?',
      ),
      'memberships': select(
        'SELECT org_id,role FROM merchant_members WHERE user_id=?',
      ),
      'accountAudit': select(
        'SELECT event,created_at FROM account_audit WHERE user_id=?',
      ),
      'supportTickets': select(
        'SELECT id,number,subject,status,created_at FROM support_tickets WHERE user_id=?',
      ),
      'supportMessages': select(
        'SELECT m.ticket_id,m.body,m.created_at FROM support_messages m JOIN support_tickets t ON t.id=m.ticket_id WHERE t.user_id=? AND m.internal=0',
      ),
      'supportPhotos': database.db
          .select(
            'SELECT p.id,p.ticket_id,p.width,p.height,p.content FROM support_photos p JOIN support_tickets t ON t.id=p.ticket_id WHERE t.user_id=? AND ((p.message_id IS NULL AND p.user_id=?) OR p.message_id IN (SELECT id FROM support_messages WHERE internal=0))',
            [user, user],
          )
          .map(
            (r) => {
              'id': r['id'],
              'ticketId': r['ticket_id'],
              'width': r['width'],
              'height': r['height'],
              'jpegBase64': base64Encode(r['content'] as List<int>),
            },
          )
          .toList(),
    };
  }

  Future<void> erase(
    String user,
    Map<String, dynamic> body,
    String session,
  ) async {
    await authorize(user, body, session);
    database.transaction(() {
      if (database.db.select(
        "SELECT id FROM orders WHERE user_id=? AND status IN ('awaitingPayment','reserved','cancelling')",
        [user],
      ).isNotEmpty) {
        throw const ApiFailure(
          409,
          'Najprv dokonči alebo zruš aktívne objednávky.',
        );
      }
      if (database.db.select(
        "SELECT org_id FROM merchant_members WHERE user_id=? AND role='owner'",
        [user],
      ).isNotEmpty) {
        throw const ApiFailure(
          409,
          'Najprv odovzdaj vlastníctvo firmy inému členovi.',
        );
      }
      final current = row(user);
      if (database.db.select(
            "SELECT user_id FROM platform_roles WHERE user_id=? AND role='admin'",
            [user],
          ).isNotEmpty &&
          (database.db
                      .select(
                        "SELECT COUNT(*) n FROM platform_roles p JOIN users u ON u.id=p.user_id WHERE p.role='admin' AND u.disabled=0",
                      )
                      .first['n']
                  as int) <
              2) {
        throw const ApiFailure(
          409,
          'Najprv odovzdaj správu platformy inému overenému správcovi.',
        );
      }
      if (current['subscription_id'] != null &&
          current['subscription_cancelled'] != 1) {
        throw const ApiFailure(409, 'Najprv vypni obnovovanie členstva.');
      }
      _revoke(user);
      database.db.execute('DELETE FROM identities WHERE user_id=?', [user]);
      database.db.execute('DELETE FROM platform_roles WHERE user_id=?', [user]);
      database.db.execute(
        'UPDATE support_agents SET active=0 WHERE user_id=?',
        [user],
      );
      database.db.execute(
        "UPDATE support_tickets SET assignee=NULL,version=version+1 WHERE assignee=? AND status NOT IN ('closed','resolved')",
        [user],
      );
      database.db.execute('DELETE FROM merchant_members WHERE user_id=?', [
        user,
      ]);
      database.db.execute('DELETE FROM reviews WHERE user_id=?', [user]);
      database.db.execute('DELETE FROM review_media WHERE user_id=?', [user]);
      database.db.execute(
        "UPDATE media_assets SET content=X'',deleted_at=? WHERE user_id=? AND kind='review'",
        [now, user],
      );
      database.db.execute('DELETE FROM support_photos WHERE user_id=?', [user]);
      database.db.execute(
        "UPDATE support_messages SET body='Obsah odstránený na žiadosť autora.' WHERE user_id=?",
        [user],
      );
      database.db.execute(
        "UPDATE mail_outbox SET status='cancelled',body='',recipient='' WHERE user_id=?",
        [user],
      );
      database.db.execute(
        "UPDATE users SET name='Odstránený účet',email=?,password_hash=NULL,salt=NULL,profile='{}',disabled=1,deleted_at=? WHERE id=?",
        ['deleted-$user@invalid.local', now, user],
      );
      audit(user, 'account-anonymized');
    });
  }
}

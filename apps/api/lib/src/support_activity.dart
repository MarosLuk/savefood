part of 'support.dart';

extension SupportActivity on SupportService {
  void initializeActivity() => database.db.execute('''
  CREATE TABLE IF NOT EXISTS support_notifications(id INTEGER PRIMARY KEY AUTOINCREMENT,user_id TEXT NOT NULL REFERENCES users(id),
   ticket_id TEXT NOT NULL REFERENCES support_tickets(id),message_id TEXT NOT NULL REFERENCES support_messages(id),
   created_at TEXT NOT NULL,read_at TEXT,UNIQUE(user_id,message_id));
  CREATE INDEX IF NOT EXISTS support_notifications_user ON support_notifications(user_id,read_at,id);
  CREATE TABLE IF NOT EXISTS support_push(id INTEGER PRIMARY KEY AUTOINCREMENT,notification_id INTEGER NOT NULL REFERENCES support_notifications(id),
   token TEXT NOT NULL,session_hash TEXT NOT NULL,status TEXT NOT NULL DEFAULT 'pending',attempts INTEGER NOT NULL DEFAULT 0,next_at TEXT NOT NULL,
   UNIQUE(notification_id,token));
 ''');
  void messageActivity(
    String ticket,
    String message,
    String? actor,
    String author,
    bool internal,
  ) {
    final t = rows('SELECT user_id FROM support_tickets WHERE id=?', [
      ticket,
    ]).first;
    final recipients = <String>{};
    if (author != 'customer' && !internal) {
      recipients.add(t['user_id'] as String);
    }
    if (author == 'customer' || internal) {
      recipients.addAll(
        rows(
          'SELECT user_id FROM support_agents WHERE active=1',
        ).map((r) => r['user_id'] as String),
      );
    }
    recipients.remove(actor);
    for (final user in recipients) {
      mail?.notice(
        user,
        'Save Food · Nová správa podpory',
        'V tvojej požiadavke zákazníckej podpory je nová správa. Otvor aplikáciu a časť Pomoc a podpora.',
        dedupe: 'support:$user:$message',
      );
      database.db.execute(
        'INSERT OR IGNORE INTO support_notifications(user_id,ticket_id,message_id,created_at) VALUES(?,?,?,?)',
        [user, ticket, message, now],
      );
      final n = rows(
        'SELECT id FROM support_notifications WHERE user_id=? AND message_id=?',
        [user, message],
      ).first['id'];
      for (final d in rows(
        'SELECT d.* FROM devices d JOIN users u ON u.id=d.user_id WHERE d.user_id=?',
        [user],
      )) {
        database.db.execute(
          'INSERT OR IGNORE INTO support_push(notification_id,token,session_hash,next_at) VALUES(?,?,?,?)',
          [n, d['token'], d['session_hash'], now],
        );
      }
    }
  }

  Map<String, dynamic> activity(String user, {int? before}) {
    final agent = isAgent(user);
    final records = rows(
      '''SELECT n.*,t.subject,t.number,m.internal,m.rowid message_cursor FROM support_notifications n JOIN support_tickets t ON t.id=n.ticket_id
    JOIN support_messages m ON m.id=n.message_id WHERE n.user_id=? AND (?=1 OR (t.user_id=? AND m.internal=0)) AND (? IS NULL OR n.id<?) ORDER BY n.id DESC LIMIT 51''',
      [user, agent ? 1 : 0, user, before, before],
    );
    final page = records.take(50).toList();
    final unread = rows(
      '''SELECT COUNT(DISTINCT n.ticket_id) n FROM support_notifications n JOIN support_tickets t ON t.id=n.ticket_id JOIN support_messages m ON m.id=n.message_id
    WHERE n.user_id=? AND n.read_at IS NULL AND (?=1 OR (t.user_id=? AND m.internal=0))''',
      [user, agent ? 1 : 0, user],
    ).first['n'];
    return {
      'unread': unread,
      'isAgent': agent,
      'notifications': page
          .map(
            (r) => {
              'id': r['id'],
              'ticketId': r['ticket_id'],
              'number':
                  'NVP-${(r['number'] as int).toString().padLeft(5, '0')}',
              'subject': r['subject'],
              'createdAt': r['created_at'],
              'read': r['read_at'] != null,
              'internal': r['internal'] == 1,
              'messageCursor': r['message_cursor'],
            },
          )
          .toList(),
      'nextCursor': records.length > 50 ? page.last['id'] : null,
      'through': page.firstOrNull?['id'] ?? 0,
    };
  }

  void readTicket(String user, String id, int through) {
    _owned(user, id);
    final visible = rows(
      'SELECT rowid n FROM support_messages WHERE ticket_id=? AND rowid=? AND (?=1 OR internal=0)',
      [id, through, isAgent(user) ? 1 : 0],
    );
    if (visible.isEmpty) {
      throw const ApiFailure(400, 'Neplatná pozícia konverzácie.');
    }
    database.db.execute(
      '''UPDATE support_notifications SET read_at=COALESCE(read_at,?) WHERE user_id=? AND ticket_id=?
    AND message_id IN (SELECT id FROM support_messages WHERE ticket_id=? AND rowid<=?)''',
      [now, user, id, id, through],
    );
  }

  void readActivity(String user, int through) {
    if (through < 0) {
      throw const ApiFailure(400, 'Neplatná pozícia upozornení.');
    }
    database.db.execute(
      'UPDATE support_notifications SET read_at=COALESCE(read_at,?) WHERE user_id=? AND id<=?',
      [now, user, through],
    );
  }

  Future<void> drainSupportPush(StockPushGateway gateway) async {
    if (!gateway.configured) return;
    for (final j in rows(
      """SELECT p.*,n.user_id,n.ticket_id,n.read_at,m.internal,t.user_id owner FROM support_push p JOIN support_notifications n ON n.id=p.notification_id
    JOIN support_messages m ON m.id=n.message_id JOIN support_tickets t ON t.id=n.ticket_id
    WHERE p.status='pending' AND p.attempts<5 AND p.next_at<=? ORDER BY p.next_at,p.id LIMIT 40""",
      [now],
    )) {
      final devices = rows(
        'SELECT u.profile FROM devices d JOIN users u ON u.id=d.user_id JOIN sessions s ON s.token_hash=d.session_hash WHERE d.token=? AND d.user_id=? AND d.session_hash=? AND s.expires>?',
        [j['token'], j['user_id'], j['session_hash'], now],
      );
      final allowed =
          devices.isNotEmpty &&
          database.decode(
                devices.first['profile'] as String,
              )['supportAlerts'] ==
              true &&
          j['read_at'] == null &&
          (j['internal'] == 0 && j['owner'] == j['user_id'] ||
              isAgent(j['user_id'] as String));
      if (!allowed) {
        database.db.execute(
          "UPDATE support_push SET status='skipped' WHERE id=?",
          [j['id']],
        );
        continue;
      }
      try {
        final valid = await gateway.send(
          j['token'] as String,
          'Nová správa v podpore',
          'Otvor aplikáciu a pozri si priebeh požiadavky.',
          {'ticketId': j['ticket_id'] as String, 'kind': 'support'},
        );
        database.db.execute(
          "UPDATE support_push SET status='sent' WHERE id=?",
          [j['id']],
        );
        if (!valid) {
          database.db.execute('DELETE FROM devices WHERE token=?', [
            j['token'],
          ]);
        }
      } catch (_) {
        final attempts = (j['attempts'] as int) + 1;
        database.db.execute(
          'UPDATE support_push SET attempts=?,status=?,next_at=? WHERE id=?',
          [
            attempts,
            attempts >= 5 ? 'failed' : 'pending',
            clock()
                .toUtc()
                .add(Duration(seconds: 30 * (1 << attempts)))
                .toIso8601String(),
            j['id'],
          ],
        );
      }
    }
  }
}

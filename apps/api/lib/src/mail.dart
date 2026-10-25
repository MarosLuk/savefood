import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import 'database.dart';

abstract interface class MailGateway {
  bool get configured;
  Future<void> send(String id, String to, String subject, String text);
}

class DisabledMailGateway implements MailGateway {
  @override
  bool get configured => false;
  @override
  Future<void> send(String id, String to, String subject, String text) async =>
      throw StateError('Mail is not configured.');
}

class ResendMailGateway implements MailGateway {
  ResendMailGateway(this.key, this.from, {http.Client? client})
    : client = client ?? http.Client();
  final String key, from;
  final http.Client client;
  @override
  bool get configured => key.isNotEmpty && from.isNotEmpty;
  @override
  Future<void> send(String id, String to, String subject, String text) async {
    final response = await client
        .post(
          Uri.https('api.resend.com', '/emails'),
          headers: {
            'Authorization': 'Bearer $key',
            'Content-Type': 'application/json',
            'Idempotency-Key': 'nevyhadzuj/$id',
          },
          body: jsonEncode({
            'from': from,
            'to': [to],
            'subject': subject,
            'text': text,
          }),
        )
        .timeout(const Duration(seconds: 20));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        'Mail provider rejected delivery (${response.statusCode}).',
      );
    }
  }
}

class MailService {
  MailService(this.database, this.gateway, {DateTime Function()? clock})
    : clock = clock ?? DateTime.now {
    database.db.execute(
      '''CREATE TABLE IF NOT EXISTS mail_outbox(
      id TEXT PRIMARY KEY,user_id TEXT,recipient TEXT NOT NULL,subject TEXT NOT NULL,
      body TEXT NOT NULL,created_at TEXT NOT NULL,expires TEXT NOT NULL,
      status TEXT NOT NULL DEFAULT 'pending',attempts INTEGER NOT NULL DEFAULT 0,
      next_at TEXT NOT NULL,error TEXT,dedupe TEXT UNIQUE);
      CREATE INDEX IF NOT EXISTS mail_pending ON mail_outbox(status,next_at);''',
    );
  }
  final MarketplaceDatabase database;
  final MailGateway gateway;
  final DateTime Function() clock;
  bool draining = false;
  void notice(
    String user,
    String subject,
    String text, {
    required String dedupe,
  }) {
    final r = database.db.select('SELECT * FROM users WHERE id=?', [
      user,
    ]).firstOrNull;
    if (r == null ||
        r['disabled'] == 1 ||
        r['deleted_at'] != null ||
        database.decode(r['profile'] as String)['emailNotifications'] ==
            false) {
      return;
    }
    enqueue(user, r['email'] as String, subject, text, dedupe: dedupe);
  }

  String enqueue(
    String user,
    String to,
    String subject,
    String text, {
    Duration lifetime = const Duration(hours: 23),
    String? dedupe,
  }) {
    final id = const Uuid().v4(), now = clock().toUtc();
    database.db.execute(
      '''INSERT OR IGNORE INTO mail_outbox
      (id,user_id,recipient,subject,body,created_at,expires,next_at,dedupe)
      VALUES(?,?,?,?,?,?,?,?,?)''',
      [
        id,
        user,
        to,
        subject,
        text,
        now.toIso8601String(),
        now.add(lifetime).toIso8601String(),
        now.toIso8601String(),
        dedupe,
      ],
    );
    return id;
  }

  Future<void> drain() async {
    if (draining) return;
    draining = true;
    try {
      final now = clock().toUtc().toIso8601String();
      database.db.execute(
        "UPDATE mail_outbox SET status=CASE WHEN status='pending' THEN 'expired' ELSE status END,body='' WHERE expires<=? AND body!=''",
        [now],
      );
      if (!gateway.configured) return;
      final rows = database.db
          .select(
            "SELECT * FROM mail_outbox WHERE status='pending' AND next_at<=? ORDER BY created_at,id LIMIT 20",
            [now],
          )
          .map((r) => Map<String, dynamic>.from(r))
          .toList();
      for (final r in rows) {
        try {
          await gateway.send(
            r['id'] as String,
            r['recipient'] as String,
            r['subject'] as String,
            r['body'] as String,
          );
          database.db.execute(
            "UPDATE mail_outbox SET status='sent',body='',error=NULL WHERE id=?",
            [r['id']],
          );
        } catch (_) {
          final attempts = (r['attempts'] as int) + 1;
          database.db.execute(
            'UPDATE mail_outbox SET attempts=?,status=?,next_at=?,error=? WHERE id=?',
            [
              attempts,
              attempts >= 6 ? 'failed' : 'pending',
              clock()
                  .toUtc()
                  .add(Duration(minutes: 1 << attempts))
                  .toIso8601String(),
              'Doručenie zlyhalo. Obsah ani poverenia sa nelogujú.',
              r['id'],
            ],
          );
          if (attempts >= 6) {
            database.db.execute("UPDATE mail_outbox SET body='' WHERE id=?", [
              r['id'],
            ]);
          }
        }
      }
      database.db.execute(
        "DELETE FROM mail_outbox WHERE status!='pending' AND created_at<?",
        [clock().toUtc().subtract(const Duration(days: 30)).toIso8601String()],
      );
    } finally {
      draining = false;
    }
  }
}

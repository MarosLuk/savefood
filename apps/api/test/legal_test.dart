import 'dart:convert';
import 'package:marketplace_server/marketplace_server.dart';
import 'package:marketplace_server/src/auth.dart';
import 'package:marketplace_server/src/legal.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

void main() {
  late MarketplaceServer app;
  late DateTime now;
  setUp(() {
    now = DateTime.utc(2026, 10, 25, 12);
    app = MarketplaceServer(
      const ServerConfig(databasePath: ':memory:', demoShowcase: true),
      clock: () => now,
    );
  });
  tearDown(() => app.close());
  test(
    'published policies are immutable and each acceptance records its exact version',
    () {
      final old = app.legal.current(), draft = app.legal.draft();
      app.legal.accept('showcase-customer', {
        'version': old['version'],
        'accepted': true,
        'electronicInvoice': true,
      });
      app.legal.save({
        ...draft,
        'terms': '${draft['terms']} Nové pravidlo.',
      }, publish: true);
      expect(app.legal.current()['version'], 2);
      expect(app.legal.current(version: 1)['terms'], old['terms']);
      expect(
        () => app.legal.accept('showcase-customer', {
          'version': 1,
          'accepted': true,
        }),
        throwsA(isA<ApiFailure>()),
      );
      final production = LegalService(
        app.database,
        production: true,
        demo: false,
        clock: () => now,
      );
      expect(
        () => production.requireAccepted('showcase-customer'),
        throwsA(isA<ApiFailure>()),
      );
      production.accept('showcase-customer', {'version': 2, 'accepted': true});
      expect(
        () => production.requireAccepted('showcase-customer'),
        throwsA(isA<ApiFailure>()),
      );
      production.accept('showcase-customer', {
        'version': 2,
        'accepted': true,
        'electronicInvoice': true,
      });
      production.requireAccepted('showcase-customer');
    },
  );
  test(
    'unpublished drafts and missing operator details cannot replace a published version',
    () {
      final d = app.legal.draft();
      app.legal.save({...d, 'operator': ''});
      expect(app.legal.current()['version'], 1);
      expect(
        () => app.legal.save({
          ...app.legal.draft(),
          'operator': '',
        }, publish: true),
        throwsA(isA<ApiFailure>()),
      );
      expect(() => app.legal.save(d), throwsA(isA<ApiFailure>()));
    },
  );
  test(
    'retention erases old closed support text, photos and order contact details without changing money',
    () {
      final old = app.database.db
          .select(
            "SELECT id,payload FROM orders WHERE status='collected' AND user_id='showcase-customer' LIMIT 1",
          )
          .first;
      final payload = app.database.decode(old['payload'] as String);
      final total = payload['total'];
      payload['createdAt'] = '2010-01-01T00:00:00.000Z';
      app.database.db.execute('UPDATE orders SET payload=? WHERE id=?', [
        jsonEncode(payload),
        old['id'],
      ]);
      final t = app.support.create('showcase-customer', {
        'subject': 'Staršia otázka',
        'message': 'Súkromné osobné údaje',
        'category': 'other',
      });
      app.database.db.execute(
        "UPDATE support_tickets SET status='closed',updated_at='2010-01-01T00:00:00.000Z' WHERE id=?",
        [t['id']],
      );
      app.legal.clean();
      final order = app.database.decode(
        app.database.db.select('SELECT payload FROM orders WHERE id=?', [
              old['id'],
            ]).first['payload']
            as String,
      );
      expect(order['invoice']['email'], '');
      expect(order['total'], total);
      expect(
        app.database.db
            .select('SELECT body FROM support_messages WHERE ticket_id=?', [
              t['id'],
            ])
            .every((r) => !(r['body'] as String).contains('Súkromné')),
        true,
      );
    },
  );
  test(
    'legal publishing is restricted to administrators and audited',
    () async {
      final draft = app.legal.draft();
      for (final entry in {
        'showcase-customer': 403,
        'showcase-support': 200,
      }.entries) {
        final token = app.auth.createSession(entry.key)['token'];
        final r = await app.handler(
          Request(
            'POST',
            Uri.parse('http://localhost/v1/platform/legal'),
            headers: {
              'authorization': 'Bearer $token',
              'content-type': 'application/json',
            },
            body: jsonEncode({
              ...draft,
              'publish': true,
              'idempotencyKey': 'legal-publish-operation',
            }),
          ),
        );
        expect(r.statusCode, entry.value, reason: await r.readAsString());
      }
      expect(
        app.database.db.select(
          "SELECT id FROM platform_audit WHERE event='legal-updated'",
        ),
        hasLength(1),
      );
    },
  );
  test(
    'optional mail respects account preference; security mail remains deliverable',
    () {
      app.database.db.execute(
        "UPDATE users SET profile=? WHERE id='showcase-customer'",
        [
          jsonEncode({'emailNotifications': false}),
        ],
      );
      app.mail.notice(
        'showcase-customer',
        'Neposlať',
        'Text',
        dedupe: 'test-optional',
      );
      expect(
        app.database.db.select(
          "SELECT id FROM mail_outbox WHERE dedupe='test-optional'",
        ),
        isEmpty,
      );
      app.mail.enqueue(
        'showcase-customer',
        'customer@demo.nevyhadzuj.test',
        'Bezpečnosť účtu',
        'Text',
        dedupe: 'test-security',
      );
      expect(
        app.database.db.select(
          "SELECT id FROM mail_outbox WHERE dedupe='test-security'",
        ),
        hasLength(1),
      );
    },
  );
}

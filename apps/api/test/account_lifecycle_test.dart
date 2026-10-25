import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:marketplace_server/marketplace_server.dart';
import 'package:marketplace_server/src/auth.dart';
import 'package:marketplace_server/src/mail.dart';
import 'package:test/test.dart';

class TestMail implements MailGateway {
  final sent = <String>[];
  bool fail = false;
  @override
  bool get configured => true;
  @override
  Future<void> send(String id, String to, String subject, String text) async {
    if (fail) throw StateError('offline');
    sent.add(text);
  }
}

void main() {
  late MarketplaceServer app;
  late TestMail gateway;
  late DateTime clock;
  late String user, session;
  setUp(() async {
    clock = DateTime.utc(2026, 10, 25, 12);
    gateway = TestMail();
    app = MarketplaceServer(
      const ServerConfig(databasePath: ':memory:'),
      mail: gateway,
      clock: () => clock,
    );
    final result = await app.auth.register({
      'email': 'someone@example.test',
      'name': 'Test Account',
      'password': 'very-long-password',
    });
    user = result['userId'] as String;
    session = 'Bearer ${result['token']}';
  });
  tearDown(() => app.close());
  String code() => RegExp(r'kód: (\d{8})')
      .firstMatch(
        app.database.db
                .select(
                  'SELECT body FROM mail_outbox ORDER BY rowid DESC LIMIT 1',
                )
                .first['body']
            as String,
      )!
      .group(1)!;
  Future<Map<String, dynamic>> challenge(String purpose) async {
    final result = await app.accounts.request(
      {'purpose': purpose, 'email': 'someone@example.test'},
      user: purpose == 'reset' ? null : user,
      session: session,
    );
    return {'challengeId': result['challengeId'], 'code': code()};
  }

  test(
    'verification is single-use, session-bound and does not expose credentials',
    () async {
      final proof = await challenge('verify');
      await expectLater(
        app.accounts.confirm(proof, user: user, session: 'other'),
        throwsA(isA<ApiFailure>()),
      );
      await app.accounts.confirm(proof, user: user, session: session);
      expect(app.profile(user)['emailVerified'], true);
      await expectLater(
        app.accounts.confirm(proof, user: user, session: session),
        throwsA(isA<ApiFailure>()),
      );
      final exported = jsonEncode(app.accounts.export(user));
      expect(exported, isNot(contains('password_hash')));
      expect(exported, isNot(contains(session)));
      expect(exported, isNot(contains(proof['code'])));
    },
  );
  test(
    'recovery does not enumerate accounts and rejects guessed codes after five attempts',
    () async {
      final missing = await app.accounts.request({
        'purpose': 'reset',
        'email': 'unknown@example.test',
      });
      expect(missing.keys.toSet(), {'requested', 'challengeId'});
      expect(app.database.db.select('SELECT id FROM mail_outbox'), isEmpty);
      final proof = await challenge('reset');
      for (var i = 0; i < 5; i++) {
        await expectLater(
          app.accounts.confirm({
            ...proof,
            'code': 'wrong',
            'password': 'replacement-password',
          }),
          throwsA(isA<ApiFailure>()),
        );
      }
      await expectLater(
        app.accounts.confirm({...proof, 'password': 'replacement-password'}),
        throwsA(isA<ApiFailure>()),
      );
    },
  );
  test(
    'recovery expires, rotates the password and revokes every session',
    () async {
      var proof = await challenge('reset');
      clock = clock.add(const Duration(minutes: 16));
      await expectLater(
        app.accounts.confirm({...proof, 'password': 'replacement-password'}),
        throwsA(isA<ApiFailure>()),
      );
      proof = await challenge('reset');
      await app.accounts.confirm({
        ...proof,
        'password': 'replacement-password',
      });
      expect(() => app.auth.requireUser(session), throwsA(isA<ApiFailure>()));
      await expectLater(
        app.auth.login({
          'email': 'someone@example.test',
          'password': 'very-long-password',
        }),
        throwsA(isA<ApiFailure>()),
      );
      expect(
        await app.auth.login({
          'email': 'someone@example.test',
          'password': 'replacement-password',
        }),
        contains('token'),
      );
    },
  );
  test(
    'email change requires current credential and confirmation of the target',
    () async {
      await expectLater(
        app.accounts.request(
          {
            'purpose': 'email',
            'email': 'new@example.test',
            'currentPassword': 'wrong',
          },
          user: user,
          session: session,
        ),
        throwsA(isA<ApiFailure>()),
      );
      final proof = await app.accounts.request(
        {
          'purpose': 'email',
          'email': 'new@example.test',
          'currentPassword': 'very-long-password',
        },
        user: user,
        session: session,
      );
      expect(app.profile(user)['email'], 'someone@example.test');
      await app.accounts.confirm(
        {'challengeId': proof['challengeId'], 'code': code()},
        user: user,
        session: session,
      );
      expect(app.profile(user)['email'], 'new@example.test');
      expect(() => app.auth.requireUser(session), throwsA(isA<ApiFailure>()));
    },
  );
  test(
    'password change supports a one-use email grant and rejects stale grants',
    () async {
      final proof = await challenge('authorize');
      final grant = await app.accounts.confirm(
        proof,
        user: user,
        session: session,
      );
      await app.accounts.password(user, {
        'grant': grant['grant'],
        'password': 'new-long-password',
      }, session);
      await expectLater(
        app.accounts.password(user, {
          'grant': grant['grant'],
          'password': 'another-password',
        }, session),
        throwsA(isA<ApiFailure>()),
      );
    },
  );
  test(
    'erasure removes credentials, identities and profile and permits address reuse',
    () async {
      await app.accounts.erase(user, {
        'currentPassword': 'very-long-password',
      }, session);
      expect(() => app.auth.requireUser(session), throwsA(isA<ApiFailure>()));
      final row = app.database.db.select('SELECT * FROM users WHERE id=?', [
        user,
      ]).first;
      expect(row['profile'], '{}');
      expect(row['password_hash'], isNull);
      expect(row['disabled'], 1);
      expect(
        await app.auth.register({
          'email': 'someone@example.test',
          'name': 'Another User',
          'password': 'very-long-password',
        }),
        contains('token'),
      );
    },
  );
  test('owner cannot erase an organization into an orphaned state', () async {
    final demo = MarketplaceServer(
      const ServerConfig(databasePath: ':memory:', demoShowcase: true),
    );
    addTearDown(demo.close);
    final token = demo.auth.createSession('showcase-bakery')['token'];
    await demo.accounts.request(
      {'purpose': 'authorize'},
      user: 'showcase-bakery',
      session: 'Bearer $token',
    );
    final text =
        demo.database.db
                .select(
                  'SELECT body FROM mail_outbox ORDER BY rowid DESC LIMIT 1',
                )
                .first['body']
            as String;
    final id = demo.database.db
        .select('SELECT id FROM account_challenges ORDER BY rowid DESC LIMIT 1')
        .first['id'];
    final grant = await demo.accounts.confirm(
      {
        'challengeId': id,
        'code': RegExp(r'kód: (\d{8})').firstMatch(text)!.group(1),
      },
      user: 'showcase-bakery',
      session: 'Bearer $token',
    );
    await expectLater(
      demo.accounts.erase('showcase-bakery', {
        'grant': grant['grant'],
      }, 'Bearer $token'),
      throwsA(isA<ApiFailure>()),
    );
  });
  test(
    'mail retries persist across failures, stop after success and clear sensitive body',
    () async {
      await challenge('verify');
      gateway.fail = true;
      await app.mail.drain();
      expect(
        app.database.db
            .select('SELECT attempts FROM mail_outbox')
            .first['attempts'],
        1,
      );
      clock = clock.add(const Duration(minutes: 3));
      gateway.fail = false;
      await app.mail.drain();
      await app.mail.drain();
      expect(gateway.sent, hasLength(1));
      expect(
        app.database.db
            .select('SELECT body,status FROM mail_outbox')
            .first['body'],
        '',
      );
    },
  );
  test(
    'Resend adapter sends an idempotency header and never accepts failed delivery',
    () async {
      final gateway = ResendMailGateway(
        'secret',
        'hello@example.test',
        client: MockClient((request) async {
          expect(request.url.toString(), 'https://api.resend.com/emails');
          expect(request.headers['Idempotency-Key'], 'nevyhadzuj/job-1');
          expect((jsonDecode(request.body) as Map)['text'], 'Hello');
          return http.Response('{}', 503);
        }),
      );
      await expectLater(
        gateway.send('job-1', 'test@example.test', 'Subject', 'Hello'),
        throwsStateError,
      );
    },
  );
}

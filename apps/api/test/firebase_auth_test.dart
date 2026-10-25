import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jose/jose.dart';
import 'package:marketplace_server/marketplace_server.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

// Disposable local RSA fixtures, never provider or production credentials.
void main() {
  final now = DateTime.utc(2026, 10, 25, 16);
  final seconds = now.millisecondsSinceEpoch ~/ 1000;
  final key = JsonWebKey.fromPem(
    File('test/fixtures/firebase-test-private.pem').readAsStringSync(),
    keyId: 'test-key',
  );
  final certificate = File(
    'test/fixtures/firebase-test-certificate.pem',
  ).readAsStringSync();
  late MarketplaceServer app;
  late Map<String, dynamic> user;
  late int keyRequests, lookupRequests;
  var lookupStatus = 200;
  String jwt({
    String provider = 'google',
    Map<String, dynamic> changes = const {},
  }) {
    final claims = <String, dynamic>{
      'iss': 'https://securetoken.google.com/savefood-test',
      'aud': 'savefood-test',
      'sub': 'firebase-user-1',
      'iat': seconds,
      'auth_time': seconds - 10,
      'exp': seconds + 3600,
      'email': 'sofia@example.test',
      'email_verified': true,
      'firebase': {'sign_in_provider': '$provider.com'},
      ...changes,
    };
    final builder = JsonWebSignatureBuilder()..jsonContent = claims;
    builder.addRecipient(key, algorithm: 'RS256');
    return builder.build().toCompactSerialization();
  }

  Future<Response> exchange(
    String token, {
    String provider = 'google',
    Map<String, dynamic>? consent,
  }) async => app.handler(
    Request(
      'POST',
      Uri.parse('http://localhost/v1/auth/firebase'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({
        'idToken': token,
        'provider': provider,
        'legalConsent': ?consent,
      }),
    ),
  );
  setUp(() {
    keyRequests = lookupRequests = 0;
    lookupStatus = 200;
    user = {
      'localId': 'firebase-user-1',
      'email': 'sofia@example.test',
      'emailVerified': true,
      'displayName': 'Sofia Test',
      'disabled': false,
      'validSince': '${seconds - 100}',
      'providerUserInfo': [
        {'providerId': 'google.com'},
        {'providerId': 'apple.com'},
      ],
    };
    app = MarketplaceServer(
      ServerConfig(
        databasePath: ':memory:',
        seedDemo: false,
        firebaseAuthProjectId: 'savefood-test',
        firebaseAuthApiKey: 'test-public-api-key',
        firebaseGoogleEnabled: true,
        firebaseAppleEnabled: true,
      ),
      clock: () => now,
      authClient: MockClient((r) async {
        if (r.url.host == 'www.googleapis.com') {
          keyRequests++;
          expect(
            r.url.path,
            '/robot/v1/metadata/x509/securetoken@system.gserviceaccount.com',
          );
          return http.Response(
            jsonEncode({'test-key': certificate}),
            200,
            headers: {'cache-control': 'public, max-age=3600'},
          );
        }
        expect(r.url.host, 'identitytoolkit.googleapis.com');
        expect(r.url.path, '/v1/accounts:lookup');
        lookupRequests++;
        expect(r.url.queryParameters['key'], 'test-public-api-key');
        return http.Response(
          jsonEncode({
            'users': [user],
          }),
          lookupStatus,
        );
      }),
    );
  });
  tearDown(() => app.close());
  test(
    'verified Google registration and subsequent Apple login share only the same Firebase UID',
    () async {
      final first = await exchange(jwt());
      expect(first.statusCode, 200, reason: await first.readAsString());
      final session = app.auth.database.db
          .select('SELECT user_id FROM sessions')
          .single['user_id'];
      expect(app.auth.user(session as String)['email_verified'], 1);
      final second = await exchange(jwt(provider: 'apple'), provider: 'apple');
      final body = jsonDecode(await second.readAsString()) as Map;
      expect(body['created'], false);
      expect(body['userId'], session);
      expect(app.database.db.select('SELECT id FROM users'), hasLength(1));
      expect(keyRequests, 1); // Cache honored across provider logins.
      expect(lookupRequests, 2); // Account status is never cached.
    },
  );
  test(
    'Firebase cannot take over an existing password/email identity',
    () async {
      app.database.db.execute(
        'INSERT INTO users(id,email,name) VALUES(?,?,?)',
        ['existing', 'sofia@example.test', 'Existing'],
      );
      expect((await exchange(jwt())).statusCode, 409);
      expect(app.database.db.select('SELECT user_id FROM identities'), isEmpty);
      expect(app.database.db.select('SELECT user_id FROM sessions'), isEmpty);
    },
  );
  test(
    'Apple private relay and first-login-only display name are supported',
    () async {
      user['email'] = 'private@privaterelay.appleid.com';
      user.remove('displayName');
      final response = await exchange(
        jwt(provider: 'apple', changes: {'email': user['email']}),
        provider: 'apple',
      );
      expect(response.statusCode, 200);
      expect(
        app.database.db.select('SELECT email FROM users').single['email'],
        user['email'],
      );
    },
  );
  final badClaims = <String, Map<String, dynamic>>{
    'wrong project': {'aud': 'another-project'},
    'wrong issuer': {'iss': 'https://attacker.example'},
    'expired': {'exp': seconds},
    'issued in future': {'iat': seconds + 60},
    'old authentication': {'auth_time': seconds - 601},
    'unverified email': {'email_verified': false},
    'empty UID': {'sub': ''},
    'custom/password provider': {
      'firebase': {'sign_in_provider': 'custom'},
    },
    'unconfigured tenant': {
      'firebase': {'sign_in_provider': 'google.com', 'tenant': 'other'},
    },
  };
  for (final c in badClaims.entries) {
    test(
      'rejects ${c.key} before creating a user or contacting account lookup',
      () async {
        expect((await exchange(jwt(changes: c.value))).statusCode, 401);
        expect(app.database.db.select('SELECT id FROM users'), isEmpty);
        expect(lookupRequests, 0);
      },
    );
  }
  test('tampered token cannot reach live lookup', () async {
    final parts = jwt().split('.');
    final claims =
        jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))))
            as Map;
    claims['sub'] = 'attacker';
    parts[1] = base64Url
        .encode(utf8.encode(jsonEncode(claims)))
        .replaceAll('=', '');
    expect((await exchange(parts.join('.'))).statusCode, 401);
    expect(lookupRequests, 0);
  });
  for (final field in [
    'disabled',
    'revoked',
    'deleted',
    'unverified',
    'different UID',
    'different provider',
  ]) {
    test('rejects current Firebase state: $field', () async {
      switch (field) {
        case 'disabled':
          user['disabled'] = true;
        case 'revoked':
          user['validSince'] = '$seconds';
        case 'deleted':
          lookupStatus = 400;
        case 'unverified':
          user['emailVerified'] = false;
        case 'different UID':
          user['localId'] = 'other';
        case 'different provider':
          user['providerUserInfo'] = [];
      }
      expect((await exchange(jwt())).statusCode, 401);
      expect(app.database.db.select('SELECT id FROM users'), isEmpty);
    });
  }
  test('local suspension blocks a valid Firebase identity', () async {
    expect((await exchange(jwt())).statusCode, 200);
    app.database.db.execute('UPDATE users SET disabled=1');
    final count = app.database.db
        .select('SELECT token_hash FROM sessions')
        .length;
    expect((await exchange(jwt())).statusCode, 401);
    expect(
      app.database.db.select('SELECT token_hash FROM sessions'),
      hasLength(count),
    );
  });
  test(
    'new production Firebase account requires current consent and rolls back on failure',
    () async {
      // Reuse the same HTTP fixture with a production server and no fake mail.
      final production = MarketplaceServer(
        ServerConfig(
          databasePath: ':memory:',
          production: true,
          seedDemo: false,
          paymentMode: 'disabled',
          firebaseAuthProjectId: 'savefood-test',
          firebaseAuthApiKey: 'test-public-api-key',
          firebaseGoogleEnabled: true,
        ),
        clock: () => now,
        authClient: app.auth.client,
      );
      addTearDown(production.close);
      app.legal.save({
        'revision': 0,
        'operator': 'Test operator',
        'registration': '12345678',
        'address': 'Test street 1',
        'contact': 'test@example.test',
        'terms': 'Terms for test registration. ' * 10,
        'privacy': 'Privacy for test registration. ' * 10,
        'retention': {
          'orders': 3650,
          'support': 365,
          'accountAudit': 365,
          'mail': 30,
          'mediaDraftHours': 24,
        },
      }, publish: true);
      production.legal.save({
        ...app.legal.current(),
        'revision': 0,
      }, publish: true);
      Future<Response> request(Map<String, dynamic>? c) async =>
          production.handler(
            Request(
              'POST',
              Uri.parse('http://localhost/v1/auth/firebase'),
              headers: {'content-type': 'application/json'},
              body: jsonEncode({
                'idToken': jwt(),
                'provider': 'google',
                'legalConsent': ?c,
              }),
            ),
          );
      expect((await request(null)).statusCode, 428);
      expect(production.database.db.select('SELECT id FROM users'), isEmpty);
      expect((await request({'version': 0, 'accepted': true})).statusCode, 409);
      expect(production.database.db.select('SELECT id FROM users'), isEmpty);
      expect((await request({'version': 1, 'accepted': true})).statusCode, 200);
      expect(
        production.database.db.select('SELECT user_id FROM legal_acceptances'),
        hasLength(1),
      );
      expect(
        (await request(null)).statusCode,
        200,
      ); // Existing identity needs no new registration.
    },
  );
  test('unconfigured Firebase route fails closed', () async {
    final disabled = MarketplaceServer(
      const ServerConfig(databasePath: ':memory:', seedDemo: false),
    );
    addTearDown(disabled.close);
    final response = await disabled.handler(
      Request(
        'POST',
        Uri.parse('http://localhost/v1/auth/firebase'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({'idToken': jwt(), 'provider': 'google'}),
      ),
    );
    expect(response.statusCode, 503);
    expect(disabled.database.db.select('SELECT id FROM users'), isEmpty);
  });
}

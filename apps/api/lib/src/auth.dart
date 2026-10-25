import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';
import 'package:http/http.dart' as http;
import 'package:jose/jose.dart';
import 'package:uuid/uuid.dart';
import 'config.dart';
import 'database.dart';
import 'payments.dart';
part 'firebase_auth.dart';

class ApiFailure implements Exception {
  const ApiFailure(this.status, this.message);
  final int status;
  final String message;
}

String hashToken(String value) =>
    crypto.sha256.convert(utf8.encode(value)).toString();
String randomSecret([int bytes = 32]) => base64UrlEncode(
  List.generate(bytes, (_) => Random.secure().nextInt(256)),
).replaceAll('=', '');
String stringField(Map<String, dynamic> body, String key, {int max = 250}) {
  final value = body[key];
  if (value is! String || value.length > max) {
    throw ApiFailure(400, 'Neplatné pole: $key.');
  }
  return value.trim();
}

class AuthService {
  AuthService(
    this.database,
    this.config, {
    http.Client? client,
    DateTime Function()? clock,
  }) : client = client ?? http.Client(),
       clock = clock ?? DateTime.now;
  final MarketplaceDatabase database;
  final ServerConfig config;
  final http.Client client;
  final DateTime Function() clock;
  final _passwordAlgorithm = Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: 210000,
    bits: 256,
  );
  final Map<String, ({int attempts, DateTime until})> _limits = {};
  late final firebase = FirebaseIdentityVerifier(config, client, clock: clock);
  void rateLimit(String key) {
    final now = clock();
    _limits.removeWhere((_, v) => v.until.isBefore(now));
    final previous = _limits[key];
    if (previous != null && previous.attempts >= 12) {
      throw const ApiFailure(429, 'Príliš veľa pokusov. Skús to o 15 minút.');
    }
    _limits[key] = (
      attempts: (previous?.attempts ?? 0) + 1,
      until: previous?.until ?? now.add(const Duration(minutes: 15)),
    );
  }

  Future<String> _passwordHash(String password, String salt) async {
    final key = await _passwordAlgorithm.deriveKey(
      secretKey: SecretKey(utf8.encode(password)),
      nonce: base64Url.decode(base64Url.normalize(salt)),
    );
    return base64UrlEncode(await key.extractBytes());
  }

  Future<(String, String)> encodePassword(String password) async {
    if (password.length < 12 || password.length > 128) {
      throw const ApiFailure(400, 'Heslo musí mať 12 až 128 znakov.');
    }
    final salt = randomSecret(16);
    return (await _passwordHash(password, salt), salt);
  }

  Future<void> checkPassword(String id, Object? password) async {
    final current = user(id);
    if (password is! String ||
        password.length > 128 ||
        current['salt'] == null) {
      throw const ApiFailure(
        403,
        'Over zmenu aktuálnym heslom alebo e-mailovým kódom.',
      );
    }
    final actual = await _passwordHash(password, current['salt'] as String);
    if (!constantTimeEqual(
          utf8.encode(actual),
          utf8.encode(current['password_hash'] as String? ?? ''),
        ) ||
        user(id)['password_hash'] != current['password_hash']) {
      throw const ApiFailure(403, 'Aktuálne heslo nie je správne.');
    }
  }

  Map<String, dynamic> user(String id) {
    final rows = database.db.select('SELECT * FROM users WHERE id=?', [id]);
    final result = rows.isEmpty ? null : Map<String, dynamic>.from(rows.first);
    if (result == null ||
        result['disabled'] == 1 ||
        result['deleted_at'] != null) {
      throw const ApiFailure(401, 'Prihlás sa znova.');
    }
    return result;
  }

  String requireUser(String? authorization) {
    if (authorization == null || !authorization.startsWith('Bearer ')) {
      throw const ApiFailure(401, 'Pre túto akciu sa prihlás.');
    }
    final rows = database.db.select(
      'SELECT user_id FROM sessions WHERE token_hash=? AND expires>?',
      [
        hashToken(authorization.substring(7)),
        clock().toUtc().toIso8601String(),
      ],
    );
    if (rows.isEmpty) {
      throw const ApiFailure(401, 'Prihlásenie vypršalo. Prihlás sa znova.');
    }
    final id = rows.first['user_id'] as String;
    user(id);
    return id;
  }

  Map<String, dynamic> createSession(String userId) {
    user(userId);
    final token = randomSecret();
    database.db.execute(
      'INSERT INTO sessions(token_hash,user_id,expires) VALUES(?,?,?)',
      [
        hashToken(token),
        userId,
        clock().add(const Duration(days: 30)).toUtc().toIso8601String(),
      ],
    );
    return {'token': token, 'userId': userId};
  }

  Future<Map<String, dynamic>> register(Map<String, dynamic> body) async {
    final email = stringField(body, 'email').toLowerCase();
    final name = stringField(body, 'name');
    final password = body['password'];
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email) ||
        name.length < 2 ||
        password is! String ||
        password.length < 12 ||
        password.length > 128) {
      throw const ApiFailure(
        400,
        'Zadaj meno, platný e-mail a heslo s aspoň 12 znakmi.',
      );
    }
    if (database.db.select('SELECT id FROM users WHERE email=?', [
      email,
    ]).isNotEmpty) {
      throw const ApiFailure(
        409,
        'Tento e-mail už má účet. Použi prihlásenie.',
      );
    }
    final salt = randomSecret(16);
    final passwordHash = await _passwordHash(password, salt);
    final id = const Uuid().v4();
    // Check uniqueness again after the asynchronous password hash.
    return database.transaction(() {
      if (database.db.select('SELECT id FROM users WHERE email=?', [
        email,
      ]).isNotEmpty) {
        throw const ApiFailure(409, 'Tento e-mail už má účet.');
      }
      database.db.execute(
        'INSERT INTO users(id,email,name,password_hash,salt) VALUES(?,?,?,?,?)',
        [id, email, name, passwordHash, salt],
      );
      return createSession(id);
    });
  }

  Future<Map<String, dynamic>> login(Map<String, dynamic> body) async {
    final email = stringField(body, 'email').toLowerCase();
    final password = body['password'];
    if (password is! String || password.length > 128) {
      throw const ApiFailure(400, 'Neplatné heslo.');
    }
    final rows = database.db.select(
      'SELECT id,password_hash,salt FROM users WHERE email=?',
      [email],
    );
    // Perform the same expensive operation even if the user is unknown.
    final salt = rows.isEmpty || rows.first['salt'] == null
        ? base64UrlEncode(List.filled(16, 0))
        : rows.first['salt'] as String;
    final actual = await _passwordHash(password, salt);
    final expected = rows.isEmpty
        ? ''
        : rows.first['password_hash'] as String? ?? '';
    if (!constantTimeEqual(utf8.encode(actual), utf8.encode(expected))) {
      throw const ApiFailure(401, 'E-mail alebo heslo nie je správne.');
    }
    return createSession(rows.first['id'] as String);
  }

  void logout(String? authorization) {
    if (authorization?.startsWith('Bearer ') ?? false) {
      database.db.execute('DELETE FROM sessions WHERE token_hash=?', [
        hashToken(authorization!.substring(7)),
      ]);
    }
  }

  Map<String, bool> get providers => {
    'google':
        config.googleClientId.isNotEmpty &&
        config.googleClientSecret.isNotEmpty,
    'apple':
        config.appleClientId.isNotEmpty && config.appleClientSecret.isNotEmpty,
    'facebook':
        config.facebookAppId.isNotEmpty && config.facebookAppSecret.isNotEmpty,
  };
  Map<String, dynamic> beginOAuth(String provider) {
    if (providers[provider] != true) {
      throw const ApiFailure(
        503,
        'Tento poskytovateľ ešte nie je nakonfigurovaný. Použi e-mail.',
      );
    }
    final id = const Uuid().v4(),
        poll = randomSecret(),
        state = randomSecret(),
        nonce = randomSecret();
    database.db.execute(
      'INSERT INTO oauth_handoffs(id,poll_hash,state_hash,provider,nonce,expires) VALUES(?,?,?,?,?,?)',
      [
        id,
        hashToken(poll),
        hashToken(state),
        provider,
        nonce,
        clock().add(const Duration(minutes: 10)).toUtc().toIso8601String(),
      ],
    );
    final callback = '${config.publicUrl}/v1/auth/oauth/$provider/callback';
    final url = switch (provider) {
      'google' => Uri.https('accounts.google.com', '/o/oauth2/v2/auth', {
        'client_id': config.googleClientId,
        'redirect_uri': callback,
        'response_type': 'code',
        'scope': 'openid email profile',
        'state': state,
        'nonce': nonce,
      }),
      'apple' => Uri.https('appleid.apple.com', '/auth/authorize', {
        'client_id': config.appleClientId,
        'redirect_uri': callback,
        'response_type': 'code',
        'response_mode': 'form_post',
        'scope': 'name email',
        'state': state,
        'nonce': nonce,
      }),
      _ => Uri.https('www.facebook.com', '/v23.0/dialog/oauth', {
        'client_id': config.facebookAppId,
        'redirect_uri': callback,
        'response_type': 'code',
        'scope': 'email,public_profile',
        'state': state,
      }),
    };
    return {'id': id, 'pollSecret': poll, 'url': url.toString()};
  }

  Future<void> finishOAuth(String provider, Map<String, String> params) async {
    final rows = database.db.select(
      'SELECT * FROM oauth_handoffs WHERE state_hash=? AND provider=? AND expires>? AND consumed=0',
      [
        hashToken(params['state'] ?? ''),
        provider,
        clock().toUtc().toIso8601String(),
      ],
    );
    if (rows.isEmpty || params['code'] == null) {
      throw const ApiFailure(
        400,
        'Prihlásenie sa nepodarilo overiť. Začni znova.',
      );
    }
    final handoff = rows.first;
    final callback = '${config.publicUrl}/v1/auth/oauth/$provider/callback';
    String subject, email, name;
    if (provider == 'facebook') {
      final tokenResponse = await client
          .get(
            Uri.https('graph.facebook.com', '/v23.0/oauth/access_token', {
              'client_id': config.facebookAppId,
              'client_secret': config.facebookAppSecret,
              'redirect_uri': callback,
              'code': params['code']!,
            }),
          )
          .timeout(const Duration(seconds: 15));
      final access = (jsonDecode(tokenResponse.body) as Map)['access_token'];
      if (tokenResponse.statusCode != 200 || access is! String) {
        throw const ApiFailure(401, 'Facebook prihlásenie zlyhalo.');
      }
      final proof = crypto.Hmac(
        crypto.sha256,
        utf8.encode(config.facebookAppSecret),
      ).convert(utf8.encode(access)).toString();
      final profileResponse = await client
          .get(
            Uri.https('graph.facebook.com', '/v23.0/me', {
              'fields': 'id,name,email',
              'appsecret_proof': proof,
            }),
            headers: {'Authorization': 'Bearer $access'},
          )
          .timeout(const Duration(seconds: 15));
      if (profileResponse.statusCode != 200) {
        throw const ApiFailure(401, 'Profil sa nepodarilo overiť.');
      }
      final profile = jsonDecode(profileResponse.body) as Map;
      subject = profile['id'] as String;
      email = profile['email'] as String? ?? '';
      name = profile['name'] as String? ?? 'Záchranca';
    } else {
      final apple = provider == 'apple';
      final response = await client
          .post(
            Uri.parse(
              apple
                  ? 'https://appleid.apple.com/auth/token'
                  : 'https://oauth2.googleapis.com/token',
            ),
            body: {
              'grant_type': 'authorization_code',
              'code': params['code']!,
              'redirect_uri': callback,
              'client_id': apple ? config.appleClientId : config.googleClientId,
              'client_secret': apple
                  ? config.appleClientSecret
                  : config.googleClientSecret,
            },
          )
          .timeout(const Duration(seconds: 15));
      final body = jsonDecode(response.body) as Map;
      if (response.statusCode != 200 || body['id_token'] is! String) {
        throw const ApiFailure(401, 'Poskytovateľ odmietol prihlásenie.');
      }
      final raw = body['id_token'] as String;
      final header =
          jsonDecode(
                utf8.decode(
                  base64Url.decode(base64Url.normalize(raw.split('.').first)),
                ),
              )
              as Map;
      if (header['alg'] != 'RS256') {
        throw const ApiFailure(401, 'Neplatný podpis identity.');
      }
      final token = JsonWebToken.unverified(raw);
      final keys = JsonWebKeyStore()
        ..addKeySetUrl(
          Uri.parse(
            apple
                ? 'https://appleid.apple.com/auth/keys'
                : 'https://www.googleapis.com/oauth2/v3/certs',
          ),
        );
      if (!await token.verify(keys)) {
        throw const ApiFailure(401, 'Podpis identity sa nepodarilo overiť.');
      }
      final claims = token.claims.toJson();
      final expectedIssuer = apple
          ? 'https://appleid.apple.com'
          : 'https://accounts.google.com';
      final audience = apple ? config.appleClientId : config.googleClientId;
      if (claims['iss'] != expectedIssuer ||
          claims['aud'] != audience ||
          claims['nonce'] != handoff['nonce'] ||
          claims['exp'] is! num ||
          (claims['exp'] as num) * 1000 <= clock().millisecondsSinceEpoch ||
          !(claims['email_verified'] == true ||
              claims['email_verified'] == 'true')) {
        throw const ApiFailure(401, 'Identita nemá platné overené údaje.');
      }
      subject = claims['sub'] as String;
      email = claims['email'] as String? ?? '';
      name = claims['name'] as String? ?? 'Záchranca';
    }
    if (email.isEmpty) {
      throw const ApiFailure(
        400,
        'Poskytovateľ neposkytol e-mail. Použi e-mailové prihlásenie.',
      );
    }
    database.transaction(() {
      final identities = database.db.select(
        'SELECT user_id FROM identities WHERE provider=? AND subject=?',
        [provider, subject],
      );
      String userId;
      if (identities.isNotEmpty) {
        userId = identities.first['user_id'] as String;
      } else {
        if (database.db.select('SELECT id FROM users WHERE email=?', [
          email.toLowerCase(),
        ]).isNotEmpty) {
          throw const ApiFailure(
            409,
            'Účet s týmto e-mailom už existuje. Použi jeho pôvodný spôsob prihlásenia.',
          );
        }
        userId = const Uuid().v4();
        database.db.execute('INSERT INTO users(id,email,name) VALUES(?,?,?)', [
          userId,
          email.toLowerCase(),
          name,
        ]);
        database.db.execute(
          'INSERT INTO identities(provider,subject,user_id) VALUES(?,?,?)',
          [provider, subject, userId],
        );
      }
      database.db.execute(
        'UPDATE oauth_handoffs SET user_id=? WHERE id=? AND consumed=0',
        [userId, handoff['id']],
      );
      if (provider == 'google' || provider == 'apple') {
        database.db.execute('UPDATE users SET email_verified=1 WHERE id=?', [
          userId,
        ]);
      }
    });
  }

  Map<String, dynamic> pollOAuth(String id, String secret) {
    final rows = database.db.select(
      'SELECT * FROM oauth_handoffs WHERE id=? AND poll_hash=? AND expires>? AND consumed=0',
      [id, hashToken(secret), clock().toUtc().toIso8601String()],
    );
    if (rows.isEmpty) {
      throw const ApiFailure(401, 'Prihlásenie vypršalo. Začni znova.');
    }
    if (rows.first['user_id'] == null) return {'pending': true};
    return database.transaction(() {
      database.db.execute('UPDATE oauth_handoffs SET consumed=1 WHERE id=?', [
        id,
      ]);
      return createSession(rows.first['user_id'] as String);
    });
  }
}

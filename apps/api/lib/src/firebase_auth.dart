part of 'auth.dart';

/// Only Google-signed Firebase ID tokens from the configured project are accepted.
/// The live lookup checks account deletion, disablement and token revocation too.
class FirebaseIdentityVerifier {
  FirebaseIdentityVerifier(
    this.config,
    this.client, {
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now;
  final ServerConfig config;
  final http.Client client;
  final DateTime Function() clock;
  Map<String, JsonWebKey> _keys = {};
  DateTime _expires = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastFetch = DateTime.fromMillisecondsSinceEpoch(0);
  Future<void>? _fetching;
  bool enabled(String provider) =>
      config.firebaseAuthEnabled &&
      switch (provider) {
        'google' => config.firebaseGoogleEnabled,
        'apple' => config.firebaseAppleEnabled,
        _ => false,
      };

  Future<void> _loadKeys() async {
    if (_fetching != null) return _fetching;
    if (clock().difference(_lastFetch) < const Duration(seconds: 15)) return;
    _lastFetch = clock();
    final pending = () async {
      final response = await client
          .get(
            Uri.parse(
              'https://www.googleapis.com/robot/v1/metadata/x509/securetoken@system.gserviceaccount.com',
            ),
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        throw const ApiFailure(
          503,
          'Overenie prihlásenia je dočasne nedostupné.',
        );
      }
      final body = jsonDecode(response.body) as Map;
      final keys = <String, JsonWebKey>{};
      for (final entry in body.entries) {
        keys[entry.key as String] = JsonWebKey.fromPem(
          entry.value as String,
          keyId: entry.key as String,
        );
      }
      if (keys.isEmpty) {
        throw const ApiFailure(
          503,
          'Overenie prihlásenia je dočasne nedostupné.',
        );
      }
      final maxAge =
          int.tryParse(
            RegExp(r'max-age=(\d+)')
                    .firstMatch(response.headers['cache-control'] ?? '')
                    ?.group(1) ??
                '',
          ) ??
          300;
      _keys = keys;
      _expires = clock().add(Duration(seconds: maxAge.clamp(0, 86400)));
    }();
    _fetching = pending;
    try {
      await pending;
    } finally {
      _fetching = null;
    }
  }

  Future<Map<String, String>> verify(String raw, String provider) async {
    if (!enabled(provider)) {
      throw const ApiFailure(
        503,
        'Tento spôsob prihlásenia ešte nie je aktivovaný.',
      );
    }
    try {
      if (raw.length > 16384 || raw.split('.').length != 3) {
        throw const FormatException();
      }
      final header =
          jsonDecode(
                utf8.decode(
                  base64Url.decode(base64Url.normalize(raw.split('.').first)),
                ),
              )
              as Map;
      if (header['alg'] != 'RS256' || header['kid'] is! String) {
        throw const FormatException();
      }
      final token = JsonWebToken.unverified(raw);
      final c = token.claims.toJson();
      final now = clock().millisecondsSinceEpoch ~/ 1000;
      final sub = c['sub'],
          exp = c['exp'],
          iat = c['iat'],
          authTime = c['auth_time'];
      final firebase = c['firebase'];
      if (sub is! String ||
          sub.isEmpty ||
          sub.length > 128 ||
          exp is! int ||
          exp <= now ||
          iat is! int ||
          iat > now + 30 ||
          authTime is! int ||
          authTime > now + 30 ||
          now - authTime > 600 ||
          iat < authTime ||
          exp <= iat ||
          c['aud'] != config.firebaseAuthProjectId ||
          c['iss'] !=
              'https://securetoken.google.com/${config.firebaseAuthProjectId}' ||
          c['email_verified'] != true ||
          firebase is! Map ||
          firebase['tenant'] != null ||
          firebase['sign_in_provider'] != '$provider.com') {
        throw const FormatException();
      }
      if (clock().isAfter(_expires) || !_keys.containsKey(header['kid'])) {
        await _loadKeys();
      }
      final key = _keys[header['kid']];
      if (key == null || !clock().isBefore(_expires)) {
        throw const ApiFailure(
          503,
          'Overenie prihlásenia je dočasne nedostupné. Skús znova.',
        );
      }
      final store = JsonWebKeyStore()..addKey(key);
      if (!await token.verify(store)) throw const FormatException();
      final response = await client
          .post(
            Uri.https('identitytoolkit.googleapis.com', '/v1/accounts:lookup', {
              'key': config.firebaseAuthApiKey,
            }),
            headers: {'content-type': 'application/json'},
            body: jsonEncode({'idToken': raw}),
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode >= 500 || response.statusCode == 429) {
        throw const ApiFailure(
          503,
          'Prihlásenie je dočasne nedostupné. Skús znova.',
        );
      }
      if (response.statusCode != 200) throw const FormatException();
      final users = (jsonDecode(response.body) as Map)['users'];
      if (users is! List || users.length != 1) throw const FormatException();
      final u = users.single as Map;
      final since = int.tryParse(u['validSince']?.toString() ?? '');
      final email = u['email'];
      if (u['localId'] != sub ||
          u['disabled'] == true ||
          u['emailVerified'] != true ||
          since == null ||
          authTime < since ||
          email is! String ||
          email.length > 250 ||
          !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email) ||
          c['email'] is! String ||
          (c['email'] as String).toLowerCase() != email.toLowerCase() ||
          !((u['providerUserInfo'] as List?) ?? []).any(
            (p) => p is Map && p['providerId'] == '$provider.com',
          )) {
        throw const FormatException();
      }
      final suppliedName = u['displayName'];
      return {
        'uid': sub,
        'email': email.toLowerCase(),
        'name': suppliedName is String && suppliedName.trim().length >= 2
            ? suppliedName.trim().substring(
                0,
                min(suppliedName.trim().length, 100),
              )
            : 'Záchranca',
      };
    } on ApiFailure {
      rethrow;
    } on FormatException {
      throw const ApiFailure(
        401,
        'Prihlásenie sa nepodarilo overiť. Prihlás sa znova.',
      );
    } catch (_) {
      throw const ApiFailure(
        503,
        'Overenie prihlásenia je dočasne nedostupné. Skús znova.',
      );
    }
  }
}

extension FirebaseLogin on AuthService {
  Future<Map<String, dynamic>> loginFirebase(
    Map<String, dynamic> body, {
    void Function()? beforeCreate,
    void Function(String id)? afterCreate,
  }) async {
    final provider = stringField(body, 'provider'),
        raw = stringField(body, 'idToken', max: 16384);
    final identity = await firebase.verify(raw, provider);
    return database.transaction(() {
      final namespace = 'firebase:${config.firebaseAuthProjectId}';
      final existing = database.db.select(
        'SELECT user_id FROM identities WHERE provider=? AND subject=?',
        [namespace, identity['uid']],
      );
      if (existing.isNotEmpty) {
        final id = existing.first['user_id'] as String;
        user(id); // Includes local suspension and erasure checks.
        return {...createSession(id), 'created': false};
      }
      if (database.db.select('SELECT id FROM users WHERE email=?', [
        identity['email'],
      ]).isNotEmpty) {
        throw const ApiFailure(
          409,
          'Účet s týmto e-mailom už existuje. Použi jeho pôvodný spôsob prihlásenia.',
        );
      }
      beforeCreate?.call();
      final id = const Uuid().v4();
      database.db.execute(
        'INSERT INTO users(id,email,name,email_verified) VALUES(?,?,?,1)',
        [id, identity['email'], identity['name']],
      );
      database.db.execute(
        'INSERT INTO identities(provider,subject,user_id) VALUES(?,?,?)',
        [namespace, identity['uid'], id],
      );
      afterCreate?.call(id);
      return {...createSession(id), 'created': true};
    });
  }
}

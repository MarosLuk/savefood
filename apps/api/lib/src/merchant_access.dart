part of 'merchant.dart';

extension MerchantAccess on MerchantService {
  void initializeAccess() => database.db.execute('''
    CREATE TABLE IF NOT EXISTS platform_organizations(org_id TEXT PRIMARY KEY REFERENCES merchant_organizations(id),status TEXT NOT NULL,reason TEXT NOT NULL,updated_at TEXT NOT NULL);
    CREATE TABLE IF NOT EXISTS platform_stores(store_id TEXT PRIMARY KEY REFERENCES merchant_stores(id),paused INTEGER NOT NULL DEFAULT 0,reason TEXT NOT NULL);
    CREATE TABLE IF NOT EXISTS platform_offers(offer_id TEXT PRIMARY KEY REFERENCES offers(id) ON DELETE CASCADE,hidden INTEGER NOT NULL DEFAULT 0,reason TEXT NOT NULL);
    CREATE TABLE IF NOT EXISTS merchant_member_scopes(org_id TEXT NOT NULL,user_id TEXT NOT NULL,all_stores INTEGER NOT NULL DEFAULT 1,
      PRIMARY KEY(org_id,user_id),FOREIGN KEY(org_id,user_id) REFERENCES merchant_members(org_id,user_id) ON DELETE CASCADE);
    CREATE TABLE IF NOT EXISTS merchant_member_stores(org_id TEXT NOT NULL,user_id TEXT NOT NULL,store_id TEXT NOT NULL REFERENCES merchant_stores(id),
      PRIMARY KEY(org_id,user_id,store_id),FOREIGN KEY(org_id,user_id) REFERENCES merchant_members(org_id,user_id) ON DELETE CASCADE);
    CREATE TABLE IF NOT EXISTS merchant_invites(id TEXT PRIMARY KEY,org_id TEXT NOT NULL REFERENCES merchant_organizations(id),email TEXT NOT NULL,
      role TEXT NOT NULL,store_ids TEXT,token_hash TEXT NOT NULL,expires TEXT NOT NULL,revoked INTEGER NOT NULL DEFAULT 0,accepted_by TEXT,created_at TEXT NOT NULL);
  ''');
  bool canAccessStore(String user, String store) => _rows(
    '''SELECT m.user_id FROM merchant_members m JOIN merchant_stores s ON s.org_id=m.org_id
    LEFT JOIN merchant_member_scopes p ON p.org_id=m.org_id AND p.user_id=m.user_id
    WHERE m.user_id=? AND s.id=? AND (m.role='owner' OR COALESCE(p.all_stores,1)=1 OR EXISTS(SELECT 1 FROM merchant_member_stores a WHERE a.org_id=m.org_id AND a.user_id=m.user_id AND a.store_id=s.id))''',
    [user, store],
  ).isNotEmpty;
  void setMemberScope(String org, String member, Map<String, dynamic> body) {
    if (!body.containsKey('storeIds')) return;
    final value = body['storeIds'];
    if (value != null && value is! List) {
      throw const ApiFailure(400, 'Vyber pobočky.');
    }
    final stores = (value as List?)?.cast<String>().toSet().toList();
    if (stores != null && (stores.isEmpty || stores.length > 1000)) {
      throw const ApiFailure(
        400,
        'Priraď aspoň jednu pobočku alebo všetky pobočky.',
      );
    }
    for (final id in stores ?? <String>[]) {
      if (_rows('SELECT id FROM merchant_stores WHERE id=? AND org_id=?', [
        id,
        org,
      ]).isEmpty) {
        throw const ApiFailure(403, 'Pobočka nepatrí firme.');
      }
    }
    database.db.execute(
      'INSERT INTO merchant_member_scopes VALUES(?,?,?) ON CONFLICT(org_id,user_id) DO UPDATE SET all_stores=excluded.all_stores',
      [org, member, stores == null ? 1 : 0],
    );
    database.db.execute(
      'DELETE FROM merchant_member_stores WHERE org_id=? AND user_id=?',
      [org, member],
    );
    for (final id in stores ?? <String>[]) {
      database.db.execute('INSERT INTO merchant_member_stores VALUES(?,?,?)', [
        org,
        member,
        id,
      ]);
    }
  }

  Map<String, dynamic> invite(
    String user,
    Map<String, dynamic> body,
  ) => database.transaction(() {
    final org = _text(body, 'organizationId');
    _org(user, org, owner: true);
    final email = _text(body, 'email').toLowerCase(),
        role = _text(body, 'role');
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email) ||
        !{'staff', 'manager'}.contains(role)) {
      throw const ApiFailure(400, 'Zadaj e-mail a rolu.');
    }
    if (mail == null || !mail!.gateway.configured && !allowDemoImages) {
      throw const ApiFailure(503, 'Najprv nakonfiguruj doručovanie e-mailov.');
    }
    final storeIds = body['storeIds'] as List?;
    if (storeIds != null && (storeIds.isEmpty || storeIds.length > 1000)) {
      throw const ApiFailure(400, 'Vyber pobočky.');
    }
    for (final id in storeIds ?? []) {
      if (_rows('SELECT id FROM merchant_stores WHERE id=? AND org_id=?', [
        id,
        org,
      ]).isEmpty) {
        throw const ApiFailure(403, 'Cudzia pobočka.');
      }
    }
    final id = _id(),
        token = randomSecret(),
        expires = clock()
            .toUtc()
            .add(const Duration(days: 7))
            .toIso8601String();
    database.db.execute(
      'UPDATE merchant_invites SET revoked=1 WHERE org_id=? AND email=? AND accepted_by IS NULL',
      [org, email],
    );
    database.db.execute(
      'INSERT INTO merchant_invites(id,org_id,email,role,store_ids,token_hash,expires,created_at) VALUES(?,?,?,?,?,?,?,?)',
      [
        id,
        org,
        email,
        role,
        storeIds == null ? null : jsonEncode(storeIds),
        hashToken(token),
        expires,
        _now,
      ],
    );
    final link = Uri.parse(appUrl).replace(
      fragment: Uri(
        queryParameters: {'merchantInvite': id, 'inviteToken': token},
      ).query,
    );
    // The API returns the invite identity, never its bearer secret. Only email contains the link.
    mail!.enqueue(
      user,
      email,
      'Save Food · Pozvánka do tímu',
      'Dostal/a si pozvánku do firmy ${_org(user, org)['name']}. Prihlás sa overeným účtom s touto adresou.\n\nOtvoriť pozvánku: $link\nIdentifikátor pozvánky: $id\nKód pozvánky: $token\n\nPozvánka platí 7 dní.',
      dedupe: 'invite/$id',
    );
    return {'id': id, 'email': email, 'expires': expires};
  });
  Map<String, dynamic> acceptInvite(String user, Map<String, dynamic> body) =>
      database.transaction(() {
        final id = _text(body, 'inviteId'), token = _text(body, 'token');
        final r = _one('SELECT * FROM merchant_invites WHERE id=?', [id]);
        final account = _one(
          'SELECT email,email_verified FROM users WHERE id=?',
          [user],
        );
        if (r['revoked'] == 1 ||
            r['accepted_by'] != null ||
            (r['expires'] as String).compareTo(_now) <= 0 ||
            r['token_hash'] != hashToken(token) ||
            account['email'] != r['email'] ||
            account['email_verified'] != 1) {
          throw const ApiFailure(
            403,
            'Pozvánka nie je platná pre tvoj overený účet.',
          );
        }
        final previous = _rows(
          'SELECT role FROM merchant_members WHERE org_id=? AND user_id=?',
          [r['org_id'], user],
        );
        if (previous.isNotEmpty) {
          throw const ApiFailure(
            409,
            'Už si členom tímu. Práva upraví vlastník.',
          );
        }
        database.db.execute('INSERT INTO merchant_members VALUES(?,?,?)', [
          r['org_id'],
          user,
          r['role'],
        ]);
        setMemberScope(r['org_id'] as String, user, {
          'storeIds': r['store_ids'] == null
              ? null
              : jsonDecode(r['store_ids'] as String),
        });
        database.db.execute(
          'UPDATE merchant_invites SET accepted_by=? WHERE id=?',
          [user, id],
        );
        return {'accepted': true, 'organizationId': r['org_id']};
      });
  Map<String, dynamic> accessOverview(String user, String org) {
    _org(user, org, owner: true);
    return {
      'members':
          _rows(
                '''SELECT m.user_id,m.role,u.email,u.name,COALESCE(p.all_stores,1) all_stores FROM merchant_members m
      JOIN users u ON u.id=m.user_id LEFT JOIN merchant_member_scopes p ON p.org_id=m.org_id AND p.user_id=m.user_id WHERE m.org_id=?''',
                [org],
              )
              .map(
                (m) => {
                  ...m,
                  'storeIds': m['all_stores'] == 1
                      ? null
                      : _rows(
                          'SELECT store_id FROM merchant_member_stores WHERE org_id=? AND user_id=?',
                          [org, m['user_id']],
                        ).map((s) => s['store_id']).toList(),
                },
              )
              .toList(),
      'invites': _rows(
        'SELECT id,email,role,store_ids,expires,revoked,accepted_by FROM merchant_invites WHERE org_id=? ORDER BY rowid DESC LIMIT 100',
        [org],
      ),
    };
  }

  Map<String, dynamic> revokeInvite(String user, String id) =>
      database.transaction(() {
        final r = _one('SELECT org_id FROM merchant_invites WHERE id=?', [id]);
        _org(user, r['org_id'] as String, owner: true);
        database.db.execute(
          'UPDATE merchant_invites SET revoked=1 WHERE id=?',
          [id],
        );
        return {'revoked': true};
      });
  Map<String, dynamic> transferOwnership(
    String user,
    Map<String, dynamic> body,
  ) => database.transaction(() {
    final org = _text(body, 'organizationId');
    _org(user, org, owner: true);
    final email = _text(body, 'email').toLowerCase();
    final target =
        _one(
              'SELECT m.user_id FROM merchant_members m JOIN users u ON u.id=m.user_id WHERE m.org_id=? AND u.email=? AND u.email_verified=1 AND u.disabled=0',
              [org, email],
            )['user_id']
            as String;
    if (target == user) {
      throw const ApiFailure(400, 'Vyber iného overeného člena tímu.');
    }
    database.db.execute(
      "UPDATE merchant_members SET role='manager' WHERE org_id=? AND user_id=?",
      [org, user],
    );
    database.db.execute(
      "UPDATE merchant_members SET role='owner' WHERE org_id=? AND user_id=?",
      [org, target],
    );
    setMemberScope(org, target, {'storeIds': null});
    return {'transferred': true, 'ownerId': target};
  });
}

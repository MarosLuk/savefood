part of 'billing.dart';

extension AccountingConnector on BillingService {
  void initializeAccounting() => database.db.execute(
    '''CREATE TABLE IF NOT EXISTS accounting_integrations(id TEXT PRIMARY KEY,scope TEXT NOT NULL,name TEXT NOT NULL,token_hash TEXT NOT NULL UNIQUE,revoked INTEGER NOT NULL DEFAULT 0,acknowledged INTEGER NOT NULL DEFAULT 0,delivered INTEGER NOT NULL DEFAULT 0,created_at TEXT NOT NULL,last_seen TEXT);''',
  );
  List<Map<String, dynamic>> connectors(String scope) => database.db
      .select(
        'SELECT id,name,revoked,acknowledged,created_at,last_seen,(SELECT COUNT(*) FROM billing_documents d WHERE d.scope=i.scope AND d.rowid>i.acknowledged) pending FROM accounting_integrations i WHERE scope=? ORDER BY rowid DESC LIMIT 50',
        [scope],
      )
      .map((r) => Map<String, dynamic>.from(r))
      .toList();
  Map<String, dynamic> createConnector(String scope, Map<String, dynamic> b) {
    final name = stringField(b, 'name', max: 100);
    if (name.length < 2) {
      throw const ApiFailure(400, 'Pomenuj účtovné pripojenie.');
    }
    final id = const Uuid().v4(), token = 'nvp_accounting_${randomSecret()}';
    database.db.execute(
      'INSERT INTO accounting_integrations(id,scope,name,token_hash,created_at) VALUES(?,?,?,?,?)',
      [id, scope, name, hashToken(token), now],
    );
    return {'id': id, 'token': token};
  }

  void revokeConnector(String scope, String id) => database.db.execute(
    'UPDATE accounting_integrations SET revoked=1 WHERE id=? AND scope=?',
    [id, scope],
  );
  Map<String, dynamic> accountingIdentity(String? authorization) {
    if (authorization == null ||
        !authorization.startsWith('Bearer nvp_accounting_')) {
      throw const ApiFailure(401, 'Chýba účtovný token.');
    }
    final row = database.db.select(
      'SELECT * FROM accounting_integrations WHERE token_hash=? AND revoked=0',
      [hashToken(authorization.substring(7))],
    ).firstOrNull;
    if (row == null) {
      throw const ApiFailure(401, 'Účtovný token nie je platný.');
    }
    if (row['scope'] != 'platform' &&
        database.db.select(
          "SELECT org_id FROM platform_organizations WHERE org_id=? AND status='suspended'",
          [row['scope']],
        ).isNotEmpty) {
      throw const ApiFailure(403, 'Firma je pozastavená.');
    }
    return Map<String, dynamic>.from(row);
  }

  Map<String, dynamic> accountingPage(
    String? authorization,
  ) => database.transaction(() {
    final i = accountingIdentity(authorization);
    final docs = database.db.select(
      'SELECT rowid cursor,id FROM billing_documents WHERE scope=? AND rowid>? ORDER BY rowid LIMIT 101',
      [i['scope'], i['acknowledged']],
    );
    final page = docs.take(100).toList(),
        through = page.lastOrNull?['cursor'] ?? i['acknowledged'];
    database.db.execute(
      'UPDATE accounting_integrations SET delivered=MAX(delivered,?),last_seen=? WHERE id=?',
      [through, now, i['id']],
    );
    return {
      'schema': 'nevyhadzuj.billing.v1',
      'integrationId': i['id'],
      'through': through,
      'hasMore': docs.length > 100,
      'documents': page
          .map((d) => {...read(d['id'] as String), 'sequence': d['cursor']})
          .toList(),
    };
  });
  Map<String, dynamic> accountingAck(
    String? authorization,
    Map<String, dynamic> b,
  ) {
    final i = accountingIdentity(authorization), n = b['through'];
    if (n is! int || n < 0 || n > (i['delivered'] as int)) {
      throw const ApiFailure(409, 'Doklady sa najprv musia doručiť.');
    }
    database.db.execute(
      'UPDATE accounting_integrations SET acknowledged=MAX(acknowledged,?),last_seen=? WHERE id=?',
      [n, now, i['id']],
    );
    return {'ok': true};
  }
}

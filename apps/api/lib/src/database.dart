import 'dart:convert';
import 'dart:io';
import 'dart:ffi';
import 'package:sqlite3/sqlite3.dart';
import 'package:sqlite3/open.dart' as sqlite_loader;
import 'package:marketplace_domain/marketplace_domain.dart'
    show normalizeSearch;

class MarketplaceDatabase {
  MarketplaceDatabase(String path) : db = _open(path) {
    db.execute('PRAGMA foreign_keys=ON');
    db.execute('PRAGMA journal_mode=WAL');
    db.execute('PRAGMA busy_timeout=5000');
    db.createFunction(
      functionName: 'normalized',
      argumentCount: const AllowedArgumentCount(1),
      deterministic: true,
      // Pure text normalization is safe in the search-maintenance triggers.
      directOnly: false,
      function: (args) => normalizeSearch(args.first?.toString() ?? ''),
    );
    db.execute('''
      CREATE TABLE IF NOT EXISTS users (
        id TEXT PRIMARY KEY, email TEXT NOT NULL UNIQUE, name TEXT NOT NULL,
        password_hash TEXT, salt TEXT, profile TEXT NOT NULL DEFAULT '{}',
        credit INTEGER NOT NULL DEFAULT 0 CHECK(credit>=0), member_until TEXT,
        trial_used INTEGER NOT NULL DEFAULT 0, subscription_id TEXT, subscription_cancelled INTEGER NOT NULL DEFAULT 0);
      CREATE TABLE IF NOT EXISTS sessions (
        token_hash TEXT PRIMARY KEY, user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        expires TEXT NOT NULL);
      CREATE TABLE IF NOT EXISTS offers (id TEXT PRIMARY KEY, payload TEXT NOT NULL, fixture_day TEXT);
      CREATE TABLE IF NOT EXISTS orders (
        id TEXT PRIMARY KEY, user_id TEXT NOT NULL REFERENCES users(id),
        idempotency TEXT NOT NULL, request_hash TEXT NOT NULL, payload TEXT NOT NULL,
        status TEXT NOT NULL, expires TEXT, payment_session TEXT, payment_intent TEXT,
        UNIQUE(user_id,idempotency));
      CREATE INDEX IF NOT EXISTS orders_user ON orders(user_id);
      CREATE TABLE IF NOT EXISTS ledger (
        id TEXT PRIMARY KEY, user_id TEXT NOT NULL REFERENCES users(id),
        order_id TEXT NOT NULL REFERENCES orders(id), kind TEXT NOT NULL,
        amount INTEGER NOT NULL, created_at TEXT NOT NULL, UNIQUE(order_id,kind));
      CREATE TABLE IF NOT EXISTS payment_events (id TEXT PRIMARY KEY, received_at TEXT NOT NULL);
      CREATE TABLE IF NOT EXISTS identities (provider TEXT NOT NULL, subject TEXT NOT NULL,
        user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE, PRIMARY KEY(provider,subject));
      CREATE TABLE IF NOT EXISTS oauth_handoffs (id TEXT PRIMARY KEY, poll_hash TEXT NOT NULL,
        state_hash TEXT NOT NULL UNIQUE, provider TEXT NOT NULL, nonce TEXT NOT NULL,
        expires TEXT NOT NULL, user_id TEXT, consumed INTEGER NOT NULL DEFAULT 0);
      CREATE TABLE IF NOT EXISTS membership_checkouts(user_id TEXT PRIMARY KEY REFERENCES users(id),session_id TEXT NOT NULL,url TEXT NOT NULL,expires TEXT NOT NULL);
      CREATE TABLE IF NOT EXISTS reviews (user_id TEXT NOT NULL REFERENCES users(id), offer_id TEXT NOT NULL,
        rating INTEGER NOT NULL CHECK(rating BETWEEN 1 AND 5), comment TEXT NOT NULL,
        created_at TEXT NOT NULL, PRIMARY KEY(user_id,offer_id));
      CREATE TABLE IF NOT EXISTS devices(token TEXT PRIMARY KEY,user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        session_hash TEXT NOT NULL,platform TEXT NOT NULL);
      CREATE TABLE IF NOT EXISTS push_outbox(id TEXT PRIMARY KEY,token TEXT NOT NULL,user_id TEXT NOT NULL,offer_id TEXT NOT NULL,
        pickup TEXT NOT NULL,title TEXT NOT NULL,body TEXT NOT NULL,attempts INTEGER NOT NULL DEFAULT 0,
        processed INTEGER NOT NULL DEFAULT 0,UNIQUE(token,offer_id,pickup));
      CREATE TABLE IF NOT EXISTS merchant_organizations(id TEXT PRIMARY KEY,name TEXT NOT NULL,
        company_id TEXT NOT NULL,contact_email TEXT NOT NULL,created_at TEXT NOT NULL);
      CREATE TABLE IF NOT EXISTS merchant_members(org_id TEXT NOT NULL REFERENCES merchant_organizations(id),
        user_id TEXT NOT NULL REFERENCES users(id),role TEXT NOT NULL CHECK(role IN ('owner','manager','staff')),
        PRIMARY KEY(org_id,user_id));
      CREATE TABLE IF NOT EXISTS merchant_stores(id TEXT PRIMARY KEY,org_id TEXT NOT NULL REFERENCES merchant_organizations(id),
        payload TEXT NOT NULL);
      CREATE INDEX IF NOT EXISTS merchant_stores_org ON merchant_stores(org_id);
      CREATE TABLE IF NOT EXISTS stock_products(id TEXT PRIMARY KEY,org_id TEXT NOT NULL REFERENCES merchant_organizations(id),
        sku TEXT NOT NULL,payload TEXT NOT NULL,UNIQUE(org_id,sku));
      CREATE TABLE IF NOT EXISTS stock_lots(id TEXT PRIMARY KEY,store_id TEXT NOT NULL REFERENCES merchant_stores(id),
        product_id TEXT NOT NULL REFERENCES stock_products(id),lot_code TEXT NOT NULL,on_hand INTEGER NOT NULL CHECK(on_hand>=0),
        deadline TEXT NOT NULL,date_type TEXT NOT NULL,quality TEXT NOT NULL,version INTEGER NOT NULL DEFAULT 1,
        UNIQUE(store_id,product_id,lot_code));
      CREATE INDEX IF NOT EXISTS stock_lots_store ON stock_lots(store_id,deadline);
      CREATE TABLE IF NOT EXISTS stock_reservations(order_id TEXT NOT NULL REFERENCES orders(id),
        offer_id TEXT NOT NULL REFERENCES offers(id),lot_id TEXT NOT NULL REFERENCES stock_lots(id),
        quantity INTEGER NOT NULL CHECK(quantity>0),state TEXT NOT NULL CHECK(state IN ('held','consumed','released')),
        PRIMARY KEY(order_id,offer_id,lot_id));
      CREATE INDEX IF NOT EXISTS stock_reservations_lot ON stock_reservations(lot_id,state);
      CREATE TABLE IF NOT EXISTS stock_movements(id TEXT PRIMARY KEY,store_id TEXT NOT NULL REFERENCES merchant_stores(id),
        lot_id TEXT NOT NULL REFERENCES stock_lots(id),actor TEXT NOT NULL,kind TEXT NOT NULL,
        physical_delta INTEGER NOT NULL,reserved_delta INTEGER NOT NULL,reason TEXT NOT NULL,created_at TEXT NOT NULL);
      CREATE TABLE IF NOT EXISTS bundle_rules(id TEXT PRIMARY KEY,store_id TEXT NOT NULL REFERENCES merchant_stores(id),
        payload TEXT NOT NULL,enabled INTEGER NOT NULL DEFAULT 1,created_at TEXT NOT NULL);
      CREATE TABLE IF NOT EXISTS merchant_offers(offer_id TEXT PRIMARY KEY REFERENCES offers(id),
        store_id TEXT NOT NULL REFERENCES merchant_stores(id),state TEXT NOT NULL CHECK(state IN ('draft','published','paused')),
        recipe TEXT NOT NULL,rule_id TEXT REFERENCES bundle_rules(id),business_day TEXT,created_at TEXT NOT NULL,
        UNIQUE(rule_id,business_day));
      CREATE INDEX IF NOT EXISTS merchant_offers_store ON merchant_offers(store_id,state);
      CREATE TABLE IF NOT EXISTS merchant_order_lines(order_id TEXT NOT NULL REFERENCES orders(id),
        offer_id TEXT NOT NULL REFERENCES offers(id),store_id TEXT NOT NULL REFERENCES merchant_stores(id),
        quantity INTEGER NOT NULL CHECK(quantity>0),PRIMARY KEY(order_id,offer_id));
      CREATE INDEX IF NOT EXISTS merchant_lines_store ON merchant_order_lines(store_id,order_id);
      CREATE INDEX IF NOT EXISTS merchant_lines_offer ON merchant_order_lines(offer_id,order_id);
      CREATE TABLE IF NOT EXISTS stock_integrations(id TEXT PRIMARY KEY,store_id TEXT NOT NULL REFERENCES merchant_stores(id),
        name TEXT NOT NULL,token_hash TEXT NOT NULL UNIQUE,revoked INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,last_seen TEXT);
      CREATE TABLE IF NOT EXISTS stock_events(integration_id TEXT NOT NULL REFERENCES stock_integrations(id),
        event_id TEXT NOT NULL,request_hash TEXT NOT NULL,response TEXT NOT NULL,created_at TEXT NOT NULL,
        PRIMARY KEY(integration_id,event_id));
      CREATE TABLE IF NOT EXISTS merchant_events(id TEXT PRIMARY KEY,store_id TEXT NOT NULL REFERENCES merchant_stores(id),
        actor TEXT NOT NULL,kind TEXT NOT NULL,detail TEXT NOT NULL,created_at TEXT NOT NULL);
      CREATE TABLE IF NOT EXISTS merchant_requests(user_id TEXT NOT NULL REFERENCES users(id),
        idempotency TEXT NOT NULL,request_hash TEXT NOT NULL,response TEXT NOT NULL,
        PRIMARY KEY(user_id,idempotency));
      CREATE TABLE IF NOT EXISTS stock_sync_versions(integration_id TEXT NOT NULL REFERENCES stock_integrations(id),
        lot_id TEXT NOT NULL REFERENCES stock_lots(id),sequence INTEGER NOT NULL,
        PRIMARY KEY(integration_id,lot_id));
    ''');
    final columns = db
        .select('PRAGMA table_info(users)')
        .map((row) => row['name'])
        .toSet();
    if (!columns.contains('subscription_id')) {
      db.execute('ALTER TABLE users ADD COLUMN subscription_id TEXT');
    }
    if (!columns.contains('subscription_cancelled')) {
      db.execute(
        'ALTER TABLE users ADD COLUMN subscription_cancelled INTEGER NOT NULL DEFAULT 0',
      );
    }
    if (!db
        .select('PRAGMA table_info(merchant_offers)')
        .any((r) => r['name'] == 'eligible_until')) {
      db.execute('ALTER TABLE merchant_offers ADD COLUMN eligible_until TEXT');
    }
  }
  final Database db;
  int _transactionDepth = 0;
  static bool _linuxConfigured = false;
  static Database _open(String path) {
    if (Platform.isLinux && !_linuxConfigured) {
      sqlite_loader.open.overrideFor(
        sqlite_loader.OperatingSystem.linux,
        () => DynamicLibrary.open('libsqlite3.so.0'),
      );
      _linuxConfigured = true;
    }
    if (path == ':memory:') return sqlite3.openInMemory();
    File(path).parent.createSync(recursive: true);
    return sqlite3.open(path);
  }

  T transaction<T>(T Function() action) {
    final level = _transactionDepth++;
    try {
      db.execute(level == 0 ? 'BEGIN IMMEDIATE' : 'SAVEPOINT nested_$level');
    } catch (_) {
      _transactionDepth--;
      rethrow;
    }
    try {
      final value = action();
      db.execute(level == 0 ? 'COMMIT' : 'RELEASE SAVEPOINT nested_$level');
      return value;
    } catch (_) {
      if (level == 0) {
        db.execute('ROLLBACK');
      } else {
        db.execute('ROLLBACK TO SAVEPOINT nested_$level');
        db.execute('RELEASE SAVEPOINT nested_$level');
      }
      rethrow;
    } finally {
      _transactionDepth--;
    }
  }

  Map<String, dynamic> decode(String text) =>
      Map<String, dynamic>.from(jsonDecode(text) as Map);
  void close() => db.dispose();
}

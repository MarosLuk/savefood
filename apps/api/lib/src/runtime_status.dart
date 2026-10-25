import 'dart:convert';
import 'dart:io';
import 'billing.dart';
import 'config.dart';
import 'database.dart';
import 'legal.dart';
import 'mail.dart';

class RuntimeStatus {
  RuntimeStatus(
    this.database,
    this.config,
    this.mail,
    this.billing,
    this.legal,
  );
  final MarketplaceDatabase database;
  final ServerConfig config;
  final MailService mail;
  final BillingService billing;
  final LegalService legal;
  final started = DateTime.now().toUtc();
  final Map<String, Map<String, num>> requests = {};
  bool get databaseReady {
    try {
      return database.db.select('SELECT 1 AS ok').first['ok'] == 1;
    } catch (_) {
      return false;
    }
  }

  void observe(String method, String path, int status, int microseconds) {
    final parts = path.split('/').where((p) => p.isNotEmpty).toList();
    final category = parts.isEmpty
        ? 'root'
        : parts.first == 'v1' && parts.length > 1
        ? parts[1]
        : parts.first;
    const known = {
      'root',
      'health',
      'v1',
      'auth',
      'account',
      'config',
      'catalog',
      'places',
      'me',
      'orders',
      'offers',
      'merchant',
      'support',
      'platform',
      'integrations',
      'media',
      'documents',
      'legal',
      'club',
      'devices',
      'payments',
      'payment',
    };
    final key =
        '$method:${known.contains(category) ? category : 'other'}:${status ~/ 100}xx';
    final r = requests.putIfAbsent(
      key,
      () => {'count': 0, 'totalMs': 0.0, 'maxMs': 0.0},
    );
    final ms = microseconds / 1000;
    r['count'] = r['count']! + 1;
    r['totalMs'] = r['totalMs']! + ms;
    if (ms > r['maxMs']!) r['maxMs'] = ms;
  }

  Map<String, dynamic> report() {
    bool https(String value) => Uri.tryParse(value)?.scheme == 'https';
    final checks = <Map<String, dynamic>>[];
    void check(String key, String label, bool ok, {bool required = true}) =>
        checks.add({
          'key': key,
          'label': label,
          'ok': ok,
          'required': required,
        });
    check('database', 'Databáza je dostupná', databaseReady);
    check(
      'environment',
      'Produkčný režim bez demo dát',
      config.production && !config.seedDemo && !config.demoShowcase,
    );
    check(
      'https',
      'HTTPS adresy a povolené originy',
      https(config.publicUrl) &&
          https(config.appUrl) &&
          https(config.merchantAppUrl) &&
          config.allowedOrigins.isNotEmpty &&
          config.allowedOrigins.every(https),
    );
    check(
      'mail',
      'E-mailová služba je nakonfigurovaná',
      mail.gateway.configured,
    );
    check(
      'legal',
      'Podmienky a identita prevádzkovateľa sú publikované',
      legal.current()['configured'] == true && legal.current()['demo'] != true,
    );
    check(
      'billing',
      'Predávajúci a fakturačný profil platformy sú vyplnené',
      billing.model != null &&
          billing.profile('platform')['configured'] == true &&
          billing.profile('platform')['demo'] != true,
    );
    check(
      'admin',
      'Existuje overený aktívny správca',
      database.db
          .select(
            "SELECT p.user_id FROM platform_roles p JOIN users u ON u.id=p.user_id WHERE p.role='admin' AND u.disabled=0 AND u.email_verified=1 LIMIT 1",
          )
          .isNotEmpty,
    );
    check(
      'font',
      'Písmo PDF dokladov je dostupné',
      File(config.billingFontPath).existsSync(),
    );
    var backupFresh = false;
    try {
      final marker =
          jsonDecode(
                File('${config.databasePath}.backup.json').readAsStringSync(),
              )
              as Map;
      final date = DateTime.parse(marker['createdAt'] as String);
      backupFresh =
          marker['integrity'] == 'ok' &&
          DateTime.now().toUtc().difference(date).inHours < 26;
    } catch (_) {
      /* Missing marker means an unverified backup. */
    }
    check(
      'backup',
      'Lokálna overená záloha za posledných 26 hodín',
      backupFresh,
    );
    check(
      'payments',
      'Platby sú aktivované (záverečná etapa)',
      config.paymentMode == 'stripe' && config.stripeLiveMode,
      required: false,
    );
    check(
      'oauth',
      'Je nakonfigurované sociálne prihlásenie',
      config.googleClientId.isNotEmpty ||
          config.appleClientId.isNotEmpty ||
          config.facebookAppId.isNotEmpty,
      required: false,
    );
    check(
      'push',
      'Sú nakonfigurované push notifikácie',
      config.firebaseServiceAccount.isNotEmpty,
      required: false,
    );
    final rows = database.db.select(
      'SELECT status,COUNT(*) count FROM mail_outbox GROUP BY status',
    );
    return {
      'operational': databaseReady,
      'launchReady': checks
          .where((c) => c['required'] == true)
          .every((c) => c['ok'] == true),
      'paymentsDeferred': config.paymentMode != 'stripe',
      'startedAt': started.toIso8601String(),
      'uptimeSeconds': DateTime.now().toUtc().difference(started).inSeconds,
      'checks': checks,
      'requests': requests,
      'mail': rows.map((r) => Map<String, dynamic>.from(r)).toList(),
      'documentsPending': database.db
          .select('SELECT COUNT(*) count FROM billing_pending')
          .first['count'],
      'refundsPending': database.db
          .select(
            "SELECT COUNT(*) count FROM finance_refunds WHERE status!='completed'",
          )
          .first['count'],
    };
  }
}

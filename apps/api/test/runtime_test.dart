import 'dart:convert';
import 'package:marketplace_server/marketplace_server.dart';
import 'package:marketplace_server/src/auth.dart';
import 'package:marketplace_server/src/billing.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

void main() {
  test(
    'configured shop seller is initialized once and cannot switch through billing settings',
    () {
      final app = MarketplaceServer(
        const ServerConfig(
          databasePath: ':memory:',
          seedDemo: false,
          billingSellerModel: 'merchantSeller',
        ),
      );
      addTearDown(app.close);
      expect(app.billing.model, 'merchantSeller');
      expect(
        () => app.billing.setModel('platformSeller'),
        throwsA(isA<ApiFailure>().having((e) => e.status, 'status', 409)),
      );
      final reopened = BillingService(app.database, app.finance, app.config);
      expect(reopened.model, 'merchantSeller');
      expect(app.billing.profile('platform')['configured'], false);
    },
  );
  test(
    'a conflicting deployment cannot silently replace the stored seller',
    () {
      final app = MarketplaceServer(
        const ServerConfig(databasePath: ':memory:', seedDemo: false),
      );
      addTearDown(app.close);
      app.billing.setModel('platformSeller');
      expect(
        () => BillingService(
          app.database,
          app.finance,
          const ServerConfig(billingSellerModel: 'merchantSeller'),
        ),
        throwsStateError,
      );
      expect(app.billing.model, 'platformSeller');
    },
  );
  test('seller environment configuration rejects misspellings', () {
    expect(
      () => ServerConfig.fromEnvironment({
        'BILLING_SELLER_MODEL': 'merchantSeler',
      }),
      throwsArgumentError,
    );
    final config = ServerConfig.fromEnvironment({
      'BILLING_SELLER_MODEL': 'merchantSeller',
    });
    expect(config.billingSellerModel, 'merchantSeller');
  });
  test(
    'production can prepare merchant operations with payments explicitly disabled, never sandboxed',
    () async {
      final config = ServerConfig.fromEnvironment({
        'APP_ENV': 'production',
        'SEED_DEMO': 'false',
        'PAYMENT_MODE': 'disabled',
        'PUBLIC_URL': 'https://api.example.test',
        'APP_URL': 'https://app.example.test',
        'MERCHANT_APP_URL': 'https://merchant.example.test',
        'DATABASE_PATH': ':memory:',
      });
      final app = MarketplaceServer(config);
      addTearDown(app.close);
      expect(app.payments, isA<DisabledPaymentGateway>());
      expect(app.finance.gateway, isA<DisabledConnectGateway>());
      await expectLater(app.reserve('nobody', {}), throwsA(isA<ApiFailure>()));
      await expectLater(
        app.finance.gateway.createAccount('org', 'name', 'email'),
        throwsA(isA<ApiFailure>()),
      );
      expect(app.database.db.select('SELECT id FROM orders'), isEmpty);
      expect(
        () => ServerConfig.fromEnvironment({
          'APP_ENV': 'production',
          'PAYMENT_MODE': 'sandbox',
        }),
        throwsArgumentError,
      );
    },
  );
  test(
    'readiness details require an administrator and request metrics do not contain customer IDs or query text',
    () async {
      final app = MarketplaceServer(
        const ServerConfig(databasePath: ':memory:', demoShowcase: true),
      );
      addTearDown(app.close);
      final token = app.auth.createSession('showcase-support')['token'];
      final health = await app.handler(
        Request('GET', Uri.parse('http://localhost/health/ready')),
      );
      expect(health.statusCode, 200);
      expect(health.headers['x-request-id'], isNotEmpty);
      final private = await app.handler(
        Request('GET', Uri.parse('http://localhost/v1/platform/readiness')),
      );
      expect(private.statusCode, 401);
      await app.handler(
        Request(
          'GET',
          Uri.parse(
            'http://localhost/v1/orders/secret-user-id?query=private-text',
          ),
          headers: {'authorization': 'Bearer $token'},
        ),
      );
      final response = await app.handler(
        Request(
          'GET',
          Uri.parse('http://localhost/v1/platform/readiness'),
          headers: {'authorization': 'Bearer $token'},
        ),
      );
      expect(response.statusCode, 200);
      final report = jsonDecode(await response.readAsString()) as Map;
      expect(report['launchReady'], false);
      expect(jsonEncode(report['requests']), isNot(contains('secret-user-id')));
      expect(jsonEncode(report['requests']), isNot(contains('private-text')));
    },
  );
}

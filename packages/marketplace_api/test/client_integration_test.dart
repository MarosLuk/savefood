import 'dart:io';
import 'package:marketplace_api/marketplace_api.dart';
import 'package:marketplace_domain/marketplace_domain.dart';
import 'package:marketplace_server/marketplace_server.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:test/test.dart';

void main() {
  test(
    'two independent clients share authoritative orders, stock, favorites and wallet',
    () async {
      final app = MarketplaceServer(
        const ServerConfig(databasePath: ':memory:'),
        clock: () => DateTime.utc(2026, 10, 23, 12),
      );
      final server = await io.serve(
        app.handler,
        InternetAddress.loopbackIPv4,
        0,
      );
      final base = 'http://127.0.0.1:${server.port}';
      final vault = MemoryTokenVault();
      final first = MarketplaceApi(base, vault: vault),
          second = MarketplaceApi(base, vault: MemoryTokenVault());
      addTearDown(() async {
        first.close();
        second.close();
        await server.close(force: true);
        app.close();
      });
      await first.register(
        'Jana Test',
        'jana@example.test',
        'A secure test password 123',
      );
      await second.login('jana@example.test', 'A secure test password 123');
      await first.updateProfile({
        'favorites': ['butter'],
        'marketing': false,
      });
      expect((await second.me())['favorites'], ['butter']);
      await first.activateTrial('KLUB30');
      final before = (await first.catalog())
          .firstWhere((o) => o.id == 'butter')
          .stock;
      final order = await first.reserve(
        cart: {'butter': 1},
        invoice: const InvoiceDetails(
          name: 'Jana Test',
          email: 'jana@example.test',
          street: 'Ulica 1',
          city: 'Bratislava',
          postcode: '81101',
        ),
        coupon: 'VITAJ10',
        useCredit: false,
        key: MarketplaceApi.newIdempotencyKey(),
      );
      expect(order.total, 359);
      expect(
        (await second.catalog()).firstWhere((o) => o.id == 'butter').stock,
        before - 1,
      );
      final account = await second.me();
      expect((account['orders'] as List).single['id'], order.id);
      await second.finishOrder(order, collect: true);
      expect((await first.me())['credit'], 35);
      await first.logout();
      expect(vault.token, isNull);
      await expectLater(
        first.me(),
        throwsA(isA<ApiException>().having((e) => e.status, 'status', 401)),
      );
    },
  );
  test('a new client restores a token without storing passwords', () async {
    final app = MarketplaceServer(const ServerConfig(databasePath: ':memory:'));
    final server = await io.serve(app.handler, InternetAddress.loopbackIPv4, 0);
    final vault = MemoryTokenVault();
    final base = 'http://127.0.0.1:${server.port}';
    final first = MarketplaceApi(base, vault: vault);
    await first.register(
      'Jana Test',
      'restore@example.test',
      'A secure test password 123',
    );
    first.close();
    final restored = MarketplaceApi(base, vault: vault);
    await restored.restoreSession();
    expect((await restored.me())['email'], 'restore@example.test');
    restored.close();
    await server.close(force: true);
    app.close();
  });
}

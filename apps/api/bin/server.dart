import 'dart:io';
import 'package:marketplace_server/marketplace_server.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

Future<void> main(List<String> args) async {
  if (args.contains('--healthcheck')) {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
    try {
      final r = await client.getUrl(
        Uri.parse(
          'http://127.0.0.1:${Platform.environment['PORT'] ?? '8080'}/health/ready',
        ),
      );
      final response = await r.close().timeout(const Duration(seconds: 5));
      await response.drain<void>();
      exitCode = response.statusCode == 200 ? 0 : 1;
    } catch (_) {
      exitCode = 1;
    } finally {
      client.close(force: true);
    }
    return;
  }
  final config = ServerConfig.fromEnvironment(Platform.environment);
  await serveMarketplace(config);
}

Future<void> serveMarketplace(ServerConfig config) async {
  final app = MarketplaceServer(config);
  if (config.demoShowcase) {
    await app.prepareShowcasePresentation();
    for (final org in app.finance.rows(
      "SELECT org_id FROM merchant_members WHERE user_id='showcase-bakery'",
    )) {
      app.finance.queue('showcase-bakery', org['org_id'] as String);
    }
    await app.finance.drain();
  }
  final server = await shelf_io.serve(app.handler, config.host, config.port);
  stdout.writeln(
    'Nevyhadzuj API listening on ${server.address.address}:${server.port} (${config.paymentMode})',
  );
  ProcessSignal.sigint.watch().listen((_) async {
    await server.close(force: true);
    app.close();
    exit(0);
  });
  ProcessSignal.sigterm.watch().listen((_) async {
    await server.close(force: true);
    app.close();
    exit(0);
  });
}

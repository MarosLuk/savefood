import 'dart:io';
import 'package:marketplace_server/marketplace_server.dart';
import 'server.dart' show serveMarketplace;

/// Deliberately ignores .env and payment/provider credentials.
Future<void> main() async {
  final port = int.tryParse(Platform.environment['DEMO_PORT'] ?? '') ?? 8080;
  final instance = Platform.environment['DEMO_INSTANCE'] ?? 'showcase';
  if (!RegExp(r'^[a-z0-9][a-z0-9-]{0,50}$').hasMatch(instance)) {
    throw ArgumentError('DEMO_INSTANCE must be a short lowercase name.');
  }
  stdout.writeln('DEMO · fictional profiles and stock; no real payments.');
  await serveMarketplace(
    ServerConfig(
      port: port,
      databasePath: 'data/demo-$instance.sqlite',
      publicUrl: 'http://127.0.0.1:$port',
      appUrl: 'http://127.0.0.1:7357',
      demoShowcase: true,
      settlementDelayHours: 0,
    ),
  );
}

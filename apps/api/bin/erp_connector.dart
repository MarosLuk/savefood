import 'dart:io';
import 'package:marketplace_server/src/database.dart';
import 'package:marketplace_server/src/erp_bridge.dart';

Future<void> main(List<String> args) async {
  final env = Platform.environment;
  String required(String key) {
    final value = env[key];
    if (value == null || value.isEmpty) {
      throw ArgumentError('Missing $key (configure outside source control).');
    }
    return value;
  }

  final db = MarketplaceDatabase(
    env['CONNECTOR_STATE_PATH'] ?? 'data/erp-connector.sqlite',
  );
  final bridge = ErpBridge(
    marketplace: Uri.parse(required('MARKETPLACE_URL')),
    stockToken: required(
      args.contains('--accounting') ? 'ACCOUNTING_TOKEN' : 'STOCK_TOKEN',
    ),
    erp: Uri.parse(required('ERP_URL')),
    erpToken: required('ERP_TOKEN'),
    state: db,
    pullIncoming: env['ERP_PULL_INCOMING'] == 'true',
    allowLoopback: env['ERP_ALLOW_LOOPBACK'] == 'true',
  );
  try {
    do {
      try {
        final result = args.contains('--accounting')
            ? await bridge.accountingOnce()
            : await bridge.once();
        stdout.writeln(
          'ERP: sent ${result['sent']}, received ${result['received']}',
        );
      } catch (e) {
        stderr.writeln(
          'ERP synchronization stopped safely (${e.runtimeType}). Check connector status and mapping before retry.',
        );
        if (args.contains('--once')) {
          exitCode = 1;
          break;
        }
      }
      if (args.contains('--once')) break;
      await Future<void>.delayed(const Duration(seconds: 15));
    } while (true);
  } finally {
    bridge.close();
    db.close();
  }
}

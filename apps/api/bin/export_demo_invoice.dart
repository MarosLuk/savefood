import 'dart:io';
import 'package:marketplace_server/marketplace_server.dart';

Future<void> main() async {
  final app = MarketplaceServer(
    const ServerConfig(databasePath: ':memory:', demoShowcase: true),
  );
  try {
    await app.prepareShowcasePresentation();
    final row = app.database.db
        .select(
          "SELECT id FROM billing_documents WHERE kind='invoice' AND scope!='platform' ORDER BY rowid LIMIT 1",
        )
        .first;
    final bytes = await app.billing.pdf(row['id'] as String);
    final output = File('artifacts/demo-faktura.pdf');
    await output.parent.create(recursive: true);
    await output.writeAsBytes(bytes);
    stdout.writeln('Created ${output.path} (${bytes.length} bytes).');
  } finally {
    app.close();
  }
}

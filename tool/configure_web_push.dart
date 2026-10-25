import 'dart:convert';
import 'dart:io';

// Run from the repository root. Uses only Firebase public app configuration.
Future<void> main(List<String> args) async {
  if (args.length != 1) {
    stderr.writeln(
      'Usage: dart run tool/configure_web_push.dart config/app.json',
    );
    exitCode = 64;
    return;
  }
  final config = jsonDecode(await File(args.single).readAsString()) as Map;
  final publicConfig = {
    'apiKey': config['FIREBASE_API_KEY'],
    'appId': config['FIREBASE_APP_ID'],
    'messagingSenderId': config['FIREBASE_MESSAGING_SENDER_ID'],
    'projectId': config['FIREBASE_PROJECT_ID'],
  };
  if (publicConfig.values.any((v) => v is! String || v.isEmpty)) {
    throw ArgumentError('Fill in the Firebase public app configuration first.');
  }
  await File('apps/mobile/web/firebase-messaging-sw.js').writeAsString('''
// Generated from public Firebase configuration. No service account keys belong here.
importScripts('https://www.gstatic.com/firebasejs/12.19.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/12.19.0/firebase-messaging-compat.js');
firebase.initializeApp(${jsonEncode(publicConfig)});
firebase.messaging();
''');
  stdout.writeln('Created apps/mobile/web/firebase-messaging-sw.js');
}

import 'package:firebase_core/firebase_core.dart';

/// Shared by Auth and FCM, with no initialization when project files are absent.
abstract final class FirebaseRuntime {
  static const projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
  static const apiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const appId = String.fromEnvironment('FIREBASE_APP_ID');
  static const senderId = String.fromEnvironment(
    'FIREBASE_MESSAGING_SENDER_ID',
  );
  static bool get configured =>
      [projectId, apiKey, appId, senderId].every((v) => v.isNotEmpty);
  static Future<FirebaseApp>? _initializing;
  static Future<FirebaseApp> initialize() => _initializing ??= _initialize();
  static Future<FirebaseApp> _initialize() async {
    if (!configured) {
      throw StateError('Firebase projekt ešte nie je nakonfigurovaný.');
    }
    try {
      if (Firebase.apps.isNotEmpty) return Firebase.app();
      return await Firebase.initializeApp(
        options: FirebaseOptions(
          apiKey: apiKey,
          appId: appId,
          messagingSenderId: senderId,
          projectId: projectId,
          authDomain:
              const String.fromEnvironment('FIREBASE_AUTH_DOMAIN').isEmpty
              ? '$projectId.firebaseapp.com'
              : const String.fromEnvironment('FIREBASE_AUTH_DOMAIN'),
          iosBundleId: 'com.dakoty.savefood',
        ),
      );
    } catch (_) {
      _initializing = null;
      rethrow;
    }
  }
}

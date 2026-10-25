import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'firebase_runtime.dart';

class SocialSignInFailure implements Exception {
  const SocialSignInFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

abstract interface class SocialSignIn {
  String get projectId;
  bool get ready;
  Future<void> initialize();
  Future<String?> signIn(String provider);
  Future<void> signOut();
}

/// Firebase is a short-lived identity exchange. The application session remains
/// in its existing vault, and Firebase never signs the marketplace in silently.
class FirebaseSocialSignIn implements SocialSignIn {
  static const enabled = bool.fromEnvironment('FIREBASE_AUTH_ENABLED');
  @override
  String get projectId => FirebaseRuntime.projectId;
  @override
  bool ready = false;
  bool _googleReady = false;
  @override
  Future<void> initialize() async {
    if (!enabled || !FirebaseRuntime.configured) return;
    await FirebaseRuntime.initialize();
    if (kIsWeb) await FirebaseAuth.instance.setPersistence(Persistence.NONE);
    ready = true;
  }

  @override
  Future<String?> signIn(String provider) async {
    if (!ready || !{'google', 'apple'}.contains(provider)) {
      throw const SocialSignInFailure(
        'Tento spôsob prihlásenia ešte nie je aktivovaný.',
      );
    }
    try {
      UserCredential result;
      if (provider == 'google' && !kIsWeb) {
        if (!_googleReady) {
          const clientId = String.fromEnvironment('GOOGLE_SIGN_IN_CLIENT_ID');
          const serverId = String.fromEnvironment(
            'GOOGLE_SIGN_IN_SERVER_CLIENT_ID',
          );
          await GoogleSignIn.instance.initialize(
            clientId: clientId.isEmpty ? null : clientId,
            serverClientId: serverId.isEmpty ? null : serverId,
          );
          _googleReady = true;
        }
        final account = await GoogleSignIn.instance.authenticate();
        final googleToken = account.authentication.idToken;
        if (googleToken == null) {
          throw const SocialSignInFailure(
            'Google neposkytol platné prihlásenie. Skús znova.',
          );
        }
        result = await FirebaseAuth.instance.signInWithCredential(
          GoogleAuthProvider.credential(idToken: googleToken),
        );
      } else {
        final AuthProvider authProvider = provider == 'apple'
            ? (AppleAuthProvider()
                ..addScope('email')
                ..addScope('name'))
            : (GoogleAuthProvider()
                ..setCustomParameters({'prompt': 'select_account'}));
        result = kIsWeb
            ? await FirebaseAuth.instance.signInWithPopup(authProvider)
            : await FirebaseAuth.instance.signInWithProvider(authProvider);
      }
      final token = await result.user?.getIdToken(true);
      if (token == null || token.isEmpty) {
        throw const SocialSignInFailure(
          'Prihlásenie sa nepodarilo dokončiť. Skús znova.',
        );
      }
      return token;
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return null;
      throw const SocialSignInFailure(
        'Google prihlásenie sa nepodarilo dokončiť. Skús znova.',
      );
    } on FirebaseAuthException catch (e) {
      if ({
        'popup-closed-by-user',
        'cancelled-popup-request',
        'web-context-canceled',
        'canceled',
        'user-cancelled',
      }.contains(e.code)) {
        return null;
      }
      throw SocialSignInFailure(switch (e.code) {
        'account-exists-with-different-credential' =>
          'Tento e-mail má iný spôsob prihlásenia. Použi ho.',
        'popup-blocked' =>
          'Prehliadač zablokoval prihlasovacie okno. Povoľ ho a skús znova.',
        'network-request-failed' =>
          'Skontroluj pripojenie a skús prihlásenie znova.',
        'user-disabled' => 'Tento účet je pozastavený. Obráť sa na podporu.',
        'operation-not-allowed' || 'unauthorized-domain' =>
          'Tento spôsob prihlásenia ešte nie je aktivovaný.',
        _ => 'Prihlásenie sa nepodarilo dokončiť. Skús znova.',
      });
    }
  }

  @override
  Future<void> signOut() async {
    if (!ready) return;
    try {
      await FirebaseAuth.instance.signOut();
    } catch (_) {
      /* Retry at next explicit login. */
    }
    if (_googleReady && !kIsWeb) {
      try {
        await GoogleSignIn.instance.signOut();
      } catch (_) {
        /* Local provider cleanup. */
      }
    }
  }
}

import 'dart:async';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import '../state/app_store.dart';
import 'firebase_runtime.dart';

/// Enabled only with a real Firebase project. No dummy token or successful
/// delivery is fabricated when platform credentials are absent.
class StockAlerts {
  bool initialized = false, busy = false;
  String signature = '';
  int apnsAttempts = 0;
  Timer? debounce;
  Future<void> initialize(AppStore store) async {
    if (!store.remoteEnabled || !FirebaseRuntime.configured) return;
    await FirebaseRuntime.initialize();
    initialized = true;
    store.addListener(() => _schedule(store));
    FirebaseMessaging.instance.onTokenRefresh.listen((_) {
      _schedule(store, force: true);
    });
    FirebaseMessaging.onMessage.listen((message) {
      if (message.data['kind'] == 'support') store.receiveSupportActivity();
      if (message.notification?.title != null) {
        store.showNotification(message.notification!.title!);
      }
    });
    void opened(RemoteMessage message) {
      if (message.data['kind'] == 'support') {
        store.openSupportTicket(message.data['ticketId'] ?? '');
      } else {
        store.refreshRemote();
      }
    }

    FirebaseMessaging.onMessageOpenedApp.listen(opened);
    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) opened(initial);
    _schedule(store);
  }

  void _schedule(AppStore store, {bool force = false}) {
    final next =
        '${store.signedIn}:${store.favoriteAlerts}:${store.supportAlerts}:${store.email}';
    if (!force && next == signature) return;
    signature = next;
    debounce?.cancel();
    debounce = Timer(const Duration(milliseconds: 500), () => _sync(store));
  }

  Future<void> _sync(AppStore store) async {
    if (!initialized || busy) return;
    busy = true;
    try {
      if (!store.signedIn) {
        await FirebaseMessaging.instance.setAutoInitEnabled(false);
        await FirebaseMessaging.instance.deleteToken();
        return;
      }
      if (store.serverConfig['pushEnabled'] != true) return;
      if (!store.favoriteAlerts && !store.supportAlerts) {
        await store.api!.request('POST', '/v1/devices/remove', body: {});
        await FirebaseMessaging.instance.setAutoInitEnabled(false);
        await FirebaseMessaging.instance.deleteToken();
        return;
      }
      final permission = await FirebaseMessaging.instance.requestPermission();
      if (permission.authorizationStatus != AuthorizationStatus.authorized &&
          permission.authorizationStatus != AuthorizationStatus.provisional) {
        return;
      }
      await FirebaseMessaging.instance.setAutoInitEnabled(true);
      // APNs registration can complete shortly after the permission dialog.
      if (!kIsWeb &&
          defaultTargetPlatform == TargetPlatform.iOS &&
          await FirebaseMessaging.instance.getAPNSToken() == null) {
        if (apnsAttempts++ < 5) {
          debounce = Timer(
            const Duration(seconds: 3),
            () => _schedule(store, force: true),
          );
        }
        return;
      }
      apnsAttempts = 0;
      final token = await FirebaseMessaging.instance.getToken(
        vapidKey: kIsWeb
            ? const String.fromEnvironment('FIREBASE_VAPID_KEY')
            : null,
      );
      if (token != null) {
        await store.api!.request(
          'POST',
          '/v1/devices',
          body: {
            'token': token,
            'platform': kIsWeb ? 'web' : defaultTargetPlatform.name,
          },
        );
      }
    } catch (_) {
      store.showNotification(
        'Upozornenia sa nepodarilo zapnúť. Skontroluj povolenie v nastaveniach zariadenia.',
      );
    } finally {
      busy = false;
    }
  }
}

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:marketplace_domain/marketplace_domain.dart';
import 'package:timezone/data/latest.dart' as timezone_data;
import 'package:timezone/timezone.dart' as tz;
import '../state/app_store.dart';

class PickupNotifications {
  final plugin = FlutterLocalNotificationsPlugin();
  bool ready = false;
  String signature = '';
  Timer? debounce;
  Future<void> initialize() async {
    if (kIsWeb ||
        !{
          TargetPlatform.iOS,
          TargetPlatform.android,
        }.contains(defaultTargetPlatform)) {
      return;
    }
    timezone_data.initializeTimeZones();
    await plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );
    ready = true;
  }

  void attach(AppStore store) {
    void changed() {
      final next =
          '${store.pickupReminders}:${store.favoriteAlerts}:${store.orders.map((o) => '${o.id}:${o.status.name}:${o.items.map((i) => '${i.collected}:${i.refundCount}').join()}').join(',')}';
      if (next == signature || !ready) return;
      signature = next;
      debounce?.cancel();
      debounce = Timer(const Duration(milliseconds: 350), () => _sync(store));
    }

    store.addListener(changed);
    changed();
  }

  Future<void> _sync(AppStore store) async {
    try {
      await plugin.cancelAll();
      final active = store.orders
          .where((o) => o.status == OrderStatus.reserved)
          .toList();
      if (!store.pickupReminders || active.isEmpty) return;
      final granted =
          await plugin
              .resolvePlatformSpecificImplementation<
                IOSFlutterLocalNotificationsPlugin
              >()
              ?.requestPermissions(alert: true, badge: true, sound: true) ??
          await plugin
              .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin
              >()
              ?.requestNotificationsPermission() ??
          false;
      if (!granted) return;
      var notificationId = 1;
      for (final order in active) {
        for (final item in order.items) {
          if (item.collected || item.refunded) continue;
          final when = item.pickupStart.subtract(const Duration(minutes: 30));
          if (!when.isAfter(DateTime.now())) continue;
          await plugin.zonedSchedule(
            notificationId++,
            'Dobroty na teba čakajú',
            '${item.store} · vyzdvihnutie o 30 minút',
            tz.TZDateTime.from(when, tz.UTC),
            const NotificationDetails(
              android: AndroidNotificationDetails(
                'pickup_reminders',
                'Vyzdvihnutie balíčkov',
                channelDescription: 'Pripomienky rezervovaných balíčkov',
                importance: Importance.high,
                priority: Priority.high,
              ),
              iOS: DarwinNotificationDetails(),
            ),
            androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
            payload: order.id,
          );
          if (notificationId > 40) return;
        }
      }
    } catch (_) {
      /* Notification delivery is optional; reservations remain available in Orders. */
    }
  }
}

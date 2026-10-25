import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:design_system/design_system.dart';
import 'package:marketplace_data/marketplace_data.dart';
import 'app.dart';
import 'state/app_store.dart';
import 'services/token_vault.dart';
import 'services/notifications.dart';
import 'services/stock_alerts.dart';

void main() {
  startMarketplace(
    merchantPortal:
        const bool.fromEnvironment('MERCHANT_PORTAL') ||
        Uri.base.queryParameters['portal'] == 'merchant',
  );
}

void startMarketplace({bool merchantPortal = false, bool adminPortal = false}) {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(Bootstrap(merchantPortal: merchantPortal, adminPortal: adminPortal));
}

class Bootstrap extends StatefulWidget {
  const Bootstrap({
    super.key,
    this.merchantPortal = false,
    this.adminPortal = false,
  });
  final bool merchantPortal;
  final bool adminPortal;
  @override
  State<Bootstrap> createState() => _BootstrapState();
}

class _BootstrapState extends State<Bootstrap> {
  final navigatorKey = GlobalKey<NavigatorState>();
  AppStore? store;
  String? error;
  LocalMarketplaceRepository? repository;
  final notifications = PickupNotifications();
  final stockAlerts = StockAlerts();
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      const baseUrl = String.fromEnvironment(
        'API_BASE_URL',
        defaultValue: 'https://46.62.223.67:8453',
      );
      final key = baseUrl.isEmpty
          ? LocalMarketplaceRepository.storageKey
          : '${LocalMarketplaceRepository.storageKey}.${base64UrlEncode(utf8.encode(baseUrl))}';
      repository = await LocalMarketplaceRepository.open(key: key);
      final api = baseUrl.isEmpty
          ? null
          : MarketplaceApi(baseUrl, vault: SecureTokenVault(baseUrl));
      final appStore = AppStore(repository!, api: api);
      await appStore.restore();
      await appStore.initializeRemote();
      if (appStore.remoteEnabled) {
        try {
          await appStore.socialAuth.initialize();
        } catch (_) {
          appStore.showNotification(
            'Prihlásenie cez Apple a Google momentálne nie je dostupné.',
          );
        }
      }
      if (appStore.pendingSupportPhotoTicket != null) {
        appStore.openSupportTicket(appStore.pendingSupportPhotoTicket!);
      }
      try {
        await notifications.initialize();
        notifications.attach(appStore);
      } catch (_) {
        /* Platforms without notification support still work. */
      }
      try {
        await stockAlerts.initialize(appStore);
      } catch (_) {
        appStore.showNotification('Upozornenia momentálne nie sú dostupné.');
      }
      if (mounted) setState(() => store = appStore);
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'Údaje aplikácie sa nepodarilo načítať. Môžeš skúsiť znova alebo obnoviť lokálne dáta.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (store != null) {
      return NevyhadzujApp(
        store: store!,
        startInMerchantPortal: widget.merchantPortal,
        startInAdminPortal: widget.adminPortal,
      );
    }
    return MaterialApp(
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: appTheme(Brightness.light),
      darkTheme: appTheme(Brightness.dark),
      home: Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const AppText(
                    'Save Food',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -1,
                    ),
                  ),
                  const SizedBox(height: 24),
                  if (error == null)
                    const SizedBox(width: 80, child: LinearProgressIndicator())
                  else ...[
                    AppText(error!, textAlign: TextAlign.center),
                    const SizedBox(height: 24),
                    PrimaryButton(
                      'Skúsiť znova',
                      onPressed: () {
                        setState(() => error = null);
                        load();
                      },
                    ),
                    if (repository != null)
                      TextButton(
                        onPressed: () async {
                          final confirmed = await showDialog<bool>(
                            context: navigatorKey.currentContext!,
                            builder: (c) => AlertDialog(
                              title: const AppText('Obnoviť lokálne dáta?'),
                              content: const AppText(
                                'Vymaže to nastavenia a lokálne demo záchrany v tomto zariadení. Objednávky na serveri zostanú zachované.',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(c, false),
                                  child: const AppText('Ponechať'),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.pop(c, true),
                                  child: const AppText('Obnoviť'),
                                ),
                              ],
                            ),
                          );
                          if (confirmed == true) {
                            await repository!.clear();
                            if (mounted) {
                              setState(() => error = null);
                              load();
                            }
                          }
                        },
                        child: const AppText('Obnoviť lokálne dáta'),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:design_system/design_system.dart';
import 'state/app_store.dart';
import 'features/home.dart';
import 'features/catalog.dart';
import 'features/account.dart';
import 'features/account_security.dart';
import 'features/commerce.dart';
import 'features/onboarding.dart';
import 'features/location.dart';
import 'features/merchant/portal.dart';
import 'features/merchant/media_library.dart';
import 'features/merchant/team.dart';
import 'features/reviews.dart';
import 'features/platform/admin.dart';
import 'features/demo.dart';
import 'features/support/support.dart';
import 'features/support/activity.dart';
import 'widgets/common.dart';
import 'l10n/copy.dart';

class NevyhadzujApp extends StatefulWidget {
  const NevyhadzujApp({
    super.key,
    required this.store,
    this.startInMerchantPortal = false,
    this.startInAdminPortal = false,
  });
  final AppStore store;
  final bool startInMerchantPortal;
  final bool startInAdminPortal;
  @override
  State<NevyhadzujApp> createState() => _NevyhadzujAppState();
}

class _NevyhadzujAppState extends State<NevyhadzujApp>
    with WidgetsBindingObserver {
  AppStore get store => widget.store;
  final navigatorKey = GlobalKey<NavigatorState>();
  bool supportNavigationScheduled = false;
  void openPendingSupport() {
    if (supportNavigationScheduled || store.supportTicketToOpen == null) return;
    supportNavigationScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      supportNavigationScheduled = false;
      if (!mounted || !store.signedIn || navigatorKey.currentState == null) {
        return;
      }
      final id = store.supportTicketToOpen;
      store.supportTicketToOpen = null;
      if (id != null) {
        navigatorKey.currentState!.push(
          MaterialPageRoute<void>(builder: (_) => TicketScreen(ticketId: id)),
        );
      }
    });
  }

  late bool showMerchant = widget.startInMerchantPortal;
  late bool showAdmin = widget.startInAdminPortal;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    store.addListener(openPendingSupport);
    openPendingSupport();
    if (store.pendingReviewOffer != null && store.signedIn) {
      final reviewOffer = store.pendingReviewOffer!;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          navigatorKey.currentState?.push(
            MaterialPageRoute<void>(
              builder: (_) => ScreenScaffold(
                title: 'Hodnotenie balíčka',
                child: ReviewsSheet(offerId: reviewOffer),
              ),
            ),
          );
        }
      });
    }
    if (store.pendingMediaOrganization != null && store.signedIn) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          navigatorKey.currentState?.push(
            MaterialPageRoute<void>(
              builder: (_) => MerchantMediaScreen(
                organizationId: store.pendingMediaOrganization!,
                select: false,
                recover: true,
              ),
            ),
          );
        }
      });
    }
    final link = Uri.splitQueryString(Uri.base.fragment);
    final purpose = link['accountAction'];
    if (link['merchantInvite'] != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          navigatorKey.currentState?.push(
            MaterialPageRoute<void>(
              builder: (_) => MerchantInviteScreen(
                inviteId: link['merchantInvite'],
                token: link['inviteToken'],
              ),
            ),
          );
        }
      });
    }
    if ({'reset', 'verify', 'email'}.contains(purpose) &&
        link['challenge'] != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          navigatorKey.currentState?.push(
            MaterialPageRoute<void>(
              builder: (_) => AccountActionScreen(
                purpose: purpose!,
                challengeId: link['challenge'],
                initialCode: link['code'],
              ),
            ),
          );
        }
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    store.removeListener(openPendingSupport);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && store.remoteEnabled) {
      if (store.pendingOAuth != null) {
        unawaited(store.finishOAuth().catchError((_) => false));
      } else {
        unawaited(store.refreshRemote());
      }
    }
  }

  @override
  Widget build(BuildContext context) => StoreScope(
    store: store,
    child: ListenableBuilder(
      listenable: store,
      builder: (context, _) => MaterialApp(
        navigatorKey: navigatorKey,
        title: showAdmin
            ? 'Save Food Administrácia'
            : showMerchant
            ? 'Save Food Predajca'
            : 'Save Food',
        debugShowCheckedModeBanner: false,
        theme: appTheme(Brightness.light),
        darkTheme: appTheme(Brightness.dark),
        themeMode: store.themeMode,
        themeAnimationDuration:
            WidgetsBinding
                .instance
                .platformDispatcher
                .accessibilityFeatures
                .disableAnimations
            ? Duration.zero
            : const Duration(milliseconds: 220),
        locale: Locale(store.language),
        supportedLocales: const [Locale('sk'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        builder: (context, child) => UiLanguage(
          language: store.language,
          resolve: store.language == 'en' ? resolveEnglish : (value) => value,
          child: AnnotatedRegion<SystemUiOverlayStyle>(
            value: Theme.of(context).brightness == Brightness.dark
                ? SystemUiOverlayStyle.light
                : SystemUiOverlayStyle.dark,
            child: child!,
          ),
        ),
        home: showAdmin
            ? PlatformAdminScreen(
                onExit: () => setState(() => showAdmin = false),
              )
            : showMerchant
            ? MerchantPortalScreen(
                onExit: () {
                  setState(() => showMerchant = false);
                  unawaited(store.refreshRemote());
                },
              )
            : store.onboardingComplete ||
                  const bool.fromEnvironment('SKIP_ONBOARDING')
            ? const AppShell()
            : const OnboardingScreen(),
      ),
    ),
  );
}

class AppShell extends StatefulWidget {
  const AppShell({super.key});
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int selected = 0;
  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final c = context.colors;
    final isEnglish = store.language == 'en';
    final tabs = [
      isEnglish ? 'Discover' : 'Objavuj',
      isEnglish ? 'Explore' : 'Preskúmať',
      isEnglish ? 'Favorites' : 'Obľúbené',
    ];
    void explore() => setState(() => selected = 1);
    return Scaffold(
      extendBody: true,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1100),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 14),
                  child: Row(
                    children: [
                      Expanded(
                        child: Semantics(
                          button: true,
                          label: 'Vybrať polohu',
                          child: InkWell(
                            borderRadius: BorderRadius.circular(15),
                            onTap: () =>
                                pushPage(context, const LocationScreen()),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 5),
                              child: Row(
                                children: [
                                  Container(
                                    width: 38,
                                    height: 38,
                                    decoration: BoxDecoration(
                                      color: c.tint,
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    child: Icon(
                                      AppIcons.pin,
                                      size: 20,
                                      color: c.blue,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        AppText(
                                          isEnglish
                                              ? 'SOMETHING GOOD NEARBY'
                                              : 'NIEČO DOBRÉ V OKOLÍ',
                                          style: TextStyle(
                                            color: c.muted,
                                            fontSize: 9,
                                            fontWeight: FontWeight.w600,
                                            letterSpacing: 1,
                                          ),
                                        ),
                                        const SizedBox(height: 3),
                                        Row(
                                          children: [
                                            Flexible(
                                              child: AppText(
                                                store.locationLabel
                                                    .split(',')
                                                    .first,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: context.text.titleMedium
                                                    ?.copyWith(fontSize: 15),
                                              ),
                                            ),
                                            const SizedBox(width: 5),
                                            Icon(
                                              AppIcons.chevronDown,
                                              size: 14,
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const SupportActivityButton(round: true),
                      const SizedBox(width: 8),
                      RoundButton(
                        icon: AppIcons.bag,
                        label: 'Košík',
                        badge: store.cartCount,
                        onPressed: () => pushPage(context, const CartScreen()),
                      ),
                      const SizedBox(width: 8),
                      RoundButton(
                        icon: AppIcons.user,
                        label: 'Profil',
                        onPressed: () =>
                            pushPage(context, const ProfileScreen()),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (store.demoShowcase)
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1100),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Row(
                      children: [
                        const TagPill('DEMO'),
                        const SizedBox(width: 10),
                        Expanded(
                          child: AppText(
                            store.signedIn
                                ? store.name
                                : 'Pripravené účty a živý sklad',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.text.bodySmall,
                          ),
                        ),
                        TextButton(
                          onPressed: () async {
                            final persona = await showDemoPicker(context);
                            if (persona?.merchant == true && context.mounted) {
                              await pushPage(
                                context,
                                const MerchantPortalScreen(),
                              );
                              await store.refreshRemote();
                            } else if (persona?.id == 'support' &&
                                context.mounted) {
                              await pushPage(context, const SupportScreen());
                            }
                          },
                          child: const Text('Demo profily'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            if (store.notificationInfo != null)
              MaterialBanner(
                backgroundColor: c.tint,
                content: AppText(store.notificationInfo!),
                actions: [
                  TextButton(
                    onPressed: store.dismissNotification,
                    child: const AppText('Rozumiem'),
                  ),
                ],
              ),
            if (store.connectionError != null)
              MaterialBanner(
                backgroundColor: c.warm,
                content: AppText(store.connectionError!),
                actions: [
                  TextButton(
                    onPressed: store.refreshRemote,
                    child: const AppText('Znova'),
                  ),
                ],
              ),
            if (store.persistenceError != null)
              MaterialBanner(
                backgroundColor: c.warm,
                content: AppText(store.persistenceError!),
                actions: [
                  TextButton(
                    onPressed: () => store.retrySave().catchError((_) {}),
                    child: const AppText('Znova'),
                  ),
                ],
              ),
            Expanded(
              child: IndexedStack(
                index: selected,
                children: [
                  HomeScreen(onExplore: explore),
                  CatalogScreen(),
                  FavoritesScreen(onExplore: explore),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Align(
          heightFactor: 1,
          alignment: Alignment.bottomCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
              child: GlassSurface(
                child: Padding(
                  padding: const EdgeInsets.all(5),
                  child: Row(
                    children: List.generate(3, (i) {
                      final active = i == selected;
                      final icons = [
                        active ? AppIcons.homeActive : AppIcons.home,
                        active ? AppIcons.exploreActive : AppIcons.explore,
                        active ? AppIcons.heartActive : AppIcons.heart,
                      ];
                      return Expanded(
                        child: Semantics(
                          selected: active,
                          button: true,
                          label: tabs[i],
                          excludeSemantics: true,
                          child: InkWell(
                            onTap: () => setState(() => selected = i),
                            borderRadius: BorderRadius.circular(28),
                            child: AnimatedContainer(
                              duration: MediaQuery.disableAnimationsOf(context)
                                  ? Duration.zero
                                  : const Duration(milliseconds: 180),
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(
                                color: active ? c.tint : Colors.transparent,
                                borderRadius: BorderRadius.circular(28),
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    icons[i],
                                    size: 23,
                                    color: active ? c.blue : c.muted,
                                  ),
                                  const SizedBox(height: 4),
                                  AppText(
                                    tabs[i],
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: active
                                          ? FontWeight.w700
                                          : FontWeight.w500,
                                      color: active ? c.blue : c.muted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

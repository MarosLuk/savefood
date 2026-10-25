import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marketplace_data/marketplace_data.dart';
import 'package:nevyhadzuj/app.dart';
import 'package:nevyhadzuj/features/commerce.dart';
import 'package:nevyhadzuj/state/app_store.dart';

AppStore demoStore() => AppStore(
  MemoryMarketplaceRepository(),
  clock: () => DateTime(2026, 10, 23, 14),
)..onboardingComplete = true;
Future<void> launch(
  WidgetTester tester,
  AppStore store, {
  Size size = const Size(390, 844),
  double scale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(NevyhadzujApp(store: store));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    final loader = FontLoader('Inter')
      ..addFont(rootBundle.load('assets/fonts/InterVariable.ttf'));
    await loader.load();
  });
  testWidgets('home renders and all three tabs remain available', (
    tester,
  ) async {
    await launch(tester, demoStore());
    expect(find.text('Dobré jedlo.\nDruhá šanca.'), findsOneWidget);
    await tester.tap(find.text('Preskúmať'));
    await tester.pumpAndSettle();
    expect(find.text('Na čo máš chuť?'), findsOneWidget);
    await tester.tap(find.text('Obľúbené'));
    await tester.pumpAndSettle();
    expect(find.text('Tvoje srdcovky'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('saved offers appear and can be removed', (tester) async {
    final store = demoStore();
    store.toggleFavorite('butter');
    await launch(tester, store);
    await tester.tap(find.text('Obľúbené'));
    await tester.pumpAndSettle();
    expect(find.text('Láska na prvé sústo'), findsNothing);
    expect(store.saved, hasLength(1));
    store.toggleFavorite('butter');
    await tester.pumpAndSettle();
    expect(find.text('Láska na prvé sústo'), findsOneWidget);
  });
  testWidgets('dark mode changes surfaces and survives navigation', (
    tester,
  ) async {
    final store = demoStore();
    await launch(tester, store);
    store.setTheme(ThemeMode.dark);
    await tester.pumpAndSettle();
    final context = tester.element(find.byType(Scaffold).first);
    expect(Theme.of(context).brightness, Brightness.dark);
    await tester.tap(find.byTooltip('Profil'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nastavenia'));
    await tester.pumpAndSettle();
    expect(find.text('Tmavý'), findsOneWidget);
    await tester.tap(find.text('Svetlý'));
    await tester.pumpAndSettle();
    expect(store.themeMode, ThemeMode.light);
    expect(tester.takeException(), isNull);
  });
  testWidgets('empty cart offers a way back to the catalog', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: StoreScope(
          store: demoStore(),
          child: Builder(builder: (context) => const SizedBox()),
        ),
      ),
    );
    await launch(tester, demoStore());
    await tester.tap(find.byTooltip('Košík'));
    await tester.pumpAndSettle();
    expect(find.text('Miesto na niečo dobré'), findsOneWidget);
  });
  testWidgets('checkout blocks reservation without invoice and agreement', (
    tester,
  ) async {
    final store = demoStore();
    store.addToCart(store.offer('butter')!);
    await launch(tester, store);
    await tester.tap(find.byTooltip('Košík'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pokračovať k rezervácii'));
    await tester.pumpAndSettle();
    expect(find.byType(CheckoutScreen), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Demo rezervácia · 3,98 €'),
    );
    expect(button.onPressed, isNull);
  });
  testWidgets('English switches main navigation', (tester) async {
    final store = demoStore()..language = 'en';
    await launch(tester, store);
    expect(find.text('Discover'), findsOneWidget);
    expect(find.text('Good food.\nA second chance.'), findsOneWidget);
  });
  testWidgets('onboarding can be skipped without authentication', (
    tester,
  ) async {
    final store = demoStore()..onboardingComplete = false;
    await launch(tester, store);
    await tester.tap(find.text('Preskočiť'));
    await tester.pumpAndSettle();
    expect(find.text('Dobré jedlo.\nDruhá šanca.'), findsOneWidget);
    expect(store.signedIn, isFalse);
  });
  testWidgets('large accessibility text remains usable', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await launch(tester, demoStore());
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Preskúmať'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  for (final size in [
    const Size(375, 812),
    const Size(768, 1024),
    const Size(1440, 1000),
  ]) {
    testWidgets('home adapts to $size', (tester) async {
      await launch(tester, demoStore(), size: size);
      expect(tester.takeException(), isNull);
    });
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marketplace_data/marketplace_data.dart';
import 'package:marketplace_domain/marketplace_domain.dart';
import 'package:nevyhadzuj/app.dart';
import 'package:nevyhadzuj/features/commerce.dart';
import 'package:nevyhadzuj/state/app_store.dart';

void main() {
  setUpAll(() async {
    await (FontLoader(
      'Inter',
    )..addFont(rootBundle.load('assets/fonts/InterVariable.ttf'))).load();
  });
  testWidgets(
    'billing, checkout, confirmation and pickup form one working flow',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = AppStore(
        MemoryMarketplaceRepository(),
        clock: () => DateTime(2026, 10, 23, 14),
      )..onboardingComplete = true;
      store.addToCart(store.offer('butter')!);
      store.activateClub('');
      await tester.pumpWidget(NevyhadzujApp(store: store));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Košík'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pokračovať k rezervácii'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Doplniť fakturačné údaje'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Uložiť údaje'));
      await tester.pumpAndSettle();
      expect(find.text('Zadaj celé meno.'), findsOneWidget);
      final fields = find.byType(TextFormField);
      final values = [
        'Jana Test',
        'jana@example.test',
        'Testovacia 1',
        'Bratislava',
        '81101',
      ];
      for (var index = 0; index < values.length; index++) {
        await tester.ensureVisible(fields.at(index));
        await tester.enterText(fields.at(index), values[index]);
      }
      await tester.tap(find.text('Uložiť údaje'));
      await tester.pumpAndSettle();
      final scrollable = find
          .descendant(
            of: find.byType(CheckoutScreen),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(
        find.byType(CheckboxListTile),
        300,
        scrollable: scrollable,
      );
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Demo rezervácia · 3,98 €'));
      await tester.pumpAndSettle();
      expect(find.text('Dobrá vec sa podarila.'), findsOneWidget);
      expect(store.orders, hasLength(1));
      expect(store.cart, isEmpty);
      await tester.tap(find.text('Mám vyzdvihnuté'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Potvrdiť prevzatie'));
      await tester.pumpAndSettle();
      expect(store.orders.single.status, OrderStatus.collected);
      expect(store.credit, 39);
      expect(tester.takeException(), isNull);
    },
  );
}

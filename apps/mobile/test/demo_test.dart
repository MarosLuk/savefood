import 'dart:convert';
import 'dart:io';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:marketplace_data/marketplace_data.dart';
import 'package:nevyhadzuj/features/demo.dart';
import 'package:nevyhadzuj/state/app_store.dart';

AppStore demoStore({bool enabled = true}) {
  var persona = 'customer';
  final api = MarketplaceApi(
    'https://demo.example.test',
    vault: MemoryTokenVault(),
    client: MockClient((r) async {
      Object result;
      switch (r.url.path) {
        case '/v1/config':
          result = {'demoShowcase': enabled, 'paymentMode': 'sandbox'};
        case '/v1/catalog':
          result = {
            'offers': seedCatalog(
              DateTime(2026, 10, 25, 12),
            ).map((o) => o.toJson()).toList(),
          };
        case '/v1/auth/demo':
          persona = (jsonDecode(r.body) as Map)['persona'] as String;
          result = {'token': 'demo-session-$persona'};
        case '/v1/me':
          result = {
            'name': persona,
            'email': '$persona@demo.nevyhadzuj.test',
            'credit': persona == 'customer' ? 750 : 0,
            'favorites': persona == 'customer' ? ['butter'] : <String>[],
            'orders': <Object>[],
            'invoice': <String, dynamic>{},
          };
        default:
          result = <String, dynamic>{};
      }
      return http.Response(
        jsonEncode(result),
        200,
        headers: {'content-type': 'application/json'},
      );
    }),
  );
  return AppStore(
    MemoryMarketplaceRepository(),
    api: api,
    clock: () => DateTime(2026, 10, 25, 12),
  );
}

void main() {
  test(
    'switching demo accounts clears cart, checkout and previous private data',
    () async {
      final s = demoStore();
      addTearDown(s.dispose);
      await s.initializeRemote();
      await s.enterDemo('customer');
      expect(s.credit, 750);
      expect(s.favorites, {'butter'});
      s.addToCart(s.offer('butter')!);
      s.coupon = 'VITAJ';
      s.useCredit = true;
      await s.enterDemo('bakery');
      expect(s.email, 'bakery@demo.nevyhadzuj.test');
      expect(s.credit, 0);
      expect(s.favorites, isEmpty);
      expect(s.orders, isEmpty);
      expect(s.cart, isEmpty);
      expect(s.coupon, isEmpty);
      expect(s.useCredit, false);
      expect(s.onboardingComplete, true);
      await s.enterDemo('customer');
      expect(s.credit, 750);
      expect(s.favorites, {'butter'});
    },
  );
  test('ordinary API cannot expose demo profiles', () async {
    final s = demoStore(enabled: false);
    addTearDown(s.dispose);
    await s.initializeRemote();
    await expectLater(s.enterDemo('bakery'), throwsStateError);
    expect(s.signedIn, false);
  });
  test(
    'all curated photos exist, decode and galleries contain no duplicate images',
    () async {
      for (final name in demoImageNames) {
        final bytes = await File('assets/images/$name.jpg').readAsBytes();
        final decoded = await decodeImageFromList(bytes);
        expect(decoded.width, greaterThanOrEqualTo(600));
        decoded.dispose();
        final gallery = offerGallery(name);
        expect(gallery.toSet().length, gallery.length);
        expect(gallery.every(demoImageNames.contains), true);
      }
      expect(offerGallery('https://merchant.example.test/own.jpg'), [
        'https://merchant.example.test/own.jpg',
      ]);
    },
  );

  for (final size in [const Size(375, 812), const Size(1440, 1000)]) {
    for (final brightness in Brightness.values) {
      testWidgets(
        'demo picker fits $size in $brightness and opens chosen identity',
        (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final store = demoStore();
          addTearDown(store.dispose);
          await store.initializeRemote();
          await tester.pumpWidget(
            StoreScope(
              store: store,
              child: MaterialApp(
                theme: appTheme(brightness),
                home: Builder(
                  builder: (context) => Scaffold(
                    body: DemoAccessCard(
                      onPressed: () => showDemoPicker(context),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.text('Otvoriť pripravené demo'));
          await tester.pumpAndSettle();
          expect(find.text('Sofia · zákazníčka'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.tap(find.text('Sofia · zákazníčka'));
          await tester.pumpAndSettle();
          expect(store.signedIn, true);
          expect(store.email, 'customer@demo.nevyhadzuj.test');
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}

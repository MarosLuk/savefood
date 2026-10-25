import 'dart:io';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:design_system/design_system.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:marketplace_data/marketplace_data.dart';
import 'package:nevyhadzuj/features/merchant/controller.dart';
import 'package:nevyhadzuj/features/merchant/portal.dart';
import 'package:nevyhadzuj/state/app_store.dart';
import 'support/merchant_fixture.dart';

void main() {
  testWidgets(
    'export actual merchant Flutter screens for web and mobile',
    (tester) async {
      for (final font in {
        'Inter': 'assets/fonts/InterVariable.ttf',
        'packages/phosphor_flutter/PhosphorRegular':
            'packages/phosphor_flutter/lib/fonts/Phosphor.ttf',
        'packages/phosphor_flutter/PhosphorFill':
            'packages/phosphor_flutter/lib/fonts/Phosphor-Fill.ttf',
      }.entries) {
        await (FontLoader(
          font.key,
        )..addFont(rootBundle.load(font.value))).load();
      }
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      for (final size in [const Size(1440, 1000), const Size(402, 874)]) {
        tester.view.physicalSize = size;
        for (final brightness in [Brightness.light, Brightness.dark]) {
          await tester.pumpWidget(const SizedBox.shrink());
          final api = MarketplaceApi(
            'https://api.example.test',
            vault: MemoryTokenVault(),
            client: MockClient(
              (r) async => http.Response(
                jsonEncode(merchantFixture()),
                200,
                headers: {'content-type': 'application/json'},
              ),
            ),
          );
          final c = MerchantController(api);
          await c.load();
          final app = AppStore(
            MemoryMarketplaceRepository(),
            clock: () => DateTime(2026, 10, 24, 12),
          );
          final key = GlobalKey();
          await tester.pumpWidget(
            RepaintBoundary(
              key: key,
              child: StoreScope(
                store: app,
                child: MaterialApp(
                  debugShowCheckedModeBanner: false,
                  theme: appTheme(brightness),
                  home: MerchantPortalScreen(controller: c),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          for (final page in {
            'overview': 'Prehľad',
            'stock': 'Sklad',
            'automation': 'Pravidlá',
          }.entries) {
            if (page.key != 'overview') {
              await tester.tap(find.text(page.value).last);
              await tester.pumpAndSettle();
            }
            expect(tester.takeException(), isNull);
            await tester.runAsync(() async {
              final boundary =
                  key.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary;
              final img = await boundary.toImage(
                pixelRatio: size.width > 1000 ? 1 : 2,
              );
              final bytes = await img.toByteData(
                format: ui.ImageByteFormat.png,
              );
              await File(
                '../../docs/screenshots/merchant-${size.width > 1000 ? 'web' : 'mobile'}-${page.key}-${brightness.name}.png',
              ).writeAsBytes(bytes!.buffer.asUint8List());
              img.dispose();
            });
          }
          await tester.pumpWidget(const SizedBox.shrink());
          c.dispose();
          app.dispose();
          api.close();
        }
      }
    },
    skip: !const bool.fromEnvironment('CAPTURE_PREVIEWS'),
  );
}

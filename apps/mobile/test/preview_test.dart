import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marketplace_data/marketplace_data.dart';
import 'package:nevyhadzuj/app.dart';
import 'package:nevyhadzuj/features/offer_detail.dart';
import 'package:nevyhadzuj/features/commerce.dart';
import 'package:nevyhadzuj/state/app_store.dart';
import 'package:nevyhadzuj/widgets/payment_options.dart';

void main() {
  testWidgets(
    'export actual Flutter screens for visual review',
    (tester) async {
      for (final font in {
        'Inter': 'assets/fonts/InterVariable.ttf',
        'packages/phosphor_flutter/PhosphorRegular':
            'packages/phosphor_flutter/lib/fonts/Phosphor.ttf',
        'packages/phosphor_flutter/PhosphorFill':
            'packages/phosphor_flutter/lib/fonts/Phosphor-Fill.ttf',
      }.entries) {
        final loader = FontLoader(font.key)
          ..addFont(rootBundle.load(font.value));
        await loader.load();
      }
      tester.view.physicalSize = const Size(402, 874);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final mode in [ThemeMode.light, ThemeMode.dark]) {
        await tester.pumpWidget(const SizedBox.shrink());
        final store =
            AppStore(
                MemoryMarketplaceRepository(),
                clock: () => DateTime(2026, 10, 23, 14),
              )
              ..onboardingComplete = true
              ..themeMode = mode;
        final key = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: key,
            child: NevyhadzujApp(store: store),
          ),
        );
        await tester.pumpAndSettle();
        await tester.runAsync(() async {
          final context = key.currentContext!;
          await Future.wait(
            [
              'bakery',
              'bread',
              'salad',
              'meal',
              'dessert',
              'vegetables',
              'flowers',
              'coffee',
              'cafe',
              'toast',
            ].map(
              (image) => precacheImage(
                AssetImage('assets/images/$image.jpg'),
                context,
              ),
            ),
          );
        });
        await tester.pumpAndSettle();
        Future<void> capture(String name) async {
          expect(tester.takeException(), isNull);
          await tester.runAsync(() async {
            final boundary =
                key.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            final image = await boundary.toImage(pixelRatio: 2);
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            final file = File(
              '../../docs/screenshots/flutter-$name-${mode.name}.png',
            );
            await file.parent.create(recursive: true);
            await file.writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }

        await capture('home');
        await tester.tap(find.text('Preskúmať'));
        await tester.pumpAndSettle();
        await capture('catalog');
        final context = tester.element(find.byType(Scaffold).first);
        unawaited(
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const OfferDetailScreen(offerId: 'butter'),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await capture('detail');
        store.addToCart(store.offer('butter')!);
        unawaited(
          Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const CheckoutScreen()),
          ),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byType(PaymentOptions));
        await tester.pumpAndSettle();
        await capture('checkout');
      }
    },
    skip: !const bool.fromEnvironment('CAPTURE_PREVIEWS'),
  );
}

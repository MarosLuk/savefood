import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:design_system/design_system.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:marketplace_data/marketplace_data.dart';
import 'package:nevyhadzuj/state/app_store.dart';
import 'package:nevyhadzuj/features/account_security.dart';
import 'package:nevyhadzuj/features/billing.dart';
import 'package:nevyhadzuj/features/legal.dart';
import 'package:nevyhadzuj/features/reviews.dart';
import 'package:nevyhadzuj/features/platform/admin.dart';
import 'package:nevyhadzuj/features/platform/readiness.dart';
import 'package:nevyhadzuj/features/merchant/controller.dart';
import 'package:nevyhadzuj/features/merchant/team.dart';
import 'package:nevyhadzuj/features/merchant/media_library.dart';
import 'support/merchant_fixture.dart';

void main() {
  setUpAll(() async {
    for (final font in {
      'Inter': 'assets/fonts/InterVariable.ttf',
      'packages/phosphor_flutter/PhosphorRegular':
          'packages/phosphor_flutter/lib/fonts/Phosphor.ttf',
    }.entries) {
      await (FontLoader(font.key)..addFont(rootBundle.load(font.value))).load();
    }
  });
  final policy = {
    'configured': true,
    'operator': 'DEMO · Nevyhadzuj',
    'registration': '00000000',
    'address': 'Ilustračná adresa, Bratislava',
    'contact': 'privacy@demo.nevyhadzuj.test',
    'version': 1,
    'revision': 1,
    'publishedVersion': 1,
    'publishedAt': '2026-10-25',
    'terms':
        'Demo podmienky pre nezáväzné ukážkové rezervácie. Obsah balíčka je uvedený pri ponuke a výdaj je možný iba v označenom čase. Ide o ilustračné údaje.',
    'privacy':
        'Demo aplikácia spracúva profil a objednávky, ktoré si vytvoríš. V nastaveniach máš možnosť údaje exportovať, upraviť a po dokončení objednávok účet odstrániť.',
    'retention': {
      'orders': 3650,
      'support': 365,
      'accountAudit': 365,
      'mail': 30,
      'mediaDraftHours': 24,
    },
    'demo': true,
  };
  final profile = {
    'configured': true,
    'version': 1,
    'name': 'DEMO · Dobrá pekáreň',
    'address': 'Ilustračná adresa',
    'companyId': '00000000',
    'country': 'SK',
    'contactEmail': 'billing@demo.nevyhadzuj.test',
    'prefix': 'DEMOS',
    'taxMode': 'notVat',
    'taxId': '',
    'vatId': '',
    'retentionDays': 3650,
    'rates': {},
  };
  Future<AppStore> setup({
    void Function(http.Request)? observe,
    Future<http.Response?> Function(http.Request)? respond,
  }) async {
    final vault = MemoryTokenVault();
    await vault.write('test-token');
    final api = MarketplaceApi(
      'https://api.example.test',
      vault: vault,
      client: MockClient((r) async {
        observe?.call(r);
        final override = await respond?.call(r);
        if (override != null) return override;
        final path = r.url.path;
        Object result;
        if (path == '/v1/legal' || path == '/v1/platform/legal') {
          result = policy;
        } else if (path.contains('/billing')) {
          result = {
            'profile': profile,
            'model': 'merchantSeller',
            'connectors': [],
          };
        } else if (path.contains('/documents')) {
          result = {
            'rows': [
              {
                'id': 'doc',
                'number': 'DEMOS-2026-000001',
                'kind': 'invoice',
                'issuedAt': '2026-10-25',
                'title': 'Voňavý pekárenský balíček',
                'gross': 399,
                'demo': true,
              },
            ],
          };
        } else if (path == '/v1/platform/overview') {
          result = {
            'users': 1250,
            'organizations': 84,
            'stores': 112,
            'offers': 630,
            'reviews': 490,
            'openTickets': 12,
            'role': 'admin',
          };
        } else if (path == '/v1/platform/readiness') {
          result = {
            'launchReady': false,
            'checks': [
              {
                'key': 'database',
                'label': 'Databáza je dostupná',
                'ok': true,
                'required': true,
              },
              {
                'key': 'mail',
                'label': 'E-mailová služba je nakonfigurovaná',
                'ok': false,
                'required': true,
              },
            ],
            'requests': {},
            'documentsPending': 0,
            'refundsPending': 0,
            'uptimeSeconds': 180,
            'mail': [],
          };
        } else if (path.startsWith('/v1/platform/resources/')) {
          result = {
            'rows': [
              {
                'id': 'user-1',
                'name': 'Sofia Novotná',
                'email': 'sofia@demo.nevyhadzuj.test',
                'email_verified': 1,
                'disabled': 0,
                'version': 0,
              },
            ],
          };
        } else if (path.endsWith('/reviews')) {
          result = {
            'reviews': [],
            'summary': {
              'count': 24,
              'average': 4.8,
              'quality': 4.9,
              'value': 4.8,
              'quantity': 4.6,
              'pickup': 4.9,
              'stars': {'5': 20, '4': 3, '3': 1},
            },
            'eligible': true,
          };
        } else if (path == '/v1/merchant/media') {
          result = {'photos': []};
        } else if (path.contains('/access')) {
          result = {
            'members': [
              {
                'userId': 'owner',
                'name': 'Sofia',
                'email': 'owner@demo.nevyhadzuj.test',
                'role': 'owner',
              },
            ],
            'invites': [],
          };
        } else if (path == '/v1/merchant/workspace') {
          result = merchantFixture();
        } else {
          result = {};
        }
        return http.Response(
          jsonEncode(result),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    await api.restoreSession();
    return AppStore(MemoryMarketplaceRepository(), api: api)
      ..email = 'sofia@demo.nevyhadzuj.test'
      ..name = 'Sofia Novotná'
      ..emailVerified = true
      ..platformRole = 'admin'
      ..serverConfig = {'demoShowcase': true, 'paymentMode': 'sandbox'};
  }

  for (final size in [const Size(375, 812), const Size(1440, 1000)]) {
    for (final brightness in Brightness.values) {
      testWidgets('completion screens fit $size / ${brightness.name}', (
        tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final store = await setup();
        final c = MerchantController(store.api!);
        await c.load();
        addTearDown(store.dispose);
        addTearDown(c.dispose);
        final pages = <String, Widget>{
          'account-security': const AccountSecurityScreen(),
          'billing': const BillingScreen(organizationId: 'org'),
          'legal': const LegalScreen(consent: true),
          'admin': const PlatformAdminScreen(),
          'readiness': const PlatformReadinessScreen(),
          'team': MerchantTeamScreen(controller: c),
          'media': const MerchantMediaScreen(organizationId: 'org'),
          'reviews': const Scaffold(body: ReviewsSheet(offerId: 'offer')),
        };
        for (final entry in pages.entries) {
          await tester.pumpWidget(const SizedBox.shrink());
          final key = GlobalKey();
          await tester.pumpWidget(
            RepaintBoundary(
              key: key,
              child: StoreScope(
                store: store,
                child: MaterialApp(
                  debugShowCheckedModeBanner: false,
                  theme: appTheme(brightness),
                  home: entry.value,
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: entry.key);
          if (Platform.environment['RENDER_COMPLETION'] == '1' &&
              {'billing', 'admin', 'reviews', 'team'}.contains(entry.key)) {
            await tester.runAsync(() async {
              final boundary =
                  key.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary;
              final picture = await boundary.toImage();
              final bytes = await picture.toByteData(
                format: ui.ImageByteFormat.png,
              );
              await File(
                '../../docs/screenshots/completion-${entry.key}-${size.width < 600 ? 'mobile' : 'web'}-${brightness.name}.png',
              ).writeAsBytes(bytes!.buffer.asUint8List());
              picture.dispose();
            });
          }
        }
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
  testWidgets(
    'billing form sends integer retention and exact VAT basis points',
    (tester) async {
      Map? submitted;
      final store = await setup(
        observe: (r) {
          if (r.method == 'POST' && r.url.path == '/v1/merchant/billing/org') {
            submitted = jsonDecode(r.body) as Map;
          }
        },
      );
      addTearDown(store.dispose);
      await tester.pumpWidget(
        StoreScope(
          store: store,
          child: MaterialApp(
            theme: appTheme(Brightness.light),
            home: const BillingScreen(organizationId: 'org'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Fakturačný profil a sadzby'));
      await tester.pumpAndSettle();
      final rate = find.byKey(const ValueKey('merchant-rate_bakery'));
      await tester.ensureVisible(rate);
      await tester.enterText(rate, '23');
      await tester.tap(find.text('Uložiť'));
      await tester.pumpAndSettle();
      expect(submitted?['retentionDays'], 3650);
      expect(submitted?['rates']['bakery'], 2300);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'switching accounts discards late private responses and starts a fresh load',
    (tester) async {
      for (final kind in ['reviews', 'documents', 'media']) {
        final old = Completer<http.Response>();
        var calls = 0;
        Map<String, dynamic> payload(String text) => switch (kind) {
          'reviews' => {
            'reviews': [],
            'eligible': true,
            'ownReview': {
              'rating': 4,
              'comment': text,
              'quality': 4,
              'value': 4,
              'quantity': 4,
              'pickup': 4,
              'version': 1,
              'attachments': [],
            },
            'summary': {'count': 1, 'average': 4},
          },
          'documents' => {
            'rows': [
              {
                'id': text,
                'number': 'DEMO-1',
                'kind': 'invoice',
                'title': text,
                'issuedAt': '2026-10-25',
                'gross': 399,
              },
            ],
          },
          _ => {'photos': []},
        };
        http.Response response(Map body) => http.Response(
          jsonEncode(body),
          200,
          headers: {'content-type': 'application/json'},
        );
        final store = await setup(
          respond: (r) async {
            final matches = kind == 'reviews'
                ? r.url.path.endsWith('/reviews')
                : kind == 'documents'
                ? r.url.path == '/v1/merchant/documents/org'
                : r.url.path == '/v1/merchant/media';
            if (!matches) return null;
            calls++;
            return calls == 1
                ? old.future
                : response(payload('account-second'));
          },
        );
        final screen = switch (kind) {
          'reviews' => const Scaffold(body: ReviewsSheet(offerId: 'offer')),
          'documents' => const BillingScreen(organizationId: 'org'),
          _ => const MerchantMediaScreen(organizationId: 'org'),
        };
        await tester.pumpWidget(
          StoreScope(
            store: store,
            child: MaterialApp(theme: appTheme(Brightness.light), home: screen),
          ),
        );
        await tester.pump();
        expect(calls, 1);
        store.email = 'second@example.test';
        store.receiveSupportActivity();
        await tester.pumpAndSettle();
        expect(calls, 2, reason: kind);
        old.complete(response(payload('private-first')));
        await tester.pumpAndSettle();
        expect(
          find.textContaining('private-first'),
          findsNothing,
          reason: kind,
        );
        if (kind != 'media') {
          expect(
            find.textContaining('account-second'),
            findsOneWidget,
            reason: kind,
          );
        }
        expect(tester.takeException(), isNull, reason: kind);
        await tester.pumpWidget(const SizedBox.shrink());
        store.dispose();
      }
    },
  );
}

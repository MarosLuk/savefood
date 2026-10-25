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
import 'package:nevyhadzuj/features/merchant/finance.dart';
import 'package:nevyhadzuj/features/support/support.dart';
import 'package:nevyhadzuj/state/app_store.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

Map<String, dynamic> ticketFixture({
  bool agent = false,
  String id = 'ticket-123',
}) => {
  'id': id,
  'number': 'NVP-00001',
  'subject': 'Otázka k môjmu balíčku',
  'category': 'pickup',
  'status': 'open',
  'priority': 'normal',
  'createdAt': '2026-10-25T12:00:00Z',
  'updatedAt': '2026-10-25T12:00:00Z',
  'canManage': agent,
  'version': 1,
  'messages': [
    {
      'id': 'm1',
      'author': 'customer',
      'body': 'Kde je výdajné miesto?',
      'createdAt': '2026-10-25T12:00:00Z',
    },
    {
      'id': 'm2',
      'author': 'assistant',
      'body': 'Čas a adresu nájdeš v detaile objednávky.',
      'createdAt': '2026-10-25T12:01:00Z',
    },
  ],
};
Map<String, dynamic> financeFixture() => {
  'organization': 'Pekáreň Maslo',
  'organizationId': 'org',
  'currency': 'EUR',
  'mode': 'sandbox',
  'connectEnabled': true,
  'account': {'id': 'demo_acct_org', 'ready': true, 'automatic': false},
  'commissionBps': 1000,
  'delayHours': 24,
  'totals': {
    'sales': 16800,
    'refunded': 900,
    'commission': 1590,
    'sellerNet': 14310,
    'transferred': 9900,
    'eligible': 4410,
  },
  'entries': [
    {
      'id': 'line',
      'orderId': '12345678-order',
      'store': 'Pekáreň Maslo',
      'storeId': 'store',
      'offerId': 'bread',
      'title': 'Voňavý koniec dňa',
      'image': 'bread',
      'quantity': 2,
      'gross': 900,
      'discount': 90,
      'commission': 81,
      'sellerNet': 729,
      'state': 'eligible',
      'createdAt': '2026-10-25T12:00:00Z',
      'providerIds': <String>[],
    },
  ],
};

void main() {
  const capturePreviews = bool.fromEnvironment('CAPTURE_PREVIEWS');
  final captureKey = GlobalKey();
  var fontsLoaded = false;
  Future<void> capture(WidgetTester tester, String name) async {
    if (!capturePreviews) return;
    if (!fontsLoaded) {
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
      fontsLoaded = true;
      await tester.pumpAndSettle();
    }
    await tester.runAsync(() async {
      final boundary =
          captureKey.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
      final picture = await boundary.toImage();
      final bytes = await picture.toByteData(format: ui.ImageByteFormat.png);
      await File(
        '../../docs/screenshots/$name.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
      picture.dispose();
    });
  }

  test(
    'accounting export includes the final calendar day across Bratislava DST and year boundaries',
    () {
      tz_data.initializeTimeZones();
      final place = tz.getLocation('Europe/Bratislava');
      expect(
        accountingExportDates(
          tz.TZDateTime(place, 2026, 9, 25),
          tz.TZDateTime(place, 2026, 10, 25),
        ),
        ('2026-09-25', '2026-10-26'),
      );
      expect(
        accountingExportDates(
          tz.TZDateTime(place, 2026, 3, 29),
          tz.TZDateTime(place, 2026, 3, 29),
        ),
        ('2026-03-29', '2026-03-30'),
      );
      expect(
        accountingExportDates(DateTime(2026, 12, 31), DateTime(2026, 12, 31)),
        ('2026-12-31', '2027-01-01'),
      );
    },
  );
  Future<AppStore> store({
    bool agent = false,
    void Function(http.Request)? observe,
  }) async {
    final vault = MemoryTokenVault();
    await vault.write('mock-token');
    final api = MarketplaceApi(
      'https://api.example.test',
      vault: vault,
      client: MockClient((r) async {
        observe?.call(r);
        Object result;
        if (r.url.path == '/v1/support/tickets' && r.method == 'GET') {
          result = {
            'isAgent': agent,
            'tickets': [ticketFixture(agent: agent)],
          };
        } else if (r.url.path.startsWith('/v1/support/')) {
          result = ticketFixture(agent: agent);
        } else if (r.url.path == '/v1/merchant/finance/org') {
          result = financeFixture();
        } else {
          result = {'queued': 0};
        }
        return http.Response(
          jsonEncode(result),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    await api.restoreSession();
    final s = AppStore(MemoryMarketplaceRepository(), api: api)
      ..email = 'demo@example.test'
      ..name = 'Sofia';
    addTearDown(s.dispose);
    return s;
  }

  Future<void> mount(
    WidgetTester tester,
    AppStore s,
    Widget screen,
    Size size,
    Brightness brightness, {
    double scale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
    });
    await tester.pumpWidget(
      RepaintBoundary(
        key: captureKey,
        child: StoreScope(
          store: s,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: appTheme(brightness),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: screen,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final size in [const Size(375, 812), const Size(1440, 1000)]) {
    for (final brightness in Brightness.values) {
      testWidgets('finance and support fit $size $brightness', (tester) async {
        final s = await store();
        await mount(
          tester,
          s,
          const MerchantFinanceScreen(organizationId: 'org'),
          size,
          brightness,
        );
        expect(find.text('Dobré jedlo.\nPrehľadné čísla.'), findsOneWidget);
        expect(tester.takeException(), isNull);
        final device = size.width < 600 ? 'mobile' : 'web';
        await capture(tester, 'finance-$device-render-${brightness.name}');
        await mount(tester, s, const SupportScreen(), size, brightness);
        expect(find.text('Otázka k môjmu balíčku'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await capture(tester, 'support-$device-render-${brightness.name}');
        await tester.ensureVisible(find.text('Otázka k môjmu balíčku'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Otázka k môjmu balíčku'));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('Automatický asistent'),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        expect(find.text('Automatický asistent'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }
  testWidgets('customer creates a ticket with no order and sends a follow-up', (
    tester,
  ) async {
    final writes = <http.Request>[];
    final s = await store(
      observe: (r) {
        if (r.method == 'POST') writes.add(r);
      },
    );
    await mount(
      tester,
      s,
      const SupportScreen(),
      const Size(390, 844),
      Brightness.light,
    );
    await tester.tap(find.byKey(const ValueKey('support-create-ticket')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('merchant-subject')),
      'Potrebujem pomoc',
    );
    await tester.enterText(
      find.byKey(const ValueKey('merchant-message')),
      'Prosím o informáciu k aplikácii.',
    );
    await tester.ensureVisible(find.text('Uložiť'));
    await tester.tap(find.text('Uložiť'));
    await tester.pumpAndSettle();
    final create = writes.firstWhere(
      (r) => r.url.path == '/v1/support/tickets',
    );
    expect((jsonDecode(create.body) as Map)['orderId'], isNull);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('support-reply-message')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(
      find.byKey(const ValueKey('support-reply-message')),
      'Ďakujem, dopĺňam podrobnosti.',
    );
    await tester.ensureVisible(find.text('Odoslať správu'));
    await tester.tap(find.text('Odoslať správu'));
    await tester.pumpAndSettle();
    expect(writes.any((r) => r.url.path.endsWith('/messages')), true);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'operator has assignment and internal-note controls; customer does not',
    (tester) async {
      final s = await store(agent: true);
      await mount(
        tester,
        s,
        const TicketScreen(ticketId: 'ticket-123'),
        const Size(390, 844),
        Brightness.dark,
      );
      expect(find.text('Pracovisko operátora'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Interná poznámka · zákazník ju neuvidí'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        find.text('Interná poznámka · zákazník ju neuvidí'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('large text preserves readable finance content', (tester) async {
    final s = await store();
    await mount(
      tester,
      s,
      const MerchantFinanceScreen(organizationId: 'org'),
      const Size(390, 844),
      Brightness.dark,
      scale: 1.8,
    );
    expect(tester.takeException(), isNull);
  });
}

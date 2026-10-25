import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:design_system/design_system.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image_picker/image_picker.dart';
import 'package:marketplace_data/marketplace_data.dart';
import 'package:nevyhadzuj/features/support/activity.dart';
import 'package:nevyhadzuj/features/support/photo.dart';
import 'package:nevyhadzuj/features/support/support.dart';
import 'package:nevyhadzuj/state/app_store.dart';
import 'operations_test.dart' show ticketFixture;

void main() {
  final png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jS1sAAAAASUVORK5CYII=',
  );
  Future<AppStore> setup(List<http.Request> writes) async {
    var read = false;
    final vault = MemoryTokenVault();
    await vault.write('mock-session');
    final api = MarketplaceApi(
      'https://api.example.test',
      vault: vault,
      client: MockClient((r) async {
        if (r.method == 'POST') writes.add(r);
        Object result;
        if (r.url.path == '/v1/support/notifications') {
          result = {
            'unread': read ? 0 : 1,
            'through': 12,
            'notifications': [
              {
                'id': 12,
                'ticketId': 'ticket-123',
                'number': 'NVP-00001',
                'subject': 'Odpoveď ku kvalite',
                'createdAt': '2026-10-25T12:00:00Z',
                'read': read,
              },
            ],
          };
        } else if (r.url.path.endsWith('/photos') && r.method == 'POST') {
          result = {
            'id': 'photo-1',
            'width': 1,
            'height': 1,
            'size': png.length,
          };
        } else if (r.url.path == '/v1/support/photos/photo-1') {
          return http.Response.bytes(
            png,
            200,
            headers: {'content-type': 'image/png'},
          );
        } else {
          if (r.url.path.endsWith('/read')) read = true;
          result = {...ticketFixture(), 'lastMessageCursor': 2};
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
      ..email = 'sofia@example.test';
    addTearDown(s.dispose);
    addTearDown(api.close);
    return s;
  }

  Future<void> mount(WidgetTester t, AppStore s, Widget screen) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    addTearDown(() => t.pumpWidget(const SizedBox.shrink()));
    await t.pumpWidget(
      StoreScope(
        store: s,
        child: MaterialApp(theme: appTheme(Brightness.dark), home: screen),
      ),
    );
    await t.pumpAndSettle();
  }

  testWidgets(
    'a selected private photo uploads and its ID is sent with the reply',
    (t) async {
      final writes = <http.Request>[];
      final s = await setup(writes);
      await mount(
        t,
        s,
        TicketScreen(
          ticketId: 'ticket-123',
          photoPicker: (_) async => [XFile.fromData(png, name: 'claim.png')],
        ),
      );
      await t.scrollUntilVisible(
        find.text('Priložiť fotografie'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await t.pumpAndSettle();
      await t.tap(find.text('Priložiť fotografie'));
      await t.pumpAndSettle();
      expect(find.byType(SupportPhotoView), findsOneWidget);
      await t.scrollUntilVisible(
        find.text('Odoslať správu'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await t.pumpAndSettle();
      await t.tap(find.text('Odoslať správu'));
      await t.pumpAndSettle();
      final upload = writes.firstWhere((r) => r.url.path.endsWith('/photos'));
      expect(upload.headers['Authorization'], 'Bearer mock-session');
      final reply = writes.firstWhere((r) => r.url.path.endsWith('/messages'));
      expect((jsonDecode(reply.body) as Map)['attachments'], ['photo-1']);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'notification opens its ticket and acknowledges only the loaded message cursor',
    (t) async {
      final writes = <http.Request>[];
      final s = await setup(writes);
      await mount(t, s, const SupportActivityScreen());
      await t.scrollUntilVisible(
        find.text('Odpoveď ku kvalite'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await t.pumpAndSettle();
      await t.tap(find.text('Odpoveď ku kvalite'));
      await t.pumpAndSettle();
      expect(find.text('Otázka k môjmu balíčku'), findsOneWidget);
      final read = writes.firstWhere((r) => r.url.path.endsWith('/read'));
      expect((jsonDecode(read.body) as Map)['through'], 2);
      expect(t.takeException(), isNull);
    },
  );
}

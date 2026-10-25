import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:marketplace_server/marketplace_server.dart';
import 'package:marketplace_server/src/support.dart';
import 'package:marketplace_server/src/auth.dart';
import 'package:test/test.dart';

class SupportTestPush implements StockPushGateway {
  final sent = <Map<String, String>>[];
  @override
  bool get configured => true;
  @override
  Future<bool> send(
    String token,
    String title,
    String body,
    Map<String, String> data,
  ) async {
    sent.add({'token': token, 'title': title, 'body': body, ...data});
    return true;
  }

  @override
  void close() {}
}

void main() {
  late MarketplaceServer app;
  late String id;
  setUp(() {
    app = MarketplaceServer(
      const ServerConfig(databasePath: ':memory:', demoShowcase: true),
      clock: () => DateTime.utc(2026, 10, 25, 12),
    );
    id =
        app.support.create('showcase-customer', {
              'subject': 'Šarža chladenej zeleniny',
              'message': 'Prosím preveriť kvalitu balíčka.',
              'category': 'foodQuality',
            })['id']
            as String;
  });
  tearDown(() => app.close());
  Uint8List photo() =>
      Uint8List.fromList(img.encodePng(img.Image(width: 8, height: 6)));
  test(
    'photos are transcoded and scoped to ticket, sender and internal message',
    () async {
      final p = await app.support.addPhoto('showcase-support', id, photo());
      expect(p['mimeType'], 'image/jpeg');
      expect(p['width'], 8);
      expect(
        () => app.support.photo('showcase-bakery', p['id'] as String),
        throwsA(isA<ApiFailure>()),
      );
      expect(
        () => app.support.photo('showcase-customer', p['id'] as String),
        throwsA(isA<ApiFailure>()),
      );
      final message = app.support.reply('showcase-support', id, {
        'message': 'Súkromné posúdenie fotografie',
        'internal': true,
        'attachments': [p['id']],
      });
      expect((message['messages'] as List).last['attachments'], hasLength(1));
      expect(
        (app.support.ticket('showcase-customer', id)['messages'] as List)
            .length,
        2,
      );
      expect(
        () => app.support.photo('showcase-customer', p['id'] as String),
        throwsA(isA<ApiFailure>()),
      );
      expect(
        img
            .decodeJpg(
              app.support.photo('showcase-support', p['id'] as String),
            )!
            .width,
        8,
      );
    },
  );
  test(
    'public photo reply links once and cannot attach another person’s staged photo',
    () async {
      final p = await app.support.addPhoto('showcase-customer', id, photo());
      expect(
        () => app.support.reply('showcase-support', id, {
          'message': 'Nesprávna príloha',
          'attachments': [p['id']],
        }),
        throwsA(isA<ApiFailure>()),
      );
      app.support.reply('showcase-customer', id, {
        'message': '',
        'attachments': [p['id']],
      });
      expect(
        img.decodeJpg(
          app.support.photo('showcase-customer', p['id'] as String),
        ),
        isNotNull,
      );
      expect(
        () => app.support.reply('showcase-customer', id, {
          'message': 'Opakovanie',
          'attachments': [p['id']],
        }),
        throwsA(isA<ApiFailure>()),
      );
    },
  );
  test(
    'invalid files and oversized uploads are rejected before storage',
    () async {
      await expectLater(
        app.support.addPhoto(
          'showcase-customer',
          id,
          Uint8List.fromList('<svg/>'.codeUnits),
        ),
        throwsA(isA<ApiFailure>()),
      );
      await expectLater(
        app.support.addPhoto(
          'showcase-customer',
          id,
          Uint8List(5 * 1024 * 1024 + 1),
        ),
        throwsA(isA<ApiFailure>()),
      );
      expect(app.database.db.select('SELECT id FROM support_photos'), isEmpty);
    },
  );
  test(
    'message pagination covers full history and old read snapshots do not hide new responses',
    () {
      for (var n = 0; n < 65; n++) {
        app.support.reply('showcase-support', id, {'message': 'Odpoveď $n'});
      }
      final latest = app.support.ticket('showcase-customer', id),
          visible = (latest['messages'] as List).map((m) => m['id']).toSet();
      final older = app.support.ticket(
        'showcase-customer',
        id,
        before: latest['nextMessagesCursor'] as int,
      );
      visible.addAll((older['messages'] as List).map((m) => m['id']));
      expect(visible.length, 67);
      expect(older['nextMessagesCursor'], isNull);
      app.support.reply('showcase-support', id, {
        'message': 'Nová odpoveď po načítaní',
      });
      app.support.readTicket(
        'showcase-customer',
        id,
        latest['lastMessageCursor'] as int,
      );
      expect(
        app.support.activity('showcase-customer')['unread'],
        greaterThan(0),
      );
      final newSnapshot = app.support.ticket('showcase-customer', id);
      app.support.readTicket(
        'showcase-customer',
        id,
        newSnapshot['lastMessageCursor'] as int,
      );
      expect(
        (app.support.activity('showcase-customer')['notifications'] as List)
            .where((n) => n['ticketId'] == id)
            .every((n) => n['read'] == true),
        true,
      );
    },
  );
  test(
    'operator filters, assignment and audit are protected and use normalized search',
    () {
      final t = app.support.ticket('showcase-support', id);
      app.support.update('showcase-support', id, {
        'expectedVersion': t['version'],
        'status': 'inProgress',
        'priority': 'urgent',
        'assigneeId': 'showcase-support',
      });
      final list = app.support.list(
        'showcase-support',
        inbox: true,
        search: 'sarza',
        priority: 'urgent',
        assignment: 'mine',
      );
      expect((list['tickets'] as List).map((t) => t['id']), contains(id));
      expect(
        app.support.auditPage('showcase-support', id)['events'],
        isNotEmpty,
      );
      expect(
        () => app.support.auditPage('showcase-customer', id),
        throwsA(isA<ApiFailure>()),
      );
      expect(
        () => app.support.list('showcase-customer', inbox: true),
        throwsA(isA<ApiFailure>()),
      );
    },
  );
  test(
    'push sends generic ticket links, skips read and revoked sessions',
    () async {
      final push = SupportTestPush();
      final session = app.auth.createSession('showcase-customer');
      final sessionRow = app.database.db
          .select(
            "SELECT token_hash FROM sessions WHERE user_id='showcase-customer' ORDER BY rowid DESC LIMIT 1",
          )
          .first;
      app.database.db.execute(
        "UPDATE users SET profile=? WHERE id='showcase-customer'",
        ['{"supportAlerts":true}'],
      );
      app.database.db.execute('INSERT INTO devices VALUES(?,?,?,?)', [
        'device-support',
        'showcase-customer',
        sessionRow['token_hash'],
        'ios',
      ]);
      app.support.reply('showcase-support', id, {
        'message': 'Citlivá reklamácia a súkromné údaje nepatria do push.',
      });
      await app.support.drainSupportPush(push);
      expect(push.sent, hasLength(1));
      expect(push.sent.first['ticketId'], id);
      expect(push.sent.first['body'], isNot(contains('Citlivá')));
      app.support.reply('showcase-support', id, {
        'message': 'Po odhlásení sa neodošle.',
      });
      app.auth.logout('Bearer ${session['token']}');
      await app.support.drainSupportPush(push);
      expect(push.sent, hasLength(1));
    },
  );
}

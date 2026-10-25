import 'dart:convert';
import 'package:marketplace_server/src/billing.dart';
import 'package:marketplace_domain/marketplace_domain.dart';
import 'package:marketplace_server/marketplace_server.dart';
import 'package:marketplace_server/src/auth.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

void main() {
  late MarketplaceServer app;
  late DateTime now;
  late String org, offer;
  late RescueOrder order;
  setUp(() async {
    now = DateTime.utc(2026, 10, 25, 12);
    app = MarketplaceServer(
      const ServerConfig(
        databasePath: ':memory:',
        demoShowcase: true,
        billingFontPath: '../../apps/mobile/assets/fonts/InterVariable.ttf',
      ),
      clock: () => now,
    );
    final w = app.merchants.workspace('showcase-bakery');
    org = (w['organizations'] as List).first['id'] as String;
    offer =
        (w['offers'] as List).firstWhere(
              (o) => o['state'] == 'published' && (o['available'] as int) >= 3,
            )['offer']['id']
            as String;
    final p = app.billing.profile(org);
    app.billing.saveProfile(org, {
      ...p,
      'taxMode': 'vat',
      'vatId': 'SKDEMO',
      'rates': {for (final c in FoodCategory.values) c.name: 2300},
    });
    order = await app.reserve('showcase-customer', {
      'idempotencyKey': 'billing-three-units',
      'invoice': app.profile('showcase-customer')['invoice'],
      'coupon': 'VITAJ10',
      'items': [
        {'offerId': offer, 'quantity': 3},
      ],
    });
  });
  tearDown(() => app.close());
  void collect() {
    now = order.items.single.pickupStart.toUtc().add(
      const Duration(minutes: 1),
    );
    app.collect('showcase-customer', order.id, order.pickupCode!);
  }

  Future<void> refund(int n, String key) async {
    final t = app.support.create('showcase-customer', {
      'subject': 'Vrátenie časti',
      'message': 'Reklamácia kvality balíčka.',
      'category': 'foodQuality',
      'orderId': order.id,
    });
    final token = app.auth.createSession('showcase-support')['token'];
    final r = await app.handler(
      Request(
        'POST',
        Uri.parse('http://localhost/v1/support/tickets/${t['id']}/refund'),
        headers: {
          'authorization': 'Bearer $token',
          'content-type': 'application/json',
        },
        body: jsonEncode({
          'offerIds': [offer],
          'quantities': {offer: n},
          'reason': 'Čiastočná reklamácia',
          'idempotencyKey': key,
        }),
      ),
    );
    expect(r.statusCode, 200, reason: await r.readAsString());
    return;
  }

  test(
    'immutable invoices and per-unit credit notes conserve tax and discounted gross',
    () async {
      expect(app.billing.forOrder(order.id), isEmpty);
      collect();
      final initial = app.billing.forOrder(order.id);
      expect(initial, hasLength(2));
      final sale = initial.firstWhere(
        (d) => d['orgId'] == org && d['issuer']['vatId'] == 'SKDEMO',
      );
      final snapshot = jsonEncode(sale);
      app.billing.saveProfile(org, {
        ...app.billing.profile(org),
        'name': 'Zmenené údaje',
        'rates': {for (final c in FoodCategory.values) c.name: 500},
      });
      app.billing.sync(app.finance.order(order.id));
      expect(app.billing.forOrder(order.id), hasLength(2));
      expect(jsonEncode(app.billing.read(sale['id'] as String)), snapshot);
      await refund(1, 'billing-refund-first');
      await refund(2, 'billing-refund-rest');
      final docs = app.billing
          .forOrder(order.id)
          .where((d) => d['issuer']['vatId'] == 'SKDEMO')
          .toList();
      expect(docs, hasLength(3));
      for (final key in ['net', 'vat', 'gross']) {
        expect(docs.fold<int>(0, (n, d) => n + (d[key] as int)), 0);
      }
      expect(
        docs
            .skip(1)
            .every(
              (d) =>
                  d['originalDocumentId'] == sale['id'] &&
                  d['issuer']['name'] == sale['issuer']['name'],
            ),
        true,
      );
      final pdf = await app.billing.pdf(sale['id'] as String);
      expect(utf8.decode(pdf.take(4).toList()), '%PDF');
      expect(await app.billing.pdf(sale['id'] as String), pdf);
    },
  );
  test(
    'refund before collection reduces invoice without creating a fictitious credit note',
    () async {
      await refund(1, 'billing-before-collect');
      collect();
      final docs = app.billing.forOrder(order.id);
      expect(docs, hasLength(2));
      expect(
        docs.every((d) => d['kind'] == 'invoice' && d['quantity'] == 2),
        true,
      );
    },
  );
  test(
    'missing approved tax rate defers only affected documents and resumes once configured',
    () {
      app.billing.saveProfile(org, {...app.billing.profile(org), 'rates': {}});
      collect();
      expect(
        app.database.db.select(
          'SELECT * FROM billing_pending WHERE order_id=?',
          [order.id],
        ),
        hasLength(1),
      );
      app.billing.saveProfile(org, {
        ...app.billing.profile(org),
        'rates': {for (final c in FoodCategory.values) c.name: 2300},
      });
      app.billing.retryPending(org: org);
      expect(app.billing.forOrder(order.id), hasLength(2));
      expect(
        app.database.db.select(
          'SELECT * FROM billing_pending WHERE order_id=?',
          [order.id],
        ),
        isEmpty,
      );
    },
  );
  test(
    'document download is private to buyer, issuer owner and authorized platform staff',
    () async {
      collect();
      final id = app.billing.forOrder(order.id).first['id'];
      for (final entry in {
        'showcase-customer': 200,
        'showcase-bakery': 200,
        'showcase-restaurant': 404,
        'showcase-support': 200,
      }.entries) {
        final token = app.auth.createSession(entry.key)['token'];
        final r = await app.handler(
          Request(
            'GET',
            Uri.parse('http://localhost/v1/documents/$id/pdf'),
            headers: {'authorization': 'Bearer $token'},
          ),
        );
        expect(r.statusCode, entry.value);
        await r.read().drain<void>();
      }
    },
  );
  test('profile version and document integrity are enforced', () {
    final p = app.billing.profile(org);
    expect(
      () => app.billing.saveProfile(org, {...p, 'version': 0}),
      throwsA(isA<ApiFailure>()),
    );
    collect();
    final id = app.billing.forOrder(order.id).first['id'];
    app.database.db.execute(
      "UPDATE billing_documents SET payload='{}' WHERE id=?",
      [id],
    );
    expect(() => app.billing.read(id as String), throwsA(isA<ApiFailure>()));
  });
  test(
    'accounting connector can read only its issuer documents, retries before acknowledgement and revokes immediately',
    () {
      collect();
      final token =
          'Bearer ${app.billing.createConnector(org, {'name': 'Účtovný test'})['token']}';
      final first = app.billing.accountingPage(token),
          docs = first['documents'] as List;
      expect(docs, hasLength(1));
      expect(docs.every((d) => d['issuer']['vatId'] == 'SKDEMO'), true);
      expect(app.billing.accountingPage(token)['documents'], docs);
      expect(
        () => app.billing.accountingAck(token, {
          'through': (first['through'] as int) + 10000,
        }),
        throwsA(isA<ApiFailure>()),
      );
      app.billing.accountingAck(token, {'through': first['through']});
      expect(app.billing.accountingPage(token)['documents'], isEmpty);
      final row = app.billing.accountingIdentity(token);
      app.billing.revokeConnector(org, row['id'] as String);
      expect(
        () => app.billing.accountingPage(token),
        throwsA(isA<ApiFailure>()),
      );
    },
  );
  test(
    'expired documents are erased only after claims close; a retained credit note keeps its source',
    () async {
      collect();
      await refund(1, 'billing-retention-refund');
      final own = app.billing
          .forOrder(order.id)
          .where((d) => d['issuer']['vatId'] == 'SKDEMO')
          .toList();
      final invoice = own.firstWhere((d) => d['kind'] == 'invoice'),
          credit = own.firstWhere((d) => d['kind'] == 'creditNote');
      app.database.db.execute(
        "UPDATE billing_documents SET retention_until='2000-01-01T00:00:00Z' WHERE id=?",
        [invoice['id']],
      );
      expect(app.billing.cleanExpired(), 0);
      app.database.db.execute(
        "UPDATE support_tickets SET status='closed' WHERE order_id=?",
        [order.id],
      );
      expect(app.billing.cleanExpired(), 0);
      app.database.db.execute(
        "UPDATE billing_documents SET retention_until='2000-01-01T00:00:00Z' WHERE id=?",
        [credit['id']],
      );
      expect(app.billing.cleanExpired(), 2);
      expect(
        () => app.billing.read(invoice['id'] as String),
        throwsA(isA<ApiFailure>()),
      );
      expect(
        app.finance.rows(
          'SELECT id FROM finance_journal WHERE line_id IN (SELECT id FROM finance_lines WHERE order_id=?)',
          [order.id],
        ),
        isNotEmpty,
      );
    },
  );
}

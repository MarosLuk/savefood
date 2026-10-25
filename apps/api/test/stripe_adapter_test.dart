import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:marketplace_domain/marketplace_domain.dart';
import 'package:marketplace_server/marketplace_server.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

void main() {
  final now = DateTime.utc(2026, 10, 23, 12);
  const config = ServerConfig(
    databasePath: ':memory:',
    paymentMode: 'stripe',
    stripeSecret: 'sk_test_mock',
    stripeWebhookSecret: 'whsec_mock',
    stripeClubPriceId: 'price_club',
  );
  test(
    'Stripe membership is activated by a verified webhook and renewal can be stopped',
    () async {
      var creates = 0, cancellations = 0;
      final gateway = StripePaymentGateway(
        config,
        client: MockClient((r) async {
          Map<String, dynamic> result;
          if (r.url.path == '/v1/prices/price_club') {
            result = {
              'active': true,
              'currency': 'eur',
              'unit_amount': 499,
              'recurring': {'interval': 'month', 'interval_count': 1},
            };
          } else if (r.url.path == '/v1/checkout/sessions') {
            creates++;
            final form = Uri.splitQueryString(r.body);
            expect(form['mode'], 'subscription');
            expect(form['line_items[0][price]'], 'price_club');
            expect(r.headers['Idempotency-Key'], startsWith('club-'));
            result = {
              'id': 'cs_club',
              'url': 'https://checkout.stripe.com/mock',
            };
          } else if (r.method == 'POST') {
            expect(
              Uri.splitQueryString(r.body)['cancel_at_period_end'],
              'true',
            );
            cancellations++;
            result = {'id': 'sub_club', 'cancel_at_period_end': true};
          } else {
            result = {
              'id': 'sub_club',
              'metadata': {'user_id': 'member'},
              'status': 'active',
              'items': {
                'data': [
                  {
                    'current_period_end':
                        now
                            .add(const Duration(days: 30))
                            .millisecondsSinceEpoch ~/
                        1000,
                  },
                ],
              },
            };
          }
          return http.Response(
            jsonEncode(result),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      final app = MarketplaceServer(
        config,
        payments: gateway,
        clock: () => now,
      );
      addTearDown(app.close);
      app.database.db.execute(
        'INSERT INTO users(id,email,name) VALUES(?,?,?)',
        ['member', 'member@example.test', 'Member'],
      );
      final token = app.auth.createSession('member')['token'];
      Future<Response> call(String path) async => app.handler(
        Request(
          'POST',
          Uri.parse('http://localhost$path'),
          headers: {
            'authorization': 'Bearer $token',
            'content-type': 'application/json',
          },
          body: '{}',
        ),
      );
      expect((await call('/v1/club/checkout')).statusCode, 200);
      expect((await call('/v1/club/checkout')).statusCode, 200);
      expect(creates, 1);
      expect(app.profile('member')['memberUntil'], isNull);
      final event = jsonEncode({
        'id': 'evt_club',
        'type': 'checkout.session.completed',
        'data': {
          'object': {
            'id': 'cs_club',
            'mode': 'subscription',
            'metadata': {'user_id': 'member'},
            'subscription': 'sub_club',
          },
        },
      });
      final time = now.millisecondsSinceEpoch ~/ 1000;
      final sig = Hmac(
        sha256,
        utf8.encode('whsec_mock'),
      ).convert(utf8.encode('$time.$event'));
      Future<Response> webhook() async => app.handler(
        Request(
          'POST',
          Uri.parse('http://localhost/v1/payments/webhook'),
          headers: {'stripe-signature': 't=$time,v1=$sig'},
          body: event,
        ),
      );
      expect((await webhook()).statusCode, 200);
      expect((await webhook()).statusCode, 200);
      expect(
        DateTime.parse(app.profile('member')['memberUntil'] as String),
        now.add(const Duration(days: 30)),
      );
      expect((await call('/v1/club/cancel')).statusCode, 200);
      expect(cancellations, 1);
      expect(app.profile('member')['clubRenewalCancelled'], true);
      expect(app.profile('member')['memberUntil'], isNotNull);
    },
  );
  test(
    'Stripe payment and refund requests use cents and stable idempotency',
    () async {
      final requests = <http.Request>[];
      final gateway = StripePaymentGateway(
        config,
        client: MockClient((r) async {
          requests.add(r);
          return http.Response(
            jsonEncode(
              r.url.path == '/v1/refunds'
                  ? {'id': 're_mock'}
                  : {
                      'id': 'cs_order',
                      'url': 'https://checkout.stripe.com/mock',
                      'payment_status': 'paid',
                      'payment_intent': 'pi_order',
                    },
            ),
            200,
          );
        }),
      );
      addTearDown(gateway.client.close);
      final order = RescueOrder(
        id: 'order123',
        createdAt: now,
        items: [],
        total: 398,
        discount: 0,
        serviceFee: 8,
        creditUsed: 0,
        cashback: 0,
        invoice: const InvoiceDetails(),
      );
      final payment = await gateway.create(order, 'user@example.test');
      expect(payment.paid, true);
      expect(
        Uri.splitQueryString(
          requests.first.body,
        )['line_items[0][price_data][unit_amount]'],
        '398',
      );
      expect(requests.first.headers['Idempotency-Key'], 'order123');
      await gateway.cancel('cs_order', null);
      expect(requests.last.headers['Idempotency-Key'], 'refund-cs_order');
      expect(
        Uri.splitQueryString(requests.last.body)['payment_intent'],
        'pi_order',
      );
    },
  );
  test('unpaid Stripe checkout is expired rather than refunded', () async {
    final requests = <http.Request>[];
    final gateway = StripePaymentGateway(
      config,
      client: MockClient((r) async {
        requests.add(r);
        return http.Response(
          jsonEncode({'id': 'cs_pending', 'payment_status': 'unpaid'}),
          200,
        );
      }),
    );
    addTearDown(gateway.client.close);
    await gateway.cancel('cs_pending', null);
    expect(requests.last.url.path, '/v1/checkout/sessions/cs_pending/expire');
    expect(requests.last.headers['Idempotency-Key'], 'expire-cs_pending');
  });
}

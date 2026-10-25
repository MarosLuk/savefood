import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:marketplace_domain/marketplace_domain.dart';
import 'package:marketplace_server/marketplace_server.dart';
import 'package:test/test.dart';

void main() {
  const config = ServerConfig(
    paymentMode: 'stripe',
    stripeSecret: 'sk_test_mock',
    connectEnabled: true,
    merchantAppUrl: 'https://merchant.example.test',
  );
  final order = RescueOrder(
    id: 'order-123',
    createdAt: DateTime.utc(2026),
    items: [],
    total: 500,
    discount: 0,
    serviceFee: 0,
    creditUsed: 0,
    cashback: 0,
    invoice: const InvoiceDetails(),
  );
  test(
    'Connect uses Accounts v2 recipient capabilities, pinned version and authenticated app return',
    () async {
      final gateway = StripeConnectGateway(
        config,
        client: MockClient((r) async {
          expect(r.headers['Stripe-Version'], StripeConnectGateway.apiVersion);
          if (r.url.path == '/v2/core/accounts') {
            final b = jsonDecode(r.body) as Map;
            expect(b.containsKey('type'), false);
            expect(b['dashboard'], 'express');
            expect(
              b['configuration']['recipient']['capabilities']['stripe_balance']['stripe_transfers']['requested'],
              true,
            );
            expect(r.headers['Idempotency-Key'], 'connect-account-org');
            return http.Response(
              jsonEncode({
                'id': 'acct_1',
                'livemode': false,
                'configuration': {
                  'recipient': {
                    'capabilities': {
                      'stripe_balance': {
                        'stripe_transfers': {'status': 'active'},
                      },
                    },
                  },
                },
              }),
              200,
            );
          }
          expect(r.url.path, '/v2/core/account_links');
          final b = jsonDecode(r.body) as Map;
          expect(b['use_case']['account_onboarding']['configurations'], [
            'recipient',
          ]);
          expect(
            b['use_case']['account_onboarding']['refresh_url'],
            startsWith('https://merchant.example.test/'),
          );
          return http.Response(
            jsonEncode({'url': 'https://accounts.stripe.com/r/acct_1'}),
            200,
          );
        }),
      );
      addTearDown(gateway.close);
      expect(
        (await gateway.createAccount(
          'org',
          'Shop',
          'shop@example.test',
        ))['ready'],
        true,
      );
      expect(
        await gateway.onboarding('acct_1'),
        startsWith('https://accounts.stripe.com/'),
      );
    },
  );
  test(
    'transfer funding is explicit and refunds are verified against their immutable request',
    () async {
      var unsafe = false;
      final gateway = StripeConnectGateway(
        config,
        client: MockClient((r) async {
          Object result;
          if (r.url.path == '/v1/payment_intents/pi_1') {
            result = {
              'id': 'pi_1',
              'status': 'succeeded',
              'amount': 500,
              'currency': 'eur',
              'latest_charge': 'ch_1',
              'metadata': {'order_id': order.id},
            };
          } else if (r.url.path == '/v1/charges/ch_1') {
            result = {
              'id': 'ch_1',
              'paid': true,
              'amount': 500,
              'currency': 'eur',
              'amount_refunded': 0,
              'disputed': false,
            };
          } else if (r.url.path == '/v1/transfers') {
            final b = Uri.splitQueryString(r.body);
            expect(b['source_transaction'], 'ch_1');
            expect(b['destination'], 'acct_1');
            expect(b['amount'], '200');
            expect(r.headers['Idempotency-Key'], 'settlement-job-1');
            expect(b.containsKey('application_fee_amount'), false);
            result = {'id': 'tr_1'};
          } else {
            expect(r.url.path, '/v1/refunds');
            final b = Uri.splitQueryString(r.body);
            expect(b['payment_intent'], 'pi_1');
            expect(b['amount'], '100');
            result = {
              'id': 're_1',
              'status': 'succeeded',
              'amount': unsafe ? 101 : 100,
              'currency': 'eur',
              'metadata': {'order_id': order.id, 'refund_id': 'refund-1'},
            };
          }
          return http.Response(jsonEncode(result), 200);
        }),
      );
      addTearDown(gateway.close);
      expect(
        await gateway.transfer(
          'job-1',
          'acct_1',
          200,
          order.id,
          charge: 'ch_1',
        ),
        'tr_1',
      );
      expect(
        (await gateway.refund(
          'refund-1',
          'pi_1',
          'pi_1',
          order,
          100,
        ))['status'],
        'succeeded',
      );
      unsafe = true;
      await expectLater(
        gateway.refund('refund-1', 'pi_1', 'pi_1', order, 100),
        throwsA(isA<Exception>()),
      );
    },
  );
  test(
    'inactive recipient and mismatching payment cannot become an eligible payout',
    () async {
      final gateway = StripeConnectGateway(
        config,
        client: MockClient(
          (r) async => http.Response(
            jsonEncode(
              r.url.path.startsWith('/v2/')
                  ? {
                      'id': 'acct_1',
                      'configuration': {
                        'recipient': {
                          'capabilities': {
                            'stripe_balance': {
                              'stripe_transfers': {'status': 'restricted'},
                            },
                          },
                        },
                      },
                    }
                  : {
                      'id': 'pi_1',
                      'status': 'succeeded',
                      'amount': 500,
                      'currency': 'eur',
                      'latest_charge': 'ch_1',
                      'metadata': {'order_id': 'somebody-else'},
                    },
            ),
            200,
          ),
        ),
      );
      addTearDown(gateway.close);
      expect((await gateway.account('acct_1'))['ready'], false);
      await expectLater(
        gateway.charge('pi_1', 'pi_1', order),
        throwsA(isA<Exception>()),
      );
    },
  );
}

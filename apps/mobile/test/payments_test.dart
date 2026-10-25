import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:marketplace_data/marketplace_data.dart';
import 'package:marketplace_domain/marketplace_domain.dart';
import 'package:nevyhadzuj/services/payments.dart';
import 'package:nevyhadzuj/state/app_store.dart';

const invoice = InvoiceDetails(
  name: 'Jana Test',
  email: 'jana@example.test',
  street: 'Ulica 1',
  city: 'Bratislava',
  postcode: '81101',
);
RescueOrder order({
  PaymentFlow flow = PaymentFlow.native,
  OrderStatus status = OrderStatus.awaitingPayment,
  int total = 398,
}) => RescueOrder(
  id: 'native-order',
  createdAt: DateTime(2026, 10, 24, 14),
  items: [],
  total: total,
  discount: 0,
  serviceFee: 8,
  creditUsed: 0,
  cashback: 0,
  invoice: invoice,
  status: status,
  paymentFlow: flow,
  paymentUrl: flow == PaymentFlow.hosted
      ? 'https://checkout.stripe.com/mock'
      : null,
);

class FakePresenter implements NativePaymentPresenter {
  @override
  bool supported = true;
  int calls = 0;
  bool fail = false;
  PaymentResult result = PaymentResult.pending;
  @override
  Future<PaymentResult> present(
    PaymentSheetDetails details,
    InvoiceDetails invoice,
    Brightness brightness,
  ) async {
    calls++;
    if (fail) throw StateError('SDK response interrupted');
    return result;
  }
}

class VerifiedStore extends AppStore {
  VerifiedStore(super.repository, {super.api});
  int refreshes = 0;
  OrderStatus authoritativeStatus = OrderStatus.awaitingPayment;
  @override
  Future<void> refreshOrder(String id) async {
    refreshes++;
    orders[0] = orders[0].withStatus(authoritativeStatus);
  }
}

void main() {
  late VerifiedStore store;
  late FakePresenter presenter;
  late PaymentCoordinator payments;
  var browserOpens = 0;
  setUp(() {
    final api = MarketplaceApi(
      'https://api.example.test',
      vault: MemoryTokenVault(),
      client: MockClient((request) async {
        expect(request.url.path, '/v1/orders/native-order/payment-sheet');
        return http.Response(
          jsonEncode({
            'clientSecret': 'pi_native_secret_private',
            'publishableKey': 'pk_test_public',
            'merchantCountry': 'SK',
            'livemode': false,
            'applePayMerchantId': 'merchant.example.test',
          }),
          200,
        );
      }),
    );
    store = VerifiedStore(MemoryMarketplaceRepository(), api: api)
      ..serverConfig = {
        'paymentMode': 'stripe',
        'payments': {'nativePaymentSheet': true},
      };
    store.orders.add(order());
    presenter = FakePresenter();
    browserOpens = 0;
    payments = PaymentCoordinator(
      native: presenter,
      openBrowser: (uri) async {
        browserOpens++;
        return true;
      },
    );
  });
  tearDown(() => store.dispose());
  test(
    'mobile uses native sheet, unsupported platforms and sandbox use hosted flow',
    () {
      expect(payments.preferredFlow(store), PaymentFlow.native);
      presenter.supported = false;
      expect(payments.preferredFlow(store), PaymentFlow.hosted);
      presenter.supported = true;
      store.serverConfig['paymentMode'] = 'sandbox';
      expect(payments.preferredFlow(store), PaymentFlow.hosted);
    },
  );
  test('SDK success cannot mark an unpaid order paid', () async {
    presenter.result = PaymentResult.completed;
    expect(
      await payments.pay(store, store.orders.single, Brightness.dark),
      PaymentResult.pending,
    );
    expect(store.orders.single.status, OrderStatus.awaitingPayment);
    expect(store.refreshes, 1);
  });
  test(
    'a successful server verification completes the native payment',
    () async {
      store.authoritativeStatus = OrderStatus.reserved;
      expect(
        await payments.pay(store, store.orders.single, Brightness.light),
        PaymentResult.completed,
      );
      expect(presenter.calls, 1);
      expect(browserOpens, 0);
    },
  );
  test(
    'dismissal preserves an unpaid reservation and checks the server',
    () async {
      presenter.result = PaymentResult.cancelled;
      expect(
        await payments.pay(store, store.orders.single, Brightness.light),
        PaymentResult.cancelled,
      );
      expect(store.orders.single.status, OrderStatus.awaitingPayment);
      expect(store.refreshes, 1);
    },
  );
  test(
    'settled payment is recovered even if the SDK response was interrupted',
    () async {
      presenter.fail = true;
      store.authoritativeStatus = OrderStatus.reserved;
      expect(
        await payments.pay(store, store.orders.single, Brightness.dark),
        PaymentResult.completed,
      );
    },
  );
  test('fully covered orders do not open the SDK or browser', () async {
    expect(
      await payments.pay(
        store,
        order(status: OrderStatus.reserved, total: 0),
        Brightness.light,
      ),
      PaymentResult.completed,
    );
    expect(presenter.calls, 0);
    expect(browserOpens, 0);
    expect(store.refreshes, 0);
  });
  test(
    'hosted checkout uses the browser and native orders never open an invalid URL',
    () async {
      expect(
        await payments.pay(
          store,
          order(flow: PaymentFlow.hosted),
          Brightness.light,
        ),
        PaymentResult.redirected,
      );
      expect(browserOpens, 1);
      presenter.supported = false;
      await expectLater(
        payments.pay(store, store.orders.single, Brightness.light),
        throwsStateError,
      );
      expect(browserOpens, 1);
    },
  );
  test(
    'wallet setup uses matching country, currency, merchant and live/test settings',
    () {
      const test = PaymentSheetDetails(
        clientSecret: 'pi_secret_test',
        publishableKey: 'pk_test_x',
        country: 'SK',
        liveMode: false,
        appleMerchantId: 'merchant.test',
      );
      final sheet = StripePaymentPresenter.parameters(
        test,
        invoice,
        Brightness.dark,
      );
      expect(sheet.applePay!.merchantCountryCode, 'SK');
      expect(sheet.googlePay!.currencyCode, 'EUR');
      expect(sheet.googlePay!.testEnv, true);
      expect(sheet.cardBrandAcceptance, isNull);
      expect(sheet.allowsDelayedPaymentMethods, false);
      expect(sheet.style, ThemeMode.dark);
      expect(sheet.billingDetails!.email, invoice.email);
      const live = PaymentSheetDetails(
        clientSecret: 'pi_secret_live',
        publishableKey: 'pk_live_x',
        country: 'SK',
        liveMode: true,
      );
      final liveSheet = StripePaymentPresenter.parameters(
        live,
        invoice,
        Brightness.light,
      );
      expect(liveSheet.googlePay!.testEnv, false);
      expect(liveSheet.applePay, isNull);
    },
  );
  test(
    'checkout retry retains the original flow and idempotency key after restart',
    () async {
      final repository = MemoryMarketplaceRepository();
      final requests = <Map<String, dynamic>>[];
      final vault = MemoryTokenVault()..token = 'session_test';
      MarketplaceApi api() => MarketplaceApi(
        'https://api.example.test',
        vault: vault,
        client: MockClient((request) async {
          if (request.url.path == '/v1/orders') {
            requests.add(
              Map<String, dynamic>.from(jsonDecode(request.body) as Map),
            );
            return http.Response('{"error":"Temporary network outage"}', 503);
          }
          return http.Response('{}', 200);
        }),
      );
      final firstApi = api();
      await firstApi.restoreSession();
      final now = DateTime(2026, 10, 24, 14);
      final first = AppStore(repository, api: firstApi, clock: () => now)
        ..offers = seedCatalog(now);
      first.saveInvoice(invoice);
      first.addToCart(first.offer('butter')!);
      await expectLater(
        first.checkout(paymentFlow: PaymentFlow.native),
        throwsStateError,
      );
      await first.flush();
      first.dispose();
      final secondApi = api();
      await secondApi.restoreSession();
      final second = AppStore(repository, api: secondApi, clock: () => now)
        ..offers = seedCatalog(now);
      addTearDown(second.dispose);
      await second.restore();
      await expectLater(
        second.checkout(paymentFlow: PaymentFlow.hosted),
        throwsStateError,
      );
      expect(requests, hasLength(2));
      expect(requests[1], requests[0]);
      expect(requests[1]['paymentFlow'], 'native');
    },
  );
  test(
    'payment confirmation waits for a stale lifecycle refresh before applying the latest status',
    () async {
      final profileGate = Completer<http.Response>();
      final profileStarted = Completer<void>();
      final vault = MemoryTokenVault()..token = 'session_test';
      var profileRequests = 0;
      final pending = order();
      final api = MarketplaceApi(
        'https://api.example.test',
        vault: vault,
        client: MockClient((request) async {
          if (request.url.path == '/v1/config') {
            return http.Response('{"paymentMode":"stripe"}', 200);
          }
          if (request.url.path == '/v1/catalog') {
            return http.Response('{"offers":[]}', 200);
          }
          if (request.url.path == '/v1/me') {
            profileRequests++;
            profileStarted.complete();
            return profileGate.future;
          }
          return http.Response(
            jsonEncode(pending.withStatus(OrderStatus.reserved).toJson()),
            200,
          );
        }),
      );
      await api.restoreSession();
      final state = AppStore(MemoryMarketplaceRepository(), api: api)
        ..orders.add(pending);
      addTearDown(state.dispose);
      final lifecycle = state.refreshRemote();
      await profileStarted.future;
      final confirmation = state.refreshOrder(pending.id);
      profileGate.complete(
        http.Response(
          jsonEncode({
            'name': 'Jana',
            'email': invoice.email,
            'credit': 0,
            'orders': [pending.toJson()],
          }),
          200,
        ),
      );
      await lifecycle;
      await confirmation;
      expect(profileRequests, 1);
      expect(state.orders.single.status, OrderStatus.reserved);
    },
  );
}

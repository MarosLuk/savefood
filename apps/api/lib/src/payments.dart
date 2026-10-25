import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:marketplace_domain/marketplace_domain.dart';
import 'config.dart';
import 'auth.dart';

class PaymentCheckout {
  const PaymentCheckout({
    required this.sessionId,
    this.url,
    this.paid = false,
    this.expired = false,
    this.paymentIntent,
    this.amount,
    this.currency,
    this.referenceId,
  });
  final String sessionId;
  final String? url, paymentIntent;
  final bool paid, expired;
  final int? amount;
  final String? currency, referenceId;
}

abstract interface class PaymentGateway {
  Future<PaymentCheckout> create(RescueOrder order, String email);
  Future<PaymentCheckout> retrieve(String sessionId);
  Future<void> cancel(String sessionId, String? paymentIntent);
}

class DisabledPaymentGateway implements PaymentGateway {
  Never unavailable() =>
      throw const ApiFailure(503, 'Platby zatiaľ nie sú aktivované.');
  @override
  Future<PaymentCheckout> create(RescueOrder order, String email) async =>
      unavailable();
  @override
  Future<PaymentCheckout> retrieve(String sessionId) async => unavailable();
  @override
  Future<void> cancel(String sessionId, String? paymentIntent) async =>
      unavailable();
}

class SandboxPaymentGateway implements PaymentGateway {
  @override
  Future<PaymentCheckout> create(RescueOrder order, String email) async =>
      PaymentCheckout(sessionId: 'sandbox_${order.id}', paid: true);
  @override
  Future<PaymentCheckout> retrieve(String sessionId) async =>
      PaymentCheckout(sessionId: sessionId, paid: true);
  @override
  Future<void> cancel(String sessionId, String? paymentIntent) async {}
}

class StripePaymentGateway implements PaymentGateway {
  StripePaymentGateway(this.config, {http.Client? client})
    : client = client ?? http.Client();
  final ServerConfig config;
  final http.Client client;
  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, String>? body,
    String? key,
  }) async {
    final request = http.Request(
      method,
      Uri.https('api.stripe.com', '/v1/$path'),
    );
    request.headers['Authorization'] = 'Bearer ${config.stripeSecret}';
    if (key != null) request.headers['Idempotency-Key'] = key;
    if (body != null) request.bodyFields = body;
    final response = await http.Response.fromStream(
      await client.send(request).timeout(const Duration(seconds: 20)),
    );
    if (response.statusCode >= 400) {
      throw StateError('Platobná brána požiadavku odmietla. Skús to znova.');
    }
    return Map<String, dynamic>.from(jsonDecode(response.body) as Map);
  }

  PaymentCheckout _checkout(Map<String, dynamic> json) => PaymentCheckout(
    sessionId: json['id'] as String,
    url: json['url'] as String?,
    paid:
        json['payment_status'] == 'paid' ||
        json['payment_status'] == 'no_payment_required',
    paymentIntent: json['payment_intent'] as String?,
    expired: json['status'] == 'expired',
  );
  @override
  Future<PaymentCheckout> create(RescueOrder order, String email) async {
    if (order.paymentFlow == PaymentFlow.native) {
      return _intent(
        await _request(
          'POST',
          'payment_intents',
          key: order.id,
          body: {
            'amount': '${order.total}',
            'currency': 'eur',
            'payment_method_types[0]': 'card',
            'metadata[order_id]': order.id,
            'transfer_group': order.id,
            'description': 'Save Food · ${order.count} balíčky',
            'receipt_email': email,
          },
        ),
      );
    }
    return _checkout(
      await _request(
        'POST',
        'checkout/sessions',
        key: order.id,
        body: {
          'mode': 'payment',
          'payment_method_types[0]': 'card',
          'customer_email': email,
          'client_reference_id': order.id,
          'metadata[order_id]': order.id,
          'payment_intent_data[metadata][order_id]': order.id,
          'payment_intent_data[transfer_group]': order.id,
          'line_items[0][price_data][currency]': 'eur',
          'line_items[0][price_data][unit_amount]': '${order.total}',
          'line_items[0][price_data][product_data][name]':
              'Save Food · ${order.items.length} balíčky',
          'line_items[0][quantity]': '1',
          'success_url':
              '${config.publicUrl}/payment/return?order=${Uri.encodeQueryComponent(order.id)}',
          'cancel_url': '${config.publicUrl}/payment/return?cancelled=1',
          'expires_at':
              '${order.createdAt.add(const Duration(minutes: 30)).millisecondsSinceEpoch ~/ 1000}',
        },
      ),
    );
  }

  PaymentCheckout _intent(Map<String, dynamic> json) => PaymentCheckout(
    sessionId: json['id'] as String,
    paid: json['status'] == 'succeeded',
    expired: json['status'] == 'canceled',
    paymentIntent: json['id'] as String,
    amount: json['amount'] as int?,
    currency: json['currency'] as String?,
    referenceId: (json['metadata'] as Map?)?['order_id'] as String?,
  );
  Future<Map<String, dynamic>> paymentIntent(String id) =>
      _request('GET', 'payment_intents/${Uri.encodeComponent(id)}');
  Future<String> clientSecret(String id, RescueOrder order) async {
    final intent = await paymentIntent(id);
    if (intent['amount'] != order.total ||
        intent['currency'] != 'eur' ||
        (intent['metadata'] as Map?)?['order_id'] != order.id ||
        intent['status'] == 'canceled') {
      throw StateError('Platobné údaje sa nezhodujú s rezerváciou.');
    }
    return intent['client_secret'] as String;
  }

  @override
  Future<PaymentCheckout> retrieve(String sessionId) async {
    if (sessionId.startsWith('pi_')) {
      return _intent(await paymentIntent(sessionId));
    }
    return _checkout(
      await _request(
        'GET',
        'checkout/sessions/${Uri.encodeComponent(sessionId)}',
      ),
    );
  }

  Future<Map<String, dynamic>> membershipPrice() => _request(
    'GET',
    'prices/${Uri.encodeComponent(config.stripeClubPriceId)}',
  );
  Future<Map<String, dynamic>> createMembership(String user, String email) =>
      _request(
        'POST',
        'checkout/sessions',
        key: 'club-$user-${DateTime.now().millisecondsSinceEpoch ~/ 1800000}',
        body: {
          'mode': 'subscription',
          'payment_method_types[0]': 'card',
          'customer_email': email,
          'metadata[user_id]': user,
          'subscription_data[metadata][user_id]': user,
          'line_items[0][price]': config.stripeClubPriceId,
          'line_items[0][quantity]': '1',
          'success_url': '${config.publicUrl}/payment/return',
          'cancel_url': '${config.publicUrl}/payment/return?cancelled=1',
        },
      );
  Future<Map<String, dynamic>> subscription(String id) =>
      _request('GET', 'subscriptions/${Uri.encodeComponent(id)}');
  Future<void> cancelRenewal(String id) async {
    await _request(
      'POST',
      'subscriptions/${Uri.encodeComponent(id)}',
      body: {'cancel_at_period_end': 'true'},
    );
  }

  @override
  Future<void> cancel(String sessionId, String? paymentIntent) async {
    final current = await retrieve(sessionId);
    if (current.expired) return;
    final intent = current.paymentIntent ?? paymentIntent;
    if (current.paid && intent != null) {
      await _request(
        'POST',
        'refunds',
        key: 'refund-$sessionId',
        body: {'payment_intent': intent},
      );
    } else if (!current.paid) {
      await _request(
        'POST',
        sessionId.startsWith('pi_')
            ? 'payment_intents/${Uri.encodeComponent(sessionId)}/cancel'
            : 'checkout/sessions/${Uri.encodeComponent(sessionId)}/expire',
        key: 'expire-$sessionId',
      );
    }
  }
}

bool constantTimeEqual(List<int> a, List<int> b) {
  var difference = a.length ^ b.length;
  for (var i = 0; i < a.length; i++) {
    difference |= a[i] ^ (i < b.length ? b[i] : 0);
  }
  return difference == 0;
}

bool verifyStripeSignature(
  String body,
  String header,
  String secret,
  DateTime now,
) {
  final parts = header.split(',');
  final timestamp = int.tryParse(
    parts
            .where((p) => p.startsWith('t='))
            .map((p) => p.substring(2))
            .firstOrNull ??
        '',
  );
  if (timestamp == null ||
      (now.millisecondsSinceEpoch ~/ 1000 - timestamp).abs() > 300) {
    return false;
  }
  final expected = Hmac(
    sha256,
    utf8.encode(secret),
  ).convert(utf8.encode('$timestamp.$body')).toString();
  return parts
      .where((p) => p.startsWith('v1='))
      .any(
        (p) => constantTimeEqual(
          utf8.encode(expected),
          utf8.encode(p.substring(3)),
        ),
      );
}

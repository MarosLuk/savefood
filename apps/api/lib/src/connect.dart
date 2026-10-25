import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:marketplace_domain/marketplace_domain.dart';
import 'auth.dart';
import 'config.dart';

abstract interface class ConnectGateway {
  Future<Map<String, dynamic>> createAccount(
    String org,
    String name,
    String email,
  );
  Future<Map<String, dynamic>> account(String id);
  Future<String> onboarding(String id);
  Future<Map<String, dynamic>> charge(
    String session,
    String? intent,
    RescueOrder order,
  );
  Future<String> transfer(
    String key,
    String account,
    int amount,
    String order, {
    String? charge,
  });
  Future<String> reverse(String key, String transfer, {int? amount});
  Future<Map<String, dynamic>> lookupTransfer(String id);
  Future<Map<String, dynamic>> lookupReversal(String transfer, String id);
  Future<Map<String, dynamic>> refund(
    String key,
    String session,
    String? intent,
    RescueOrder order,
    int amount, {
    String? existing,
  });
  void close();
}

class SandboxConnectGateway implements ConnectGateway {
  @override
  Future<Map<String, dynamic>> lookupReversal(
    String transfer,
    String id,
  ) async => throw const ApiFailure(
    409,
    'Použi testovací záznam alebo overenú Stripe reverziu.',
  );
  @override
  Future<Map<String, dynamic>> createAccount(
    String org,
    String name,
    String email,
  ) async => {
    'id': 'demo_acct_$org',
    'ready': true,
    'status': 'demo',
    'details': 'Simulované Stripe pripojenie',
  };
  @override
  Future<Map<String, dynamic>> account(String id) async => {
    'id': id,
    'ready': true,
    'status': 'demo',
    'details': 'Simulovaný účet bez bankového prevodu',
  };
  @override
  Future<String> onboarding(String id) async => '';
  @override
  Future<Map<String, dynamic>> charge(
    String session,
    String? intent,
    RescueOrder order,
  ) async => {
    'id': 'demo_charge_${order.id}',
    'amount': order.total,
    'refunded': 0,
  };
  @override
  Future<String> transfer(
    String key,
    String account,
    int amount,
    String order, {
    String? charge,
  }) async => 'demo_tr_$key';
  @override
  Future<String> reverse(String key, String transfer, {int? amount}) async =>
      'demo_rev_$key';
  @override
  Future<Map<String, dynamic>> lookupTransfer(String id) async =>
      throw const ApiFailure(
        409,
        'Demo prevod treba obnoviť jeho pôvodnou požiadavkou.',
      );
  @override
  Future<Map<String, dynamic>> refund(
    String key,
    String session,
    String? intent,
    RescueOrder order,
    int amount, {
    String? existing,
  }) async => {'id': existing ?? 'demo_ref_$key', 'status': 'succeeded'};
  @override
  void close() {}
}

class DisabledConnectGateway extends SandboxConnectGateway {
  @override
  Future<Map<String, dynamic>> lookupReversal(
    String transfer,
    String id,
  ) async => unavailable();
  Never unavailable() => throw const ApiFailure(
    503,
    'Finančné operácie zatiaľ nie sú aktivované.',
  );
  @override
  Future<Map<String, dynamic>> createAccount(
    String org,
    String name,
    String email,
  ) async => unavailable();
  @override
  Future<Map<String, dynamic>> account(String id) async => unavailable();
  @override
  Future<String> onboarding(String id) async => unavailable();
  @override
  Future<Map<String, dynamic>> charge(
    String session,
    String? intent,
    RescueOrder order,
  ) async => unavailable();
  @override
  Future<String> transfer(
    String key,
    String account,
    int amount,
    String order, {
    String? charge,
  }) async => unavailable();
  @override
  Future<String> reverse(String key, String transfer, {int? amount}) async =>
      unavailable();
  @override
  Future<Map<String, dynamic>> lookupTransfer(String id) async => unavailable();
  @override
  Future<Map<String, dynamic>> refund(
    String key,
    String session,
    String? intent,
    RescueOrder order,
    int amount, {
    String? existing,
  }) async => unavailable();
}

class StripeConnectGateway implements ConnectGateway {
  @override
  Future<Map<String, dynamic>> lookupReversal(
    String transfer,
    String id,
  ) => _request(
    'GET',
    '/v1/transfers/${Uri.encodeComponent(transfer)}/reversals/${Uri.encodeComponent(id)}',
  );
  StripeConnectGateway(this.config, {http.Client? client})
    : client = client ?? http.Client();
  final ServerConfig config;
  final http.Client client;
  static const apiVersion = '2026-09-30.endive';
  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, dynamic>? json,
    Map<String, String>? form,
    String? key,
    Map<String, String>? query,
  }) async {
    if (!config.connectEnabled || config.stripeSecret.isEmpty) {
      throw const ApiFailure(
        503,
        'Stripe Connect ešte nie je nakonfigurovaný.',
      );
    }
    final request = http.Request(
      method,
      Uri.https('api.stripe.com', path, query),
    );
    request.headers.addAll({
      'Authorization': 'Bearer ${config.stripeSecret}',
      'Stripe-Version': apiVersion,
      'Idempotency-Key': ?key,
    });
    if (json != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(json);
    }
    if (form != null) request.bodyFields = form;
    final response = await http.Response.fromStream(
      await client.send(request).timeout(const Duration(seconds: 25)),
    );
    if (response.statusCode >= 400) {
      throw const ApiFailure(
        503,
        'Stripe operáciu nepotvrdil. Obnov stav alebo skús znova.',
      );
    }
    return Map<String, dynamic>.from(jsonDecode(response.body) as Map);
  }

  Map<String, dynamic> _account(Map<String, dynamic> a) {
    final recipient = (a['configuration'] as Map?)?['recipient'] as Map?;
    final balance =
        (recipient?['capabilities'] as Map?)?['stripe_balance'] as Map?;
    final status =
        (balance?['stripe_transfers'] as Map?)?['status'] as String? ??
        'inactive';
    return {
      'id': a['id'],
      'ready': status == 'active',
      'status': status,
      'details': status == 'active'
          ? 'Účet môže prijímať prevody.'
          : 'Dokonči overenie údajov v Stripe.',
      'livemode': a['livemode'],
    };
  }

  @override
  Future<Map<String, dynamic>> createAccount(
    String org,
    String name,
    String email,
  ) async => _account(
    await _request(
      'POST',
      '/v2/core/accounts',
      key: 'connect-account-$org',
      json: {
        'display_name': name,
        'contact_email': email,
        'dashboard': 'express',
        'identity': {'country': config.merchantCountry.toLowerCase()},
        'defaults': {
          'responsibilities': {
            'fees_collector': 'application',
            'losses_collector': 'application',
          },
        },
        'configuration': {
          'recipient': {
            'capabilities': {
              'stripe_balance': {
                'stripe_transfers': {'requested': true},
              },
            },
          },
        },
        'include': ['configuration.recipient', 'requirements'],
        'metadata': {'organization_id': org},
      },
    ),
  );
  @override
  Future<Map<String, dynamic>> account(String id) async => _account(
    await _request(
      'GET',
      '/v2/core/accounts/${Uri.encodeComponent(id)}',
      query: {
        'include[0]': 'configuration.recipient',
        'include[1]': 'requirements',
      },
    ),
  );
  @override
  Future<String> onboarding(String id) async {
    // Return to the authenticated application; a fresh link requires owner auth.
    final callback =
        '${config.merchantAppUrl}/?portal=merchant&connect=refresh';
    final link = await _request(
      'POST',
      '/v2/core/account_links',
      json: {
        'account': id,
        'use_case': {
          'type': 'account_onboarding',
          'account_onboarding': {
            'configurations': ['recipient'],
            'refresh_url': callback,
            'return_url':
                '${config.merchantAppUrl}/?portal=merchant&connect=return',
          },
        },
      },
    );
    final url = link['url'] as String;
    final uri = Uri.parse(url);
    if (uri.scheme != 'https' ||
        !(uri.host == 'connect.stripe.com' ||
            uri.host == 'accounts.stripe.com')) {
      throw const ApiFailure(503, 'Stripe nevrátil platný odkaz na overenie.');
    }
    return url;
  }

  Future<String> _intent(String session, String? intent) async {
    if (intent != null && intent.startsWith('pi_')) return intent;
    if (session.startsWith('pi_')) return session;
    final checkout = await _request(
      'GET',
      '/v1/checkout/sessions/${Uri.encodeComponent(session)}',
    );
    final id = checkout['payment_intent'];
    if (id is! String) {
      throw const ApiFailure(409, 'Platba ešte nie je potvrdená.');
    }
    return id;
  }

  @override
  Future<Map<String, dynamic>> charge(
    String session,
    String? intent,
    RescueOrder order,
  ) async {
    final pi = await _request(
      'GET',
      '/v1/payment_intents/${Uri.encodeComponent(await _intent(session, intent))}',
    );
    if (pi['status'] != 'succeeded' ||
        pi['amount'] != order.total ||
        pi['currency'] != 'eur' ||
        (pi['metadata'] as Map?)?['order_id'] != order.id ||
        pi['latest_charge'] is! String) {
      throw const ApiFailure(
        409,
        'Platba nesúhlasí s objednávkou alebo ešte nie je potvrdená.',
      );
    }
    final c = await _request(
      'GET',
      '/v1/charges/${Uri.encodeComponent(pi['latest_charge'] as String)}',
    );
    if (c['paid'] != true ||
        c['currency'] != 'eur' ||
        c['amount'] != order.total ||
        c['disputed'] == true) {
      throw const ApiFailure(409, 'Platba vyžaduje kontrolu podpory.');
    }
    return {
      'id': c['id'],
      'amount': c['amount'],
      'refunded': c['amount_refunded'] ?? 0,
    };
  }

  @override
  Future<String> transfer(
    String key,
    String account,
    int amount,
    String order, {
    String? charge,
  }) async =>
      (await _request(
            'POST',
            '/v1/transfers',
            key: 'settlement-$key',
            form: {
              'amount': '$amount',
              'currency': 'eur',
              'destination': account,
              'transfer_group': order,
              'metadata[settlement_job]': key,
              'metadata[order_id]': order,
              'source_transaction': ?charge,
            },
          ))['id']
          as String;
  @override
  Future<String> reverse(String key, String transfer, {int? amount}) async =>
      (await _request(
            'POST',
            '/v1/transfers/${Uri.encodeComponent(transfer)}/reversals',
            key: 'reversal-$key',
            form: {
              'metadata[refund_id]': key,
              if (amount != null) 'amount': '$amount',
            },
          ))['id']
          as String;
  @override
  Future<Map<String, dynamic>> lookupTransfer(String id) =>
      _request('GET', '/v1/transfers/${Uri.encodeComponent(id)}');
  @override
  Future<Map<String, dynamic>> refund(
    String key,
    String session,
    String? intent,
    RescueOrder order,
    int amount, {
    String? existing,
  }) async {
    final result = existing != null
        ? await _request('GET', '/v1/refunds/${Uri.encodeComponent(existing)}')
        : await _createRefund(key, session, intent, order, amount);
    if (result['amount'] != amount ||
        result['currency'] != 'eur' ||
        (result['metadata'] as Map?)?['order_id'] != order.id ||
        (result['metadata'] as Map?)?['refund_id'] != key) {
      throw const ApiFailure(409, 'Refundácia nesúhlasí s požiadavkou.');
    }
    return result;
  }

  Future<Map<String, dynamic>> _createRefund(
    String key,
    String session,
    String? intent,
    RescueOrder order,
    int amount,
  ) async {
    await charge(session, intent, order);
    return _request(
      'POST',
      '/v1/refunds',
      key: 'line-refund-$key',
      form: {
        'payment_intent': await _intent(session, intent),
        'amount': '$amount',
        'metadata[order_id]': order.id,
        'metadata[refund_id]': key,
      },
    );
  }

  @override
  void close() => client.close();
}

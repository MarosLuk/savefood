import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:marketplace_domain/marketplace_domain.dart';
import 'package:uuid/uuid.dart';

class ApiException implements Exception {
  const ApiException(this.status, this.message);
  final int status;
  final String message;
  @override
  String toString() => message;
}

abstract interface class TokenVault {
  Future<String?> read();
  Future<void> write(String token);
  Future<void> clear();
}

class MemoryTokenVault implements TokenVault {
  String? token;
  @override
  Future<String?> read() async => token;
  @override
  Future<void> write(String value) async {
    token = value;
  }

  @override
  Future<void> clear() async {
    token = null;
  }
}

class MarketplaceApi {
  MarketplaceApi(String baseUrl, {required this.vault, http.Client? client})
    : baseUrl = baseUrl.replaceAll(RegExp(r'/+$'), ''),
      client = client ?? http.Client();
  final String baseUrl;
  final TokenVault vault;
  final http.Client client;
  String? _token;
  Future<void> _vaultWrites = Future<void>.value();
  Future<void> _vaultChange(Future<void> Function() action) {
    final pending = _vaultWrites
        .catchError((Object _) {})
        .then((_) => action());
    _vaultWrites = pending;
    return pending;
  }

  bool get authenticated => _token != null;
  static String newIdempotencyKey() => const Uuid().v4();
  Future<void> restoreSession() async {
    await _vaultWrites;
    _token = await vault.read();
  }

  Future<Map<String, dynamic>> request(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final request = http.Request(method, Uri.parse('$baseUrl$path'));
    request.headers.addAll({
      'Accept': 'application/json',
      if (body != null) 'Content-Type': 'application/json',
      if (_token != null) 'Authorization': 'Bearer $_token',
    });
    if (body != null) request.body = jsonEncode(body);
    http.Response response;
    try {
      response = await http.Response.fromStream(
        await client.send(request).timeout(const Duration(seconds: 25)),
      );
    } catch (_) {
      throw const ApiException(
        0,
        'Nepodarilo sa spojiť so serverom. Skontroluj pripojenie a skús znova.',
      );
    }
    Map<String, dynamic> json;
    try {
      json = Map<String, dynamic>.from(
        jsonDecode(utf8.decode(response.bodyBytes)) as Map,
      );
    } catch (_) {
      throw ApiException(
        response.statusCode,
        'Server nevrátil platnú odpoveď.',
      );
    }
    if (response.statusCode >= 400) {
      if (response.statusCode == 401 && !path.startsWith('/v1/auth/')) {
        _token = null;
        await _vaultChange(vault.clear);
      }
      throw ApiException(
        response.statusCode,
        json['error'] as String? ?? 'Požiadavku sa nepodarilo dokončiť.',
      );
    }
    return json;
  }

  Future<http.Response> binary(
    String method,
    String path, {
    Uint8List? bytes,
  }) async {
    final request = http.Request(method, Uri.parse('$baseUrl$path'));
    request.headers.addAll({
      'Accept': 'application/json,image/jpeg',
      if (bytes != null) 'Content-Type': 'application/octet-stream',
      if (_token != null) 'Authorization': 'Bearer $_token',
    });
    if (bytes != null) request.bodyBytes = bytes;
    http.Response response;
    try {
      response = await http.Response.fromStream(
        await client.send(request).timeout(const Duration(seconds: 45)),
      );
    } catch (_) {
      throw const ApiException(0, 'Súbor sa nepodarilo preniesť. Skús znova.');
    }
    if (response.statusCode >= 400) {
      if (response.statusCode == 401) {
        _token = null;
        await _vaultChange(vault.clear);
      }
      var message = 'Súbor sa nepodarilo načítať.';
      try {
        message =
            (jsonDecode(utf8.decode(response.bodyBytes)) as Map)['error']
                as String? ??
            message;
      } catch (_) {
        /* Keep a readable fallback for non-JSON network errors. */
      }
      throw ApiException(response.statusCode, message);
    }
    return response;
  }

  Future<void> _session(Map<String, dynamic> response) async {
    final token = response['token'] as String;
    _token = token;
    try {
      await _vaultChange(() => vault.write(token));
    } catch (_) {
      if (_token == token) _token = null;
      rethrow;
    }
  }

  Future<void> register(
    String name,
    String email,
    String password, {
    Map<String, dynamic>? legalConsent,
  }) async => _session(
    await request(
      'POST',
      '/v1/auth/register',
      body: {
        'name': name,
        'email': email,
        'password': password,
        'legalConsent': ?legalConsent,
      },
    ),
  );
  Future<void> login(String email, String password) async => _session(
    await request(
      'POST',
      '/v1/auth/login',
      body: {'email': email, 'password': password},
    ),
  );
  Future<bool> loginFirebase(
    String idToken,
    String provider, {
    Map<String, dynamic>? legalConsent,
    bool Function()? accept,
  }) async {
    final result = await request(
      'POST',
      '/v1/auth/firebase',
      body: {
        'idToken': idToken,
        'provider': provider,
        'legalConsent': ?legalConsent,
      },
    );
    if (accept != null && !accept()) {
      // Revoke a late exchange without replacing another account's local token.
      try {
        await client
            .post(
              Uri.parse('$baseUrl/v1/auth/logout'),
              headers: {
                'authorization': 'Bearer ${result['token']}',
                'content-type': 'application/json',
              },
              body: '{}',
            )
            .timeout(const Duration(seconds: 5));
      } catch (_) {
        /* The unused session is never saved. */
      }
      return false;
    }
    await _session(result);
    return accept == null || accept();
  }

  Future<void> enterDemo(String persona) async => _session(
    await request('POST', '/v1/auth/demo', body: {'persona': persona}),
  );
  Future<void> logout() async {
    try {
      if (authenticated) await request('POST', '/v1/auth/logout', body: {});
    } finally {
      _token = null;
      await _vaultChange(vault.clear);
    }
  }

  Future<List<FoodOffer>> catalog() async =>
      _decodeOffers(await request('GET', '/v1/catalog'));
  List<FoodOffer> _decodeOffers(Map<String, dynamic> json) =>
      (json['offers'] as List)
          .map((o) => FoodOffer.fromJson(Map<String, dynamic>.from(o as Map)))
          .toList();
  Future<Map<String, dynamic>> me() => request('GET', '/v1/me');
  Future<Map<String, dynamic>> updateProfile(Map<String, dynamic> profile) =>
      request('PATCH', '/v1/me', body: profile);
  Future<RescueOrder> reserve({
    required Map<String, int> cart,
    required InvoiceDetails invoice,
    required String coupon,
    required bool useCredit,
    required String key,
    PaymentFlow paymentFlow = PaymentFlow.hosted,
  }) async => RescueOrder.fromJson(
    await request(
      'POST',
      '/v1/orders',
      body: {
        'items': cart.entries
            .map((e) => {'offerId': e.key, 'quantity': e.value})
            .toList(),
        'invoice': invoice.toJson(),
        'coupon': coupon,
        'useCredit': useCredit,
        'idempotencyKey': key,
        if (paymentFlow == PaymentFlow.native) 'paymentFlow': paymentFlow.name,
      },
    ),
  );
  Future<RescueOrder> finishOrder(
    RescueOrder order, {
    required bool collect,
    String? offerId,
  }) async => RescueOrder.fromJson(
    await request(
      'POST',
      '/v1/orders/${Uri.encodeComponent(order.id)}/${collect ? 'collect' : 'cancel'}',
      body: collect
          ? {'pickupCode': order.pickupCode, 'offerId': ?offerId}
          : {},
    ),
  );
  Future<RescueOrder> refreshOrder(String id) async => RescueOrder.fromJson(
    await request(
      'POST',
      '/v1/orders/${Uri.encodeComponent(id)}/refresh',
      body: {},
    ),
  );
  Future<Map<String, dynamic>> activateTrial(String code) =>
      request('POST', '/v1/club/trial', body: {'code': code});
  Future<Map<String, dynamic>> cancelClub() =>
      request('POST', '/v1/club/cancel', body: {});
  Future<Map<String, dynamic>> beginOAuth(String provider) => request(
    'POST',
    '/v1/auth/oauth/${Uri.encodeComponent(provider)}',
    body: {},
  );
  Future<bool> pollOAuth(Map<String, dynamic> handoff) async {
    final result = await request(
      'POST',
      '/v1/auth/oauth/poll/${handoff['id']}',
      body: {'pollSecret': handoff['pollSecret']},
    );
    if (result['pending'] == true) return false;
    await _session(result);
    return true;
  }

  void close() => client.close();
}

import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:marketplace_server/marketplace_server.dart';
import 'package:test/test.dart';

void main() {
  test(
    'Stripe signature verifies the exact body and enforces replay tolerance',
    () {
      final now = DateTime.utc(2026, 10, 23, 12);
      final t = now.millisecondsSinceEpoch ~/ 1000;
      const body = '{"id":"evt_test"}', secret = 'whsec_test';
      final signature = Hmac(
        sha256,
        utf8.encode(secret),
      ).convert(utf8.encode('$t.$body')).toString();
      final header = 't=$t,v1=$signature';
      expect(verifyStripeSignature(body, header, secret, now), isTrue);
      expect(verifyStripeSignature('$body ', header, secret, now), isFalse);
      expect(
        verifyStripeSignature(
          body,
          header,
          secret,
          now.add(const Duration(minutes: 6)),
        ),
        isFalse,
      );
    },
  );
  test('constant-time comparison rejects differing lengths and bytes', () {
    expect(constantTimeEqual([1, 2], [1, 2]), isTrue);
    expect(constantTimeEqual([1, 2], [1]), isFalse);
    expect(constantTimeEqual([1, 2], [1, 3]), isFalse);
  });
}

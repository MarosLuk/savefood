import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:marketplace_data/marketplace_data.dart';
import 'package:nevyhadzuj/state/app_store.dart';
import 'package:nevyhadzuj/services/social_auth.dart';

class FakeSocial implements SocialSignIn {
  @override
  String projectId = 'savefood-test';
  @override
  bool ready = true;
  Future<String?> Function()? flow;
  int cleanups = 0;
  @override
  Future<void> initialize() async {}
  @override
  Future<String?> signIn(String provider) async =>
      flow == null ? 'test-id-token' : flow!();
  @override
  Future<void> signOut() async {
    cleanups++;
  }
}

void main() {
  test(
    'consent retry completes a new social account and stores only the marketplace session',
    () async {
      final provider = FakeSocial(), vault = MemoryTokenVault();
      var exchanges = 0;
      final api = MarketplaceApi(
        'https://api.example.test',
        vault: vault,
        client: MockClient((r) async {
          if (r.url.path == '/v1/auth/firebase') {
            exchanges++;
            final b = jsonDecode(r.body) as Map;
            expect(b['idToken'], 'test-id-token');
            expect(b['provider'], 'google');
            if (exchanges == 1) {
              return http.Response('{"error":"Confirm terms"}', 428);
            }
            expect(b['legalConsent'], {'version': 2, 'accepted': true});
            return http.Response(
              '{"token":"marketplace-session","userId":"social"}',
              200,
            );
          }
          if (r.url.path == '/v1/me') {
            return http.Response(
              jsonEncode({
                'name': 'Sofia',
                'email': 'sofia@example.test',
                'credit': 0,
                'emailVerified': true,
              }),
              200,
            );
          }
          return http.Response(
            r.url.path == '/v1/catalog' ? '{"offers":[]}' : '{}',
            200,
          );
        }),
      );
      final store =
          AppStore(
              MemoryMarketplaceRepository(),
              api: api,
              socialAuth: provider,
            )
            ..serverConfig = {
              'firebaseAuth': {
                'projectId': 'savefood-test',
                'google': true,
                'apple': true,
              },
            };
      addTearDown(() {
        store.dispose();
        api.close();
      });
      expect(
        await store.authenticateSocial(
          'google',
          requestConsent: () async => {'version': 2, 'accepted': true},
        ),
        true,
      );
      expect(store.email, 'sofia@example.test');
      expect(store.signedIn, true);
      expect(vault.token, 'marketplace-session');
      expect(exchanges, 2);
      expect(provider.cleanups, 1);
      await store.signOut();
      expect(vault.token, isNull);
      expect(store.email, isEmpty);
    },
  );
  test('cancelled provider creates no API request or local account', () async {
    final provider = FakeSocial()..flow = () async => null;
    final api = MarketplaceApi(
      'https://api.example.test',
      vault: MemoryTokenVault(),
      client: MockClient((r) async => throw StateError('No request expected')),
    );
    final store =
        AppStore(MemoryMarketplaceRepository(), api: api, socialAuth: provider)
          ..serverConfig = {
            'firebaseAuth': {'projectId': 'savefood-test', 'google': true},
          };
    addTearDown(() {
      store.dispose();
      api.close();
    });
    expect(await store.authenticateSocial('google'), false);
    expect(store.signedIn, false);
    expect(provider.cleanups, 1);
  });
  test('a late provider response cannot sign in after logout', () async {
    final pending = Completer<String?>();
    final provider = FakeSocial()..flow = () => pending.future;
    final api = MarketplaceApi(
      'https://api.example.test',
      vault: MemoryTokenVault(),
      client: MockClient((r) async => throw StateError('No request expected')),
    );
    final store =
        AppStore(MemoryMarketplaceRepository(), api: api, socialAuth: provider)
          ..serverConfig = {
            'firebaseAuth': {'projectId': 'savefood-test', 'google': true},
          };
    addTearDown(() {
      store.dispose();
      api.close();
    });
    final login = store.authenticateSocial('google');
    await store.signOut();
    pending.complete('late-token');
    expect(await login, false);
    expect(store.signedIn, false);
  });
  test(
    'a late server exchange is revoked without restoring an account',
    () async {
      final pending = Completer<http.Response>();
      final requested = Completer<void>();
      final provider = FakeSocial(), vault = MemoryTokenVault();
      var revoked = false;
      final api = MarketplaceApi(
        'https://api.example.test',
        vault: vault,
        client: MockClient((r) async {
          if (r.url.path == '/v1/auth/firebase') {
            requested.complete();
            return pending.future;
          }
          expect(r.url.path, '/v1/auth/logout');
          expect(r.headers['authorization'], 'Bearer late-session');
          revoked = true;
          return http.Response('{}', 200);
        }),
      );
      final store =
          AppStore(
              MemoryMarketplaceRepository(),
              api: api,
              socialAuth: provider,
            )
            ..serverConfig = {
              'firebaseAuth': {'projectId': 'savefood-test', 'google': true},
            };
      addTearDown(() {
        store.dispose();
        api.close();
      });
      final login = store.authenticateSocial('google');
      await requested.future;
      await store.signOut();
      pending.complete(
        http.Response('{"token":"late-session","userId":"late"}', 200),
      );
      expect(await login, false);
      expect(revoked, true);
      expect(vault.token, isNull);
      expect(store.signedIn, false);
    },
  );
  test(
    'mismatched client and server projects never offer social login',
    () async {
      final provider = FakeSocial();
      final api = MarketplaceApi(
        'https://api.example.test',
        vault: MemoryTokenVault(),
      );
      final store =
          AppStore(
              MemoryMarketplaceRepository(),
              api: api,
              socialAuth: provider,
            )
            ..serverConfig = {
              'firebaseAuth': {'projectId': 'another-project', 'google': true},
            };
      addTearDown(() {
        store.dispose();
        api.close();
      });
      expect(store.firebaseProviderEnabled('google'), false);
      await expectLater(
        store.authenticateSocial('google'),
        throwsA(isA<SocialSignInFailure>()),
      );
      expect(provider.cleanups, 0);
    },
  );
}

import 'dart:convert';
import 'dart:io';
import 'package:googleapis_auth/auth_io.dart';

abstract interface class StockPushGateway {
  bool get configured;
  Future<bool> send(
    String token,
    String title,
    String body,
    Map<String, String> data,
  );
  void close();
}

class DisabledPushGateway implements StockPushGateway {
  @override
  bool get configured => false;
  @override
  Future<bool> send(
    String token,
    String title,
    String body,
    Map<String, String> data,
  ) async => false;
  @override
  void close() {}
}

class FirebasePushGateway implements StockPushGateway {
  FirebasePushGateway(this.credentialsPath);
  final String credentialsPath;
  AutoRefreshingAuthClient? _client;
  String? _project;
  @override
  bool get configured => true;
  @override
  Future<bool> send(
    String token,
    String title,
    String body,
    Map<String, String> data,
  ) async {
    if (_client == null) {
      final json = Map<String, dynamic>.from(
        jsonDecode(await File(credentialsPath).readAsString()) as Map,
      );
      _project = json['project_id'] as String;
      _client = await clientViaServiceAccount(
        ServiceAccountCredentials.fromJson(json),
        ['https://www.googleapis.com/auth/firebase.messaging'],
      );
    }
    final response = await _client!
        .post(
          Uri.https(
            'fcm.googleapis.com',
            '/v1/projects/$_project/messages:send',
          ),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'message': {
              'token': token,
              'notification': {'title': title, 'body': body},
              'data': data,
              'android': {'priority': 'high'},
              'apns': {
                'payload': {
                  'aps': {'sound': 'default'},
                },
              },
            },
          }),
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode == 404) return false;
    if (response.statusCode >= 400) throw StateError('Push delivery failed.');
    return true;
  }

  @override
  void close() => _client?.close();
}

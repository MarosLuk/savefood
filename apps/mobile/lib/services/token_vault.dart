import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:marketplace_data/marketplace_data.dart';

class SecureTokenVault implements TokenVault {
  SecureTokenVault(String baseUrl)
    : key = 'nevyhadzuj.session.${base64UrlEncode(utf8.encode(baseUrl))}';
  final String key;
  final storage = const FlutterSecureStorage();
  @override
  Future<String?> read() => storage.read(key: key);
  @override
  Future<void> write(String token) => storage.write(key: key, value: token);
  @override
  Future<void> clear() => storage.delete(key: key);
}

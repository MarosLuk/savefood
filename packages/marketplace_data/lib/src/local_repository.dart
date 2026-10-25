import 'dart:convert';
import 'package:marketplace_domain/marketplace_domain.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocalMarketplaceRepository implements MarketplaceRepository {
  LocalMarketplaceRepository(this.preferences, {this.key = storageKey});
  static Future<LocalMarketplaceRepository> open({
    String key = storageKey,
  }) async => LocalMarketplaceRepository(
    await SharedPreferences.getInstance(),
    key: key,
  );
  final SharedPreferences preferences;
  final String key;
  static const storageKey = 'nevyhadzuj.snapshot.v1';

  @override
  Future<Map<String, dynamic>?> load() async {
    final raw = preferences.getString(key);
    if (raw == null) return null;
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic> || decoded['schema'] != 1) {
      throw const FormatException('Nepodporovaný formát lokálnych dát.');
    }
    return decoded;
  }

  @override
  Future<void> save(Map<String, dynamic> snapshot) async {
    final success = await preferences.setString(key, jsonEncode(snapshot));
    if (!success) throw StateError('Dáta sa nepodarilo uložiť do zariadenia.');
  }

  @override
  Future<void> clear() async {
    final success = await preferences.remove(key);
    if (!success) throw StateError('Dáta sa nepodarilo vymazať.');
  }
}

class MemoryMarketplaceRepository implements MarketplaceRepository {
  Map<String, dynamic>? _snapshot;
  @override
  Future<Map<String, dynamic>?> load() async => _snapshot == null
      ? null
      : Map<String, dynamic>.from(jsonDecode(jsonEncode(_snapshot)) as Map);
  @override
  Future<void> save(Map<String, dynamic> snapshot) async {
    _snapshot = Map<String, dynamic>.from(
      jsonDecode(jsonEncode(snapshot)) as Map,
    );
  }

  @override
  Future<void> clear() async => _snapshot = null;
}

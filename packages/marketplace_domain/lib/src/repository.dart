/// Storage boundary. A production implementation must use authenticated,
/// server-authoritative transactions rather than trusting client snapshots.
abstract interface class MarketplaceRepository {
  Future<Map<String, dynamic>?> load();
  Future<void> save(Map<String, dynamic> snapshot);
  Future<void> clear();
}

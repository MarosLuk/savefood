import 'package:flutter/foundation.dart';
import 'dart:async';
import 'package:marketplace_api/marketplace_api.dart';
import 'package:marketplace_domain/marketplace_domain.dart';
import 'choices.dart';

class MerchantController extends ChangeNotifier {
  MerchantController(this.api);
  final MarketplaceApi api;
  MerchantWorkspace workspace = const MerchantWorkspace();
  String? storeId, error;
  bool loading = false, busy = false, _alive = true;
  Future<void>? _loadFuture;
  Timer? _searchTimer;
  int _generation = 0;
  int _pageGeneration = 0;
  final Map<String, String> queries = {};
  String? loadingSection;
  MerchantStore? get store =>
      workspace.stores.where((s) => s.id == storeId).firstOrNull;
  MerchantOrganization? get organization => workspace.organizations
      .where((o) => o.id == store?.organizationId)
      .firstOrNull;
  bool get canManage => organization?.canManage ?? false;
  bool get owner => organization?.role == MerchantRole.owner;
  List<StockProduct> get products => workspace.products
      .where((p) => p.organizationId == store?.organizationId)
      .toList();
  List<StockLot> get lots =>
      workspace.lots.where((l) => l.storeId == storeId).toList();
  List<MerchantOffer> get offers =>
      workspace.offers.where((o) => o.storeId == storeId).toList();
  List<BundleRule> get rules =>
      workspace.rules.where((r) => r.storeId == storeId).toList();
  List<MerchantOrder> get orders {
    if (workspace.paged) return workspace.orders;
    final ids = offers.map((o) => o.offer.id).toSet();
    return workspace.orders
        .where((o) => o.items.any((i) => ids.contains(i.offerId)))
        .toList();
  }

  StockProduct product(String id) =>
      workspace.products.firstWhere((p) => p.id == id);
  Future<MerchantChoicePage> lookupProducts(
    String query,
    String? before,
  ) async {
    final result = await api.merchantWorkspace(
      storeId: storeId,
      section: 'products',
      query: query,
      before: before,
    );
    return MerchantChoicePage(
      result.products
          .map(
            (p) => MerchantChoice(
              p.id,
              '${p.name} · ${p.sku} · ${p.unit.label}',
              payload: p.toJson(),
            ),
          )
          .toList(),
      result.pages['products'] as String?,
    );
  }

  Future<MerchantChoicePage> lookupLots(String query, String? before) async {
    final uri = Uri(
      path: '/v1/merchant/workspace',
      queryParameters: {
        'paged': 'true',
        'storeId': storeId!,
        'section': 'lots',
        'query': query,
        'availableOnly': 'true',
        'before': ?before,
      },
    );
    final result = MerchantWorkspace.fromJson(
      await api.request('GET', uri.toString()),
    );
    return MerchantChoicePage(
      result.lots.map((l) {
        final p = result.products.firstWhere((p) => p.id == l.productId);
        return MerchantChoice(
          l.id,
          '${p.name} · ${l.code} · voľné ${p.unit.formatAmount(l.available, withUnit: true)}',
        );
      }).toList(),
      result.pages['lots'] as String?,
    );
  }

  void _notify() {
    if (_alive) notifyListeners();
  }

  void selectStore(String id) {
    storeId = id;
    _generation++;
    _pageGeneration++;
    loadingSection = null;
    queries.clear();
    error = null;
    _notify();
    unawaited(
      Future<void>(() async {
        await _loadFuture;
        await load();
      }),
    );
  }

  Future<void> load() =>
      _loadFuture ??= _load().whenComplete(() => _loadFuture = null);
  Future<void> _load() async {
    _pageGeneration++;
    loadingSection = null;
    final generation = ++_generation, requestedStore = storeId;
    loading = true;
    _notify();
    try {
      final result = await api.merchantWorkspace(storeId: storeId);
      if (!_alive || generation != _generation || requestedStore != storeId) {
        return;
      }
      workspace = result;
      if (workspace.paged) storeId = workspace.activeStoreId;
      if (!workspace.stores.any((s) => s.id == storeId)) {
        storeId = workspace.stores.firstOrNull?.id;
      }
      error = null;
    } catch (e) {
      error = e.toString();
    } finally {
      loading = false;
      _notify();
    }
  }

  void search(String section, String value) {
    if (!workspace.paged) return;
    queries[section] = value;
    _searchTimer?.cancel();
    _searchTimer = Timer(
      const Duration(milliseconds: 350),
      () => unawaited(page(section, more: false)),
    );
  }

  Future<void> page(String section, {bool more = true}) async {
    if (!workspace.paged || storeId == null) return;
    final cursor = more ? workspace.pages[section] as String? : null;
    if (more && cursor == null) return;
    final generation = _generation, pageGeneration = ++_pageGeneration;
    loadingSection = section;
    _notify();
    try {
      final next = await api.merchantWorkspace(
        storeId: storeId,
        section: section,
        before: cursor,
        query: queries[section],
      );
      if (!_alive ||
          generation != _generation ||
          pageGeneration != _pageGeneration) {
        return;
      }
      List<T> merge<T>(
        List<T> old,
        List<T> fresh,
        String name,
        String Function(T) key,
      ) => {
        for (final v in name == section && !more ? <T>[] : old) key(v): v,
        for (final v in fresh) key(v): v,
      }.values.toList();
      workspace = MerchantWorkspace(
        organizations: next.organizations,
        stores: next.stores,
        paged: true,
        activeStoreId: storeId,
        pages: {...workspace.pages, ...next.pages},
        stockSummary: next.stockSummary,
        products: merge(
          workspace.products,
          next.products,
          '_references',
          (p) => p.id,
        ),
        lots: merge(workspace.lots, next.lots, 'lots', (l) => l.id),
        offers: merge(
          workspace.offers,
          next.offers,
          'offers',
          (o) => o.offer.id,
        ),
        rules: merge(workspace.rules, next.rules, 'rules', (r) => r.id),
        orders: merge(workspace.orders, next.orders, 'orders', (o) => o.id),
        movements: merge(
          workspace.movements,
          next.movements,
          'movements',
          (m) => m['id'] as String,
        ),
        members: next.members,
        integrations: next.integrations,
      );
      error = null;
    } catch (e) {
      if (_alive &&
          generation == _generation &&
          pageGeneration == _pageGeneration) {
        error = e.toString();
      }
    } finally {
      if (_alive &&
          generation == _generation &&
          pageGeneration == _pageGeneration) {
        loadingSection = null;
        _notify();
      }
    }
  }

  Future<Map<String, dynamic>> mutate(
    String path,
    Map<String, dynamic> body, {
    String method = 'POST',
  }) async {
    if (busy) throw StateError('Počkaj na dokončenie predchádzajúcej akcie.');
    busy = true;
    error = null;
    _notify();
    try {
      final result = await api.merchantAction(path, body, method: method);
      await _loadFuture;
      await load();
      if (error != null) {
        throw StateError(
          'Zmena je uložená. Prehľad sa nepodarilo obnoviť; obnov ho pred ďalšou úpravou.',
        );
      }
      return result;
    } catch (e) {
      error = e.toString();
      rethrow;
    } finally {
      busy = false;
      _notify();
    }
  }

  @override
  void dispose() {
    _alive = false;
    _searchTimer?.cancel();
    super.dispose();
  }
}

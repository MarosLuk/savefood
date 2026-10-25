import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marketplace_data/marketplace_data.dart';
import 'package:marketplace_domain/marketplace_domain.dart';
import 'package:nevyhadzuj/state/app_store.dart';

final now = DateTime(2026, 10, 23, 14);
const invoice = InvoiceDetails(
  name: 'Jana Nová',
  email: 'jana@example.test',
  street: 'Testovacia 1',
  city: 'Bratislava',
  postcode: '81101',
);
AppStore makeStore([MarketplaceRepository? repo]) =>
    AppStore(repo ?? MemoryMarketplaceRepository(), clock: () => now);

class FailingRepository implements MarketplaceRepository {
  bool fail = false;
  final inner = MemoryMarketplaceRepository();
  @override
  Future<Map<String, dynamic>?> load() => inner.load();
  @override
  Future<void> save(Map<String, dynamic> snapshot) async {
    if (fail) throw StateError('Disk unavailable');
    await inner.save(snapshot);
  }

  @override
  Future<void> clear() => inner.clear();
}

void main() {
  test('cart respects stock and rejects zero and expired offers', () {
    final store = makeStore();
    final o = store.offer('butter')!;
    expect(store.addToCart(o, 4), isNull);
    expect(store.addToCart(o), isNotNull);
    expect(store.addToCart(o, 0), isNotNull);
    expect(store.cartCount, 4);
    expect(store.addToCart(store.offer('gf')!), isNotNull);
  });
  test('club offers require active membership', () {
    final store = makeStore();
    final o = store.offer('toast')!;
    expect(store.addToCart(o), isNotNull);
    expect(store.activateClub(''), isNull);
    expect(store.addToCart(o), isNull);
  });
  test('invalid checkout preserves cart', () async {
    final store = makeStore();
    store.addToCart(store.offer('butter')!);
    await expectLater(store.checkout(), throwsStateError);
    expect(store.cartCount, 1);
    expect(store.orders, isEmpty);
  });
  test('reservation saves immutable invoice and consumes stock', () async {
    final store = makeStore();
    store.saveInvoice(invoice);
    store.addToCart(store.offer('butter')!, 2);
    final o = await store.checkout();
    expect(o.total, 796);
    expect(store.remaining(store.offer('butter')!), 2);
    expect(store.cart, isEmpty);
    expect(o.invoice.email, 'jana@example.test');
  });
  test('duplicate concurrent checkout is rejected', () async {
    final store = makeStore();
    store.saveInvoice(invoice);
    store.addToCart(store.offer('butter')!);
    final first = store.checkout();
    await expectLater(store.checkout(), throwsStateError);
    await first;
    expect(store.orders, hasLength(1));
  });
  test('collecting pays cashback exactly once', () async {
    final store = makeStore();
    store.activateClub('');
    store.saveInvoice(invoice);
    store.addToCart(store.offer('butter')!);
    final o = await store.checkout();
    expect(store.credit, 0);
    await store.finishOrder(o.id, collect: true);
    expect(store.credit, 39);
    await store.finishOrder(o.id, collect: true);
    expect(store.credit, 39);
    expect(store.rescued, 1);
  });
  test('cancelling releases stock and cannot later be collected', () async {
    final store = makeStore();
    store.saveInvoice(invoice);
    store.addToCart(store.offer('butter')!, 4);
    final o = await store.checkout();
    expect(store.remaining(store.offer('butter')!), 0);
    await store.finishOrder(o.id, collect: false);
    expect(store.remaining(store.offer('butter')!), 4);
    await store.finishOrder(o.id, collect: true);
    expect(store.orders.first.status, OrderStatus.cancelled);
    expect(store.credit, 0);
  });
  test(
    'credit is debited on reservation and restored once on cancel',
    () async {
      final store = makeStore();
      store.credit = 100;
      store.saveInvoice(invoice);
      store.setUseCredit(true);
      store.addToCart(store.offer('butter')!);
      final o = await store.checkout();
      expect(store.credit, 0);
      expect(o.total, 298);
      await store.finishOrder(o.id, collect: false);
      await store.finishOrder(o.id, collect: false);
      expect(store.credit, 100);
    },
  );
  test('cancelled membership blocks club items already in cart', () async {
    final store = makeStore();
    store.activateClub('');
    store.saveInvoice(invoice);
    store.addToCart(store.offer('toast')!);
    store.cancelClub();
    await expectLater(store.checkout(), throwsStateError);
    expect(store.cartCount, 1);
  });
  test('failed disk write rolls back reservation and credit', () async {
    final repo = FailingRepository();
    final store = makeStore(repo);
    store.credit = 100;
    store.setUseCredit(true);
    store.saveInvoice(invoice);
    store.addToCart(store.offer('butter')!);
    await store.flush();
    repo.fail = true;
    await expectLater(store.checkout(), throwsStateError);
    expect(store.orders, isEmpty);
    expect(store.cartCount, 1);
    expect(store.credit, 100);
    expect(store.checkingOut, isFalse);
    expect(store.persistenceError, isNotNull);
    repo.fail = false;
    await store.retrySave();
    expect(store.persistenceError, isNull);
  });
  test('failed completion restores order state and wallet', () async {
    final repo = FailingRepository();
    final store = makeStore(repo);
    store.activateClub('');
    store.saveInvoice(invoice);
    store.addToCart(store.offer('butter')!);
    final o = await store.checkout();
    repo.fail = true;
    await expectLater(store.finishOrder(o.id, collect: true), throwsStateError);
    expect(store.orders.first.status, OrderStatus.reserved);
    expect(store.credit, 0);
  });
  test(
    'dark mode, favorites, location and preferences survive restart',
    () async {
      final repo = MemoryMarketplaceRepository();
      final store = makeStore(repo);
      store.setTheme(ThemeMode.dark);
      store.toggleFavorite('butter');
      store.setLocation(kosice, 'Košice', 12);
      store.preferences(favorites: true, news: true);
      store.completeOnboarding();
      await store.flush();
      final restored = makeStore(repo);
      await restored.restore();
      expect(restored.themeMode, ThemeMode.dark);
      expect(restored.favorites, contains('butter'));
      expect(restored.location.latitude, kosice.latitude);
      expect(restored.favoriteAlerts, isTrue);
      expect(restored.marketing, isTrue);
      expect(restored.onboardingComplete, isTrue);
    },
  );
  test(
    'orders and ledger survive restart without duplicate stock debit',
    () async {
      final repo = MemoryMarketplaceRepository();
      final store = makeStore(repo);
      store.saveInvoice(invoice);
      store.addToCart(store.offer('butter')!);
      await store.checkout();
      final restored = makeStore(repo);
      await restored.restore();
      expect(restored.orders, hasLength(1));
      expect(restored.remaining(restored.offer('butter')!), 3);
    },
  );
  test(
    'new calendar day clears stale cart without losing order history',
    () async {
      final repo = MemoryMarketplaceRepository();
      final store = makeStore(repo);
      store.saveInvoice(invoice);
      store.addToCart(store.offer('butter')!);
      await store.checkout();
      store.addToCart(store.offer('bread')!);
      await store.flush();
      final tomorrow = AppStore(
        repo,
        clock: () => now.add(const Duration(days: 1)),
      );
      await tomorrow.restore();
      expect(tomorrow.cart, isEmpty);
      expect(tomorrow.orders, hasLength(1));
      expect(tomorrow.remaining(tomorrow.offer('butter')!), 4);
    },
  );
  test('club trial cannot be reused and validates coupon', () {
    final store = makeStore();
    expect(store.activateClub('BAD'), isNotNull);
    expect(store.activateClub('KLUB30'), isNull);
    expect(store.memberUntil, now.add(const Duration(days: 30)));
    store.cancelClub();
    expect(store.activateClub(''), isNotNull);
  });
}

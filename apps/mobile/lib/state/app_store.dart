import 'dart:async';
import 'package:flutter/material.dart';
import 'package:marketplace_data/marketplace_data.dart';
import 'package:marketplace_domain/marketplace_domain.dart';
import '../services/social_auth.dart';

class AppStore extends ChangeNotifier {
  AppStore(
    this.repository, {
    DateTime Function()? clock,
    this.api,
    SocialSignIn? socialAuth,
  }) : clock = clock ?? DateTime.now,
       socialAuth = socialAuth ?? FirebaseSocialSignIn() {
    offers = api == null ? seedCatalog(this.clock()) : [];
  }
  final MarketplaceRepository repository;
  final MarketplaceApi? api;
  final SocialSignIn socialAuth;
  int _socialAuthEpoch = 0;
  bool firebaseProviderEnabled(String provider) =>
      remoteEnabled &&
      socialAuth.ready &&
      (serverConfig['firebaseAuth'] as Map?)?['projectId'] ==
          socialAuth.projectId &&
      (serverConfig['firebaseAuth'] as Map?)?[provider] == true;

  Future<bool> authenticateSocial(
    String provider, {
    Future<Map<String, dynamic>?> Function()? requestConsent,
  }) async {
    if (!firebaseProviderEnabled(provider)) {
      throw const SocialSignInFailure(
        'Tento spôsob prihlásenia ešte nie je aktivovaný.',
      );
    }
    final epoch = ++_socialAuthEpoch;
    try {
      final token = await socialAuth.signIn(provider);
      if (token == null || epoch != _socialAuthEpoch || !_alive) return false;
      Map<String, dynamic>? consent;
      Future<bool> exchange() => api!.loginFirebase(
        token,
        provider,
        legalConsent: consent,
        accept: () => epoch == _socialAuthEpoch && _alive,
      );
      bool accepted;
      try {
        accepted = await exchange();
      } on ApiException catch (e) {
        if (e.status != 428 || requestConsent == null) rethrow;
        consent = await requestConsent();
        if (consent == null || epoch != _socialAuthEpoch || !_alive) {
          return false;
        }
        accepted = await exchange();
      }
      if (!accepted || epoch != _socialAuthEpoch || !_alive) return false;
      _preferenceTimer?.cancel();
      _clearAccount();
      cart.clear();
      coupon = '';
      _checkoutKey = null;
      pendingOAuth = null;
      final profile = await api!.me();
      if (epoch != _socialAuthEpoch || !_alive) return false;
      _applyAccount(profile);
      await refreshRemote();
      _changed();
      return true;
    } finally {
      await socialAuth.signOut();
    }
  }

  Map<String, dynamic> serverConfig = {};
  String? connectionError;
  String? notificationInfo;
  String? pendingSupportPhotoTicket, supportTicketToOpen;
  String? pendingMediaOrganization;
  String? pendingReviewOffer;
  Future<void> rememberReviewOffer(String? id) async {
    pendingReviewOffer = id;
    _changed();
    await _writes;
  }

  Future<void> rememberMediaOrganization(String? id) async {
    pendingMediaOrganization = id;
    _changed();
    await _writes;
  }

  int supportActivityVersion = 0;
  void receiveSupportActivity() {
    supportActivityVersion++;
    if (_alive) notifyListeners();
  }

  void openSupportTicket(String id) {
    if (!signedIn || id.isEmpty || id.length > 100) return;
    supportTicketToOpen = id;
    if (_alive) notifyListeners();
  }

  Future<void> rememberPhotoTicket(String? id) async {
    pendingSupportPhotoTicket = id;
    await _save();
  }

  void showNotification(String message) {
    notificationInfo = message;
    if (_alive) notifyListeners();
  }

  void dismissNotification() {
    notificationInfo = null;
    notifyListeners();
  }

  bool syncing = false;
  Future<void>? _remoteRefresh;
  Timer? _preferenceTimer;
  String? _checkoutKey;
  PaymentFlow _checkoutFlow = PaymentFlow.hosted;
  Map<String, dynamic> get paymentConfiguration =>
      Map<String, dynamic>.from(serverConfig['payments'] as Map? ?? {});
  bool get stripeTestMode =>
      !isDemo && paymentConfiguration['livemode'] == false;
  Map<String, dynamic>? pendingOAuth;
  bool get remoteEnabled => api != null;
  bool get isDemo =>
      api == null ||
      !{'stripe', 'disabled'}.contains(serverConfig['paymentMode']);
  bool get paymentsEnabled => serverConfig['paymentMode'] != 'disabled';
  bool get demoShowcase =>
      remoteEnabled && serverConfig['demoShowcase'] == true;
  final DateTime Function() clock;
  late List<FoodOffer> offers;
  final Set<String> favorites = {};
  final Map<String, int> cart = {};
  final List<RescueOrder> orders = [];
  OfferFilters filters = const OfferFilters();
  GeoPoint location = bratislava;
  String locationLabel = 'Bratislava, Staré Mesto';
  String name = '', email = '';
  InvoiceDetails invoice = const InvoiceDetails();
  ThemeMode themeMode = ThemeMode.system;
  String language = 'sk';
  bool onboardingComplete = false;
  bool emailNotifications = true,
      favoriteAlerts = false,
      supportAlerts = false,
      pickupReminders = true,
      marketing = false,
      analytics = false;
  bool useCredit = false, checkingOut = false;
  int credit = 0;
  String coupon = '';
  DateTime? memberUntil;
  bool trialUsed = false, clubRenewalCancelled = false;
  bool emailVerified = false, hasPassword = false;
  String? platformRole;
  String? persistenceError;
  Future<void> _writes = Future.value();
  bool _alive = true;

  DateTime get now => clock();
  bool get isMember => memberUntil?.isAfter(now) ?? false;
  bool get signedIn => api == null ? email.isNotEmpty : api!.authenticated;
  int get cartCount => cart.values.fold(0, (a, b) => a + b);
  List<FoodOffer> get nearby =>
      const OfferFilters().apply(offers, location, now, remaining: remaining);
  List<FoodOffer> get results =>
      filters.apply(offers, location, now, remaining: remaining);
  List<FoodOffer> get saved =>
      offers.where((o) => favorites.contains(o.id)).toList();
  List<RescueOrder> get activeOrders => orders
      .where(
        (o) =>
            o.status == OrderStatus.reserved ||
            o.status == OrderStatus.awaitingPayment,
      )
      .toList();
  int get rescued => orders
      .where((o) => o.status == OrderStatus.collected)
      .fold(
        0,
        (sum, o) =>
            sum +
            o.items
                .where((i) => i.collected && !i.refunded)
                .fold(0, (n, i) => n + i.remainingQuantity),
      );
  int get savedMoney => orders
      .where((o) => o.status == OrderStatus.collected)
      .fold(
        0,
        (sum, o) =>
            sum +
            o.items
                .where((i) => !i.refunded)
                .fold(
                  0,
                  (n, i) =>
                      n +
                      ((offer(i.offerId)?.originalPrice ?? i.unitPrice) -
                              i.unitPrice) *
                          i.remainingQuantity,
                ),
      );
  FoodOffer? offer(String id) {
    for (final item in offers) {
      if (item.id == id) return item;
    }
    return null;
  }

  int remaining(FoodOffer item) {
    if (remoteEnabled) return item.stock;
    var reserved = 0;
    for (final order in orders.where(
      (o) => o.status != OrderStatus.cancelled,
    )) {
      for (final line in order.items) {
        if (line.offerId == item.id && line.pickupStart == item.pickupStart) {
          reserved += line.quantity;
        }
      }
    }
    return (item.stock - reserved).clamp(0, item.stock);
  }

  bool available(FoodOffer item) =>
      remaining(item) > 0 && item.pickupEnd.isAfter(now);
  int get subtotal => cart.entries.fold(
    0,
    (sum, e) => sum + (offer(e.key)?.price ?? 0) * e.value,
  );
  CheckoutQuote get quote => CheckoutQuote.calculate(
    subtotal: subtotal,
    coupon: coupon,
    credit: credit,
    useCredit: useCredit,
    clubMember: isMember,
    minimumExternalPayment: isDemo ? 0 : 50,
  );

  Future<void> restore() async {
    final json = await repository.load();
    if (json == null) return;
    favorites.addAll((json['favorites'] as List? ?? []).cast<String>());
    orders.addAll(
      (json['orders'] as List? ?? []).map(
        (o) => RescueOrder.fromJson(Map<String, dynamic>.from(o as Map)),
      ),
    );
    _checkoutKey = json['checkoutKey'] as String?;
    _checkoutFlow = PaymentFlow.values.byName(
      json['checkoutFlow'] as String? ?? 'hosted',
    );
    coupon = json['coupon'] as String? ?? '';
    useCredit = json['useCredit'] as bool? ?? false;
    final savedDay = json['catalogDay'] as String?;
    if (savedDay == _day(now)) {
      final restored = Map<String, dynamic>.from(json['cart'] as Map? ?? {});
      for (final entry in restored.entries) {
        final item = offer(entry.key);
        if (remoteEnabled && entry.value is int && entry.value > 0) {
          cart[entry.key] = entry.value as int;
          continue;
        }
        if (item != null &&
            entry.value is int &&
            entry.value > 0 &&
            available(item)) {
          cart[entry.key] = (entry.value as int).clamp(1, remaining(item));
        }
      }
    }
    name = json['name'] as String? ?? '';
    email = json['email'] as String? ?? '';
    invoice = InvoiceDetails.fromJson(
      Map<String, dynamic>.from(json['invoice'] as Map? ?? {}),
    );
    themeMode = ThemeMode.values.byName(json['theme'] as String? ?? 'system');
    language = json['language'] as String? ?? 'sk';
    pendingSupportPhotoTicket = json['pendingSupportPhotoTicket'] as String?;
    pendingMediaOrganization = json['pendingMediaOrganization'] as String?;
    pendingReviewOffer = json['pendingReviewOffer'] as String?;
    onboardingComplete = json['onboardingComplete'] as bool? ?? false;
    favoriteAlerts = json['favoriteAlerts'] as bool? ?? false;
    supportAlerts = json['supportAlerts'] as bool? ?? false;
    pickupReminders = json['pickupReminders'] as bool? ?? true;
    marketing = json['marketing'] as bool? ?? false;
    analytics = json['analytics'] as bool? ?? false;
    emailNotifications = json['emailNotifications'] as bool? ?? true;
    credit = (json['credit'] as int? ?? 0).clamp(0, 100000000);
    trialUsed = json['trialUsed'] as bool? ?? false;
    clubRenewalCancelled = json['clubRenewalCancelled'] as bool? ?? false;
    memberUntil = DateTime.tryParse(json['memberUntil'] as String? ?? '');
    if (json['location'] != null) {
      location = GeoPoint.fromJson(
        Map<String, dynamic>.from(json['location'] as Map),
      );
    }
    locationLabel = json['locationLabel'] as String? ?? locationLabel;
  }

  static String _day(DateTime date) => '${date.year}-${date.month}-${date.day}';
  Map<String, dynamic> _snapshot() => {
    'schema': 1,
    'checkoutKey': _checkoutKey,
    'checkoutFlow': _checkoutFlow.name,
    'coupon': coupon,
    'useCredit': useCredit,
    'catalogDay': _day(now),
    'favorites': favorites.toList(),
    'cart': Map<String, int>.from(cart),
    'orders': orders.map((o) => o.toJson()).toList(),
    'name': name,
    'email': email,
    'invoice': invoice.toJson(),
    'theme': themeMode.name,
    'pendingSupportPhotoTicket': pendingSupportPhotoTicket,
    'pendingMediaOrganization': pendingMediaOrganization,
    'pendingReviewOffer': pendingReviewOffer,
    'language': language,
    'onboardingComplete': onboardingComplete,
    'favoriteAlerts': favoriteAlerts,
    'supportAlerts': supportAlerts,
    'pickupReminders': pickupReminders,
    'marketing': marketing,
    'analytics': analytics,
    'emailNotifications': emailNotifications,
    'credit': credit,
    'trialUsed': trialUsed,
    'memberUntil': memberUntil?.toIso8601String(),
    'location': location.toJson(),
    'locationLabel': locationLabel,
  };

  Future<void> _save() {
    final snapshot = _snapshot();
    final operation = _writes.then((_) => repository.save(snapshot));
    _writes = operation.then<void>(
      (_) {
        if (persistenceError != null && _alive) {
          persistenceError = null;
          notifyListeners();
        }
      },
      onError: (Object error, StackTrace stack) {
        persistenceError = 'Zmeny sa nepodarilo uložiť. Skús to znova.';
        if (_alive) notifyListeners();
      },
    );
    return operation;
  }

  void _changed() {
    notifyListeners();
    unawaited(_save().catchError((Object _) {}));
    if (api?.authenticated ?? false) {
      _preferenceTimer?.cancel();
      _preferenceTimer = Timer(const Duration(milliseconds: 350), () async {
        try {
          await api!.updateProfile({
            if (name.length >= 2) 'name': name,
            if (invoice.isValid) 'invoice': invoice.toJson(),
            'favorites': favorites.toList(),
            'favoriteAlerts': favoriteAlerts,
            'supportAlerts': supportAlerts,
            'pickupReminders': pickupReminders,
            'marketing': marketing,
            'analytics': analytics,
            'emailNotifications': emailNotifications,
          });
        } catch (error) {
          connectionError = error.toString();
          if (_alive) notifyListeners();
        }
      });
    }
  }

  void _applyAccount(Map<String, dynamic> json) {
    name = json['name'] as String;
    email = json['email'] as String;
    emailVerified = json['emailVerified'] as bool? ?? false;
    hasPassword = json['hasPassword'] as bool? ?? false;
    platformRole = json['platformRole'] as String?;
    credit = json['credit'] as int;
    trialUsed = json['trialUsed'] as bool? ?? false;
    clubRenewalCancelled = json['clubRenewalCancelled'] as bool? ?? false;
    memberUntil = DateTime.tryParse(json['memberUntil'] as String? ?? '');
    orders
      ..clear()
      ..addAll(
        (json['orders'] as List? ?? []).map(
          (o) => RescueOrder.fromJson(Map<String, dynamic>.from(o as Map)),
        ),
      );
    favorites
      ..clear()
      ..addAll((json['favorites'] as List? ?? []).cast<String>());
    invoice = InvoiceDetails.fromJson(
      Map<String, dynamic>.from(json['invoice'] as Map? ?? {}),
    );
    favoriteAlerts = json['favoriteAlerts'] as bool? ?? false;
    supportAlerts = json['supportAlerts'] as bool? ?? false;
    pickupReminders = json['pickupReminders'] as bool? ?? true;
    marketing = json['marketing'] as bool? ?? false;
    analytics = json['analytics'] as bool? ?? false;
    emailNotifications = json['emailNotifications'] as bool? ?? true;
  }

  Future<void> refreshRemote() {
    if (api == null) return Future.value();
    return _remoteRefresh ??= _performRemoteRefresh().whenComplete(
      () => _remoteRefresh = null,
    );
  }

  Future<void> _performRemoteRefresh() async {
    syncing = true;
    try {
      serverConfig = await api!.request('GET', '/v1/config');
      offers = await api!.catalog();
      if (api!.authenticated) _applyAccount(await api!.me());
      connectionError = null;
    } catch (error) {
      if (error is ApiException && error.status == 401) _clearAccount();
      connectionError = error.toString();
    } finally {
      syncing = false;
      if (_alive) notifyListeners();
    }
  }

  Future<void> initializeRemote() async {
    if (api == null) return;
    await api!.restoreSession();
    final photoEmail = email,
        photoTicket = pendingSupportPhotoTicket,
        photoOrganization = pendingMediaOrganization,
        reviewOffer = pendingReviewOffer;
    final guestFavorites = email.isEmpty ? favorites.toSet() : <String>{};
    _clearAccount();
    favorites.addAll(guestFavorites);
    await refreshRemote();
    if (api!.authenticated && email == photoEmail) {
      pendingSupportPhotoTicket = photoTicket;
      pendingMediaOrganization = photoOrganization;
      pendingReviewOffer = reviewOffer;
    }
  }

  void _clearAccount() {
    name = '';
    email = '';
    emailVerified = false;
    hasPassword = false;
    platformRole = null;
    credit = 0;
    memberUntil = null;
    trialUsed = false;
    clubRenewalCancelled = false;
    favoriteAlerts = false;
    supportAlerts = false;
    pendingSupportPhotoTicket = null;
    pendingMediaOrganization = null;
    pendingReviewOffer = null;
    supportTicketToOpen = null;
    supportActivityVersion = 0;
    marketing = false;
    analytics = false;
    emailNotifications = true;
    orders.clear();
    favorites.clear();
    invoice = const InvoiceDetails();
  }

  Future<void> authenticate({
    required String name,
    required String email,
    required String password,
    required bool register,
    Map<String, dynamic>? legalConsent,
  }) async {
    _socialAuthEpoch++;
    if (api == null) {
      saveProfile(name, email);
      return;
    }
    _preferenceTimer?.cancel();
    if (register) {
      await api!.register(name, email, password, legalConsent: legalConsent);
    } else {
      await api!.login(email, password);
    }
    _applyAccount(await api!.me());
    await refreshRemote();
    _changed();
  }

  Future<void> signOut() async {
    _socialAuthEpoch++;
    _preferenceTimer?.cancel();
    if (api != null) {
      try {
        await api!.logout();
      } catch (_) {
        /* The local token is cleared by the client even when offline. */
      }
      _clearAccount();
    } else {
      name = '';
      email = '';
    }
    cart.clear();
    coupon = '';
    _checkoutKey = null;
    _changed();
    await socialAuth.signOut();
  }

  Future<void> enterDemo(String persona) async {
    _socialAuthEpoch++;
    if (!demoShowcase) throw StateError('Pripravené demo nie je zapnuté.');
    _preferenceTimer?.cancel();
    // Finish reads from the previous account before changing its identity.
    await _remoteRefresh;
    await _writes;
    await api!.enterDemo(persona);
    _clearAccount();
    cart.clear();
    coupon = '';
    useCredit = false;
    _checkoutKey = null;
    pendingOAuth = null;
    filters = const OfferFilters();
    location = bratislava;
    locationLabel = 'Bratislava, Staré Mesto';
    _applyAccount(await api!.me());
    offers = await api!.catalog();
    onboardingComplete = true;
    connectionError = null;
    _changed();
  }

  Future<String> beginOAuth(String provider) async {
    _socialAuthEpoch++;
    if (api == null) {
      throw const ApiException(
        503,
        'Pre externé prihlásenie pripoj aplikáciu k API serveru.',
      );
    }
    pendingOAuth = await api!.beginOAuth(provider);
    return pendingOAuth!['url'] as String;
  }

  Future<bool> finishOAuth() async {
    if (api == null || pendingOAuth == null) return false;
    if (!await api!.pollOAuth(pendingOAuth!)) return false;
    pendingOAuth = null;
    _applyAccount(await api!.me());
    await refreshRemote();
    _changed();
    return true;
  }

  Future<String?> joinClub(String code) async {
    if (api == null) return activateClub(code);
    try {
      _applyAccount(await api!.activateTrial(code));
      _changed();
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  Future<void> endClub() async {
    if (api == null) {
      cancelClub();
      return;
    }
    _applyAccount(await api!.cancelClub());
    _changed();
  }

  Future<void> refreshOrder(String id) async {
    if (api == null) return;
    // A lifecycle refresh can still contain the status before SDK confirmation.
    await refreshRemote();
    final order = await api!.refreshOrder(id);
    orders.removeWhere((o) => o.id == order.id);
    orders.insert(0, order);
    if (_alive) notifyListeners();
    await _save();
  }

  Future<void> flush() => _writes;
  Future<void> retrySave() => _save();
  void completeOnboarding() {
    onboardingComplete = true;
    _changed();
  }

  void toggleFavorite(String id) {
    if (!favorites.remove(id)) favorites.add(id);
    _changed();
  }

  void setFilters(OfferFilters value) {
    filters = value;
    notifyListeners();
  }

  void setLocation(GeoPoint point, String label, double radius) {
    location = point;
    locationLabel = label;
    filters = filters.copyWith(radiusKm: radius);
    _changed();
  }

  void refreshCatalog() {
    if (api != null) {
      unawaited(refreshRemote());
      return;
    }
    offers = seedCatalog(now);
    notifyListeners();
  }

  String? addToCart(FoodOffer item, [int quantity = 1]) {
    if (checkingOut) return 'Rezervácia práve prebieha.';
    if (!available(item)) return 'Tento balíček už nie je dostupný.';
    if (item.type == OfferType.club && !isMember) {
      return 'Táto ponuka je pre členov Klubu.';
    }
    if (quantity < 1 || (cart[item.id] ?? 0) + quantity > remaining(item)) {
      return 'Viac kusov už nie je dostupných.';
    }
    cart[item.id] = (cart[item.id] ?? 0) + quantity;
    _checkoutKey = null;
    _changed();
    return null;
  }

  void setQuantity(String id, int quantity) {
    if (checkingOut) return;
    final item = offer(id);
    if (quantity <= 0) {
      cart.remove(id);
    } else if (item != null && quantity <= remaining(item)) {
      cart[id] = quantity;
    }
    if (cart.isEmpty) coupon = '';
    _checkoutKey = null;
    _changed();
  }

  String? applyCoupon(String value) {
    final code = value.trim().toUpperCase();
    if (code.isNotEmpty && !CheckoutQuote.validCoupons.contains(code)) {
      return 'Neplatný kupón. V deme skús VITAJ10.';
    }
    coupon = code;
    _checkoutKey = null;
    notifyListeners();
    return null;
  }

  void setUseCredit(bool value) {
    useCredit = value;
    _checkoutKey = null;
    notifyListeners();
  }

  void saveInvoice(InvoiceDetails value) {
    invoice = value;
    _checkoutKey = null;
    _changed();
  }

  void saveProfile(String displayName, String address) {
    name = displayName.trim();
    email = address.trim();
    _changed();
  }

  void setTheme(ThemeMode mode) {
    themeMode = mode;
    _changed();
  }

  void setLanguage(String value) {
    language = value;
    _changed();
  }

  void preferences({
    bool? favorites,
    bool? reminders,
    bool? support,
    bool? news,
    bool? statistics,
    bool? emailUpdates,
  }) {
    favoriteAlerts = favorites ?? favoriteAlerts;
    supportAlerts = support ?? supportAlerts;
    pickupReminders = reminders ?? pickupReminders;
    marketing = news ?? marketing;
    analytics = statistics ?? analytics;
    emailNotifications = emailUpdates ?? emailNotifications;
    _changed();
  }

  String? activateClub(String code) {
    if (isMember) return 'Klub už máš aktívny.';
    if (trialUsed) return 'Demo skúška už bola využitá.';
    final normalized = code.trim().toUpperCase();
    if (normalized.isNotEmpty && normalized != 'KLUB30') {
      return 'Skús demo kupón KLUB30.';
    }
    memberUntil = now.add(Duration(days: normalized.isEmpty ? 14 : 30));
    trialUsed = true;
    _changed();
    return null;
  }

  void cancelClub() {
    memberUntil = null;
    _changed();
  }

  Future<RescueOrder> checkout({
    PaymentFlow paymentFlow = PaymentFlow.hosted,
  }) async {
    if (checkingOut) throw StateError('Rezervácia už prebieha.');
    if (cart.isEmpty) throw StateError('Košík je prázdny.');
    if (api != null && !api!.authenticated) {
      throw StateError('Pre dokončenie rezervácie sa prihlás.');
    }
    if (!invoice.isValid) throw StateError('Vyplň platné fakturačné údaje.');
    for (final entry in (api == null ? cart : <String, int>{}).entries) {
      final item = offer(entry.key);
      if (item == null || !available(item) || entry.value > remaining(item)) {
        throw StateError('Dostupnosť sa zmenila. Uprav košík.');
      }
      if (item.type == OfferType.club && !isMember) {
        throw StateError('Pre klubovú ponuku potrebuješ aktívny Klub.');
      }
    }
    checkingOut = true;
    notifyListeners();
    if (api != null) {
      if (_checkoutKey == null) {
        _checkoutKey = MarketplaceApi.newIdempotencyKey();
        _checkoutFlow = paymentFlow;
      }
      try {
        await _save();
        final order = await api!.reserve(
          cart: Map.from(cart),
          invoice: invoice,
          coupon: coupon,
          useCredit: useCredit,
          key: _checkoutKey!,
          paymentFlow: _checkoutFlow,
        );
        orders.removeWhere((o) => o.id == order.id);
        orders.insert(0, order);
        cart.clear();
        coupon = '';
        _checkoutKey = null;
        await refreshRemote();
        try {
          await _save();
        } catch (_) {
          /* Server has committed the order; keep the acknowledged state. */
        }
        return order;
      } catch (e) {
        throw StateError(e.toString());
      } finally {
        checkingOut = false;
        if (_alive) notifyListeners();
      }
    }
    final oldCart = Map<String, int>.from(cart);
    final oldCredit = credit;
    final oldCoupon = coupon;
    final totals = quote;
    final order = RescueOrder(
      id: 'NV-${now.microsecondsSinceEpoch.toRadixString(36).toUpperCase()}-${orders.length + 1}',
      createdAt: now,
      items: cart.entries.map((entry) {
        final item = offer(entry.key)!;
        return OrderItem(
          offerId: item.id,
          store: item.store,
          title: item.title,
          image: item.image,
          quantity: entry.value,
          unitPrice: item.price,
          pickupStart: item.pickupStart,
          pickupEnd: item.pickupEnd,
          address: item.address,
        );
      }).toList(),
      total: totals.total,
      discount: totals.discount,
      serviceFee: totals.serviceFee,
      creditUsed: totals.creditUsed,
      cashback: totals.cashback,
      invoice: invoice,
    );
    orders.insert(0, order);
    credit -= totals.creditUsed;
    cart.clear();
    coupon = '';
    try {
      await _save();
      return order;
    } catch (_) {
      orders.removeWhere((o) => o.id == order.id);
      credit = oldCredit;
      cart.addAll(oldCart);
      coupon = oldCoupon;
      throw StateError(
        'Rezervácia sa neuložila. Košík zostal zachovaný. Skús to znova.',
      );
    } finally {
      checkingOut = false;
      if (_alive) notifyListeners();
    }
  }

  Future<void> finishOrder(
    String id, {
    required bool collect,
    String? offerId,
  }) async {
    if (checkingOut) return;
    final index = orders.indexWhere((o) => o.id == id);
    if (api != null) {
      if (index < 0) return;
      checkingOut = true;
      notifyListeners();
      try {
        await api!.finishOrder(
          orders[index],
          collect: collect,
          offerId: offerId,
        );
        await refreshRemote();
        await _save();
      } catch (e) {
        throw StateError(e.toString());
      } finally {
        checkingOut = false;
        if (_alive) notifyListeners();
      }
      return;
    }
    if (index < 0 || orders[index].status != OrderStatus.reserved) return;
    checkingOut = true;
    final previous = orders[index];
    final oldCredit = credit;
    if (!collect && previous.items.any((i) => i.collected)) {
      checkingOut = false;
      throw StateError(
        'Čiastočne vyzdvihnutú objednávku už nemožno zrušiť naraz.',
      );
    }
    final items = collect
        ? previous.items
              .map(
                (i) => offerId == null || i.offerId == offerId
                    ? i.withCollected()
                    : i,
              )
              .toList()
        : previous.items;
    final complete = collect && items.every((i) => i.collected);
    orders[index] = previous.withStatus(
      collect
          ? (complete ? OrderStatus.collected : OrderStatus.reserved)
          : OrderStatus.cancelled,
      updatedItems: items,
    );
    credit += collect
        ? (complete ? previous.cashback : 0)
        : previous.creditUsed;
    notifyListeners();
    try {
      await _save();
    } catch (_) {
      orders[index] = previous;
      credit = oldCredit;
      throw StateError('Zmenu sa nepodarilo uložiť. Skús to znova.');
    } finally {
      checkingOut = false;
      if (_alive) notifyListeners();
    }
  }

  @override
  void dispose() {
    _alive = false;
    _preferenceTimer?.cancel();
    api?.close();
    super.dispose();
  }
}

class StoreScope extends InheritedNotifier<AppStore> {
  const StoreScope({super.key, required AppStore store, required super.child})
    : super(notifier: store);
  static AppStore of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<StoreScope>()!.notifier!;
}

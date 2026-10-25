class ServerConfig {
  const ServerConfig({
    this.port = 8080,
    this.host = '127.0.0.1',
    this.geocoderUrl = '',
    this.firebaseServiceAccount = '',
    this.databasePath = 'data/marketplace.sqlite',
    this.publicUrl = 'http://localhost:8080',
    this.appUrl = 'http://localhost:7357',
    this.merchantAppUrl = 'http://localhost:7358',
    this.allowedOrigins = const [
      'http://localhost:7357',
      'http://127.0.0.1:7357',
      'http://localhost:7358',
      'http://127.0.0.1:7358',
      'http://localhost:7359',
      'http://127.0.0.1:7359',
    ],
    this.production = false,
    this.seedDemo = true,
    this.demoShowcase = false,
    this.paymentMode = 'sandbox',
    this.connectEnabled = false,
    this.commissionBps = 0,
    this.settlementDelayHours = 24,
    this.automaticSettlements = false,
    this.stripeClubPriceId = '',
    this.stripeSecret = '',
    this.stripePublishableKey = '',
    this.applePayMerchantId = '',
    this.merchantCountry = 'SK',
    this.stripeWebhookSecret = '',
    this.adminToken = '',
    this.googleClientId = '',
    this.googleClientSecret = '',
    this.appleClientId = '',
    this.appleClientSecret = '',
    this.facebookAppId = '',
    this.facebookAppSecret = '',
    this.mailApiKey = '',
    this.mailFrom = '',
    this.platformAdminEmails = const [],
    this.billingFontPath = 'apps/mobile/assets/fonts/InterVariable.ttf',
    this.billingSellerModel = '',
    this.firebaseAuthProjectId = '',
    this.firebaseAuthApiKey = '',
    this.firebaseGoogleEnabled = false,
    this.firebaseAppleEnabled = false,
  });
  final int port;
  final bool connectEnabled, automaticSettlements;
  final int commissionBps, settlementDelayHours;
  final String host, firebaseServiceAccount, geocoderUrl;
  final String stripeClubPriceId;
  final String stripePublishableKey, applePayMerchantId, merchantCountry;
  bool get stripeLiveMode => stripeSecret.startsWith('sk_live_');
  bool get nativePaymentsEnabled =>
      paymentMode == 'stripe' && stripePublishableKey.isNotEmpty;
  Map<String, dynamic> get paymentConfiguration => {
    'nativePaymentSheet': nativePaymentsEnabled,
    'publishableKey': nativePaymentsEnabled ? stripePublishableKey : '',
    'applePayMerchantId': applePayMerchantId,
    'merchantCountry': merchantCountry,
    'currency': 'EUR',
    'minimumAmount': 50,
    'livemode': stripeLiveMode,
    'cardBrands': ['visa', 'mastercard'],
    'wallets': ['apple_pay', 'google_pay'],
  };
  final String databasePath,
      publicUrl,
      appUrl,
      merchantAppUrl,
      paymentMode,
      stripeSecret,
      stripeWebhookSecret,
      adminToken;
  final String googleClientId,
      googleClientSecret,
      appleClientId,
      appleClientSecret,
      facebookAppId,
      facebookAppSecret;
  final List<String> allowedOrigins;
  final String mailApiKey, mailFrom;
  final String billingFontPath;
  final String billingSellerModel;
  final String firebaseAuthProjectId, firebaseAuthApiKey;
  final bool firebaseGoogleEnabled, firebaseAppleEnabled;
  bool get firebaseAuthEnabled =>
      firebaseAuthProjectId.isNotEmpty && firebaseAuthApiKey.isNotEmpty;
  final List<String> platformAdminEmails;
  final bool production, seedDemo, demoShowcase;

  void validateShowcase() {
    if (demoShowcase &&
        (production ||
            !seedDemo ||
            paymentMode != 'sandbox' ||
            stripeSecret.isNotEmpty ||
            mailApiKey.isNotEmpty ||
            firebaseAuthEnabled ||
            firebaseServiceAccount.isNotEmpty)) {
      throw ArgumentError(
        'DEMO_SHOWCASE requires a non-production sandbox with SEED_DEMO=true and no Stripe, Firebase or mail credentials.',
      );
    }
  }

  factory ServerConfig.fromEnvironment(Map<String, String> env) {
    final prod = env['APP_ENV'] == 'production';
    final config = ServerConfig(
      port: int.tryParse(env['PORT'] ?? '') ?? 8080,
      geocoderUrl:
          env['GEOCODER_URL'] ?? (prod ? '' : 'https://photon.komoot.io/api/'),
      host: env['HOST'] ?? (prod ? '0.0.0.0' : '127.0.0.1'),
      firebaseServiceAccount: env['FIREBASE_SERVICE_ACCOUNT_FILE'] ?? '',
      databasePath: env['DATABASE_PATH'] ?? 'data/marketplace.sqlite',
      publicUrl: env['PUBLIC_URL'] ?? 'http://localhost:8080',
      appUrl: env['APP_URL'] ?? 'http://localhost:7357',
      merchantAppUrl:
          env['MERCHANT_APP_URL'] ?? env['APP_URL'] ?? 'http://localhost:7358',
      allowedOrigins:
          (env['ALLOWED_ORIGINS'] ??
                  'http://localhost:7357,http://127.0.0.1:7357,http://localhost:7358,http://127.0.0.1:7358,http://localhost:7359,http://127.0.0.1:7359')
              .split(',')
              .map((s) => s.trim())
              .toList(),
      production: prod,
      demoShowcase: env['DEMO_SHOWCASE'] == 'true',
      seedDemo:
          env['SEED_DEMO'] == 'true' || !prod && env['SEED_DEMO'] != 'false',
      paymentMode: env['PAYMENT_MODE'] ?? 'sandbox',
      connectEnabled: env['STRIPE_CONNECT_ENABLED'] == 'true',
      automaticSettlements: env['AUTOMATIC_SETTLEMENTS'] == 'true',
      commissionBps: int.tryParse(env['PLATFORM_COMMISSION_BPS'] ?? '0') ?? -1,
      settlementDelayHours:
          int.tryParse(env['SETTLEMENT_DELAY_HOURS'] ?? '24') ?? -1,
      stripeClubPriceId: env['STRIPE_CLUB_PRICE_ID'] ?? '',
      stripeSecret: env['STRIPE_SECRET_KEY'] ?? '',
      stripePublishableKey: env['STRIPE_PUBLISHABLE_KEY'] ?? '',
      applePayMerchantId: env['APPLE_PAY_MERCHANT_ID'] ?? '',
      merchantCountry: env['MERCHANT_COUNTRY'] ?? 'SK',
      stripeWebhookSecret: env['STRIPE_WEBHOOK_SECRET'] ?? '',
      adminToken: env['ADMIN_TOKEN'] ?? '',
      googleClientId: env['GOOGLE_CLIENT_ID'] ?? '',
      googleClientSecret: env['GOOGLE_CLIENT_SECRET'] ?? '',
      appleClientId: env['APPLE_CLIENT_ID'] ?? '',
      appleClientSecret: env['APPLE_CLIENT_SECRET'] ?? '',
      facebookAppId: env['FACEBOOK_APP_ID'] ?? '',
      facebookAppSecret: env['FACEBOOK_APP_SECRET'] ?? '',
      mailApiKey: env['RESEND_API_KEY'] ?? '',
      mailFrom: env['MAIL_FROM'] ?? '',
      billingFontPath:
          env['BILLING_FONT_PATH'] ??
          'apps/mobile/assets/fonts/InterVariable.ttf',
      billingSellerModel: env['BILLING_SELLER_MODEL'] ?? '',
      firebaseAuthProjectId: env['FIREBASE_AUTH_PROJECT_ID'] ?? '',
      firebaseAuthApiKey: env['FIREBASE_AUTH_API_KEY'] ?? '',
      firebaseGoogleEnabled: env['FIREBASE_AUTH_GOOGLE_ENABLED'] == 'true',
      firebaseAppleEnabled: env['FIREBASE_AUTH_APPLE_ENABLED'] == 'true',
      platformAdminEmails: (env['PLATFORM_ADMIN_EMAILS'] ?? '')
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList(),
    );
    config.validateShowcase();
    if ((config.firebaseAuthProjectId.isEmpty !=
            config.firebaseAuthApiKey.isEmpty) ||
        ((config.firebaseGoogleEnabled || config.firebaseAppleEnabled) &&
            !config.firebaseAuthEnabled) ||
        (config.firebaseAuthProjectId.isNotEmpty &&
            !RegExp(
              r'^[a-z][a-z0-9-]{4,28}[a-z0-9]$',
            ).hasMatch(config.firebaseAuthProjectId))) {
      throw ArgumentError(
        'Firebase Auth requires a valid project ID and API key before enabling providers.',
      );
    }
    if (config.billingSellerModel.isNotEmpty &&
        !{
          'merchantSeller',
          'platformSeller',
        }.contains(config.billingSellerModel)) {
      throw ArgumentError(
        'BILLING_SELLER_MODEL must be merchantSeller or platformSeller.',
      );
    }
    if (config.commissionBps < 0 ||
        config.commissionBps > 5000 ||
        config.settlementDelayHours < 0 ||
        config.settlementDelayHours > 720) {
      throw ArgumentError('Neplatná provízia alebo čas vyúčtovania.');
    }
    if (!{'sandbox', 'stripe', 'disabled'}.contains(config.paymentMode)) {
      throw ArgumentError('PAYMENT_MODE must be sandbox, disabled or stripe.');
    }
    if (config.paymentMode == 'disabled' &&
        (config.connectEnabled || config.automaticSettlements)) {
      throw ArgumentError('Disabled payments cannot enable settlements.');
    }
    if (config.paymentMode == 'stripe' &&
        (config.stripeSecret.isEmpty || config.stripeWebhookSecret.isEmpty)) {
      throw ArgumentError('Stripe requires secret and webhook keys.');
    }
    if (!RegExp(r'^[A-Z]{2}$').hasMatch(config.merchantCountry)) {
      throw ArgumentError(
        'MERCHANT_COUNTRY must be an uppercase ISO country code.',
      );
    }
    if (config.nativePaymentsEnabled &&
        (!config.stripePublishableKey.startsWith(
          config.stripeLiveMode ? 'pk_live_' : 'pk_test_',
        ))) {
      throw ArgumentError(
        'Stripe secret and publishable keys must use the same test/live environment.',
      );
    }
    if (prod &&
        config.connectEnabled &&
        !config.merchantAppUrl.startsWith('https://')) {
      throw ArgumentError('Stripe Connect requires an HTTPS MERCHANT_APP_URL.');
    }
    if (prod &&
        (config.paymentMode == 'sandbox' ||
            config.seedDemo ||
            config.paymentMode == 'stripe' && !config.stripeLiveMode ||
            !config.publicUrl.startsWith('https://') ||
            !config.appUrl.startsWith('https://'))) {
      throw ArgumentError(
        'Production requires HTTPS, SEED_DEMO=false and live Stripe or payments disabled.',
      );
    }
    return config;
  }
}

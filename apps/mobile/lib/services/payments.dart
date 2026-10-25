import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_stripe/flutter_stripe.dart' as stripe;
import 'package:design_system/design_system.dart';
import 'package:marketplace_domain/marketplace_domain.dart';
import 'package:url_launcher/url_launcher.dart';
import '../state/app_store.dart';

enum PaymentResult { completed, pending, cancelled, redirected }

class PaymentSheetDetails {
  const PaymentSheetDetails({
    required this.clientSecret,
    required this.publishableKey,
    required this.country,
    required this.liveMode,
    this.appleMerchantId = '',
  });
  final String clientSecret, publishableKey, country, appleMerchantId;
  final bool liveMode;
  factory PaymentSheetDetails.fromJson(Map<String, dynamic> json) {
    final secret = json['clientSecret'], key = json['publishableKey'];
    if (secret is! String ||
        !secret.contains('_secret_') ||
        key is! String ||
        !key.startsWith('pk_')) {
      throw StateError('Platobné okno sa nepodarilo pripraviť. Skús znova.');
    }
    return PaymentSheetDetails(
      clientSecret: secret,
      publishableKey: key,
      country: json['merchantCountry'] as String,
      liveMode: json['livemode'] == true,
      appleMerchantId: json['applePayMerchantId'] as String? ?? '',
    );
  }
}

abstract interface class NativePaymentPresenter {
  bool get supported;
  Future<PaymentResult> present(
    PaymentSheetDetails details,
    InvoiceDetails invoice,
    Brightness brightness,
  );
}

class StripePaymentPresenter implements NativePaymentPresenter {
  @override
  bool get supported =>
      !kIsWeb &&
      {
        TargetPlatform.iOS,
        TargetPlatform.android,
      }.contains(defaultTargetPlatform);
  static stripe.SetupPaymentSheetParameters parameters(
    PaymentSheetDetails details,
    InvoiceDetails invoice,
    Brightness brightness,
  ) {
    final dark = brightness == Brightness.dark;
    final colors = dark ? AppColors.dark : AppColors.light;
    return stripe.SetupPaymentSheetParameters(
      paymentIntentClientSecret: details.clientSecret,
      merchantDisplayName: 'Save Food',
      returnURL: 'com.dakoty.savefood://stripe-redirect',
      style: dark ? ThemeMode.dark : ThemeMode.light,
      allowsDelayedPaymentMethods: false,
      applePay: details.appleMerchantId.isEmpty
          ? null
          : stripe.PaymentSheetApplePay(merchantCountryCode: details.country),
      googlePay: stripe.PaymentSheetGooglePay(
        merchantCountryCode: details.country,
        currencyCode: 'EUR',
        testEnv: !details.liveMode,
      ),
      billingDetails: stripe.BillingDetails(
        name: invoice.name,
        email: invoice.email,
        address: stripe.Address(
          city: invoice.city,
          country: details.country,
          line1: invoice.street,
          line2: null,
          postalCode: invoice.postcode,
          state: null,
        ),
      ),
      appearance: stripe.PaymentSheetAppearance(
        colors: stripe.PaymentSheetAppearanceColors(
          primary: AppColors.light.blue,
          background: colors.canvas,
          componentBackground: colors.surface,
          componentBorder: colors.line,
          componentText: colors.ink,
          primaryText: colors.ink,
          secondaryText: colors.muted,
        ),
      ),
    );
  }

  @override
  Future<PaymentResult> present(
    PaymentSheetDetails details,
    InvoiceDetails invoice,
    Brightness brightness,
  ) async {
    if (!supported) {
      throw StateError('Túto platbu dokonči v mobilnej aplikácii.');
    }
    stripe.Stripe.publishableKey = details.publishableKey;
    stripe.Stripe.merchantIdentifier = details.appleMerchantId.isEmpty
        ? null
        : details.appleMerchantId;
    stripe.Stripe.urlScheme = 'com.dakoty.savefood';
    await stripe.Stripe.instance.applySettings();
    try {
      await stripe.Stripe.instance.initPaymentSheet(
        paymentSheetParameters: parameters(details, invoice, brightness),
      );
      await stripe.Stripe.instance.presentPaymentSheet();
      return PaymentResult.pending;
    } on stripe.StripeException catch (error) {
      if (error.error.code == stripe.FailureCode.Canceled) {
        return PaymentResult.cancelled;
      }
      throw StateError(
        error.error.localizedMessage ??
            'Platba sa nepodarila. Môžeš skúsiť inú kartu alebo peňaženku.',
      );
    }
  }
}

class PaymentCoordinator {
  PaymentCoordinator({
    NativePaymentPresenter? native,
    Future<bool> Function(Uri)? openBrowser,
  }) : native = native ?? StripePaymentPresenter(),
       openBrowser = openBrowser ?? _open;
  final NativePaymentPresenter native;
  final Future<bool> Function(Uri) openBrowser;
  static Future<bool> _open(Uri uri) =>
      launchUrl(uri, mode: LaunchMode.externalApplication);
  PaymentFlow preferredFlow(AppStore store) =>
      native.supported &&
          !store.isDemo &&
          store.paymentConfiguration['nativePaymentSheet'] == true
      ? PaymentFlow.native
      : PaymentFlow.hosted;
  Future<PaymentResult> pay(
    AppStore store,
    RescueOrder order,
    Brightness brightness,
  ) async {
    if (order.status != OrderStatus.awaitingPayment) {
      return order.status == OrderStatus.reserved
          ? PaymentResult.completed
          : PaymentResult.pending;
    }
    if (order.paymentFlow == PaymentFlow.native) {
      if (!native.supported) {
        throw StateError(
          'Túto rozpracovanú platbu dokonči v mobilnej aplikácii.',
        );
      }
      final response = await store.api!.request(
        'POST',
        '/v1/orders/${Uri.encodeComponent(order.id)}/payment-sheet',
        body: {},
      );
      PaymentResult result;
      try {
        result = await native.present(
          PaymentSheetDetails.fromJson(response),
          order.invoice,
          brightness,
        );
      } catch (_) {
        // An interrupted SDK response may still correspond to a settled payment.
        await store.refreshOrder(order.id);
        if (store.orders.firstWhere((o) => o.id == order.id).status ==
            OrderStatus.reserved) {
          return PaymentResult.completed;
        }
        rethrow;
      }
      // Cancellation and SDK success both require an authoritative status check.
      await store.refreshOrder(order.id);
      final updated = store.orders.firstWhere((o) => o.id == order.id);
      return updated.status == OrderStatus.reserved
          ? PaymentResult.completed
          : result == PaymentResult.cancelled
          ? PaymentResult.cancelled
          : PaymentResult.pending;
    }
    final uri = Uri.tryParse(order.paymentUrl ?? '');
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        !await openBrowser(uri)) {
      throw StateError(
        'Platobnú stránku sa nepodarilo otvoriť. Skús to znova z rezervácie.',
      );
    }
    return PaymentResult.redirected;
  }
}

final appPayments = PaymentCoordinator();

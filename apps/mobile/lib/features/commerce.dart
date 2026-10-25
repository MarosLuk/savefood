import 'package:flutter/material.dart';
import 'package:design_system/design_system.dart';
import 'package:marketplace_domain/marketplace_domain.dart';
import '../state/app_store.dart';
import '../widgets/common.dart';
import 'orders.dart';
import 'account.dart';
import 'legal.dart';
import '../services/payments.dart';
import '../widgets/payment_options.dart';

class CartScreen extends StatelessWidget {
  const CartScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    return ScreenScaffold(
      title: 'Tvoj košík',
      bottom: store.cart.isEmpty
          ? null
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Expanded(child: AppText('Spolu za balíčky')),
                    AppText(
                      euro(store.subtotal),
                      style: context.text.titleLarge,
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                PrimaryButton(
                  'Pokračovať k rezervácii',
                  icon: AppIcons.arrowRight,
                  onPressed: () => pushPage(context, const CheckoutScreen()),
                ),
                const SizedBox(height: 8),
                AppText(
                  'Servisný poplatok 2 % uvidíš v ďalšom kroku.',
                  style: context.text.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
      child: store.cart.isEmpty
          ? Center(
              child: EmptyState(
                icon: AppIcons.bag,
                title: 'Miesto na niečo dobré',
                description:
                    'Tvoj ďalší zachránený balíček už čaká. Vyber si niečo, čo ti spraví radosť.',
                action: 'Objaviť balíčky',
                onAction: () => Navigator.pop(context),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(24),
              children: [
                AppText('Dobrá voľba.', style: context.text.headlineLarge),
                const SizedBox(height: 8),
                AppText(
                  'Tieto dobroty dostanú druhú šancu.',
                  style: context.text.bodyLarge?.copyWith(
                    color: context.colors.muted,
                  ),
                ),
                const SizedBox(height: 24),
                for (final entry in store.cart.entries)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: CartLine(
                      offer: store.offer(entry.key)!,
                      quantity: entry.value,
                    ),
                  ),
                const SizedBox(height: 12),
                SurfaceCard(
                  color: context.colors.tint,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(AppIcons.leaf, color: context.colors.blue),
                      const SizedBox(width: 12),
                      Expanded(
                        child: AppText(
                          'Každý balíček si vyzdvihneš v jeho prevádzke. Pozri si čas pri každej ponuke a vezmi si vlastnú tašku.',
                          style: context.text.bodyMedium?.copyWith(
                            color: context.colors.blue,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const AppText('Ešte si niečo vyberiem'),
                ),
              ],
            ),
    );
  }
}

class CartLine extends StatelessWidget {
  const CartLine({super.key, required this.offer, required this.quantity});
  final FoodOffer offer;
  final int quantity;
  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    return SurfaceCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(17),
                child: FoodPhoto(offer.image, width: 84, height: 90),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppText(offer.store, style: context.text.titleMedium),
                    const SizedBox(height: 4),
                    AppText(offer.title, style: context.text.bodySmall),
                    const SizedBox(height: 9),
                    AppText(
                      '${pickupDay(offer.pickupStart, store.now)} · ${offer.timeLabel}',
                      style: context.text.bodySmall?.copyWith(
                        color: context.colors.blue,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: AppText(
                  euro(offer.price * quantity),
                  style: context.text.titleLarge,
                ),
              ),
              QuantityControl(
                value: quantity,
                max: store.remaining(offer),
                onChanged: (v) => store.setQuantity(offer.id, v),
              ),
            ],
          ),
          if (!store.available(offer))
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: AppText(
                'Čas vyzdvihnutia uplynul. Odstráň balíček z košíka.',
                style: TextStyle(color: context.colors.warning),
              ),
            ),
        ],
      ),
    );
  }
}

class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({super.key});
  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  bool accepted = false, paying = false;
  String? error;
  Future<void> reserve() async {
    final store = StoreScope.of(context);
    if (paying) return;
    setState(() {
      error = null;
      paying = true;
    });
    try {
      if (store.remoteEnabled && !store.demoShowcase) {
        final consent = await showLegalConsent(context);
        if (consent == null || !mounted) return;
        await store.api!.request('POST', '/v1/legal/accept', body: consent);
      }
      final order = await store.checkout(
        paymentFlow: appPayments.preferredFlow(store),
      );
      if (!mounted) return;
      String? paymentNotice;
      try {
        final result = await appPayments.pay(
          store,
          order,
          Theme.of(context).brightness,
        );
        if (result == PaymentResult.cancelled) {
          paymentNotice =
              'Platba nebola dokončená. Rezerváciu môžeš ešte zaplatiť.';
        }
      } catch (e) {
        paymentNotice = e is StateError
            ? e.message.toString()
            : 'Platbu môžeš dokončiť z rezervácie.';
      }
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) =>
                OrderDetailScreen(orderId: order.id, justCreated: true),
          ),
        );
        if (paymentNotice != null) notice(context, paymentNotice);
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is StateError
              ? e.message.toString()
              : 'Rezerváciu sa nepodarilo dokončiť.',
        );
      }
    } finally {
      if (mounted) setState(() => paying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final q = store.quote;
    final valid =
        !paying &&
        store.paymentsEnabled &&
        (store.isDemo || q.total == 0 || q.total >= 50) &&
        store.invoice.isValid &&
        accepted &&
        store.cart.isNotEmpty &&
        (!store.remoteEnabled || store.signedIn);
    return ScreenScaffold(
      title: 'Už len jeden dobrý krok',
      bottom: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: AppText(
                error!,
                style: TextStyle(color: context.colors.warning),
              ),
            ),
          PrimaryButton(
            '${store.isDemo
                ? 'Demo rezervácia'
                : q.total == 0
                ? 'Potvrdiť rezerváciu'
                : store.stripeTestMode
                ? 'Testovacia platba'
                : 'Zaplatiť'} · ${euro(q.total)}',
            busy: store.checkingOut || paying,
            onPressed: valid ? reserve : null,
          ),
          const SizedBox(height: 8),
          AppText(
            !store.paymentsEnabled
                ? 'Rezervácie spustíme po aktivácii platieb.'
                : store.isDemo
                ? 'Bez skutočnej platby. Žiadna karta sa nezaúčtuje.'
                : 'Platbu bezpečne spracuje Stripe. Údaje karty neukladáme.',
            style: context.text.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          SurfaceCard(
            color: context.colors.tint,
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(AppIcons.shield, color: context.colors.blue, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: AppText(
                    store.isDemo
                        ? (store.remoteEnabled
                              ? 'Skúšaš serverový sandbox. Objednávka sa uloží na server, bez skutočnej platby.'
                              : 'Skúšaš demo. Rezervácia sa uloží iba do tohto zariadenia a neodošle sa do prevádzky.')
                        : 'Balíček sa rezervuje na 30 minút. Potvrdený bude po bezpečnej platbe.',
                    style: context.text.bodyMedium?.copyWith(
                      color: context.colors.blue,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          if (store.remoteEnabled && !store.signedIn) ...[
            PrimaryButton(
              'Prihlásiť sa a pokračovať',
              onPressed: () => pushPage(context, const AuthScreen()),
            ),
            const SizedBox(height: 24),
          ],
          const PaymentOptions(),
          const SizedBox(height: 28),
          AppText('Fakturačné údaje', style: context.text.titleLarge),
          const SizedBox(height: 12),
          SurfaceCard(
            padding: EdgeInsets.zero,
            child: SettingsRow(
              icon: AppIcons.receipt,
              title: store.invoice.isValid
                  ? store.invoice.name
                  : 'Doplniť fakturačné údaje',
              subtitle: store.invoice.isValid
                  ? '${store.invoice.email}\n${store.invoice.street}, ${store.invoice.city}'
                  : 'Meno, e-mail a adresa',
              onTap: () => pushPage(context, const InvoiceScreen()),
              trailing: Icon(
                AppIcons.edit,
                size: 20,
                color: context.colors.blue,
              ),
            ),
          ),
          const SizedBox(height: 28),
          AppText('Tvoje dobroty', style: context.text.titleLarge),
          const SizedBox(height: 12),
          for (final entry in store.cart.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: CartLine(
                offer: store.offer(entry.key)!,
                quantity: entry.value,
              ),
            ),
          const SizedBox(height: 16),
          AppText('Máš niečo navyše?', style: context.text.titleLarge),
          const SizedBox(height: 12),
          SurfaceCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                SettingsRow(
                  icon: AppIcons.ticket,
                  title: store.coupon.isEmpty
                      ? 'Pridať zľavový kupón'
                      : 'Kupón ${store.coupon}',
                  subtitle: store.coupon.isEmpty
                      ? 'Demo kód VITAJ10 ti dá 10 % zľavu'
                      : 'Zľava ${euro(q.discount)}',
                  onTap: () => showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    useSafeArea: true,
                    builder: (_) => const CouponSheet(),
                  ),
                ),
                SwitchListTile.adaptive(
                  title: const AppText('Použiť môj kredit'),
                  subtitle: AppText('K dispozícii ${euro(store.credit)}'),
                  value: store.useCredit,
                  onChanged: store.credit > 0 ? store.setUseCredit : null,
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          AppText('Prehľadne a bez prekvapení', style: context.text.titleLarge),
          const SizedBox(height: 16),
          SurfaceCard(
            child: Column(
              children: [
                _TotalRow('Balíčky', euro(q.subtotal)),
                if (q.discount > 0)
                  _TotalRow('Zľava s kupónom', '−${euro(q.discount)}'),
                _TotalRow('Servisný poplatok · 2 %', euro(q.serviceFee)),
                if (q.creditUsed > 0)
                  _TotalRow('Použitý kredit', '−${euro(q.creditUsed)}'),
                const Divider(height: 24),
                _TotalRow('Spolu', euro(q.total), bold: true),
                if (q.cashback > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: AppText(
                      'Po vyzdvihnutí získaš ${euro(q.cashback)} v kredite.',
                      style: TextStyle(
                        color: context.colors.blue,
                        fontSize: 12,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: accepted,
            onChanged: (v) => setState(() => accepted = v ?? false),
            title: const AppText(
              'Rozumiem času vyzdvihnutia a tomu, že obsah balíčka je prekvapenie.',
            ),
            subtitle: AppText(
              store.isDemo
                  ? 'Toto je nezáväzná demo rezervácia.'
                  : 'Obsah a čas vyzdvihnutia určuje vybraná prevádzka.',
            ),
          ),
        ],
      ),
    );
  }
}

class _TotalRow extends StatelessWidget {
  const _TotalRow(this.label, this.value, {this.bold = false});
  final String label, value;
  final bool bold;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      children: [
        Expanded(
          child: AppText(
            label,
            style: bold ? context.text.titleMedium : context.text.bodyMedium,
          ),
        ),
        AppText(
          value,
          style: bold
              ? context.text.titleLarge?.copyWith(color: context.colors.blue)
              : context.text.bodyMedium,
        ),
      ],
    ),
  );
}

class CouponSheet extends StatefulWidget {
  const CouponSheet({super.key});
  @override
  State<CouponSheet> createState() => _CouponSheetState();
}

class _CouponSheetState extends State<CouponSheet> {
  final controller = TextEditingController();
  String? error;
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      24,
      0,
      24,
      24 + MediaQuery.viewInsetsOf(context).bottom,
    ),
    child: SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SheetHeading('Malá zľava navyše'),
          const SizedBox(height: 16),
          TextField(
            controller: controller,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(
              labelText: context.tr('Kód kupónu'),
              hintText: context.tr('VITAJ10'),
              errorText: error,
            ),
          ),
          const SizedBox(height: 20),
          PrimaryButton(
            'Uplatniť kupón',
            onPressed: () {
              final message = StoreScope.of(
                context,
              ).applyCoupon(controller.text);
              if (message != null) {
                setState(() => error = message);
              } else {
                Navigator.pop(context);
              }
            },
          ),
          if (StoreScope.of(context).coupon.isNotEmpty)
            TextButton(
              onPressed: () {
                StoreScope.of(context).applyCoupon('');
                Navigator.pop(context);
              },
              child: const AppText('Odstrániť kupón'),
            ),
        ],
      ),
    ),
  );
}

class InvoiceScreen extends StatefulWidget {
  const InvoiceScreen({super.key});
  @override
  State<InvoiceScreen> createState() => _InvoiceScreenState();
}

class _InvoiceScreenState extends State<InvoiceScreen> {
  final form = GlobalKey<FormState>();
  final fields = List.generate(9, (_) => TextEditingController());
  bool initialized = false, company = false;
  @override
  void dispose() {
    for (final c in fields) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    if (!initialized) {
      final i = store.invoice;
      final values = [
        i.name,
        i.email,
        i.street,
        i.city,
        i.postcode,
        i.company,
        i.companyId,
        i.taxId,
        i.vatId,
      ];
      for (var n = 0; n < fields.length; n++) {
        fields[n].text = values[n];
      }
      company = i.company.isNotEmpty;
      initialized = true;
    }
    Widget field(
      int index,
      String label, {
      TextInputType? keyboard,
      String? Function(String?)? validator,
      List<String>? autofill,
    }) => Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        controller: fields[index],
        keyboardType: keyboard,
        autofillHints: autofill,
        textInputAction: TextInputAction.next,
        decoration: InputDecoration(labelText: context.tr(label)),
        validator:
            validator ??
            (v) => v == null || v.trim().isEmpty ? 'Vyplň toto pole.' : null,
      ),
    );
    return ScreenScaffold(
      title: 'Fakturačné údaje',
      bottom: PrimaryButton(
        'Uložiť údaje',
        icon: AppIcons.check,
        onPressed: () {
          if (!form.currentState!.validate()) return;
          store.saveInvoice(
            InvoiceDetails(
              name: fields[0].text.trim(),
              email: fields[1].text.trim(),
              street: fields[2].text.trim(),
              city: fields[3].text.trim(),
              postcode: fields[4].text.trim(),
              company: company ? fields[5].text.trim() : '',
              companyId: company ? fields[6].text.trim() : '',
              taxId: company ? fields[7].text.trim() : '',
              vatId: company ? fields[8].text.trim() : '',
            ),
          );
          Navigator.pop(context);
        },
      ),
      child: AutofillGroup(
        child: Form(
          key: form,
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              AppText(
                'Komu vystavíme dobrý pocit?',
                style: context.text.headlineMedium,
              ),
              const SizedBox(height: 10),
              AppText(
                store.remoteEnabled
                    ? 'Údaje sa bezpečne uložia k tvojmu účtu.'
                    : 'Údaje zostanú uložené iba v tomto zariadení.',
                style: context.text.bodyMedium?.copyWith(
                  color: context.colors.muted,
                ),
              ),
              const SizedBox(height: 28),
              field(
                0,
                'Meno a priezvisko',
                autofill: [AutofillHints.name],
                validator: (v) =>
                    (v?.trim().length ?? 0) < 2 ? 'Zadaj celé meno.' : null,
              ),
              field(
                1,
                'E-mail',
                keyboard: TextInputType.emailAddress,
                autofill: [AutofillHints.email],
                validator: (v) =>
                    RegExp(
                      r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                    ).hasMatch(v?.trim() ?? '')
                    ? null
                    : 'Zadaj platný e-mail.',
              ),
              field(
                2,
                'Ulica a číslo',
                autofill: [AutofillHints.streetAddressLine1],
              ),
              field(3, 'Mesto', autofill: [AutofillHints.addressCity]),
              field(
                4,
                'PSČ',
                keyboard: TextInputType.number,
                autofill: [AutofillHints.postalCode],
                validator: (v) =>
                    RegExp(r'^\d{3}\s?\d{2}$').hasMatch(v?.trim() ?? '')
                    ? null
                    : 'PSČ má 5 číslic.',
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const AppText('Nakupujem na firmu'),
                value: company,
                onChanged: (v) => setState(() => company = v),
              ),
              if (company) ...[
                const SizedBox(height: 12),
                field(5, 'Názov firmy'),
                field(
                  6,
                  'IČO',
                  keyboard: TextInputType.number,
                  validator: (v) => RegExp(r'^\d{8}$').hasMatch(v?.trim() ?? '')
                      ? null
                      : 'IČO má 8 číslic.',
                ),
                field(7, 'DIČ (nepovinné)', validator: (v) => null),
                field(8, 'IČ DPH (nepovinné)', validator: (v) => null),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

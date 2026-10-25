import 'package:flutter/material.dart';
import 'billing.dart';
import 'package:design_system/design_system.dart';
import 'package:marketplace_domain/marketplace_domain.dart';
import '../state/app_store.dart';
import '../widgets/common.dart';
import 'offer_detail.dart';
import 'support/support.dart';
import '../widgets/payment_options.dart';

bool activeStatus(OrderStatus status) =>
    status == OrderStatus.reserved || status == OrderStatus.awaitingPayment;

String orderStatus(OrderStatus status) => switch (status) {
  OrderStatus.awaitingPayment => 'Čaká na platbu',
  OrderStatus.reserved => 'Pripravené na vyzdvihnutie',
  OrderStatus.collected => 'Úspešne zachránené',
  OrderStatus.cancelled => 'Zrušená rezervácia',
};

class OrdersScreen extends StatelessWidget {
  const OrdersScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    return ScreenScaffold(
      title: 'Tvoje záchrany',
      child: store.orders.isEmpty
          ? Center(
              child: EmptyState(
                icon: AppIcons.bag,
                title: 'Prvý dobrý krok je na tebe',
                description:
                    'Tu nájdeš svoje rezervácie aj dobroty, ktoré si už zachránil.',
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(24),
              children: [
                for (final active in [true, false]) ...[
                  if (store.orders.any((o) => activeStatus(o.status) == active))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: AppText(
                        active ? 'Čakajú na teba' : 'Tvoje predošlé záchrany',
                        style: context.text.titleLarge,
                      ),
                    ),
                  for (final order in store.orders.where(
                    (o) => activeStatus(o.status) == active,
                  ))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(24),
                        onTap: () => pushPage(
                          context,
                          OrderDetailScreen(orderId: order.id),
                        ),
                        child: SurfaceCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(16),
                                    child: FoodPhoto(
                                      order.items.first.image,
                                      width: 62,
                                      height: 62,
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        AppText(
                                          order.items.first.store,
                                          style: context.text.titleMedium,
                                        ),
                                        const SizedBox(height: 5),
                                        AppText(
                                          '${bagCount(order.count)} · ${euro(order.total)}',
                                          style: context.text.bodyMedium,
                                        ),
                                      ],
                                    ),
                                  ),
                                  Icon(AppIcons.chevronRight, size: 18),
                                ],
                              ),
                              const SizedBox(height: 16),
                              TagPill(
                                orderStatus(order.status),
                                icon: order.status == OrderStatus.collected
                                    ? AppIcons.checkCircle
                                    : AppIcons.clock,
                              ),
                              const SizedBox(height: 10),
                              AppText(
                                '${shortDate(order.createdAt)} · ${store.isDemo ? 'Demo rezervácia' : 'Rezervácia'}',
                                style: context.text.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ],
            ),
    );
  }
}

class OrderDetailScreen extends StatelessWidget {
  const OrderDetailScreen({
    super.key,
    required this.orderId,
    this.justCreated = false,
  });
  final String orderId;
  final bool justCreated;
  Future<void> finish(
    BuildContext context,
    bool collect, {
    String? offerId,
  }) async {
    final store = StoreScope.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: AppText(
          collect ? 'Máš balíček pri sebe?' : 'Zrušiť rezerváciu?',
        ),
        content: AppText(
          collect
              ? 'Prevzatie potvrď až pred obsluhou. Po vyzdvihnutí všetkých balíčkov sa pripíše klubový kredit.'
              : 'Balíčky sa vrátia do ponuky. Použitý kredit sa ti vráti. Pri platbe kartou sa odošle refundácia.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const AppText('Späť'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: AppText(
              collect ? 'Potvrdiť prevzatie' : 'Zrušiť rezerváciu',
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await store.finishOrder(orderId, collect: collect, offerId: offerId);
    } catch (e) {
      if (context.mounted) {
        notice(
          context,
          e is StateError
              ? e.message.toString()
              : 'Zmenu sa nepodarilo uložiť.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final matches = store.orders.where((o) => o.id == orderId);
    if (matches.isEmpty) {
      return ScreenScaffold(
        title: 'Rezervácia',
        child: const Center(child: AppText('Rezervácia sa nenašla.')),
      );
    }
    final order = matches.first;
    final active = order.status == OrderStatus.reserved;
    final pending = order.status == OrderStatus.awaitingPayment;
    return ScreenScaffold(
      title: 'Tvoja rezervácia',
      bottom: pending
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                PayOrderButton(order: order),
                TextButton(
                  onPressed: () async {
                    try {
                      await store.refreshOrder(order.id);
                    } catch (e) {
                      if (context.mounted) notice(context, e.toString());
                    }
                  },
                  child: const AppText('Overiť stav platby'),
                ),
              ],
            )
          : active
          ? PrimaryButton(
              order.items.length > 1
                  ? 'Vyzdvihnúť ďalší balíček'
                  : 'Mám vyzdvihnuté',
              icon: AppIcons.checkCircle,
              busy: store.checkingOut,
              onPressed: () => finish(
                context,
                true,
                offerId: order.items
                    .firstWhere((i) => !i.collected && !i.refunded)
                    .offerId,
              ),
            )
          : PrimaryButton(
              'Späť k dobrotám',
              onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
            ),
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 12),
          Center(
            child: Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                color: context.colors.tint,
                shape: BoxShape.circle,
              ),
              child: Icon(
                active
                    ? AppIcons.bag
                    : order.status == OrderStatus.collected
                    ? AppIcons.checkCircle
                    : AppIcons.close,
                size: 40,
                color: context.colors.blue,
              ),
            ),
          ),
          const SizedBox(height: 22),
          AppText(
            pending
                ? 'Dokonči svoju rezerváciu.'
                : active
                ? (justCreated
                      ? 'Dobrá vec sa podarila.'
                      : 'Dobroty na teba čakajú.')
                : order.status == OrderStatus.collected
                ? 'Ďakujeme za záchranu.'
                : 'Možno nabudúce.',
            textAlign: TextAlign.center,
            style: context.text.headlineMedium,
          ),
          const SizedBox(height: 10),
          AppText(
            orderStatus(order.status),
            textAlign: TextAlign.center,
            style: context.text.bodyLarge?.copyWith(
              color: context.colors.muted,
            ),
          ),
          const SizedBox(height: 24),
          SurfaceCard(
            color: context.colors.tint,
            child: Column(
              children: [
                AppText(
                  pending
                      ? 'REZERVÁCIA ČAKÁ NA PLATBU'
                      : store.isDemo
                      ? 'DEMO KÓD VYZDVIHNUTIA'
                      : 'KÓD VYZDVIHNUTIA',
                  style: TextStyle(
                    color: context.colors.blue,
                    fontSize: 11,
                    letterSpacing: 1.4,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 10),
                SelectableText(
                  pending
                      ? '…'
                      : order.pickupCode ??
                            order.id.split('-').last.padLeft(4, '0'),
                  style: TextStyle(
                    color: context.colors.blue,
                    fontSize: 30,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 8),
                AppText(
                  store.demoShowcase
                      ? 'Kód overí predajca v spoločnom demo sklade. Nejde o skutočný nákup.'
                      : store.isDemo
                      ? 'Táto rezervácia sa neodoslala do prevádzky.'
                      : pending
                      ? 'Po zaplatení tu nájdeš kód pre obsluhu.'
                      : 'Tento kód ukáž pri vyzdvihnutí obsluhe.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          for (final item in order.items)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: SurfaceCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: FoodPhoto(item.image, width: 72, height: 72),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              AppText(
                                item.store,
                                style: context.text.titleMedium,
                              ),
                              const SizedBox(height: 4),
                              AppText(
                                '${item.remainingQuantity} × ${item.title}',
                                style: context.text.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Icon(
                          AppIcons.clock,
                          size: 20,
                          color: context.colors.blue,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: AppText(
                            '${shortDate(item.pickupStart)} · ${_time(item.pickupStart)} – ${_time(item.pickupEnd)}',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    InkWell(
                      onTap: () => openDirections(context, item.address),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          children: [
                            Icon(
                              AppIcons.pin,
                              size: 20,
                              color: context.colors.blue,
                            ),
                            const SizedBox(width: 10),
                            Expanded(child: AppText(item.address)),
                            Icon(AppIcons.external, size: 18),
                          ],
                        ),
                      ),
                    ),
                    if (item.refundCount > 0) ...[
                      const SizedBox(height: 14),
                      TagPill(
                        item.refunded
                            ? 'Refundované'
                            : 'Vrátené ${item.refundCount} z ${item.quantity} ks',
                      ),
                    ],
                    if (active && order.items.length > 1 && !item.refunded) ...[
                      const SizedBox(height: 16),
                      item.collected
                          ? TagPill('Vyzdvihnuté', icon: AppIcons.checkCircle)
                          : PrimaryButton(
                              'Prevziať tento balíček',
                              secondary: true,
                              onPressed: store.checkingOut
                                  ? null
                                  : () => finish(
                                      context,
                                      true,
                                      offerId: item.offerId,
                                    ),
                            ),
                    ],
                  ],
                ),
              ),
            ),
          SurfaceCard(
            child: Column(
              children: [
                _row(
                  context,
                  'Balíčky',
                  euro(order.items.fold(0, (sum, i) => sum + i.total)),
                ),
                if (order.discount > 0)
                  _row(context, 'Zľava', '−${euro(order.discount)}'),
                _row(context, 'Servisný poplatok', euro(order.serviceFee)),
                if (order.creditUsed > 0)
                  _row(context, 'Použitý kredit', '−${euro(order.creditUsed)}'),
                const Divider(height: 24),
                _row(
                  context,
                  store.isDemo ? 'Celkom v deme' : 'Celkom',
                  euro(order.total),
                ),
                if (order.refundedAmount > 0)
                  _row(
                    context,
                    'Vrátená suma vrátane kreditu',
                    euro(order.refundedAmount),
                  ),
                if (order.cashback > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: AppText(
                      order.status == OrderStatus.collected
                          ? '${euro(order.cashback)} sa pripísalo do kreditu.'
                          : 'Po prevzatí získaš ${euro(order.cashback)} kreditu.',
                      style: TextStyle(color: context.colors.blue),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          AppText('Fakturačné údaje', style: context.text.titleMedium),
          if (store.remoteEnabled)
            TextButton.icon(
              onPressed: () =>
                  pushPage(context, BillingScreen(orderId: order.id)),
              icon: Icon(AppIcons.receipt),
              label: const Text('Faktúry a opravné doklady'),
            ),
          const SizedBox(height: 8),
          AppText(
            '${order.invoice.name}\n${order.invoice.email}\n${order.invoice.street}, ${order.invoice.postcode} ${order.invoice.city}',
            style: context.text.bodyMedium?.copyWith(
              color: context.colors.muted,
            ),
          ),
          if ((active || pending) && order.refundedAmount == 0)
            Padding(
              padding: const EdgeInsets.only(top: 20),
              child: TextButton(
                onPressed: store.checkingOut
                    ? null
                    : () => finish(context, false),
                child: AppText(
                  store.isDemo ? 'Zrušiť demo rezerváciu' : 'Zrušiť rezerváciu',
                ),
              ),
            ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () =>
                pushPage(context, SupportScreen(orderId: order.id)),
            icon: Icon(AppIcons.help, size: 20),
            label: const Text('Potrebujem pomoc s objednávkou'),
          ),
          const SizedBox(height: 16),
          SelectableText(
            order.id,
            style: context.text.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  String _time(DateTime date) =>
      '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  Widget _row(BuildContext context, String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      children: [
        Expanded(child: AppText(label)),
        AppText(value, style: context.text.titleMedium),
      ],
    ),
  );
}

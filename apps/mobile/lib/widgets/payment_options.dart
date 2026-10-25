import 'package:flutter/material.dart';
import 'package:design_system/design_system.dart';
import 'package:marketplace_domain/marketplace_domain.dart';
import '../services/payments.dart';
import '../state/app_store.dart';
import 'common.dart';

class PaymentOptions extends StatelessWidget {
  const PaymentOptions({super.key});
  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(AppIcons.card, color: context.colors.blue),
              const SizedBox(width: 12),
              Expanded(
                child: AppText(
                  'Bezpečná platba',
                  style: context.text.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: const [
              TagPill('VISA'),
              TagPill('Mastercard'),
              TagPill('Apple Pay'),
              TagPill('Google Pay'),
            ],
          ),
          const SizedBox(height: 12),
          AppText(
            store.quote.total == 0
                ? 'Celá suma sa uhradí kreditom. Kartu nepotrebuješ.'
                : 'Kartu alebo dostupnú peňaženku si vyberieš v platobnom okne. Apple Pay a Google Pay sa zobrazia podľa zariadenia a nastavenia peňaženky.',
            style: context.text.bodySmall,
          ),
          if (store.stripeTestMode) ...[
            const SizedBox(height: 8),
            AppText(
              'Testovací režim Stripe. Skutočné peniaze sa neúčtujú.',
              style: context.text.bodySmall?.copyWith(
                color: context.colors.warning,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class PayOrderButton extends StatefulWidget {
  const PayOrderButton({super.key, required this.order});
  final RescueOrder order;
  @override
  State<PayOrderButton> createState() => _PayOrderButtonState();
}

class _PayOrderButtonState extends State<PayOrderButton> {
  bool busy = false;
  Future<void> pay() async {
    setState(() => busy = true);
    try {
      final result = await appPayments.pay(
        StoreScope.of(context),
        widget.order,
        Theme.of(context).brightness,
      );
      if (mounted && result == PaymentResult.cancelled) {
        notice(
          context,
          'Platba nebola dokončená. Rezerváciu môžeš ešte zaplatiť.',
        );
      }
    } catch (error) {
      if (mounted) {
        notice(
          context,
          error is StateError ? error.message.toString() : error.toString(),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PrimaryButton(
    'Pokračovať k platbe',
    busy: busy,
    onPressed: busy ? null : pay,
  );
}

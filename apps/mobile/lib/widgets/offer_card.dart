import 'package:flutter/material.dart';
import 'package:design_system/design_system.dart';
import 'package:marketplace_domain/marketplace_domain.dart';
import '../state/app_store.dart';
import '../features/offer_detail.dart';
import '../features/account.dart';
import 'common.dart';

class OfferCard extends StatelessWidget {
  const OfferCard(this.offer, {super.key, this.compact = false});
  final FoodOffer offer;
  final bool compact;
  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final c = context.colors;
    final saved = store.favorites.contains(offer.id);
    final stock = store.remaining(offer);
    final available = store.available(offer);
    final distance = store.location.distanceTo(offer.point);
    final photoHeight = compact ? 120.0 : 190.0;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(25),
        border: Border.all(color: c.line.withValues(alpha: .75)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(
              alpha: Theme.of(context).brightness == Brightness.dark
                  ? .10
                  : .025,
            ),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              children: [
                Semantics(
                  button: true,
                  label: '${offer.store}, ${offer.title}, ${euro(offer.price)}',
                  child: InkWell(
                    onTap: () =>
                        pushPage(context, OfferDetailScreen(offerId: offer.id)),
                    child: FoodPhoto(
                      offer.image,
                      height: photoHeight,
                      width: double.infinity,
                    ),
                  ),
                ),
                Positioned(
                  left: 12,
                  top: 12,
                  child: IgnorePointer(
                    child: TagPill(
                      !available
                          ? 'Dnes zachránené'
                          : stock <= 2
                          ? 'Posledné $stock kusy'
                          : bagCount(stock),
                      color: !available
                          ? c.muted
                          : stock <= 2
                          ? const Color(0xFF9A4F00)
                          : const Color(0xFF17385F),
                      background: stock <= 2 && available
                          ? const Color(0xFFFFECD2)
                          : const Color(0xFFF5F8FF),
                    ),
                  ),
                ),
                Positioned(
                  right: 8,
                  top: 8,
                  child: RoundButton(
                    icon: saved ? AppIcons.heartActive : AppIcons.heart,
                    label: saved
                        ? 'Odobrať z obľúbených'
                        : 'Uložiť medzi obľúbené',
                    color: saved ? c.blue : const Color(0xFF17243B),
                    background: Colors.white.withValues(alpha: .96),
                    onPressed: () => store.toggleFavorite(offer.id),
                  ),
                ),
                if (offer.type == OfferType.club)
                  Positioned(
                    left: 12,
                    bottom: 12,
                    child: TagPill(
                      'Klub',
                      icon: AppIcons.crown,
                      background: c.surface,
                    ),
                  ),
              ],
            ),
            InkWell(
              onTap: () =>
                  pushPage(context, OfferDetailScreen(offerId: offer.id)),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 15, 16, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: AppText(
                            offer.store,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.text.titleMedium,
                          ),
                        ),
                        const SizedBox(width: 5),
                        if (offer.reviews > 0) ...[
                          Icon(AppIcons.star, size: 14, color: c.warning),
                          const SizedBox(width: 4),
                          AppText(
                            '${offer.rating}',
                            style: context.text.bodySmall?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: c.ink,
                            ),
                          ),
                        ] else
                          TagPill('Novinka'),
                      ],
                    ),
                    if (!compact) ...[
                      const SizedBox(height: 4),
                      AppText(
                        offer.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.text.bodyMedium?.copyWith(
                          color: c.muted,
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    AppIcons.clock,
                                    size: 14,
                                    color: c.muted,
                                  ),
                                  const SizedBox(width: 5),
                                  Flexible(
                                    child: AppText(
                                      '${pickupDay(offer.pickupStart, store.now)} ${offer.timeLabel}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: context.text.bodySmall?.copyWith(
                                        fontSize: 11,
                                        color: c.muted,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              if (!compact) ...[
                                const SizedBox(height: 5),
                                Row(
                                  children: [
                                    Icon(
                                      AppIcons.pin,
                                      size: 14,
                                      color: c.muted,
                                    ),
                                    const SizedBox(width: 5),
                                    Flexible(
                                      child: AppText(
                                        '${distance.toStringAsFixed(1)} km od teba',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: context.text.bodySmall?.copyWith(
                                          fontSize: 11,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                        PriceText(
                          price: offer.price,
                          original: offer.originalPrice,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            if (!compact)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 12, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: AppText(
                        'Ušetríš ${offer.discountPercent} %',
                        style: context.text.bodySmall?.copyWith(
                          color: c.blue,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: context.tr('Pridať do košíka'),
                      style: IconButton.styleFrom(
                        backgroundColor: c.tint,
                        foregroundColor: c.blue,
                      ),
                      onPressed: !available
                          ? null
                          : () {
                              final error = store.addToCart(offer);
                              if (error != null &&
                                  offer.type == OfferType.club &&
                                  !store.isMember) {
                                pushPage(context, const ClubScreen());
                              } else {
                                notice(
                                  context,
                                  error ?? 'Balíček je v košíku.',
                                );
                              }
                            },
                      icon: Icon(AppIcons.plus, size: 20),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

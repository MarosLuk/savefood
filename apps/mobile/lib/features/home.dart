import 'package:flutter/material.dart';
import 'package:design_system/design_system.dart';
import 'package:marketplace_domain/marketplace_domain.dart';
import '../state/app_store.dart';
import '../widgets/common.dart';
import '../widgets/offer_card.dart';
import 'account.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.onExplore});
  final VoidCallback onExplore;
  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final c = context.colors;
    final nearby = store.nearby;
    final english = store.language == 'en';
    void browse({FoodCategory? category, OfferFeature? feature}) {
      store.setFilters(
        OfferFilters(
          categories: category == null ? {} : {category},
          features: feature == null ? {} : {feature},
        ),
      );
      onExplore();
    }

    return RefreshIndicator(
      onRefresh: () async => store.refreshCatalog(),
      child: CustomScrollView(
        key: const PageStorageKey('home'),
        slivers: [
          SliverToBoxAdapter(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1100),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 8, 24, 22),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: AppText(
                                  english
                                      ? 'Good food.\nA second chance.'
                                      : 'Dobré jedlo.\nDruhá šanca.',
                                  style: context.text.displaySmall,
                                ),
                              ),
                              Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  color: c.tint,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  AppIcons.leaf,
                                  color: c.blue,
                                  size: 24,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: _HeroBanner(
                        onTap: () => browse(),
                        english: english,
                      ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      height:
                          100 +
                          (MediaQuery.textScalerOf(context).scale(1) - 1) * 24,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        itemCount: FoodCategory.values.length,
                        separatorBuilder: (_, i) => const SizedBox(width: 17),
                        itemBuilder: (context, i) {
                          final category = FoodCategory.values[i];
                          return SizedBox(
                            width: 66,
                            child: Semantics(
                              button: true,
                              label: category.label,
                              child: InkWell(
                                onTap: () => browse(category: category),
                                borderRadius: BorderRadius.circular(20),
                                child: Column(
                                  children: [
                                    Container(
                                      width: 66,
                                      height: 66,
                                      padding: const EdgeInsets.all(3),
                                      decoration: BoxDecoration(
                                        color: c.surface,
                                        borderRadius: BorderRadius.circular(34),
                                        border: Border.all(color: c.line),
                                      ),
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(31),
                                        child: FoodPhoto(category.image),
                                      ),
                                    ),
                                    const SizedBox(height: 9),
                                    AppText(
                                      category == FoodCategory.produce
                                          ? 'Čerstvé'
                                          : category.label,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: context.text.bodySmall?.copyWith(
                                        color: c.ink,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                    SectionHeading(
                      english ? 'Too good to miss' : 'Dobroty za rohom',
                      action: english ? 'See all' : 'Všetky',
                      onAction: () => browse(),
                    ),
                    if (nearby.isEmpty)
                      EmptyState(
                        icon: AppIcons.pin,
                        title: 'Tu ešte len začíname',
                        description: store.isDemo
                            ? 'V tomto okolí zatiaľ nemáme demo ponuky. Skús Bratislavu, Košice alebo Trnavu.'
                            : 'V tomto okolí zatiaľ nie sú dostupné balíčky. Skús väčší okruh alebo sa pozri neskôr.',
                        action: 'Preskúmať ponuky',
                        onAction: onExplore,
                      )
                    else
                      _OfferRail(offers: nearby.take(6).toList()),
                    const SizedBox(height: 28),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: SurfaceCard(
                        color: c.tint,
                        padding: const EdgeInsets.all(20),
                        child: Row(
                          children: [
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: c.surface,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                AppIcons.leaf,
                                color: c.blue,
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  AppText(
                                    english
                                        ? 'Every bag makes a difference.'
                                        : 'Každý balíček sa počíta.',
                                    style: context.text.titleMedium?.copyWith(
                                      fontSize: 15,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  AppText(
                                    english
                                        ? 'Good for your wallet. Better for the planet.'
                                        : 'Pre tvoju peňaženku. Aj pre našu planétu.',
                                    style: context.text.bodySmall?.copyWith(
                                      color: c.blue,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),
                    SectionHeading(
                      english
                          ? 'Your neighborhood favorites'
                          : 'Obľúbené v susedstve',
                      subtitle: english
                          ? 'Places worth coming back to'
                          : 'Miesta, ku ktorým sa rád vrátiš',
                      action: english ? 'Explore' : 'Objaviť',
                      onAction: () =>
                          browse(feature: OfferFeature.localFavorite),
                    ),
                    _OfferRail(
                      offers: nearby
                          .where(
                            (o) =>
                                o.features.contains(OfferFeature.localFavorite),
                          )
                          .toList(),
                    ),
                    const SizedBox(height: 28),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: InkWell(
                        onTap: () => pushPage(context, const ClubScreen()),
                        borderRadius: BorderRadius.circular(26),
                        child: Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF153D88), Color(0xFF287AF4)],
                            ),
                            borderRadius: BorderRadius.circular(26),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(
                                          AppIcons.crown,
                                          color: const Color(0xFFBBD5FF),
                                          size: 20,
                                        ),
                                        const SizedBox(width: 8),
                                        const AppText(
                                          'NEVYHADZUJ KLUB',
                                          style: TextStyle(
                                            color: Color(0xFFCBDEFF),
                                            fontSize: 10,
                                            fontWeight: FontWeight.w600,
                                            letterSpacing: 1.5,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    AppText(
                                      english
                                          ? 'Good things\ncome back to you.'
                                          : 'Dobré sa ti\nvráti späť.',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 25,
                                        fontWeight: FontWeight.w700,
                                        height: 1.18,
                                        letterSpacing: -.6,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    const AppText(
                                      '10 % späť v demo kredite',
                                      style: TextStyle(
                                        color: Color(0xFFDCE9FF),
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: .15),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  AppIcons.arrowRight,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),
                    SectionHeading(
                      english ? 'A sweet ending' : 'Sladká bodka dňa',
                      action: english ? 'See all' : 'Všetky',
                      onAction: () => browse(category: FoodCategory.desserts),
                    ),
                    _OfferRail(
                      offers: nearby
                          .where((o) => o.category == FoodCategory.desserts)
                          .toList(),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 28, 24, 125),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(AppIcons.sparkle, size: 16, color: c.muted),
                          const SizedBox(width: 8),
                          Flexible(
                            child: AppText(
                              english
                                  ? 'A taste of what we’re building · Demo catalog'
                                  : 'Malé rozhodnutia. Lepší svet. · Demo katalóg',
                              style: context.text.bodySmall,
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OfferRail extends StatelessWidget {
  const _OfferRail({required this.offers});
  final List<FoodOffer> offers;
  @override
  Widget build(BuildContext context) {
    if (offers.isEmpty) return const SizedBox.shrink();
    final scale = MediaQuery.textScalerOf(context).scale(1);
    return SizedBox(
      height: 240 + (scale - 1) * 170,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        itemCount: offers.length,
        separatorBuilder: (_, i) => const SizedBox(width: 14),
        itemBuilder: (_, i) => SizedBox(
          width: 276,
          child: Align(
            alignment: Alignment.topCenter,
            child: OfferCard(offers[i], compact: true),
          ),
        ),
      ),
    );
  }
}

class FavoritesScreen extends StatelessWidget {
  const FavoritesScreen({super.key, required this.onExplore});
  final VoidCallback onExplore;
  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    return CustomScrollView(
      key: const PageStorageKey('favorites'),
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppText(
                  store.language == 'en' ? 'Your favorites' : 'Tvoje srdcovky',
                  style: context.text.headlineLarge,
                ),
                const SizedBox(height: 8),
                AppText(
                  'Dobré miesta sa oplatí mať poruke.',
                  style: context.text.bodyLarge?.copyWith(
                    color: context.colors.muted,
                  ),
                ),
                const SizedBox(height: 24),
                SurfaceCard(
                  color: context.colors.tint,
                  child: Row(
                    children: [
                      Icon(AppIcons.bell, color: context.colors.blue),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: AppText('Upozorniť, keď budú opäť dobroty'),
                      ),
                      Switch.adaptive(
                        applyCupertinoTheme: true,
                        value: store.favoriteAlerts,
                        onChanged: (v) => store.preferences(favorites: v),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        if (store.saved.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 430),
                child: EmptyState(
                  icon: AppIcons.heart,
                  title: 'Láska na prvé sústo',
                  description:
                      'Ťukni na srdiečko pri balíčku a nájdeš ho vždy tu. Tvoje ďalšie obľúbené miesto už čaká.',
                  action: 'Objaviť dobroty',
                  onAction: onExplore,
                ),
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 130),
            sliver: SliverList.separated(
              itemCount: store.saved.length,
              separatorBuilder: (_, i) => const SizedBox(height: 20),
              itemBuilder: (_, i) => Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 600),
                  child: OfferCard(store.saved[i]),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _HeroBanner extends StatelessWidget {
  const _HeroBanner({required this.onTap, required this.english});
  final VoidCallback onTap;
  final bool english;
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'Preskúmať balíčky',
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(28),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Stack(
          children: [
            const Positioned.fill(child: FoodPhoto('bakery')),
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0x55152235), Color(0xC8152235)],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Align(
                    alignment: Alignment.topRight,
                    child: TagPill(
                      'až −70 %',
                      color: Colors.white,
                      background: Color(0xFF1765E8),
                    ),
                  ),
                  const SizedBox(height: 14),
                  AppText(
                    english
                        ? 'Freshly baked.\nToo good to waste.'
                        : 'Dnes upečené.\nZajtra milované.',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 27,
                      height: 1.14,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -.7,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: AppText(
                          english ? 'Discover your bag' : 'Objav svoj balíček',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Icon(AppIcons.arrowRight, color: Colors.white, size: 20),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

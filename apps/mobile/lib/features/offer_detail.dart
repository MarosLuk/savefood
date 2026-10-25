import 'package:flutter/material.dart';
import 'package:design_system/design_system.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:marketplace_domain/marketplace_domain.dart';
import '../state/app_store.dart';
import 'package:marketplace_data/marketplace_data.dart' show offerGallery;
import '../widgets/common.dart';
import 'commerce.dart';
import 'account.dart';
import 'reviews.dart';

class OfferDetailScreen extends StatefulWidget {
  const OfferDetailScreen({super.key, required this.offerId});
  final String offerId;
  @override
  State<OfferDetailScreen> createState() => _OfferDetailScreenState();
}

class _OfferDetailScreenState extends State<OfferDetailScreen> {
  int quantity = 1, photo = 0;
  bool expanded = false;
  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final offer = store.offer(widget.offerId);
    if (offer == null) {
      return ScreenScaffold(
        title: 'Balíček',
        child: EmptyState(
          icon: AppIcons.bag,
          title: 'Ponuka sa nenašla',
          description: 'Vráť sa do katalógu a vyber si inú dobrotu.',
        ),
      );
    }
    final c = context.colors;
    final available = store.available(offer);
    final saved = store.favorites.contains(offer.id);
    final photos = offerGallery(offer.image);
    final inCart = store.cart[offer.id] ?? 0;
    final max = (store.remaining(offer) - inCart).clamp(0, 99);
    if (quantity > max && max > 0) quantity = max;
    return Scaffold(
      extendBodyBehindAppBar: true,
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 900),
                child: Stack(
                  children: [
                    SizedBox(
                      height: 360,
                      child: PageView.builder(
                        itemCount: photos.length,
                        onPageChanged: (i) => setState(() => photo = i),
                        itemBuilder: (_, i) => GestureDetector(
                          onTap: () => pushPage(
                            context,
                            PhotoGallery(images: photos, initial: i),
                          ),
                          child: FoodPhoto(
                            photos[i],
                            width: double.infinity,
                            label:
                                'Ilustračná fotografia balíčka ${offer.title}',
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: SafeArea(
                        bottom: false,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                          child: Row(
                            children: [
                              RoundButton(
                                icon: AppIcons.back,
                                label: 'Späť',
                                background: Colors.white,
                                color: const Color(0xFF17243B),
                                onPressed: () => Navigator.pop(context),
                              ),
                              const Spacer(),
                              RoundButton(
                                icon: saved
                                    ? AppIcons.heartActive
                                    : AppIcons.heart,
                                label: saved
                                    ? 'Odobrať z obľúbených'
                                    : 'Uložiť medzi obľúbené',
                                background: Colors.white,
                                color: saved
                                    ? const Color(0xFF1765E8)
                                    : const Color(0xFF17243B),
                                onPressed: () => store.toggleFavorite(offer.id),
                              ),
                              const SizedBox(width: 8),
                              RoundButton(
                                icon: AppIcons.bag,
                                label: 'Košík',
                                badge: store.cartCount,
                                background: Colors.white,
                                color: const Color(0xFF17243B),
                                onPressed: () =>
                                    pushPage(context, const CartScreen()),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 24,
                      bottom: 34,
                      child: TagPill(
                        'Ušetríš ${offer.discountPercent} %',
                        background: Colors.white,
                        color: const Color(0xFF1765E8),
                      ),
                    ),
                    Positioned(
                      right: 24,
                      bottom: 34,
                      child: TagPill(
                        '${photo + 1} / ${photos.length}',
                        background: Colors.white.withValues(alpha: .95),
                        color: const Color(0xFF17243B),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: Container(
                  transform: Matrix4.translationValues(0, -20, 0),
                  padding: const EdgeInsets.fromLTRB(24, 26, 24, 16),
                  decoration: BoxDecoration(
                    color: c.canvas,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(30),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 46,
                            height: 46,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: c.tint,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: AppText(
                              offer.store.substring(0, 1),
                              style: TextStyle(
                                color: c.blue,
                                fontSize: 24,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                AppText(
                                  offer.store,
                                  style: context.text.titleMedium,
                                ),
                                const SizedBox(height: 3),
                                AppText(
                                  offer.category.label,
                                  style: context.text.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: context.tr('Zdieľať ponuku'),
                            onPressed: () async {
                              final box =
                                  context.findRenderObject() as RenderBox?;
                              try {
                                await Share.share(
                                  '${offer.store} · ${offer.title}\n${euro(offer.price)} namiesto ${euro(offer.originalPrice)}\n${offer.address}\nPonuka v aplikácii Save Food.',
                                  sharePositionOrigin: box == null
                                      ? null
                                      : box.localToGlobal(Offset.zero) &
                                            box.size,
                                );
                              } catch (_) {
                                if (context.mounted) {
                                  notice(
                                    context,
                                    'Zdieľanie nie je v tomto prostredí dostupné.',
                                  );
                                }
                              }
                            },
                            icon: Icon(AppIcons.share, size: 20),
                          ),
                        ],
                      ),
                      const SizedBox(height: 22),
                      AppText(offer.title, style: context.text.headlineLarge),
                      const SizedBox(height: 16),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                TagPill(
                                  available
                                      ? '${store.remaining(offer)} balíčky na záchranu'
                                      : 'Dnes už zachránené',
                                  icon: AppIcons.bag,
                                ),
                                if (offer.features.isNotEmpty)
                                  TagPill(
                                    offer.features.first.label,
                                    icon: AppIcons.sparkle,
                                    background: c.warm,
                                    color: c.warning,
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          PriceText(
                            price: offer.price,
                            original: offer.originalPrice,
                            large: true,
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      SurfaceCard(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Icon(AppIcons.clock, color: c.blue, size: 22),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      AppText(
                                        'Vyzdvihnutie ${pickupDay(offer.pickupStart, store.now).toLowerCase()}',
                                        style: context.text.bodySmall,
                                      ),
                                      const SizedBox(height: 3),
                                      AppText(
                                        offer.timeLabel,
                                        style: context.text.titleMedium,
                                      ),
                                    ],
                                  ),
                                ),
                                TagPill(
                                  offer.dineIn ? 'Aj na mieste' : 'So sebou',
                                ),
                              ],
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              child: Divider(height: 1, color: c.line),
                            ),
                            InkWell(
                              onTap: () =>
                                  openDirections(context, offer.address),
                              child: Row(
                                children: [
                                  Icon(AppIcons.pin, color: c.blue, size: 22),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        AppText(
                                          offer.address,
                                          style: context.text.bodyMedium
                                              ?.copyWith(
                                                fontWeight: FontWeight.w500,
                                              ),
                                        ),
                                        const SizedBox(height: 3),
                                        AppText(
                                          '${store.location.distanceTo(offer.point).toStringAsFixed(1)} km od teba · Navigovať',
                                          style: context.text.bodySmall,
                                        ),
                                      ],
                                    ),
                                  ),
                                  Icon(
                                    AppIcons.external,
                                    color: c.muted,
                                    size: 20,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 28),
                      AppText(
                        'Malé prekvapenie. Veľká chuť.',
                        style: context.text.titleLarge,
                      ),
                      const SizedBox(height: 12),
                      AppText(
                        offer.description,
                        maxLines: expanded ? null : 4,
                        overflow: expanded
                            ? TextOverflow.visible
                            : TextOverflow.ellipsis,
                        style: context.text.bodyLarge?.copyWith(color: c.muted),
                      ),
                      TextButton(
                        onPressed: () => setState(() => expanded = !expanded),
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          alignment: Alignment.centerLeft,
                        ),
                        child: AppText(
                          expanded ? 'Zobraziť menej' : 'Prečítať viac',
                        ),
                      ),
                      if (offer.diets.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 20),
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: offer.diets
                                .map(
                                  (d) => TagPill(d.label, icon: AppIcons.leaf),
                                )
                                .toList(),
                          ),
                        ),
                      SurfaceCard(
                        color: c.tint,
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(AppIcons.info, color: c.blue, size: 20),
                            const SizedBox(width: 12),
                            Expanded(
                              child: AppText(
                                'Balíček je prekvapenie. Fotografie sú ilustračné a konkrétny obsah sa mení podľa dennej ponuky.',
                                style: context.text.bodyMedium?.copyWith(
                                  color: c.blue,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      AppText(
                        'Alergény a dôležité informácie',
                        style: context.text.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      AppText(
                        offer.allergens,
                        style: context.text.bodyMedium?.copyWith(
                          color: c.muted,
                        ),
                      ),
                      const SizedBox(height: 28),
                      InkWell(
                        borderRadius: BorderRadius.circular(24),
                        onTap: () => showModalBottomSheet<void>(
                          context: context,
                          isScrollControlled: true,
                          useSafeArea: true,
                          builder: (_) => RatingsSheet(offer: offer),
                        ),
                        child: SurfaceCard(
                          child: Row(
                            children: [
                              Container(
                                width: 56,
                                height: 56,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: c.tint,
                                  borderRadius: BorderRadius.circular(18),
                                ),
                                child: AppText(
                                  offer.reviews > 0 ? '${offer.rating}' : '—',
                                  style: context.text.titleLarge?.copyWith(
                                    color: c.blue,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    AppText(
                                      offer.reviews > 0
                                          ? 'Chutí vám u nás'
                                          : 'Nové miesto na dobrú záchranu',
                                      style: context.text.titleMedium,
                                    ),
                                    const SizedBox(height: 4),
                                    AppText(
                                      offer.reviews == 0
                                          ? 'Zatiaľ bez hodnotení'
                                          : store.isDemo
                                          ? '${offer.reviews} ukážkových hodnotení'
                                          : '${offer.reviews} overených hodnotení',
                                      style: context.text.bodySmall,
                                    ),
                                  ],
                                ),
                              ),
                              Icon(AppIcons.chevronRight, size: 20),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 28),
                      AppText(
                        'Takto môže vyzerať záchrana',
                        style: context.text.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      AppText(
                        'Ilustračná galéria, nie obsah konkrétneho balíčka.',
                        style: context.text.bodySmall,
                      ),
                      const SizedBox(height: 14),
                      SizedBox(
                        height: 108,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: photos.length,
                          separatorBuilder: (_, i) => const SizedBox(width: 10),
                          itemBuilder: (_, i) => InkWell(
                            onTap: () => pushPage(
                              context,
                              PhotoGallery(images: photos, initial: i),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(18),
                              child: FoodPhoto(
                                photos[i],
                                width: 108,
                                height: 108,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      AppText(
                        'Demo prevádzka · Dostupnosť aj hodnotenia sú ukážkové.',
                        style: context.text.bodySmall,
                      ),
                      const SizedBox(height: 12),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: c.surface,
          border: Border(top: BorderSide(color: c.line)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 14, 24, 16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: !available
                  ? PrimaryButton(
                      saved ? 'Uložené medzi obľúbenými' : 'Uložiť na neskôr',
                      secondary: true,
                      icon: AppIcons.heart,
                      onPressed: () => store.toggleFavorite(offer.id),
                    )
                  : Row(
                      children: [
                        if (max > 0) ...[
                          QuantityControl(
                            value: quantity,
                            min: 1,
                            max: max,
                            onChanged: (v) => setState(() => quantity = v),
                          ),
                          const SizedBox(width: 12),
                        ],
                        Expanded(
                          child: PrimaryButton(
                            offer.type == OfferType.club && !store.isMember
                                ? 'Objaviť Klub'
                                : max == 0
                                ? 'Prejsť do košíka'
                                : 'Zachrániť · ${euro(offer.price * quantity)}',
                            onPressed: () {
                              if (offer.type == OfferType.club &&
                                  !store.isMember) {
                                pushPage(context, const ClubScreen());
                                return;
                              }
                              if (max == 0) {
                                pushPage(context, const CartScreen());
                                return;
                              }
                              final error = store.addToCart(offer, quantity);
                              if (error != null) {
                                notice(context, error);
                                return;
                              }
                              ScaffoldMessenger.of(context)
                                ..hideCurrentSnackBar()
                                ..showSnackBar(
                                  SnackBar(
                                    content: const AppText(
                                      'Dobrá voľba! Balíček je v košíku.',
                                    ),
                                    action: SnackBarAction(
                                      label: 'Košík',
                                      onPressed: () =>
                                          pushPage(context, const CartScreen()),
                                    ),
                                  ),
                                );
                            },
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> openDirections(BuildContext context, String address) async {
  final uri = Uri.https('www.google.com', '/maps/dir/', {
    'api': '1',
    'destination': address,
    'travelmode': 'walking',
  });
  try {
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
        context.mounted) {
      notice(context, 'Navigáciu sa nepodarilo otvoriť.');
    }
  } catch (_) {
    if (context.mounted) notice(context, 'Navigácia nie je dostupná.');
  }
}

class PhotoGallery extends StatefulWidget {
  const PhotoGallery({super.key, required this.images, this.initial = 0});
  final List<String> images;
  final int initial;
  @override
  State<PhotoGallery> createState() => _PhotoGalleryState();
}

class _PhotoGalleryState extends State<PhotoGallery> {
  late final PageController controller = PageController(
    initialPage: widget.initial,
  );
  late int selected = widget.initial;
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(
      backgroundColor: Colors.black,
      foregroundColor: Colors.white,
      title: AppText('${selected + 1} / ${widget.images.length}'),
      leading: IconButton(
        tooltip: context.tr('Zavrieť galériu'),
        onPressed: () => Navigator.pop(context),
        icon: Icon(AppIcons.close),
      ),
    ),
    body: PageView.builder(
      controller: controller,
      itemCount: widget.images.length,
      onPageChanged: (i) => setState(() => selected = i),
      itemBuilder: (_, i) => InteractiveViewer(
        child: Center(
          child: FoodPhoto(
            widget.images[i],
            fit: BoxFit.contain,
            label: 'Ilustračná fotografia ${i + 1}',
          ),
        ),
      ),
    ),
    bottomNavigationBar: const SafeArea(
      child: Padding(
        padding: EdgeInsets.all(20),
        child: AppText(
          'Ilustračné fotografie',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white70),
        ),
      ),
    ),
  );
}

class RatingsSheet extends StatelessWidget {
  const RatingsSheet({super.key, required this.offer});
  final FoodOffer offer;
  @override
  Widget build(BuildContext context) => StoreScope.of(context).remoteEnabled
      ? ReviewsSheet(offer: offer)
      : SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 30),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SheetHeading('Dobré skúsenosti'),
                const SizedBox(height: 20),
                Row(
                  children: [
                    AppText(
                      '${offer.rating}',
                      style: context.text.displaySmall?.copyWith(
                        fontSize: 52,
                        color: context.colors.blue,
                      ),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: List.generate(
                              5,
                              (_) => Icon(
                                AppIcons.star,
                                size: 20,
                                color: context.colors.warning,
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          AppText(
                            '${offer.reviews} ukážkových hodnotení',
                            style: context.text.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                for (final entry in {
                  'Pomer ceny a hodnoty': 4.8,
                  'Kvalita jedla': 4.9,
                  'Veľkosť balíčka': 4.7,
                  'Vyzdvihnutie': 5.0,
                }.entries)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 18),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(child: AppText(entry.key)),
                            AppText(
                              '${entry.value}',
                              style: context.text.titleMedium,
                            ),
                          ],
                        ),
                        const SizedBox(height: 7),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(5),
                          child: LinearProgressIndicator(
                            value: entry.value / 5,
                            minHeight: 5,
                            color: context.colors.blue,
                            backgroundColor: context.colors.tint,
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 12),
                const AppText(
                  'Hodnotenia sú súčasťou demo katalógu. Reálne recenzie sa zobrazia po napojení prevádzok.',
                ),
              ],
            ),
          ),
        );
}

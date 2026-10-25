import 'package:flutter/material.dart';
import 'package:design_system/design_system.dart';
import 'package:marketplace_domain/marketplace_domain.dart';
import '../state/app_store.dart';
import '../widgets/common.dart';
import '../widgets/offer_card.dart';
import '../widgets/offer_map.dart';
import 'offer_detail.dart';

class CatalogScreen extends StatefulWidget {
  const CatalogScreen({super.key});
  @override
  State<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends State<CatalogScreen> {
  final search = TextEditingController();
  bool map = false;
  String? selected;
  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final results = store.results;
    if (search.text != store.filters.query) {
      search.value = TextEditingValue(
        text: store.filters.query,
        selection: TextSelection.collapsed(offset: store.filters.query.length),
      );
    }
    final english = store.language == 'en';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1100),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 6, 24, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppText(
                    english ? 'Find your next favorite.' : 'Na čo máš chuť?',
                    style: context.text.headlineLarge,
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: search,
                          onChanged: (v) => store.setFilters(
                            store.filters.copyWith(query: v),
                          ),
                          decoration: InputDecoration(
                            hintText: english
                                ? 'Food, place or something sweet…'
                                : 'Jedlo, podnik alebo niečo sladké…',
                            prefixIcon: Icon(AppIcons.search, size: 20),
                            suffixIcon: search.text.isEmpty
                                ? null
                                : IconButton(
                                    tooltip: context.tr('Vymazať vyhľadávanie'),
                                    onPressed: () => store.setFilters(
                                      store.filters.copyWith(query: ''),
                                    ),
                                    icon: Icon(AppIcons.close, size: 18),
                                  ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      RoundButton(
                        icon: AppIcons.filter,
                        label: 'Filtre',
                        badge: store.filters.activeCount,
                        onPressed: () => showModalBottomSheet<void>(
                          context: context,
                          isScrollControlled: true,
                          useSafeArea: true,
                          builder: (_) => const FiltersSheet(),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    height: 44,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        _QuickChip(
                          'Všetko',
                          selected: store.filters.categories.isEmpty,
                          onTap: () => store.setFilters(
                            store.filters.copyWith(categories: {}),
                          ),
                        ),
                        for (final category in FoodCategory.values)
                          _QuickChip(
                            category.label,
                            selected: store.filters.categories.contains(
                              category,
                            ),
                            onTap: () => store.setFilters(
                              store.filters.copyWith(
                                categories:
                                    store.filters.categories.contains(category)
                                    ? {}
                                    : {category},
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: AppText(
                          english
                              ? '${results.length} offers nearby'
                              : '${offerCount(results.length)} v okolí',
                          style: context.text.bodyMedium?.copyWith(
                            color: context.colors.muted,
                          ),
                        ),
                      ),
                      if (store.filters.activeCount > 0 ||
                          store.filters.query.isNotEmpty)
                        TextButton(
                          onPressed: () => store.setFilters(
                            OfferFilters(radiusKm: store.filters.radiusKm),
                          ),
                          child: const AppText('Vymazať'),
                        ),
                      TextButton.icon(
                        onPressed: () => setState(() => map = !map),
                        icon: Icon(
                          map ? AppIcons.list : AppIcons.map,
                          size: 18,
                        ),
                        label: AppText(map ? 'Zoznam' : 'Mapa'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          child: map
              ? Stack(
                  children: [
                    OfferMap(
                      center: store.location,
                      offers: results,
                      selected: selected,
                      onSelect: (o) => setState(() => selected = o.id),
                    ),
                    if (selected != null &&
                        results.any((o) => o.id == selected))
                      Positioned(
                        left: 24,
                        right: 24,
                        bottom: 110,
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 500),
                            child: SurfaceCard(
                              padding: const EdgeInsets.all(12),
                              child: InkWell(
                                onTap: () => pushPage(
                                  context,
                                  OfferDetailScreen(offerId: selected!),
                                ),
                                child: Row(
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(16),
                                      child: FoodPhoto(
                                        store.offer(selected!)!.image,
                                        width: 78,
                                        height: 78,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          AppText(
                                            store.offer(selected!)!.store,
                                            style: context.text.titleMedium,
                                          ),
                                          const SizedBox(height: 3),
                                          AppText(
                                            store.offer(selected!)!.timeLabel,
                                            style: context.text.bodySmall,
                                          ),
                                          const SizedBox(height: 5),
                                          AppText(
                                            euro(store.offer(selected!)!.price),
                                            style: TextStyle(
                                              color: context.colors.blue,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Icon(AppIcons.chevronRight, size: 20),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                )
              : results.isEmpty
              ? SingleChildScrollView(
                  child: EmptyState(
                    icon: AppIcons.search,
                    title: 'Dnes nič také nevidíme',
                    description:
                        'Skús inú kombináciu filtrov alebo väčší okruh. Niečo dobré sa určite nájde.',
                    action: 'Zrušiť filtre',
                    onAction: () => store.setFilters(
                      OfferFilters(radiusKm: store.filters.radiusKm),
                    ),
                  ),
                )
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final columns = constraints.maxWidth > 950
                        ? 3
                        : constraints.maxWidth > 650
                        ? 2
                        : 1;
                    if (columns == 1) {
                      return ListView.separated(
                        key: const PageStorageKey('catalog'),
                        padding: const EdgeInsets.fromLTRB(24, 0, 24, 130),
                        itemCount: results.length,
                        separatorBuilder: (_, i) => const SizedBox(height: 20),
                        itemBuilder: (_, i) => OfferCard(results[i]),
                      );
                    }
                    // Wrap keeps card heights intrinsic under Dynamic Type.
                    return SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 130),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 1100),
                          child: LayoutBuilder(
                            builder: (context, inner) => Wrap(
                              spacing: 20,
                              runSpacing: 20,
                              children: results
                                  .map(
                                    (o) => SizedBox(
                                      width:
                                          (inner.maxWidth -
                                              20 * (columns - 1)) /
                                          columns,
                                      child: OfferCard(o),
                                    ),
                                  )
                                  .toList(),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _QuickChip extends StatelessWidget {
  const _QuickChip(this.label, {required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: FilterChip(
      label: AppText(label),
      selected: selected,
      onSelected: (_) => onTap(),
      showCheckmark: false,
      selectedColor: context.colors.blue,
      backgroundColor: context.colors.surface,
      labelStyle: TextStyle(
        color: selected
            ? (Theme.of(context).brightness == Brightness.dark
                  ? const Color(0xFF10233E)
                  : Colors.white)
            : context.colors.muted,
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
      shape: const StadiumBorder(),
      side: BorderSide(
        color: selected ? context.colors.blue : context.colors.line,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
    ),
  );
}

class FiltersSheet extends StatefulWidget {
  const FiltersSheet({super.key});
  @override
  State<FiltersSheet> createState() => _FiltersSheetState();
}

class _FiltersSheetState extends State<FiltersSheet> {
  OfferFilters? draft;
  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    draft ??= store.filters;
    final f = draft!;
    Widget group(String title, List<Widget> children) => Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppText(title, style: context.text.titleMedium),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: children),
        ],
      ),
    );
    Widget chip(String label, bool selected, VoidCallback onTap) => ChoiceChip(
      label: AppText(label),
      selected: selected,
      onSelected: (_) => setState(onTap),
      selectedColor: context.colors.tint,
      labelStyle: TextStyle(
        color: selected ? context.colors.blue : context.colors.ink,
        fontSize: 13,
      ),
      shape: const StadiumBorder(),
      side: BorderSide(
        color: selected ? context.colors.blue : context.colors.line,
      ),
    );
    final count = f
        .apply(
          store.offers,
          store.location,
          store.now,
          remaining: store.remaining,
        )
        .length;
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * .88,
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: SheetHeading(
                'Presne podľa teba',
                onReset: () => setState(
                  () => draft = OfferFilters(
                    query: f.query,
                    radiusKm: f.radiusKm,
                  ),
                ),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 14, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    group('Na čo máš chuť?', [
                      for (final c in FoodCategory.values)
                        chip(
                          c.label,
                          f.categories.contains(c),
                          () => draft = f.copyWith(
                            categories: _toggle(f.categories, c),
                          ),
                        ),
                    ]),
                    group('Typ ponuky', [
                      chip(
                        'Balíčky s prekvapením',
                        f.type == OfferType.surprise,
                        () => draft = f.copyWith(
                          type: OfferType.surprise,
                          clearType: f.type == OfferType.surprise,
                        ),
                      ),
                      chip(
                        'Klubové ponuky',
                        f.type == OfferType.club,
                        () => draft = f.copyWith(
                          type: OfferType.club,
                          clearType: f.type == OfferType.club,
                        ),
                      ),
                    ]),
                    group('Keď sa ti to hodí', [
                      for (final p in PickupFilter.values)
                        chip(
                          switch (p) {
                            PickupFilter.any => 'Kedykoľvek',
                            PickupFilter.now => 'Práve teraz',
                            PickupFilter.today => 'Dnes',
                            PickupFilter.tomorrow => 'Zajtra',
                            PickupFilter.custom => 'Vybrať deň',
                          },
                          f.pickup == p,
                          () => draft = f.copyWith(pickup: p),
                        ),
                    ]),
                    if (f.pickup == PickupFilter.custom)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 20),
                        child: TextButton.icon(
                          icon: Icon(AppIcons.clock, size: 18),
                          label: AppText(
                            f.customDate == null
                                ? 'Zvoľ dátum vyzdvihnutia'
                                : shortDate(f.customDate!),
                          ),
                          onPressed: () async {
                            final now = store.now;
                            final date = await showDatePicker(
                              context: context,
                              initialDate: f.customDate ?? now,
                              firstDate: DateTime(now.year, now.month, now.day),
                              lastDate: now.add(const Duration(days: 30)),
                            );
                            if (date != null && mounted) {
                              setState(
                                () => draft = f.copyWith(customDate: date),
                              );
                            }
                          },
                        ),
                      ),
                    group('Stravovacie preferencie', [
                      for (final d in Diet.values)
                        chip(
                          d.label,
                          f.diets.contains(d),
                          () => draft = f.copyWith(diets: _toggle(f.diets, d)),
                        ),
                    ]),
                    group('Niečo navyše', [
                      for (final feature in OfferFeature.values)
                        chip(
                          feature.label,
                          f.features.contains(feature),
                          () => draft = f.copyWith(
                            features: _toggle(f.features, feature),
                          ),
                        ),
                    ]),
                    group('Obľúbené prevádzky', [
                      for (final s in store.nearby.map((o) => o.store).toSet())
                        chip(
                          s,
                          f.stores.contains(s),
                          () =>
                              draft = f.copyWith(stores: _toggle(f.stores, s)),
                        ),
                    ]),
                    group('Zoradiť podľa', [
                      for (final sort in OfferSort.values)
                        chip(
                          switch (sort) {
                            OfferSort.distance => 'Vzdialenosti',
                            OfferSort.rating => 'Hodnotenia',
                            OfferSort.price => 'Ceny',
                          },
                          f.sort == sort,
                          () => draft = f.copyWith(sort: sort),
                        ),
                    ]),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const AppText('Dostupné balíčky ako prvé'),
                      value: f.availableFirst,
                      onChanged: (v) =>
                          setState(() => draft = f.copyWith(availableFirst: v)),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
              child: PrimaryButton(
                'Zobraziť ${offerCount(count, accusative: true)}',
                onPressed:
                    f.pickup == PickupFilter.custom && f.customDate == null
                    ? null
                    : () {
                        store.setFilters(draft!);
                        Navigator.pop(context);
                      },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Set<T> _toggle<T>(Set<T> source, T value) {
    final result = {...source};
    if (!result.remove(value)) result.add(value);
    return result;
  }
}

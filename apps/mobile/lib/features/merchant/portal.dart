import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:design_system/design_system.dart';
import 'package:marketplace_domain/marketplace_domain.dart';
import '../../state/app_store.dart';
import '../../widgets/common.dart';
import '../account.dart';
import '../demo.dart';
import '../support/activity.dart';
import 'package:marketplace_data/marketplace_data.dart' show demoImageNames;
import 'controller.dart';
import 'warehouse.dart';
import 'team.dart';
import '../billing.dart';
import 'editor.dart';
import 'finance.dart';
import '../support/support.dart';

class MerchantPortalScreen extends StatefulWidget {
  const MerchantPortalScreen({super.key, this.controller, this.onExit});
  final MerchantController? controller;
  final VoidCallback? onExit;
  @override
  State<MerchantPortalScreen> createState() => _MerchantPortalScreenState();
}

class _MerchantPortalScreenState extends State<MerchantPortalScreen> {
  MerchantController? controller;
  String? _accountEmail;
  int tab = 0;
  String query = '';
  static const labels = [
    'Prehľad',
    'Sklad',
    'Ponuky',
    'Pravidlá',
    'Výdaj',
    'Nastavenia',
  ];
  List<IconData> get icons => [
    AppIcons.dashboard,
    AppIcons.stock,
    AppIcons.bag,
    AppIcons.sparkle,
    AppIcons.receipt,
    AppIcons.settings,
  ];
  MerchantController get c => controller!;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final app = StoreScope.of(context);
    if (widget.controller != null && controller != null) return;
    if (widget.controller == null &&
        controller != null &&
        _accountEmail == app.email) {
      return;
    }
    if (widget.controller == null) controller?.dispose();
    _accountEmail = app.email;
    controller =
        widget.controller ??
        (app.api == null ? null : MerchantController(app.api!));
    if (controller != null && (widget.controller != null || app.signedIn)) {
      unawaited(controller!.load());
    }
  }

  @override
  void dispose() {
    if (widget.controller == null) controller?.dispose();
    super.dispose();
  }

  Future<void> _openDemo() async {
    final persona = await showDemoPicker(context);
    if (!mounted || persona == null || persona.merchant) return;
    if (persona.id == 'support') {
      await pushPage(context, const SupportScreen());
      if (!mounted) return;
    }
    if (Navigator.canPop(context)) {
      Navigator.pop(context);
    } else {
      widget.onExit?.call();
    }
  }

  MerchantField _imageField({String initial = ''}) => MerchantField(
    'image',
    type: MerchantFieldType.photo,
    mediaOrganizationId: c.organization?.id,
    StoreScope.of(context).demoShowcase
        ? 'Ilustračná fotografia'
        : 'HTTPS adresa fotografie',
    initial: initial.isEmpty && StoreScope.of(context).demoShowcase
        ? 'bakery'
        : initial,
    options:
        StoreScope.of(context).demoShowcase &&
            (initial.isEmpty || demoImageNames.contains(initial))
        ? {
            for (final name in demoImageNames)
              name: switch (name) {
                'bakery' => 'Maslové pečivo',
                'bread' => 'Kváskový chlieb',
                'meal' => 'Denné menu',
                'salad' => 'Čerstvý šalát',
                'vegetables' => 'Potraviny a zelenina',
                'dessert' => 'Sladký výber',
                'toast' => 'Raňajkový výber',
                'coffee' => 'Káva',
                'cafe' => 'Kaviareň',
                _ => 'Kvety',
              },
          }
        : null,
  );

  Future<void> action(Future<Object?> Function() run, {String? success}) async {
    try {
      await run();
      if (mounted && success != null) notice(context, success);
    } catch (e) {
      if (mounted) {
        notice(context, e is StateError ? e.message.toString() : e.toString());
      }
    }
  }

  Future<Map<String, dynamic>?> edit(
    String title,
    List<MerchantField> fields,
    Future<Map<String, dynamic>> Function(Map<String, dynamic>) submit, {
    String description = '',
    bool recipe = false,
  }) => merchantEditor(
    context,
    title: title,
    fields: fields,
    submit: submit,
    description: description,
    recipeProducts: recipe ? c.products : null,
    productLookup: recipe && StoreScope.of(context).remoteEnabled
        ? c.lookupProducts
        : null,
  );
  Widget button(
    String label,
    IconData icon,
    VoidCallback? onPressed, {
    bool primary = false,
  }) => primary
      ? FilledButton.icon(
          onPressed: c.busy ? null : onPressed,
          icon: Icon(icon, size: 20),
          label: Text(label),
        )
      : OutlinedButton.icon(
          onPressed: c.busy ? null : onPressed,
          icon: Icon(icon, size: 20),
          label: Text(label),
        );
  Widget heading(
    String title,
    String description, {
    List<Widget> actions = const [],
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppText(title, style: context.text.headlineLarge),
        const SizedBox(height: 8),
        AppText(
          description,
          style: context.text.bodyLarge?.copyWith(color: context.colors.muted),
        ),
        if (actions.isNotEmpty) ...[
          const SizedBox(height: 18),
          Wrap(spacing: 10, runSpacing: 10, children: actions),
        ],
      ],
    ),
  );
  Widget empty(
    String title,
    String text, {
    VoidCallback? onAction,
    String? label,
  }) => SurfaceCard(
    child: Column(
      children: [
        Icon(AppIcons.stock, size: 40, color: context.colors.blue),
        const SizedBox(height: 12),
        AppText(title, style: context.text.titleMedium),
        const SizedBox(height: 8),
        AppText(text, textAlign: TextAlign.center),
        if (onAction != null)
          TextButton(onPressed: onAction, child: Text(label ?? 'Pokračovať')),
      ],
    ),
  );
  @override
  Widget build(BuildContext context) {
    final app = StoreScope.of(context);
    if (widget.controller == null && (!app.remoteEnabled || !app.signedIn)) {
      return ScreenScaffold(
        title: 'Pre predajcov',
        onBack: widget.onExit,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            heading(
              'Dobré jedlo.\nDobrý biznis.',
              'Vlastná prevádzka, prehľadný sklad a balíčky, ktoré dostanú druhú šancu.',
            ),
            if (app.demoShowcase) ...[
              DemoAccessCard(onPressed: _openDemo),
              const SizedBox(height: 24),
            ],
            empty(
              app.remoteEnabled
                  ? 'Prihlás sa do svojho účtu'
                  : 'Pripoj aplikáciu k serveru',
              app.remoteEnabled
                  ? 'Rovnaký účet môže nakupovať aj spravovať prevádzky.'
                  : 'Účet prevádzky a sklad sa ukladajú na server. Lokálne demo ich nevytvára.',
              onAction: app.remoteEnabled
                  ? () async {
                      await pushPage(context, const AuthScreen());
                      if (mounted) {
                        await c.load();
                        setState(() {});
                      }
                    }
                  : null,
              label: 'Prihlásiť sa alebo vytvoriť účet',
            ),
          ],
        ),
      );
    }
    return AnimatedBuilder(
      animation: c,
      builder: (context, _) {
        final body = c.loading && c.workspace.stores.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : c.error != null && c.workspace.stores.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: empty(
                    'Prehľad sa nepodarilo načítať',
                    c.error!,
                    onAction: () => c.load(),
                    label: 'Skúsiť znova',
                  ),
                ),
              )
            : c.workspace.stores.isEmpty
            ? _welcome()
            : _shell();
        return Scaffold(
          appBar: AppBar(
            leading: IconButton(
              tooltip: 'Späť',
              icon: Icon(AppIcons.back),
              onPressed: () {
                if (Navigator.canPop(context)) {
                  Navigator.pop(context);
                } else {
                  widget.onExit?.call();
                }
              },
            ),
            title: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(AppIcons.store, color: context.colors.blue, size: 24),
                const SizedBox(width: 10),
                const Flexible(child: AppText('Predajca', maxLines: 1)),
              ],
            ),
            actions: [
              const SupportActivityButton(),
              if (app.demoShowcase)
                IconButton(
                  tooltip: 'Prepnúť demo profil',
                  onPressed: _openDemo,
                  icon: Icon(AppIcons.sparkle),
                ),
              IconButton(
                tooltip: 'Obnoviť údaje',
                onPressed: c.loading ? null : () => c.load(),
                icon: Icon(AppIcons.refresh),
              ),
              IconButton(
                tooltip: 'Nastavenia predajcu',
                onPressed: () => setState(() => tab = 5),
                icon: Icon(AppIcons.settings),
              ),
              PopupMenuButton<String>(
                tooltip: 'Vzhľad a účet',
                icon: Icon(AppIcons.user),
                onSelected: (value) async {
                  if (value == 'logout') {
                    await app.signOut();
                  } else {
                    app.setTheme(switch (value) {
                      'light' => ThemeMode.light,
                      'dark' => ThemeMode.dark,
                      _ => ThemeMode.system,
                    });
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'system',
                    child: Text('Podľa zariadenia'),
                  ),
                  PopupMenuItem(value: 'light', child: Text('Svetlý vzhľad')),
                  PopupMenuItem(value: 'dark', child: Text('Tmavý vzhľad')),
                  PopupMenuItem(value: 'logout', child: Text('Odhlásiť sa')),
                ],
              ),
            ],
          ),
          body: body,
        );
      },
    );
  }

  Widget _welcome() => SingleChildScrollView(
    padding: const EdgeInsets.all(24),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 24),
            TagPill('PRE PREDAJCOV', icon: AppIcons.store),
            const SizedBox(height: 24),
            heading(
              'Z prebytkov\nnová príležitosť.',
              'Založ si firmu a prvú prevádzku. Produkty, šarže, zľavy aj objednávky budeš mať na jednom mieste.',
            ),
            SurfaceCard(
              child: Column(
                children: [
                  _benefit(
                    AppIcons.store,
                    'Jedna firma, viac prevádzok',
                    'Potraviny, reštaurácia, pekáreň aj kaviareň.',
                  ),
                  _benefit(
                    AppIcons.stock,
                    'Sklad, ktorý vie o rezerváciách',
                    'SKU, šarže, kontrola kvality a termíny výdaja.',
                  ),
                  _benefit(
                    AppIcons.sparkle,
                    'Balíčky podľa tvojich pravidiel',
                    'Návrhy na schválenie alebo automatické zverejnenie.',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            PrimaryButton(
              'Založiť účet prevádzky',
              icon: AppIcons.plus,
              onPressed: _createOrganization,
            ),
          ],
        ),
      ),
    ),
  );
  Widget _benefit(IconData icon, String title, String description) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: context.colors.blue, size: 24),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppText(title, style: context.text.titleMedium),
              const SizedBox(height: 4),
              AppText(description, style: context.text.bodySmall),
            ],
          ),
        ),
      ],
    ),
  );
  Widget _shell() => LayoutBuilder(
    builder: (context, constraints) {
      final wide = constraints.maxWidth >= 1000;
      final content = Column(
        children: [
          if (StoreScope.of(context).demoShowcase)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
              child: Row(
                children: [
                  TagPill('DEMO', icon: AppIcons.sparkle),
                  const SizedBox(width: 10),
                  Expanded(
                    child: AppText(
                      'Fiktívny sklad · bez skutočných platieb',
                      style: context.text.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
            child: DropdownButtonFormField<String>(
              key: ValueKey(c.storeId),
              initialValue: c.storeId,
              icon: Icon(AppIcons.chevronDown, size: 20),
              isExpanded: true,
              decoration: InputDecoration(
                labelText: 'Aktívna prevádzka',
                prefixIcon: Icon(AppIcons.pin),
              ),
              items: c.workspace.stores
                  .map(
                    (s) => DropdownMenuItem(
                      value: s.id,
                      child: Text(
                        '${s.name} · ${s.kind.label}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (v) {
                c.selectStore(v!);
                setState(() => query = '');
              },
            ),
          ),
          if (c.store?.platformPaused == true)
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 12, 24, 0),
              child: AppText(
                'Predaj v tejto pobočke je dočasne pozastavený správcom. Už rezervované objednávky prever s podporou.',
              ),
            ),
          if (c.error != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: AppText(
                c.error!,
                style: TextStyle(color: context.colors.warning),
              ),
            ),
          if (c.loading) const LinearProgressIndicator(),
          Expanded(
            child: RefreshIndicator(
              onRefresh: c.load,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.all(wide ? 32 : 24),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1120),
                    child: switch (tab) {
                      0 => _overview(),
                      1 => _stock(),
                      2 => _offers(),
                      3 => _automation(),
                      4 => _orders(),
                      _ => _settings(),
                    },
                  ),
                ),
              ),
            ),
          ),
          if (!wide)
            NavigationBar(
              backgroundColor: context.colors.surface,
              indicatorColor: context.colors.tint,
              labelTextStyle: WidgetStatePropertyAll(
                context.text.labelSmall?.copyWith(fontSize: 11),
              ),
              selectedIndex: tab > 4 ? 0 : tab,
              onDestinationSelected: (v) => setState(() => tab = v),
              destinations: [
                for (var i = 0; i < 5; i++)
                  NavigationDestination(icon: Icon(icons[i]), label: labels[i]),
              ],
            ),
        ],
      );
      if (!wide) return content;
      return Row(
        children: [
          NavigationRail(
            backgroundColor: context.colors.surface,
            indicatorColor: context.colors.tint,
            selectedIconTheme: IconThemeData(color: context.colors.blue),
            selectedLabelTextStyle: context.text.labelSmall?.copyWith(
              color: context.colors.blue,
            ),
            selectedIndex: tab,
            labelType: NavigationRailLabelType.all,
            onDestinationSelected: (v) => setState(() => tab = v),
            destinations: [
              for (var i = 0; i < labels.length; i++)
                NavigationRailDestination(
                  icon: Icon(icons[i]),
                  label: Text(labels[i]),
                ),
            ],
          ),
          VerticalDivider(width: 1, color: context.colors.line),
          Expanded(child: content),
        ],
      );
    },
  );
  Widget _overview() {
    final now = StoreScope.of(context).now;
    final soon = c.lots
        .where(
          (l) =>
              l.available > 0 &&
              l.deadline.isBefore(now.add(const Duration(days: 2))),
        )
        .toList();
    final draft =
        c.workspace.stockSummary['drafts'] ??
        c.offers.where((o) => o.state == 'draft').length;
    final available =
        c.workspace.stockSummary['available'] ??
        c.lots
            .where((l) => l.sellableAt(now))
            .fold(0, (n, l) => n + l.available);
    final reserved =
        c.workspace.stockSummary['reserved'] ??
        c.lots.fold(0, (n, l) => n + l.reserved);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        heading(
          'Menej odpadu.\nViac dobrých príležitostí.',
          '${c.store!.name} · živý prehľad tvojej prevádzky',
          actions: [
            button('Prijať zásoby', AppIcons.plus, _receive, primary: true),
            if (c.canManage)
              button(
                'Vytvoriť balíček',
                AppIcons.bag,
                c.products.isEmpty ? _product : _offer,
              ),
          ],
        ),
        LayoutBuilder(
          builder: (context, size) {
            final width =
                (size.maxWidth - (size.maxWidth >= 760 ? 36 : 12)) /
                (size.maxWidth >= 760 ? 4 : 2);
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _metric(
                  'Voľné jednotky',
                  _stockTotals('available', '$available'),
                  AppIcons.stock,
                  width,
                ),
                _metric(
                  'Rezervované jednotky',
                  _stockTotals('reserved', '$reserved'),
                  AppIcons.bag,
                  width,
                ),
                _metric(
                  'Šarže s blízkym termínom',
                  '${c.workspace.stockSummary['soon'] ?? soon.length}',
                  AppIcons.clock,
                  width,
                ),
                _metric(
                  'Návrhy na schválenie',
                  '$draft',
                  AppIcons.sparkle,
                  width,
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 24),
        SurfaceCard(
          color: context.colors.tint,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(AppIcons.sparkle, color: context.colors.blue),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppText(
                      'Sklad pracuje s tebou.',
                      style: context.text.titleMedium,
                    ),
                    const SizedBox(height: 6),
                    const AppText(
                      'Pravidlá vyhľadajú skontrolované potraviny s blízkym termínom a pripravia balíček. Ty rozhoduješ o zľave aj zverejnení.',
                    ),
                    TextButton(
                      onPressed: () => setState(() => tab = 3),
                      child: const Text('Nastaviť automatické balíčky'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        AppText(
          'Tieto zásoby si zaslúžia pozornosť',
          style: context.text.titleLarge,
        ),
        const SizedBox(height: 14),
        if (soon.isEmpty)
          empty(
            'Všetko má svoj čas',
            'Zásoby s blízkym termínom sa objavia tu.',
          )
        else
          for (final l in soon.take(5)) _lotCard(l, compact: true),
        const SizedBox(height: 24),
        if (c.owner)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: OutlinedButton.icon(
              onPressed: () => pushPage(
                context,
                MerchantFinanceScreen(organizationId: c.organization!.id),
              ),
              icon: Icon(AppIcons.wallet, size: 20),
              label: const Text('Tržby a vyúčtovanie'),
            ),
          ),
        AppText('Od príjmu až po výdaj', style: context.text.titleLarge),
        const SizedBox(height: 12),
        _benefit(
          AppIcons.checkCircle,
          '1. Prijmi a skontroluj',
          'Zaznamenaj šaržu a bezpečný termín výdaja.',
        ),
        _benefit(
          AppIcons.bag,
          '2. Vytvor alebo schváľ balíček',
          'Dostupnosť sa prepočíta zo spoločného skladu.',
        ),
        _benefit(
          AppIcons.receipt,
          '3. Over kód pri výdaji',
          'Rezervované jednotky sa odpočítajú zo skladu.',
        ),
      ],
    );
  }

  Widget _metric(String label, String value, IconData icon, double width) =>
      SizedBox(
        width: width,
        child: SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: context.colors.blue),
              const SizedBox(height: 18),
              AppText(value, style: context.text.headlineLarge),
              const SizedBox(height: 6),
              ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight:
                      MediaQuery.textScalerOf(
                        context,
                      ).scale(context.text.bodySmall?.fontSize ?? 12) *
                      (context.text.bodySmall?.height ?? 1.5) *
                      2,
                ),
                child: AppText(label, style: context.text.bodySmall),
              ),
            ],
          ),
        ),
      );
  Widget _stock() {
    final q = normalizeSearch(query);
    final lots = c.lots.where((l) {
      final p = c.product(l.productId);
      return normalizeSearch('${p.name} ${p.sku} ${l.code}').contains(q);
    }).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        heading(
          'Sklad pod kontrolou.',
          'Fyzický stav, rezervované množstvo a voľné zásoby podľa šarží.',
          actions: [
            button(
              'Prijať zásoby',
              AppIcons.plus,
              c.products.isEmpty ? (c.canManage ? _product : null) : _receive,
              primary: true,
            ),
            if (c.canManage) button('Nová položka', AppIcons.stock, _product),
            button(
              'Inventúry a presuny',
              AppIcons.list,
              () => pushPage(context, WarehouseScreen(controller: c)),
            ),
            button(
              'Import CSV',
              AppIcons.connection,
              c.products.isEmpty ? null : _import,
            ),
          ],
        ),
        TextField(
          key: const ValueKey('merchant-stock-search'),
          decoration: InputDecoration(
            labelText: 'Hľadať názov, SKU / EAN alebo šaržu',
            prefixIcon: Icon(AppIcons.search),
          ),
          onChanged: (v) {
            setState(() => query = v);
            c.search('lots', v);
          },
        ),
        const SizedBox(height: 20),
        if (lots.isEmpty)
          empty(
            c.products.isEmpty
                ? 'Pridaj prvú skladovú položku'
                : 'Žiadne šarže pre tento výber',
            c.products.isEmpty
                ? 'Najprv názov, SKU a alergény. Potom prijmi konkrétnu šaržu.'
                : 'Prijmi zásoby alebo uprav vyhľadávanie.',
          ),
        for (final lot in lots) _lotCard(lot),
        _more('lots', 'šarže'),
        const SizedBox(height: 24),
        ExpansionTile(
          trailing: Icon(AppIcons.chevronDown),
          tilePadding: EdgeInsets.zero,
          title: const AppText('Katalóg skladových položiek'),
          children: [
            for (final p in c.products)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: AppText(p.name),
                subtitle: AppText(
                  '${p.sku} · ${p.unit.label} · ${p.storage.label}',
                ),
                trailing: AppText(euro(p.unitValue)),
              ),
            _more('products', 'produkty'),
          ],
        ),
        ExpansionTile(
          trailing: Icon(AppIcons.chevronDown),
          tilePadding: EdgeInsets.zero,
          title: const AppText('História skladových pohybov'),
          children: [
            for (final m in c.workspace.movements.where(
              (m) => m['store_id'] == c.storeId,
            ))
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: AppText(
                  '${_movementLabel(m['kind'] as String)} · ${_movementAmount(m, 'physical_delta')} fyzicky / ${_movementAmount(m, 'reserved_delta')} rezervované',
                ),
                subtitle: AppText(
                  '${m['reason']} · ${_date(DateTime.parse(m['created_at'] as String).toLocal())}',
                ),
              ),
            _more('movements', 'skladové pohyby'),
          ],
        ),
      ],
    );
  }

  String _stockTotals(String key, String fallback) {
    final units = c.workspace.stockSummary['units'] as List?;
    return units == null || units.isEmpty
        ? fallback
        : units
              .map(
                (u) => StockUnit.values
                    .byName(u['unit'] as String)
                    .formatAmount(u[key] as int, withUnit: true),
              )
              .join(' · ');
  }

  String _movementAmount(Map m, String key) => m['unit'] == null
      ? m[key].toString()
      : StockUnit.values
            .byName(m['unit'] as String)
            .formatAmount(m[key] as int, withUnit: true);
  Widget _more(String section, String label) =>
      c.workspace.pages[section] == null
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: OutlinedButton(
            onPressed: c.loading || c.busy || c.loadingSection != null
                ? null
                : () => c.page(section),
            child: Text(
              c.loadingSection == section
                  ? 'Načítavame…'
                  : 'Načítať ďalšie $label',
            ),
          ),
        );

  Widget _lotCard(StockLot lot, {bool compact = false}) {
    final p = c.product(lot.productId), now = StoreScope.of(context).now;
    final usable = lot.sellableAt(now);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: FoodPhoto(
                    p.image,
                    width: 64,
                    height: 64,
                    label: 'Fotografia skladovej položky ${p.name}',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AppText(p.name, style: context.text.titleMedium),
                      const SizedBox(height: 4),
                      AppText(
                        '${p.sku} · šarža ${lot.code}',
                        style: context.text.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                TagPill(
                  lot.deadline.isAfter(now) ? lot.quality.label : 'Po termíne',
                ),
                TagPill(p.storage.label),
              ],
            ),
            const SizedBox(height: 12),
            AppText(
              '${lot.dateMark.label} · ${_date(lot.deadline)}',
              style: context.text.bodySmall?.copyWith(
                color: usable ? context.colors.muted : context.colors.warning,
              ),
            ),
            const SizedBox(height: 10),
            AppText(
              'Fyzicky ${p.unit.formatAmount(lot.onHand)} · rezervované ${p.unit.formatAmount(lot.reserved)} · voľné ${p.unit.formatAmount(usable ? lot.available : 0, withUnit: true)}',
              style: context.text.bodyMedium,
            ),
            if (!compact) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  TextButton.icon(
                    onPressed: c.busy ? null : () => _adjust(lot),
                    icon: Icon(AppIcons.edit, size: 20),
                    label: const Text('Skladový pohyb'),
                  ),
                  if (c.canManage)
                    TextButton.icon(
                      onPressed: c.busy ? null : () => _quality(lot),
                      icon: Icon(AppIcons.shield, size: 20),
                      label: const Text('Kontrola kvality'),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _offers() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      heading(
        'Dobroty do sveta.',
        'Vlastné ponuky, overený obsah a zľavy podľa teba.',
        actions: [
          if (c.canManage)
            button(
              'Vytvoriť balíček',
              AppIcons.plus,
              c.products.isEmpty ? _product : _offer,
              primary: true,
            ),
        ],
      ),
      if (c.offers.isEmpty)
        empty(
          'Tvoj prvý balíček čaká',
          'Prijmi sklad a vytvor obsah jedného balíčka alebo si nechaj pripraviť návrh automaticky.',
        ),
      for (final o in c.offers)
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: FoodPhoto(o.offer.image, width: 76, height: 82),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          AppText(
                            o.offer.title,
                            style: context.text.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          TagPill(_offerLabel(o.state)),
                          const SizedBox(height: 6),
                          AppText(
                            '${_date(o.offer.pickupStart)} – ${o.offer.timeLabel.split(' – ').last}',
                            style: context.text.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 16,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    AppText(
                      euro(o.offer.price),
                      style: context.text.titleLarge?.copyWith(
                        color: context.colors.blue,
                      ),
                    ),
                    AppText(
                      'Hodnota ${euro(o.offer.originalPrice)} · zľava ${o.offer.discountPercent} %',
                    ),
                    AppText('${o.available} dostupných balíčkov'),
                  ],
                ),
                ExpansionTile(
                  trailing: Icon(AppIcons.chevronDown),
                  tilePadding: EdgeInsets.zero,
                  title: const AppText('Obsah a alergény'),
                  children: [
                    for (final e in o.recipe.entries)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: AppText('${e.value} × ${c.product(e.key).name}'),
                        subtitle: AppText(c.product(e.key).allergens),
                      ),
                  ],
                ),
                if (c.canManage)
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    children: [
                      button(
                        o.state == 'published'
                            ? 'Pozastaviť'
                            : o.state == 'draft'
                            ? 'Schváliť a zverejniť'
                            : 'Zverejniť',
                        o.state == 'published'
                            ? AppIcons.close
                            : AppIcons.check,
                        () => action(
                          () => c.mutate('offers/${o.offer.id}/state', {
                            'state': o.state == 'published'
                                ? 'paused'
                                : 'published',
                          }),
                          success: 'Ponuka je aktualizovaná.',
                        ),
                        primary: true,
                      ),
                      button(
                        'Upraviť cenu',
                        AppIcons.edit,
                        () => _editOffer(o),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      _more('offers', 'ponuky'),
    ],
  );
  Widget _automation() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      heading(
        'Balíčky, ktoré sa pripravia samy.',
        'Pravidlá sledujú termíny, kategóriu a skladovaciu zónu. Kontrola beží každú minútu.',
        actions: [
          if (c.canManage)
            button(
              'Nové pravidlo',
              AppIcons.plus,
              () => _rule(),
              primary: true,
            ),
          if (c.canManage)
            button('Skontrolovať zásoby teraz', AppIcons.refresh, _runRules),
        ],
      ),
      SurfaceCard(
        color: context.colors.tint,
        child: const AppText(
          'Automatizácia používa iba skontrolované šarže a obsah s platným termínom počas celého výdaja. Návrhy neblokujú sklad; pri objednávke sa dostupnosť znova overí.',
        ),
      ),
      const SizedBox(height: 20),
      if (c.rules.isEmpty)
        empty(
          'Prvé pravidlo, menej ručnej práce',
          'Vyber kategóriu, blízkosť termínu, hodnotu obsahu a výšku zľavy.',
        ),
      for (final r in c.rules)
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(AppIcons.sparkle, color: context.colors.blue),
                    const SizedBox(width: 12),
                    Expanded(
                      child: AppText(r.name, style: context.text.titleMedium),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    TagPill(r.enabled ? 'Aktívne' : 'Vypnuté'),
                    TagPill(
                      r.autoPublish
                          ? 'Automaticky zverejniť'
                          : 'Najprv schváliť',
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                AppText(
                  '${r.category.label} · ${r.storage.label}\nDo ${r.daysBefore} dní pred termínom · obsah od ${euro(r.targetValue)}\nZľava ${r.discountPercent} % · najviac ${r.maxPacks} balíčkov denne\nVýdaj ${_minutes(r.startMinutes)} – ${_minutes(r.endMinutes)}',
                ),
                if (c.canManage) ...[
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    children: [
                      TextButton.icon(
                        onPressed: () => _rule(r),
                        icon: Icon(AppIcons.edit, size: 20),
                        label: const Text('Upraviť pravidlo'),
                      ),
                      TextButton(
                        onPressed: () => action(
                          () => c.mutate('rules/${r.id}', {
                            ...r.toJson(),
                            'enabled': !r.enabled,
                          }, method: 'PATCH'),
                        ),
                        child: Text(r.enabled ? 'Vypnúť' : 'Zapnúť'),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      _more('rules', 'pravidlá'),
    ],
  );
  Widget _orders() {
    final ids = c.workspace.paged
        ? c.orders.expand((o) => o.items).map((i) => i.offerId).toSet()
        : c.offers.map((o) => o.offer.id).toSet();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        heading(
          'Pripravené na dobrý koniec.',
          'Over kód od zákazníka a potvrď výdaj iba za túto prevádzku.',
        ),
        if (c.orders.isEmpty)
          empty(
            'Zatiaľ bez objednávok',
            'Objednávky tvojich balíčkov sa objavia tu.',
          ),
        for (final o in c.orders)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: SurfaceCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: AppText(
                          'Objednávka ${o.id.substring(0, 8).toUpperCase()}',
                          style: context.text.titleMedium,
                        ),
                      ),
                      TagPill(_orderLabel(o.status)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  for (final i in o.items.where((i) => ids.contains(i.offerId)))
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: AppText(
                        '${i.remainingQuantity} × ${i.title}${i.collected ? ' · vydané' : ''}${i.refundCount > 0 ? ' · vrátené ${i.refundCount} ks' : ''}',
                      ),
                    ),
                  if (o.atRisk)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: AppText(
                        'Pozor: rezervovaná šarža vyžaduje riešenie. Výdaj je zablokovaný; skontroluj kvalitu a rieš storno s prevádzkovateľom.',
                        style: TextStyle(color: context.colors.warning),
                      ),
                    ),
                  if (o.status == 'reserved' &&
                      o.items.any(
                        (i) => ids.contains(i.offerId) && !i.collected,
                      )) ...[
                    const SizedBox(height: 14),
                    button(
                      'Overiť kód a vydať',
                      AppIcons.check,
                      o.atRisk ? null : () => _pickup(o),
                      primary: true,
                    ),
                  ],
                  if (c.canManage &&
                      {'reserved', 'awaitingPayment'}.contains(o.status) &&
                      !o.items.any((i) => i.collected) &&
                      o.cancellableStoreId == c.storeId)
                    TextButton(
                      onPressed: () => _cancel(o),
                      child: const Text('Stornovať a vrátiť platbu'),
                    ),
                ],
              ),
            ),
          ),
        _more('orders', 'objednávky'),
      ],
    );
  }

  Widget _settings() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      heading(
        'Všetko pre tvoju prevádzku.',
        '${c.organization!.name} · IČO ${c.organization!.companyId}',
      ),
      SurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppText('Prevádzky', style: context.text.titleLarge),
            const SizedBox(height: 12),
            for (final s in c.workspace.stores.where(
              (s) => s.organizationId == c.organization!.id,
            ))
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(AppIcons.store, color: context.colors.blue),
                title: AppText(s.name),
                subtitle: AppText(s.address),
              ),
            if (c.owner)
              TextButton.icon(
                onPressed: _store,
                icon: Icon(AppIcons.plus),
                label: const Text('Pridať prevádzku'),
              ),
          ],
        ),
      ),
      const SizedBox(height: 20),
      if (c.owner) ...[
        SurfaceCard(
          color: context.colors.tint,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppText(
                'Od dobrého jedla k dobrým číslam.',
                style: context.text.titleLarge,
              ),
              const SizedBox(height: 10),
              const AppText(
                'Tržby, Stripe pripojenie, výplaty po výdaji a exporty pre účtovníctvo.',
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => pushPage(
                  context,
                  MerchantFinanceScreen(organizationId: c.organization!.id),
                ),
                icon: Icon(AppIcons.wallet, size: 20),
                label: const Text('Tržby a vyúčtovanie'),
              ),
              OutlinedButton.icon(
                onPressed: () => pushPage(
                  context,
                  BillingScreen(organizationId: c.organization!.id),
                ),
                icon: Icon(AppIcons.receipt),
                label: const Text('Faktúry a fakturačný profil'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppText('Tím', style: context.text.titleLarge),
              const SizedBox(height: 10),
              const AppText(
                'Manažér spravuje ponuky a kvalitu. Personál prijíma zásoby a vydáva objednávky. Roly platia pre prevádzky firmy.',
              ),
              for (final m in c.workspace.members.where(
                (m) => m['org_id'] == c.organization!.id,
              ))
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: AppText(m['name'] as String),
                  subtitle: AppText(
                    '${m['email']} · ${_roleLabel(m['role'] as String)}',
                  ),
                  trailing: m['role'] == 'owner'
                      ? null
                      : IconButton(
                          tooltip: 'Odobrať prístup',
                          onPressed: () => _removeMember(m),
                          icon: Icon(AppIcons.close),
                        ),
                ),
              TextButton.icon(
                onPressed: _member,
                icon: Icon(AppIcons.plus),
                label: const Text('Pridať kolegu s existujúcim účtom'),
              ),
              OutlinedButton(
                onPressed: () =>
                    pushPage(context, MerchantTeamScreen(controller: c)),
                child: const Text('Tím, pozvánky a prístupy pobočiek'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppText(
                'Pokladňa a externý sklad',
                style: context.text.titleLarge,
              ),
              const SizedBox(height: 10),
              const AppText(
                'Samostatný token môže prijímať skladové udalosti iba pre túto prevádzku. Nový príjem z integrácie čaká na kontrolu kvality.',
              ),
              for (final i in c.workspace.integrations.where(
                (i) => i['store_id'] == c.storeId,
              ))
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(AppIcons.connection),
                  title: AppText(i['name'] as String),
                  subtitle: AppText(
                    i['revoked'] == 1
                        ? 'Odpojené'
                        : i['last_seen'] == null
                        ? 'Čaká na prvú udalosť'
                        : 'Posledná udalosť ${_date(DateTime.parse(i['last_seen'] as String).toLocal())} · čaká ${i['pending'] ?? 0} zmien',
                  ),
                  trailing: i['revoked'] == 1
                      ? null
                      : TextButton(
                          onPressed: () => _revoke(i),
                          child: const Text('Odpojiť'),
                        ),
                ),
              TextButton.icon(
                onPressed: _integration,
                icon: Icon(AppIcons.plus),
                label: const Text('Vytvoriť skladové pripojenie'),
              ),
              const SizedBox(height: 12),
              const SelectableText(
                'POST /v1/integrations/stock\nBearer token · eventId · operation · sku · lotCode\nOperácie: receive, adjust, set',
              ),
            ],
          ),
        ),
      ],
    ],
  );
  Future<void> _createOrganization() async {
    await edit(
      'Účet prevádzkovateľa',
      [
        const MerchantField('name', 'Názov firmy'),
        const MerchantField(
          'companyId',
          'IČO · 8 číslic',
          type: MerchantFieldType.number,
        ),
        MerchantField(
          'contactEmail',
          'Kontaktný e-mail',
          initial: StoreScope.of(context).email,
        ),
        ..._storeFields(),
      ],
      (v) => c.mutate('organizations', {
        'idempotencyKey': v['idempotencyKey'],
        'name': v['name'],
        'companyId': v['companyId'],
        'contactEmail': v['contactEmail'],
        'store': _storeBody(v),
      }),
      description:
          'Vytvoríš firmu a prvú prevádzku. Jej vlastník môže pridávať ďalšie prevádzky a členov tímu.',
    );
  }

  List<MerchantField> _storeFields() => [
    const MerchantField('storeName', 'Názov prevádzky'),
    MerchantField(
      'kind',
      'Typ prevádzky',
      initial: 'grocery',
      options: {for (final k in StoreKind.values) k.name: k.label},
    ),
    const MerchantField('address', 'Adresa vyzdvihnutia'),
    const MerchantField(
      'latitude',
      'Zemepisná šírka',
      hint: '48.1486',
      type: MerchantFieldType.number,
    ),
    const MerchantField(
      'longitude',
      'Zemepisná dĺžka',
      hint: '17.1077',
      type: MerchantFieldType.number,
    ),
  ];
  Map<String, dynamic> _storeBody(Map<String, dynamic> v) => {
    'name': v['storeName'],
    'kind': v['kind'],
    'address': v['address'],
    'point': {
      'lat': double.parse((v['latitude'] as String).replaceAll(',', '.')),
      'lng': double.parse((v['longitude'] as String).replaceAll(',', '.')),
    },
  };
  Future<void> _store() async {
    await edit(
      'Nová prevádzka',
      _storeFields(),
      (v) => c.mutate('stores', {
        'idempotencyKey': v['idempotencyKey'],
        'organizationId': c.organization!.id,
        ..._storeBody(v),
      }),
    );
  }

  Future<void> _product() async {
    await edit(
      'Nová skladová položka',
      [
        const MerchantField('name', 'Názov potraviny'),
        const MerchantField('sku', 'SKU / EAN'),
        MerchantField(
          'category',
          'Kategória',
          initial: 'bakery',
          options: _categories,
        ),
        MerchantField(
          'unit',
          'Skladová jednotka',
          initial: 'piece',
          options: {for (final u in StockUnit.values) u.name: u.label},
        ),
        const MerchantField(
          'unitValue',
          'Bežná hodnota jednotky (€)',
          type: MerchantFieldType.money,
        ),
        const MerchantField(
          'allergens',
          'Alergény podľa označenia',
          type: MerchantFieldType.multiline,
        ),
        MerchantField(
          'storage',
          'Skladovanie',
          initial: 'ambient',
          options: _zones,
        ),
        _imageField(),
      ],
      (v) => c.mutate('products', {
        ...v,
        'organizationId': c.organization!.id,
        'unitValue': moneyValue(v['unitValue']),
      }),
      description:
          'SKU zostáva textom aj s úvodnými nulami. Pri balení alebo porcii sa eviduje celý kus, nie zlomok.',
    );
  }

  Future<void> _receive() async {
    if (c.products.isEmpty) {
      if (c.canManage) await _product();
      return;
    }
    final tomorrow = StoreScope.of(context).now.add(const Duration(days: 1));
    await edit(
      'Príjem zásob',
      [
        MerchantField(
          'productId',
          'Skladová položka',
          lookup: c.workspace.paged ? c.lookupProducts : null,
          initial: c.products.first.id,
          options: {for (final p in c.products) p.id: '${p.name} · ${p.sku}'},
        ),
        const MerchantField('lotCode', 'Označenie šarže'),
        const MerchantField(
          'quantity',
          'Počet jednotiek',
          type: MerchantFieldType.number,
        ),
        MerchantField(
          'dateType',
          'Typ označeného dátumu',
          initial: 'useBy',
          options: {for (final d in DateMark.values) d.name: d.label},
        ),
        MerchantField(
          'deadline',
          'Najneskorší bezpečný výdaj',
          initial: localDateTime(
            DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 23, 59),
          ),
          type: MerchantFieldType.dateTime,
        ),
        MerchantField(
          'quality',
          'Kontrola kvality',
          initial: 'quarantine',
          options: {
            'quarantine': 'Čaká na kontrolu',
            if (c.canManage) 'checked': 'Skontrolované · vhodné na predaj',
          },
        ),
      ],
      (v) => c.mutate('stock/receive', {
        ...v,
        'storeId': c.storeId,
        'quantityDisplay': v['quantity'],
        'deadline': utcValue(v['deadline']),
      }),
      description:
          'Pri hotovom jedle určuje bezpečný čas prevádzkovateľ. Skontrolované označ iba overené potraviny so zachovaným skladovaním a balením.',
    );
  }

  Future<void> _adjust(StockLot lot) async {
    await edit(
      'Skladový pohyb',
      [
        const MerchantField(
          'delta',
          'Zmena množstva · napr. −2 alebo 5',
          type: MerchantFieldType.number,
        ),
        const MerchantField('reason', 'Dôvod pohybu'),
      ],
      (v) => c.mutate('lots/${lot.id}/adjust', {
        ...v,
        'version': lot.version,
        'deltaDisplay': v['delta'],
      }),
      description:
          'Predaj mimo aplikácie alebo inventúrna oprava. Rezervované zásoby nemožno odpísať.',
    );
  }

  Future<void> _quality(StockLot lot) async {
    await edit(
      'Kontrola šarže',
      [
        MerchantField(
          'quality',
          'Nový stav',
          initial: lot.quality.name,
          options: {for (final q in StockQuality.values) q.name: q.label},
        ),
        const MerchantField('reason', 'Dôvod a výsledok kontroly'),
      ],
      (v) => c.mutate('lots/${lot.id}/quality', {...v, 'version': lot.version}),
      description:
          'Zablokovaná šarža sa prestane ponúkať. Existujúce rezervácie sa označia na riešenie a výdaj sa zastaví.',
    );
  }

  Future<void> _offer() async {
    if (c.products.isEmpty) return;
    final now = StoreScope.of(context).now;
    final day = DateTime(now.year, now.month, now.day + 1);
    await edit(
      'Vlastný balíček',
      [
        const MerchantField('title', 'Názov balíčka'),
        MerchantField(
          'category',
          'Kategória obsahu',
          initial: c.products.first.category.name,
          options: _categories,
        ),
        const MerchantField(
          'description',
          'Čo má zákazník vedieť',
          type: MerchantFieldType.multiline,
        ),
        _imageField(initial: c.products.first.image),
        const MerchantField(
          'price',
          'Cena po zľave (€)',
          type: MerchantFieldType.money,
        ),
        const MerchantField(
          'stock',
          'Maximálny počet balíčkov',
          initial: '10',
          type: MerchantFieldType.number,
        ),
        MerchantField(
          'pickupStart',
          'Výdaj od',
          initial: localDateTime(day.add(const Duration(hours: 16))),
          type: MerchantFieldType.dateTime,
        ),
        MerchantField(
          'pickupEnd',
          'Výdaj do',
          initial: localDateTime(day.add(const Duration(hours: 18))),
          type: MerchantFieldType.dateTime,
        ),
        const MerchantField(
          'state',
          'Zverejnenie',
          initial: 'draft',
          options: {
            'draft': 'Uložiť návrh',
            'published': 'Zverejniť pre zákazníkov',
          },
        ),
      ],
      (v) => c.mutate('offers', {
        ...v,
        'storeId': c.storeId,
        'price': moneyValue(v['price']),
        'stock': integerValue(v['stock']),
        'pickupStart': utcValue(v['pickupStart']),
        'pickupEnd': utcValue(v['pickupEnd']),
      }),
      recipe: true,
      description:
          'Hodnota pred zľavou a alergény sa spočítajú z obsahu. Položky musia mať rovnakú kategóriu a skladovanie a byť vhodné až do konca výdaja.',
    );
  }

  Future<void> _editOffer(MerchantOffer o) async {
    await edit(
      'Cena a údaje ponuky',
      [
        MerchantField('title', 'Názov', initial: o.offer.title),
        MerchantField(
          'price',
          'Cena po zľave (€)',
          initial: (o.offer.price / 100).toStringAsFixed(2),
          type: MerchantFieldType.money,
        ),
        MerchantField(
          'stock',
          'Celkový limit balíčkov',
          initial: '${o.offer.stock}',
          type: MerchantFieldType.number,
        ),
        MerchantField(
          'description',
          'Popis',
          initial: o.offer.description,
          type: MerchantFieldType.multiline,
        ),
        _imageField(initial: o.offer.image),
      ],
      (v) => c.mutate('offers/${o.offer.id}', {
        ...v,
        'price': moneyValue(v['price']),
        'stock': integerValue(v['stock']),
      }, method: 'PATCH'),
      description:
          'Zmena ceny platí pre nové objednávky. Obsah a výdajové okno existujúcej ponuky sa nemenia.',
    );
  }

  Future<void> _rule([BundleRule? rule]) async {
    await edit(
      rule == null ? 'Nové automatické pravidlo' : 'Upraviť pravidlo',
      [
        MerchantField(
          'name',
          'Názov výsledného balíčka',
          initial: rule?.name ?? '',
        ),
        MerchantField(
          'category',
          'Kategória',
          initial: rule?.category.name ?? 'bakery',
          options: _categories,
        ),
        MerchantField(
          'storage',
          'Skladovacia zóna',
          initial: rule?.storage.name ?? 'ambient',
          options: _zones,
        ),
        MerchantField(
          'daysBefore',
          'Koľko dní pred termínom · 0 až 14',
          initial: '${rule?.daysBefore ?? 1}',
          type: MerchantFieldType.number,
        ),
        MerchantField(
          'targetValue',
          'Minimálna hodnota obsahu (€)',
          initial: ((rule?.targetValue ?? 1000) / 100).toStringAsFixed(2),
          type: MerchantFieldType.money,
        ),
        MerchantField(
          'discountPercent',
          'Zľava (%) · 1 až 90',
          initial: '${rule?.discountPercent ?? 60}',
          type: MerchantFieldType.number,
        ),
        MerchantField(
          'maxPacks',
          'Denný limit balíčkov',
          initial: '${rule?.maxPacks ?? 20}',
          type: MerchantFieldType.number,
        ),
        MerchantField(
          'start',
          'Výdaj od · HH:mm',
          initial: _minutes(rule?.startMinutes ?? 960),
        ),
        MerchantField(
          'end',
          'Výdaj do · HH:mm',
          initial: _minutes(rule?.endMinutes ?? 1080),
        ),
        MerchantField(
          'autoPublish',
          'Spôsob zverejnenia',
          initial: '${rule?.autoPublish ?? false}',
          options: const {
            'false': 'Najprv schváliť návrh',
            'true': 'Automaticky zverejniť',
          },
        ),
      ],
      (v) => c.mutate(
        rule == null ? 'rules' : 'rules/${rule.id}',
        {
          ...v,
          'storeId': c.storeId,
          'targetValue': moneyValue(v['targetValue']),
          'daysBefore': integerValue(v['daysBefore']),
          'discountPercent': integerValue(v['discountPercent']),
          'maxPacks': integerValue(v['maxPacks']),
          'startMinutes': _parseMinutes(v['start'] as String),
          'endMinutes': _parseMinutes(v['end'] as String),
          'autoPublish': v['autoPublish'] == 'true',
          'enabled': rule?.enabled ?? true,
        },
        method: rule == null ? 'POST' : 'PATCH',
      ),
      description:
          'Každé pravidlo vytvorí najviac jeden balíček na deň. Najbližšie termíny majú prednosť; kontrola kvality a dostatok skladu sú povinné.',
    );
  }

  Future<void> _runRules() => action(() async {
    final result = await c.mutate('stores/${c.storeId}/automation', {});
    final results = result['results'] as List;
    final made = results
        .where((r) => ['draft', 'published'].contains(r['status']))
        .length;
    if (mounted) {
      notice(
        context,
        made > 0
            ? 'Pripravené ponuky: $made. Nájdeš ich v Ponukách.'
            : 'Bez nových ponúk. Pravidlo už dnes vytvorilo balíček, skončilo výdajové okno alebo chýbajú vhodné zásoby.',
      );
    }
    return result;
  });
  Future<void> _pickup(MerchantOrder o) async {
    await edit(
      'Overenie pri výdaji',
      const [MerchantField('pickupCode', 'Kód z aplikácie zákazníka')],
      (v) => c.mutate('stores/${c.storeId}/orders/${o.id}/collect', v),
      description:
          'Kód zadaj pri odovzdaní balíčka. Sklad sa odpočíta iba za túto prevádzku.',
    );
  }

  Future<void> _cancel(MerchantOrder o) async {
    await edit(
      'Storno a vrátenie platby',
      const [MerchantField('reason', 'Dôvod storna')],
      (v) => c.mutate('stores/${c.storeId}/orders/${o.id}/cancel', v),
      description:
          'Zruší celú objednávku tejto prevádzky, uvoľní rezervovaný sklad a odošle vrátenie uhradenej platby. Pripísanie peňazí závisí od poskytovateľa a banky.',
    );
  }

  Future<void> _import() async {
    await edit(
      'Import skladových šarží',
      const [
        MerchantField(
          'delimiter',
          'Oddeľovač',
          initial: ',',
          options: {',': 'Čiarka', ';': 'Bodkočiarka'},
        ),
        MerchantField('csv', 'CSV obsah', type: MerchantFieldType.multiline),
      ],
      (v) => c.mutate('stores/${c.storeId}/import', v),
      description:
          'Najviac 200 riadkov, existujúce SKU. Hlavička: sku,lotCode,quantity,deadline,dateType\nPríklad: 000123,SARZA-1,10,2026-12-01T22:59:00Z,useBy\nImportované šarže čakajú na kontrolu. Chyba zruší celý import.',
    );
  }

  Future<void> _integration() async {
    final result = await edit(
      'Pripojenie skladu',
      const [MerchantField('name', 'Názov systému alebo pripojenia')],
      (v) => c.mutate('integrations', {...v, 'storeId': c.storeId}),
    );
    if (result == null || !mounted) return;
    final token = result['token'] as String?;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Skladové pripojenie'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                token == null
                    ? 'Pripojenie už bolo vytvorené. Token nemožno znova zobraziť; odpoj ho a vytvor nové.'
                    : 'Token sa zobrazí iba teraz. Ulož ho do konfigurácie svojho skladového systému.',
              ),
              if (token != null) ...[
                const SizedBox(height: 16),
                SelectableText(token),
              ],
            ],
          ),
        ),
        actions: [
          if (token != null)
            TextButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: token));
                notice(this.context, 'Token je skopírovaný.');
              },
              child: const Text('Kopírovať token'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Hotovo'),
          ),
        ],
      ),
    );
  }

  Future<void> _member() async {
    await edit(
      'Prístup kolegu',
      const [
        MerchantField('email', 'E-mail existujúceho účtu'),
        MerchantField(
          'role',
          'Rola',
          initial: 'staff',
          options: {
            'staff': 'Personál · sklad a výdaj',
            'manager': 'Manažér · ponuky a pravidlá',
          },
        ),
      ],
      (v) => c.mutate('members', {...v, 'organizationId': c.organization!.id}),
    );
  }

  Future<void> _confirm(
    String title,
    String text,
    Future<Object?> Function() run,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(text),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Späť'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Potvrdiť'),
          ),
        ],
      ),
    );
    if (confirmed == true) await action(run);
  }

  Future<void> _removeMember(Map<String, dynamic> m) => _confirm(
    'Odobrať prístup',
    'Kolega ${m['email']} stratí prístup k prevádzkam firmy.',
    () => c.mutate('members', {
      'organizationId': c.organization!.id,
      'email': m['email'],
      'role': 'remove',
    }),
  );
  Future<void> _revoke(Map<String, dynamic> i) => _confirm(
    'Odpojiť systém',
    'Skladový token pripojenia ${i['name']} prestane fungovať.',
    () => c.mutate('integrations/${i['id']}/revoke', {}),
  );
  Map<String, String> get _categories => {
    for (final k in FoodCategory.values.where((k) => k != FoodCategory.flowers))
      k.name: k.label,
  };
  Map<String, String> get _zones => {
    for (final z in StorageZone.values) z.name: z.label,
  };
  String _date(DateTime d) =>
      '${d.day}. ${d.month}. ${d.year} · ${_minutes(d.hour * 60 + d.minute)}';
  String _minutes(int n) =>
      '${(n ~/ 60).toString().padLeft(2, '0')}:${(n % 60).toString().padLeft(2, '0')}';
  int _parseMinutes(String s) {
    final parts = s.split(':');
    if (parts.length != 2) throw StateError('Čas zadaj ako HH:mm.');
    final h = int.tryParse(parts[0]), m = int.tryParse(parts[1]);
    if (h == null || m == null || h < 0 || h > 23 || m < 0 || m > 59) {
      throw StateError('Neplatný čas.');
    }
    return h * 60 + m;
  }

  String _offerLabel(String s) => switch (s) {
    'draft' => 'Návrh na schválenie',
    'published' => 'Zverejnené',
    _ => 'Pozastavené',
  };
  String _orderLabel(String s) => switch (s) {
    'awaitingPayment' => 'Čaká na platbu',
    'reserved' => 'Na vyzdvihnutie',
    'collected' => 'Vydané',
    'cancelling' => 'Rieši sa storno',
    _ => 'Zrušené',
  };
  String _roleLabel(String s) => switch (s) {
    'owner' => 'Vlastník',
    'manager' => 'Manažér',
    _ => 'Personál',
  };
  String _movementLabel(String s) => switch (s) {
    'receive' => 'Príjem',
    'adjust' => 'Oprava',
    'reserve' => 'Rezervácia',
    'release' => 'Uvoľnenie',
    'collect' => 'Výdaj',
    'inventory' => 'Inventúra',
    'transfer_out' => 'Odoslanie presunu',
    'transfer_in' => 'Príjem presunu',
    'transfer_return' => 'Návrat presunu',
    _ => 'Kontrola',
  };
}

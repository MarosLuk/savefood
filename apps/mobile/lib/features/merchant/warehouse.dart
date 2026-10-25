import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:design_system/design_system.dart';
import 'package:marketplace_api/marketplace_api.dart';
import 'package:marketplace_domain/marketplace_domain.dart';
import '../../state/app_store.dart';
import '../../widgets/common.dart';
import 'controller.dart';
import 'editor.dart';

String warehouseQuantity(int amount, Map product) {
  final unit = StockUnit.values.byName(product['unit'] as String);
  return unit.scale == 1
      ? '$amount × ${product['name']}'
      : '${unit.formatAmount(amount, withUnit: true)} · ${product['name']}';
}

String warehouseStatus(String s) => switch (s) {
  'draft' => 'Rozpracované',
  'posted' => 'Zaúčtované',
  'inTransit' => 'Na ceste',
  'received' => 'Prijaté',
  'returned' => 'Vrátené na kontrolu',
  _ => 'Zrušené',
};
String warehouseEvent(String s) => switch (s) {
  'created' => 'Vytvorené',
  'counted' => 'Uložené počty',
  'rebased' => 'Obnovená predloha',
  'posted' => 'Schválená inventúra',
  'dispatch' => 'Odoslané',
  'receive' => 'Prijaté',
  'return' => 'Fyzicky vrátené',
  _ => 'Zrušené',
};
Future<bool> confirmWarehouse(
  BuildContext context,
  String title,
  String message,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: AppText(title),
        content: AppText(message),
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
    ) ??
    false;
Widget warehouseAudit(
  BuildContext context,
  Map<String, dynamic> data,
) => ExpansionTile(
  title: const AppText('História operácie'),
  trailing: Icon(AppIcons.chevronDown),
  children: [
    for (final a in data['audit'] as List? ?? [])
      ListTile(
        title: AppText(warehouseEvent(a['event'] as String)),
        subtitle: AppText(
          '${a['detail']}\n${a['actor'] ?? ''} · ${shortDate(DateTime.parse(a['created_at'] as String).toLocal())}',
        ),
      ),
  ],
);

class WarehouseScreen extends StatefulWidget {
  const WarehouseScreen({super.key, required this.controller});
  final MerchantController controller;
  @override
  State<WarehouseScreen> createState() => _WarehouseScreenState();
}

class _WarehouseScreenState extends State<WarehouseScreen> {
  Map<String, dynamic>? data;
  String? error, email;
  bool loading = true;
  MerchantController get c => widget.controller;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final identity = StoreScope.of(context).email;
    if (email != identity) {
      email = identity;
      data = null;
      load();
    }
  }

  Future<void> load({String? more}) async {
    final identity = email;
    setState(() => loading = true);
    try {
      final j = await c.api.request(
        'GET',
        '/v1/merchant/stock/operations?storeId=${Uri.encodeComponent(c.storeId!)}${more == null ? '' : '&${more == "counts" ? "beforeCounts" : "beforeTransfers"}=${data?["${more}Next"]}'}',
      );
      if (mounted && identity == email) {
        setState(() {
          data = more == null
              ? j
              : {
                  ...data!,
                  more: [...data![more] as List, ...j[more] as List],
                  '${more}Next': j['${more}Next'],
                };
          error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> open(String kind, String id) async {
    await pushPage(
      context,
      WarehouseDetailScreen(controller: c, kind: kind, id: id),
    );
    if (!mounted) return;
    await c.load();
    await load();
  }

  Future<void> createCount() async {
    final j = await merchantEditor(
      context,
      title: 'Nová inventúra',
      description:
          'Počítanie zásoby nemení. Rozdiely naraz schváli vedúci; zmenené šarže treba prepočítať.',
      fields: const [
        MerchantField(
          'reason',
          'Dôvod inventúry',
          initial: 'Pravidelná kontrola skladu',
        ),
      ],
      submit: (b) =>
          c.api.merchantAction('stock/counts', {'storeId': c.storeId, ...b}),
    );
    if (j != null && mounted) await open('counts', j['id'] as String);
  }

  Future<void> createTransfer() async {
    final stores =
        (data?['destinations'] is List
                ? (data!['destinations'] as List)
                      .map(
                        (s) => MerchantStore.fromJson(
                          Map<String, dynamic>.from(s as Map),
                        ),
                      )
                      .toList()
                : c.workspace.stores)
            .where(
              (s) =>
                  s.organizationId == c.store!.organizationId &&
                  s.id != c.storeId,
            )
            .toList();
    final lots = c.lots
        .where(
          (l) => l.available > 0 && l.sellableAt(StoreScope.of(context).now),
        )
        .toList();
    if (stores.isEmpty || lots.isEmpty && !c.workspace.paged) {
      notice(
        context,
        'Presun potrebuje druhú pobočku firmy a skontrolovanú voľnú zásobu.',
      );
      return;
    }
    final j = await merchantEditor(
      context,
      title: 'Presun medzi pobočkami',
      description:
          'Koncept zásoby neodpočíta. Po odoslaní zostanú na ceste až do fyzického príjmu v cieli.',
      fields: [
        MerchantField(
          'lotId',
          'Zdrojová šarža',
          lookup: c.workspace.paged ? c.lookupLots : null,
          initial: lots.firstOrNull?.id ?? '',
          options: lots.isEmpty
              ? null
              : {
                  for (final l in lots)
                    l.id:
                        '${c.product(l.productId).name} · ${l.code} · voľné ${c.product(l.productId).unit.formatAmount(l.available, withUnit: true)}',
                },
        ),
        MerchantField(
          'destinationStoreId',
          'Cieľová pobočka',
          initial: stores.first.id,
          options: {for (final s in stores) s.id: s.name},
        ),
        const MerchantField(
          'quantity',
          'Počet jednotiek',
          initial: '1',
          type: MerchantFieldType.number,
        ),
        const MerchantField('reason', 'Dôvod presunu'),
      ],
      submit: (b) => c.api.merchantAction('stock/transfers', {
        ...b,
        'quantityDisplay': b['quantity'],
      }),
    );
    if (j != null && mounted) await open('transfers', j['id'] as String);
  }

  @override
  Widget build(BuildContext context) {
    final c = this.c;
    return ScreenScaffold(
      title: 'Inventúry a presuny',
      actions: [
        IconButton(
          tooltip: 'Obnoviť skladové operácie',
          onPressed: loading ? null : load,
          icon: Icon(AppIcons.refresh),
        ),
      ],
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          SurfaceCard(
            color: context.colors.tint,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TagPill('KAŽDÝ KUS MÁ SVOJE MIESTO', icon: AppIcons.stock),
                const SizedBox(height: 18),
                AppText(
                  'Presné zásoby.\nPokojný výdaj.',
                  style: context.text.headlineLarge,
                ),
                const SizedBox(height: 12),
                AppText(c.store?.name ?? ''),
                const SizedBox(height: 12),
                const AppText(
                  'Prepočítaj skutočné množstvá alebo pošli voľné zásoby do druhej pobočky. Rezervované jedlo zostáva chránené.',
                ),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    FilledButton.icon(
                      onPressed: loading ? null : createCount,
                      icon: Icon(AppIcons.list, size: 20),
                      label: const Text('Nová inventúra'),
                    ),
                    if (c.canManage)
                      OutlinedButton.icon(
                        onPressed: loading ? null : createTransfer,
                        icon: Icon(AppIcons.navigation, size: 20),
                        label: const Text('Nový presun'),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          if (error != null)
            SurfaceCard(color: context.colors.warm, child: AppText(error!)),
          if (loading) const LinearProgressIndicator(),
          AppText('Inventúry', style: context.text.titleLarge),
          const SizedBox(height: 12),
          if ((data?['counts'] as List? ?? []).isEmpty)
            const SurfaceCard(
              child: AppText(
                'Prvá inventúra pripraví zoznam šarží na prepočítanie.',
              ),
            ),
          for (final row in data?['counts'] as List? ?? [])
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: SurfaceCard(
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: AppText(row['reason'] as String),
                  subtitle: AppText(
                    '${warehouseStatus(row['status'] as String)} · ${shortDate(DateTime.parse(row['created_at'] as String))}',
                  ),
                  trailing: Icon(AppIcons.chevronRight),
                  onTap: () => open('counts', row['id'] as String),
                ),
              ),
            ),
          if (data?['countsNext'] != null)
            TextButton(
              onPressed: loading ? null : () => load(more: 'counts'),
              child: const Text('Staršie inventúry'),
            ),
          const SizedBox(height: 24),
          AppText('Presuny zásob', style: context.text.titleLarge),
          const SizedBox(height: 12),
          if ((data?['transfers'] as List? ?? []).isEmpty)
            const SurfaceCard(
              child: AppText(
                'Odoslané aj prichádzajúce zásoby sa zobrazia tu.',
              ),
            ),
          for (final row in data?['transfers'] as List? ?? [])
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: InkWell(
                onTap: () => open('transfers', row['id'] as String),
                borderRadius: BorderRadius.circular(24),
                child: SurfaceCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: FoodPhoto(
                              row['product']['image'] as String,
                              width: 58,
                              height: 58,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: AppText(
                              warehouseQuantity(
                                row['quantity'] as int,
                                row['product'] as Map,
                              ),
                              style: context.text.titleMedium,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      AppText(
                        '${row['source']['name']} → ${row['destination']['name']}',
                      ),
                      const SizedBox(height: 10),
                      TagPill(warehouseStatus(row['status'] as String)),
                    ],
                  ),
                ),
              ),
            ),
          if (data?['transfersNext'] != null)
            TextButton(
              onPressed: loading ? null : () => load(more: 'transfers'),
              child: const Text('Staršie presuny'),
            ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

class WarehouseDetailScreen extends StatefulWidget {
  const WarehouseDetailScreen({
    super.key,
    required this.controller,
    required this.kind,
    required this.id,
  });
  final MerchantController controller;
  final String kind, id;
  @override
  State<WarehouseDetailScreen> createState() => _WarehouseDetailScreenState();
}

class _WarehouseDetailScreenState extends State<WarehouseDetailScreen> {
  Map<String, dynamic>? data;
  String? error, email;
  bool busy = false, loading = true, checked = false;
  String query = '';
  final edits = <String, String>{};
  bool get counting => widget.kind == 'counts';
  MerchantController get c => widget.controller;
  String get path => 'stock/${widget.kind}/${widget.id}';
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final identity = StoreScope.of(context).email;
    if (email != identity) {
      email = identity;
      data = null;
      edits.clear();
      load();
    }
  }

  Timer? searchTimer;
  int generation = 0;
  final knownLines = <String, Map>{};
  @override
  void dispose() {
    searchTimer?.cancel();
    super.dispose();
  }

  Future<void> load({bool more = false}) async {
    final identity = email, g = ++generation;
    setState(() => loading = true);
    try {
      final suffix = counting
          ? Uri(
              queryParameters: {
                if (more && data?['linesNext'] != null)
                  'after': data!['linesNext'].toString(),
                'query': query,
              },
            ).toString()
          : '';
      final j = await c.api.request('GET', '/v1/merchant/$path$suffix');
      if (!mounted || identity != email || g != generation) return;
      if (counting) {
        for (final l in j['lines'] as List) {
          knownLines[l['lot_id'] as String] = l as Map;
        }
      }
      setState(() {
        if (more && data?['version'] != j['version']) {
          data = j;
          edits.clear();
          knownLines.clear();
          error =
              'Inventúru medzičasom zmenil kolega. Obnovili sme aktuálnu stránku.';
        } else {
          data = more
              ? {
                  ...j,
                  'lines': [...data!['lines'] as List, ...j['lines'] as List],
                }
              : j;
          error = null;
        }
      });
    } catch (e) {
      if (mounted && g == generation) setState(() => error = e.toString());
    } finally {
      if (mounted && g == generation) setState(() => loading = false);
    }
  }

  Future<void> action(
    String action, {
    Map<String, dynamic> extra = const {},
  }) async {
    if (busy || data == null) return;
    final prompt = switch (action) {
      'post' => (
        'Schváliť inventúru?',
        'Počty sa zapíšu do fyzického skladu naraz. Rezervácie musia zostať pokryté.',
      ),
      'dispatch' => (
        'Tovar fyzicky odoslaný?',
        '${warehouseQuantity(data!['quantity'] as int, data!['product'] as Map)} sa odpočíta zo zdrojovej pobočky a zostane evidovaných na ceste.',
      ),
      'receive' => (
        'Potvrdiť fyzický príjem?',
        'Zásoby pribudnú v cieľovej pobočke s pôvodným termínom. ${checked ? 'Potvrdzuješ aj kontrolu kvality.' : 'Zostanú na kontrolu kvality.'}',
      ),
      'return' => (
        'Tovar sa fyzicky vrátil?',
        'Vrátené kusy pribudnú v pôvodnej pobočke ako samostatná šarža na kontrolu.',
      ),
      'cancel' => (
        'Zrušiť rozpracovanú operáciu?',
        'Operácia sa uzavrie bez zmeny fyzického skladu.',
      ),
      'rebase' when edits.isNotEmpty => (
        'Obnoviť predlohu inventúry?',
        'Neuložené počty sa zahodia. Zmenené šarže bude treba znovu prepočítať.',
      ),
      _ => null,
    };
    if (prompt != null &&
        !await confirmWarehouse(context, prompt.$1, prompt.$2)) {
      return;
    }
    if (!mounted) return;
    setState(() => busy = true);
    try {
      final j = await c.api.merchantAction(path, {
        'version': data!['version'],
        'action': action,
        'reason': switch (action) {
          'dispatch' => 'Fyzické odoslanie potvrdené obsluhou',
          'receive' => 'Fyzický príjem potvrdený obsluhou',
          'return' => 'Fyzický návrat potvrdený obsluhou',
          'cancel' => 'Operáciu zrušila obsluha',
          _ => 'Spracovanie inventúry',
        },
        if (!counting) 'lotVersion': data!['lot']['version'],
        'checked': checked,
        'physicallyReturned': action == 'return',
        ...extra,
      });
      if (!mounted) return;
      setState(() {
        data = j;
        edits.clear();
        error = null;
      });
      await c.load();
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> save() async {
    final lines = <Map<String, dynamic>>[];
    for (final edit in edits.entries) {
      int? qty;
      try {
        final line =
            knownLines[edit.key] ??
            (data!['lines'] as List).cast<Map>().firstWhere(
              (l) => l['lot_id'] == edit.key,
            );
        qty = _unit(line).parseAmount(edit.value);
      } on FormatException {
        qty = null;
      }
      if (qty == null || qty < 0 || qty > 1000000) {
        notice(
          context,
          'Zadaj platné nezáporné množstvá. Váhy a objemy majú najviac tri desatinné miesta.',
        );
        return;
      }
      lines.add({'lotId': edit.key, 'counted': qty});
    }
    if (lines.isEmpty) return;
    if (lines.length > 200) {
      notice(context, 'Ulož najviac 200 zmenených šarží naraz.');
      return;
    }
    await action('save', extra: {'lines': lines});
  }

  @override
  Widget build(BuildContext context) {
    final d = data;
    return ScreenScaffold(
      title: counting ? 'Inventúra skladu' : 'Detail presunu',
      actions: [
        IconButton(
          tooltip: 'Obnoviť detail operácie',
          onPressed: busy
              ? null
              : () async {
                  if (edits.isEmpty ||
                      await confirmWarehouse(
                        context,
                        'Obnoviť údaje?',
                        'Neuložené počty sa zahodia.',
                      )) {
                    await load();
                  }
                },
          icon: Icon(AppIcons.refresh),
        ),
      ],
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: SurfaceCard(
                color: context.colors.warm,
                child: AppText(error!),
              ),
            ),
          if (loading) const LinearProgressIndicator(),
          if (d != null) ...[
            TagPill(warehouseStatus(d['status'] as String)),
            const SizedBox(height: 16),
            AppText(
              counting
                  ? d['reason'] as String
                  : warehouseQuantity(
                      d['quantity'] as int,
                      d['product'] as Map,
                    ),
              style: context.text.headlineMedium,
            ),
            const SizedBox(height: 12),
            AppText(
              counting
                  ? d['store']['name'] as String
                  : '${d['source']['name']} → ${d['destination']['name']}',
            ),
            const SizedBox(height: 24),
            if (counting) ..._countWidgets(d) else ..._transferWidgets(d),
            const SizedBox(height: 24),
            warehouseAudit(context, d),
          ],
        ],
      ),
    );
  }

  List<Widget> _countWidgets(Map<String, dynamic> d) {
    final lines = (d['lines'] as List).cast<Map>();
    final draft = d['status'] == 'draft';
    final stats = d['lineStats'] as Map?;
    final complete = stats == null
        ? lines.every((l) => l['counted'] != null && l['stale'] != true)
        : stats['missing'] == 0 && stats['stale'] == 0;
    return [
      SurfaceCard(
        color: context.colors.tint,
        child: AppText(
          '${stats?['counted'] ?? lines.where((l) => l['counted'] != null).length} z ${stats?['total'] ?? lines.length} šarží prepočítaných\nRozdiely: ${stats?['changed'] ?? lines.where((l) => l['counted'] != null && l['counted'] != l['expected']).length} šarží',
        ),
      ),
      const SizedBox(height: 16),
      if (draft)
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            FilledButton.icon(
              onPressed: busy || edits.isEmpty ? null : save,
              icon: Icon(AppIcons.check, size: 20),
              label: const Text('Uložiť počty'),
            ),
            OutlinedButton(
              onPressed: busy ? null : () => action('rebase'),
              child: const Text('Obnoviť zmenené šarže'),
            ),
            if (c.canManage)
              FilledButton(
                onPressed: busy || !complete || edits.isNotEmpty
                    ? null
                    : () => action('post'),
                child: const Text('Schváliť inventúru'),
              ),
            if (c.canManage)
              TextButton(
                onPressed: busy ? null : () => action('cancel'),
                child: const Text('Zrušiť inventúru'),
              ),
          ],
        ),
      const SizedBox(height: 16),
      TextField(
        decoration: const InputDecoration(labelText: 'Názov, SKU alebo šarža'),
        onChanged: (v) {
          query = v;
          searchTimer?.cancel();
          searchTimer = Timer(
            const Duration(milliseconds: 350),
            () => unawaited(load()),
          );
        },
      ),
      const SizedBox(height: 16),
      for (final l in lines)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppText(
                  l['product']['name'] as String,
                  style: context.text.titleMedium,
                ),
                const SizedBox(height: 6),
                AppText('${l['product']['sku']} · ${l['lot_code']}'),
                const SizedBox(height: 8),
                AppText(
                  'Podľa predlohy ${_unit(l).formatAmount(l['expected'] as int)} · teraz ${_unit(l).formatAmount(l['on_hand'] as int)} · rezervované ${_unit(l).formatAmount(l['reserved'] as int)}',
                ),
                if (l['stale'] == true) ...[
                  const SizedBox(height: 8),
                  const TagPill('ZMENENÉ · OBNOV A PREPOČÍTAJ'),
                ],
                const SizedBox(height: 12),
                TextFormField(
                  key: ValueKey('count-${d['version']}-${l['lot_id']}'),
                  initialValue:
                      edits[l['lot_id']] ??
                      (l['counted'] == null
                          ? ''
                          : _unit(l).formatAmount(l['counted'] as int)),
                  enabled: draft && !busy,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]')),
                  ],
                  decoration: InputDecoration(
                    labelText:
                        'Skutočný počet · ${StockUnit.values.byName(l['product']['unit'] as String).label}',
                  ),
                  onChanged: (v) =>
                      setState(() => edits[l['lot_id'] as String] = v),
                ),
              ],
            ),
          ),
        ),
      if (d['linesNext'] != null)
        TextButton(
          onPressed: loading ? null : () => load(more: true),
          child: const Text('Načítať ďalšie šarže'),
        ),
    ];
  }

  StockUnit _unit(Map line) =>
      StockUnit.values.byName(line['product']['unit'] as String);
  List<Widget> _transferWidgets(Map<String, dynamic> d) => [
    ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: FoodPhoto(
        d['product']['image'] as String,
        height: 220,
        width: double.infinity,
      ),
    ),
    const SizedBox(height: 18),
    SurfaceCard(
      child: AppText(
        'Šarža: ${d['lot']['lotCode']}\nPôvodný termín: ${shortDate(DateTime.parse(d['lot']['deadline'] as String))}\n${d['canDispatch'] == false ? 'Stav zdroja spravuje druhá pobočka.' : 'Voľné v zdroji: ${_unit(d).formatAmount((d['lot']['onHand'] as int) - (d['lot']['reserved'] as int), withUnit: true)}'}\n${d['reason']}',
      ),
    ),
    const SizedBox(height: 18),
    if (d['status'] == 'draft' && c.canManage && d['canDispatch'] != false)
      Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          FilledButton.icon(
            onPressed: busy ? null : () => action('dispatch'),
            icon: Icon(AppIcons.navigation, size: 20),
            label: const Text('Potvrdiť odoslanie'),
          ),
          TextButton(
            onPressed: busy ? null : () => action('cancel'),
            child: const Text('Zrušiť koncept'),
          ),
        ],
      ),
    if (d['status'] == 'inTransit') ...[
      if (c.canManage && d['canReceive'] != false)
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          title: const AppText('Tovar bol pri príjme skontrolovaný'),
          subtitle: const AppText('Inak zostane v cieli na kontrolu kvality.'),
          value: checked,
          onChanged: busy ? null : (v) => setState(() => checked = v ?? false),
        ),
      Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          FilledButton.icon(
            onPressed: busy || d['canReceive'] == false
                ? null
                : () => action('receive'),
            icon: Icon(AppIcons.stock, size: 20),
            label: const Text('Potvrdiť fyzický príjem'),
          ),
          if (c.canManage && d['canDispatch'] != false)
            OutlinedButton(
              onPressed: busy ? null : () => action('return'),
              child: const Text('Potvrdiť návrat do zdroja'),
            ),
        ],
      ),
    ],
  ];
}

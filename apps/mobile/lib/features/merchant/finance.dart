import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:design_system/design_system.dart';
import 'package:marketplace_api/marketplace_api.dart';
import 'package:marketplace_domain/marketplace_domain.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../state/app_store.dart';
import '../../services/file_export.dart';
import '../../widgets/common.dart';

/// Date picker values are local calendar days; elapsed 24 hours can cross DST.
(String, String) accountingExportDates(DateTime start, DateTime end) => (
  DateTime.utc(
    start.year,
    start.month,
    start.day,
  ).toIso8601String().substring(0, 10),
  DateTime.utc(
    end.year,
    end.month,
    end.day + 1,
  ).toIso8601String().substring(0, 10),
);

class MerchantFinanceScreen extends StatefulWidget {
  const MerchantFinanceScreen({super.key, required this.organizationId});
  final String organizationId;
  @override
  State<MerchantFinanceScreen> createState() => _MerchantFinanceScreenState();
}

class _MerchantFinanceScreenState extends State<MerchantFinanceScreen> {
  Map<String, dynamic>? data;
  String? email, error;
  bool loading = true, busy = false;
  Timer? timer;
  MarketplaceApi get api => StoreScope.of(context).api!;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final identity = StoreScope.of(context).email;
    if (email != identity) {
      email = identity;
      data = null;
      unawaited(load());
    }
    timer ??= Timer.periodic(const Duration(seconds: 8), (_) {
      if (mounted && !busy && ModalRoute.of(context)?.isCurrent == true) {
        unawaited(load(quiet: true));
      }
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> load({bool quiet = false}) async {
    final identity = email;
    if (!quiet && mounted) setState(() => loading = true);
    try {
      final response = await api.merchantFinance(widget.organizationId);
      if (mounted && email == identity) {
        setState(() {
          data = response;
          error = null;
        });
      }
    } catch (e) {
      if (mounted && email == identity) setState(() => error = e.toString());
    } finally {
      if (mounted && email == identity) setState(() => loading = false);
    }
  }

  Future<void> action(String name, Map<String, dynamic> body) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final result = await api.financeAction(widget.organizationId, name, body);
      if (!mounted) return;
      if (name == 'connect' &&
          result['url'] is String &&
          (result['url'] as String).isNotEmpty) {
        if (!await launchUrl(
              Uri.parse(result['url'] as String),
              mode: LaunchMode.externalApplication,
            ) &&
            mounted) {
          notice(context, 'Overenie sa nepodarilo otvoriť. Skús znova.');
        }
      } else if (name == 'settle') {
        notice(
          context,
          (result['queued'] as int) > 0
              ? 'Vyúčtovanie je zaradené na spracovanie.'
              : 'Zatiaľ nie sú ďalšie položky po uplynutí ochrannej lehoty.',
        );
      }
      await load(quiet: true);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> export() async {
    if (busy) return;
    setState(() => busy = true);
    final identity = email;
    final shareOrigin = Rect.fromLTWH(
      0,
      0,
      MediaQuery.sizeOf(context).width,
      100,
    );
    try {
      final today = DateUtils.dateOnly(DateTime.now().toUtc());
      final range = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2020),
        lastDate: today,
        initialDateRange: DateTimeRange(
          start: DateTime(today.year, today.month, today.day - 30),
          end: today,
        ),
        helpText: 'Účtovné obdobie (najviac 366 dní, UTC)',
        saveText: 'Exportovať',
      );
      if (!mounted || range == null || identity != email) return;
      final (from, to) = accountingExportDates(range.start, range.end);
      final result = await api.accountingExport(
        widget.organizationId,
        from: from,
        to: to,
      );
      if (!mounted || identity != email) return;
      await exportCsvFile(
        result['filename'] as String,
        utf8.encode(result['content'] as String),
        shareOrigin,
      );
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final totals = Map<String, dynamic>.from(data?['totals'] as Map? ?? {});
    final account = Map<String, dynamic>.from(data?['account'] as Map? ?? {});
    final entries = (data?['entries'] as List? ?? []).cast<Map>();
    return Scaffold(
      appBar: AppBar(
        title: const AppText('Tržby a vyúčtovanie'),
        actions: [
          IconButton(
            tooltip: 'Obnoviť vyúčtovanie',
            onPressed: busy ? null : () => load(),
            icon: Icon(AppIcons.refresh),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1120),
          child: loading && data == null
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: load,
                  child: ListView(
                    padding: const EdgeInsets.all(24),
                    children: [
                      if (error != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: SurfaceCard(
                            color: c.warm,
                            child: AppText(error!),
                          ),
                        ),
                      if (data != null) ...[
                        SurfaceCard(
                          color: c.tint,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(AppIcons.wallet, color: c.blue),
                                  const SizedBox(width: 10),
                                  Flexible(
                                    child: TagPill(
                                      data!['mode'] == 'sandbox'
                                          ? 'DEMO VYÚČTOVANIE'
                                          : 'FINANCIE',
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 20),
                              AppText(
                                'Dobré jedlo.\nPrehľadné čísla.',
                                style: context.text.headlineLarge,
                              ),
                              const SizedBox(height: 8),
                              AppText(
                                data!['organization'] as String,
                                style: context.text.bodyLarge,
                              ),
                              const SizedBox(height: 16),
                              AppText(
                                'Predajca dostane sumu za vydané balíčky po odpočítaní dohodnutej provízie. Prevod na Stripe účet a výplata na bankový účet sú samostatné kroky.',
                                style: context.text.bodyMedium,
                              ),
                              if (data!['mode'] == 'sandbox') ...[
                                const SizedBox(height: 12),
                                const AppText(
                                  'V deme sú všetky prevody simulované. Žiadne peniaze sa neprevádzajú.',
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        LayoutBuilder(
                          builder: (context, size) {
                            final columns = size.maxWidth >= 780 ? 4 : 2,
                                width =
                                    (size.maxWidth - 12 * (columns - 1)) /
                                    columns;
                            return Wrap(
                              spacing: 12,
                              runSpacing: 12,
                              children: [
                                for (final metric in [
                                  ('Predaj po zľavách', 'sales', AppIcons.bag),
                                  (
                                    'Prevedené predajcovi',
                                    'transferred',
                                    AppIcons.checkCircle,
                                  ),
                                  (
                                    'Čaká na vyúčtovanie',
                                    'eligible',
                                    AppIcons.clock,
                                  ),
                                  (
                                    'Refundované balíčky',
                                    'refunded',
                                    AppIcons.refresh,
                                  ),
                                ])
                                  SizedBox(
                                    width: width,
                                    child: SurfaceCard(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Icon(metric.$3, color: c.blue),
                                          const SizedBox(height: 16),
                                          FittedBox(
                                            fit: BoxFit.scaleDown,
                                            child: AppText(
                                              euro(
                                                totals[metric.$2] as int? ?? 0,
                                              ),
                                              style: context.text.headlineSmall,
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          ConstrainedBox(
                                            constraints: const BoxConstraints(
                                              minHeight: 40,
                                            ),
                                            child: AppText(
                                              metric.$1,
                                              style: context.text.bodySmall,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 24),
                        SurfaceCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(AppIcons.shield, color: c.blue),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: AppText(
                                      'Účet na prijímanie platieb',
                                      style: context.text.titleLarge,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 14),
                              TagPill(
                                account['ready'] == true
                                    ? 'Pripravený na prevody'
                                    : 'Čaká na pripojenie alebo overenie',
                              ),
                              const SizedBox(height: 10),
                              if (account['id'] != null)
                                SelectableText(
                                  account['id'] as String,
                                  style: context.text.bodySmall,
                                ),
                              const SizedBox(height: 10),
                              AppText(
                                'Aktuálna provízia: ${((data!['commissionBps'] as int) / 100).toStringAsFixed(2)} %. Ochranná lehota po výdaji: ${data!['delayHours']} h. Sadzba sa uloží pri vytvorení objednávky.',
                              ),
                              const SizedBox(height: 16),
                              Wrap(
                                spacing: 10,
                                runSpacing: 10,
                                children: [
                                  FilledButton.icon(
                                    onPressed:
                                        busy || data!['connectEnabled'] != true
                                        ? null
                                        : () => action('connect', {}),
                                    icon: Icon(AppIcons.connection, size: 20),
                                    label: Text(
                                      data!['mode'] == 'sandbox'
                                          ? 'Pripojiť demo účet'
                                          : 'Dokončiť overenie v Stripe',
                                    ),
                                  ),
                                  OutlinedButton.icon(
                                    onPressed: busy || account['id'] == null
                                        ? null
                                        : () => action('refresh', {}),
                                    icon: Icon(AppIcons.refresh, size: 20),
                                    label: const Text('Overiť stav účtu'),
                                  ),
                                  OutlinedButton.icon(
                                    onPressed: busy || account['ready'] != true
                                        ? null
                                        : () => action('settle', {}),
                                    icon: Icon(AppIcons.wallet, size: 20),
                                    label: const Text('Spustiť vyúčtovanie'),
                                  ),
                                ],
                              ),
                              if (data!['connectEnabled'] != true) ...[
                                const SizedBox(height: 12),
                                const AppText(
                                  'Prijímanie výplat sa sprístupní po zapojení Stripe Connect.',
                                ),
                              ],
                              SwitchListTile(
                                contentPadding: EdgeInsets.zero,
                                title: const AppText(
                                  'Automatické vyúčtovanie po výdaji',
                                ),
                                subtitle: const AppText(
                                  'Po ochrannej lehote a iba pri spôsobilom účte.',
                                ),
                                value: account['automatic'] == true,
                                onChanged: busy || account['id'] == null
                                    ? null
                                    : (v) =>
                                          action('automatic', {'enabled': v}),
                              ),
                              if (busy) const LinearProgressIndicator(),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        SurfaceCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              AppText(
                                'Podklady pre účtovníctvo',
                                style: context.text.titleLarge,
                              ),
                              const SizedBox(height: 10),
                              const AppText(
                                'Export za zvolené obdobie obsahuje párovanie objednávok, platby kartou, kredit, provízie a vratky v centoch. Ide o účtovný podklad; DPH neurčuje a nenahrádza daňový doklad.',
                              ),
                              const SizedBox(height: 14),
                              OutlinedButton.icon(
                                onPressed: busy ? null : export,
                                icon: Icon(AppIcons.receipt, size: 20),
                                label: const Text('Exportovať účtovný CSV'),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 28),
                        AppText(
                          'Od objednávky po prevod',
                          style: context.text.titleLarge,
                        ),
                        if (entries.length >=
                            (data!['entryLimit'] as int? ?? 500)) ...[
                          const SizedBox(height: 8),
                          const AppText(
                            'Zobrazuje sa posledných 500 položiek. Súhrny zahŕňajú celú históriu; staršie záznamy nájdeš v exporte.',
                          ),
                        ],
                        const SizedBox(height: 14),
                        if (entries.isEmpty)
                          const SurfaceCard(
                            child: AppText(
                              'Prvé položky sa zobrazia po vytvorení objednávky.',
                            ),
                          ),
                        for (final e in entries)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: SurfaceCard(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(14),
                                        child: FoodPhoto(
                                          e['image'] as String,
                                          width: 64,
                                          height: 64,
                                        ),
                                      ),
                                      const SizedBox(width: 14),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            AppText(
                                              e['title'] as String,
                                              style: context.text.titleMedium,
                                            ),
                                            const SizedBox(height: 4),
                                            AppText(
                                              '${e['store']} · ${e['quantity']} ×',
                                              style: context.text.bodySmall,
                                            ),
                                            const SizedBox(height: 6),
                                            TagPill(
                                              financeState(
                                                e['state'] as String,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 14),
                                  Wrap(
                                    spacing: 18,
                                    runSpacing: 8,
                                    children: [
                                      AppText(
                                        'Predaj ${euro((e['gross'] as int) - (e['discount'] as int))}',
                                      ),
                                      AppText(
                                        'Provízia ${euro(e['commission'] as int)}',
                                      ),
                                      AppText(
                                        'Predajca ${euro(e['sellerNet'] as int)}',
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  AppText(
                                    'Objednávka ${(e['orderId'] as String).substring(0, 8).toUpperCase()} · ${shortDate(DateTime.parse(e['createdAt'] as String).toLocal())}',
                                    style: context.text.bodySmall,
                                  ),
                                  if (e['error'] != null) ...[
                                    const SizedBox(height: 8),
                                    AppText(
                                      e['error'] as String,
                                      style: TextStyle(color: c.warning),
                                    ),
                                  ],
                                  if ((e['providerIds'] as List)
                                      .isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    SelectableText(
                                      (e['providerIds'] as List).join('\n'),
                                      style: context.text.bodySmall,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                      ] else if (error == null)
                        const AppText('Vyúčtovanie nie je dostupné.'),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}

String financeState(String state) => switch (state) {
  'eligible' => 'Po výdaji · čaká na vyúčtovanie',
  'transferred' => 'Prevedené na Stripe účet',
  'queued' => 'Prevod sa pripravuje',
  'awaitingPickup' => 'Čaká na vyzdvihnutie',
  'awaitingPayment' => 'Čaká na platbu',
  'refunding' => 'Refundácia sa spracúva',
  'refunded' => 'Refundované',
  'review' => 'Preveruje podpora',
  'failed' => 'Prevod potrebuje obnoviť',
  'cancelled' => 'Zrušené',
  _ => state,
};

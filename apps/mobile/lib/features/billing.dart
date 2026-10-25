import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:design_system/design_system.dart';
import 'package:marketplace_domain/marketplace_domain.dart';
import '../state/app_store.dart';
import '../widgets/common.dart';
import '../services/file_export.dart';
import 'merchant/editor.dart';

class BillingScreen extends StatefulWidget {
  const BillingScreen({
    super.key,
    this.organizationId,
    this.orderId,
    this.platform = false,
  });
  final String? organizationId, orderId;
  final bool platform;
  @override
  State<BillingScreen> createState() => _BillingScreenState();
}

class _BillingScreenState extends State<BillingScreen> {
  Map<String, dynamic>? settings;
  List<Map<String, dynamic>> rows = [];
  String? next, error, pending;
  bool loading = false, busy = false;
  String? identity;
  int generation = 0;
  String get listPath => widget.orderId != null
      ? '/v1/orders/${widget.orderId}/documents'
      : widget.platform
      ? '/v1/platform/documents'
      : '/v1/merchant/documents/${widget.organizationId}';
  String get settingsPath => widget.platform
      ? '/v1/platform/billing'
      : '/v1/merchant/billing/${widget.organizationId}';
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final user = StoreScope.of(context).email;
    if (identity != user) {
      identity = user;
      generation++;
      rows = [];
      settings = null;
      pending = null;
      next = null;
      error = null;
      loading = false;
      busy = false;
      if (user.isNotEmpty) unawaited(load());
    }
  }

  Future<void> load({bool more = false}) async {
    if (loading) return;
    setState(() => loading = true);
    final who = identity, g = ++generation;
    try {
      final api = StoreScope.of(context).api!;
      final result = await api.request(
        'GET',
        '$listPath${more && next != null ? '?before=${Uri.encodeQueryComponent(next!)}' : ''}',
      );
      final profile = widget.orderId == null
          ? await api.request('GET', settingsPath)
          : null;
      if (!mounted || who != identity || g != generation) return;
      setState(() {
        rows = [
          if (more) ...rows,
          ...(result['rows'] as List).cast<Map<String, dynamic>>(),
        ];
        next = result['nextCursor'] as String?;
        pending = result['pending'] as String?;
        settings = profile;
        error = null;
      });
    } catch (e) {
      if (mounted && who == identity && g == generation) {
        setState(() => error = e.toString());
      }
    } finally {
      if (mounted && who == identity && g == generation) {
        setState(() => loading = false);
      }
    }
  }

  Future<void> download(Map d) async {
    if (busy) return;
    setState(() => busy = true);
    final who = identity;
    final origin = Rect.fromLTWH(0, 0, MediaQuery.sizeOf(context).width, 100);
    try {
      final data = await StoreScope.of(
        context,
      ).api!.binary('GET', '/v1/documents/${d['id']}/pdf');
      if (!mounted || who != identity) return;
      await exportDataFile(
        '${d['number']}.pdf',
        data.bodyBytes,
        origin,
        mimeType: 'application/pdf',
      );
    } catch (e) {
      if (mounted && who == identity) setState(() => error = e.toString());
    } finally {
      if (mounted && who == identity) setState(() => busy = false);
    }
  }

  Future<void> export() async {
    // Export the complete filtered ledger through keyset pages, without loading PDFs.
    if (busy) return;
    setState(() => busy = true);
    final who = identity;
    final origin = Rect.fromLTWH(0, 0, MediaQuery.sizeOf(context).width, 100);
    try {
      final api = StoreScope.of(context).api!;
      final all = <Map<String, dynamic>>[];
      String? cursor;
      do {
        final page = await api.request(
          'GET',
          '$listPath${cursor == null ? '' : '?before=${Uri.encodeQueryComponent(cursor)}'}',
        );
        if (!mounted || who != identity) return;
        all.addAll((page['rows'] as List).cast<Map<String, dynamic>>());
        cursor = page['nextCursor'] as String?;
      } while (cursor != null);
      if (!mounted || who != identity) return;
      await exportDataFile(
        'uctovne-doklady.json',
        Uint8List.fromList(
          utf8.encode(
            const JsonEncoder.withIndent(
              '  ',
            ).convert({'schema': 'nevyhadzuj.billing.v1', 'documents': all}),
          ),
        ),
        origin,
        mimeType: 'application/json',
      );
    } catch (e) {
      if (mounted && who == identity) setState(() => error = e.toString());
    } finally {
      if (mounted && who == identity) setState(() => busy = false);
    }
  }

  Future<void> configure() async {
    final p = Map<String, dynamic>.from(settings?['profile'] as Map? ?? {}),
        rates = Map<String, dynamic>.from(p['rates'] as Map? ?? {});
    await merchantEditor(
      context,
      title: 'Vystavovateľ dokladov',
      description:
          'Údaje a sadzby schvaľuje prevádzkovateľ so svojím účtovníkom. Zmena platí pre nové doklady; vystavené doklady zostávajú zachované.',
      fields: [
        if (widget.platform)
          MerchantField(
            'model',
            'Kto predáva potraviny',
            initial: settings?['model'] as String? ?? '',
            options: const {
              'merchantSeller': 'Partnerská predajňa / reštaurácia',
              'platformSeller': 'Prevádzkovateľ platformy',
            },
          ),
        for (final entry in const {
          'name': 'Obchodné meno',
          'address': 'Sídlo a poštová adresa',
          'companyId': 'IČO / registračné číslo',
          'country': 'Krajina (SK)',
          'contactEmail': 'Fakturačný e-mail',
          'prefix': 'Predpona číselného radu',
        }.entries)
          MerchantField(
            entry.key,
            entry.value,
            initial: p[entry.key] as String? ?? '',
          ),
        MerchantField(
          'taxMode',
          'Režim DPH',
          initial: p['taxMode'] as String? ?? 'notVat',
          options: const {'notVat': 'Neplatiteľ DPH', 'vat': 'Platiteľ DPH'},
        ),
        MerchantField(
          'taxId',
          'DIČ',
          initial: p['taxId'] as String? ?? '',
          optional: true,
        ),
        MerchantField(
          'vatId',
          'IČ DPH',
          initial: p['vatId'] as String? ?? '',
          optional: true,
        ),
        MerchantField(
          'retentionDays',
          'Schválená archivácia (dni)',
          initial: '${p['retentionDays'] ?? ''}',
          type: MerchantFieldType.number,
        ),
        for (final key in [...FoodCategory.values.map((c) => c.name), 'fee'])
          MerchantField(
            'rate_$key',
            'DPH ${key == 'fee' ? 'služba platformy' : FoodCategory.values.firstWhere((c) => c.name == key).label} (%)',
            initial: rates[key] == null ? '' : '${(rates[key] as int) / 100}',
            optional: true,
          ),
      ],
      submit: (b) async {
        final output = {
          ...b,
          'version': p['version'] ?? 0,
          'retentionDays': integerValue(b['retentionDays']),
          'rates': {
            for (final key in [
              ...FoodCategory.values.map((c) => c.name),
              'fee',
            ])
              if ((b['rate_$key'] as String).isNotEmpty)
                key: _rate(b['rate_$key'] as String),
          },
        };
        return StoreScope.of(
          context,
        ).api!.request('POST', settingsPath, body: output);
      },
    );
    if (mounted) await load();
  }

  bool get canWrite =>
      !widget.platform || StoreScope.of(context).platformRole == 'admin';
  Future<void> connector() async {
    final result = await merchantEditor(
      context,
      title: 'Účtovné pripojenie',
      description:
          'Pripojenie umožní účtovnému konektoru čítať iba doklady tohto vystavovateľa. Token zobrazíme iba raz.',
      fields: const [MerchantField('name', 'Názov účtovného systému')],
      submit: (b) => StoreScope.of(
        context,
      ).api!.request('POST', '$settingsPath/connectors', body: b),
    );
    if (!mounted) return;
    if (result?['token'] != null) {
      await showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          title: const AppText('Token účtovného pripojenia'),
          content: SingleChildScrollView(
            child: SelectableText(result!['token'] as String),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Hotovo'),
            ),
          ],
        ),
      );
    }
    if (mounted) await load();
  }

  Future<void> revoke(Map row) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const AppText('Odpojiť účtovníctvo?'),
        content: AppText(row['name'] as String),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Späť'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Odpojiť'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await StoreScope.of(context).api!.request(
        'POST',
        '$settingsPath/connectors/${row['id']}/revoke',
        body: {},
      );
      if (mounted) await load();
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  int _rate(String text) {
    final value = num.tryParse(text.replaceAll(',', '.'));
    if (value == null ||
        value < 0 ||
        value > 100 ||
        (value * 100).round() / 100 != value) {
      throw StateError('Sadzba DPH má najviac dve desatinné miesta.');
    }
    return (value * 100).round();
  }

  @override
  Widget build(BuildContext context) => ScreenScaffold(
    title: 'Faktúry a doklady',
    actions: [
      IconButton(
        tooltip: 'Obnoviť doklady',
        onPressed: loading ? null : () => load(),
        icon: Icon(AppIcons.refresh),
      ),
    ],
    child: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        AppText(
          'Doklady na jednom mieste.',
          style: context.text.headlineMedium,
        ),
        const SizedBox(height: 12),
        const AppText(
          'Faktúra sa vystaví po prevzatí. Refundácia vystavenej položky vytvorí opravný doklad s odkazom na pôvodnú faktúru.',
        ),
        const SizedBox(height: 20),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: AppText(
              error!,
              style: TextStyle(color: context.colors.warning),
            ),
          ),
        if (pending != null)
          SurfaceCard(
            child: AppText(
              'Doklady čakajú na doplnenie údajov vystavovateľa: $pending',
            ),
          ),
        if (settings != null) ...[
          SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppText(
                  (settings!['profile'] as Map)['name'] as String? ??
                      'Fakturačný profil nie je vyplnený',
                  style: context.text.titleMedium,
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: busy || !canWrite ? null : configure,
                  icon: Icon(AppIcons.edit, size: 18),
                  label: const Text('Fakturačný profil a sadzby'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: busy || rows.isEmpty ? null : export,
            icon: Icon(AppIcons.download, size: 18),
            label: const Text('Export dokladov pre účtovníctvo (JSON)'),
          ),
          const SizedBox(height: 16),
          for (final row in settings!['connectors'] as List? ?? [])
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: AppText(row['name'] as String),
              subtitle: AppText(
                row['revoked'] == 1
                    ? 'Odpojené'
                    : 'Čaká ${row['pending']} dokladov',
              ),
              trailing: row['revoked'] == 1 || !canWrite
                  ? null
                  : TextButton(
                      onPressed: () => revoke(row as Map),
                      child: const Text('Odpojiť'),
                    ),
            ),
          if (canWrite)
            TextButton.icon(
              onPressed: busy ? null : connector,
              icon: Icon(AppIcons.connection),
              label: const Text('Pripojiť účtovný systém'),
            ),
          const SizedBox(height: 20),
        ],
        if (loading) const LinearProgressIndicator(),
        if (!loading && rows.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: AppText('Zatiaľ tu nie sú vystavené doklady.'),
          ),
        for (final d in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: SurfaceCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppText(
                    '${d['kind'] == 'creditNote' ? 'Opravná faktúra' : 'Faktúra'} · ${d['number']}',
                    style: context.text.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  AppText(
                    '${d['title']}\n${d['issuedAt']} · ${euro(d['gross'] as int)}',
                  ),
                  if (d['demo'] == true)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: AppText('DEMO · fiktívny účtovný doklad'),
                    ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: busy ? null : () => download(d),
                    icon: Icon(AppIcons.download, size: 18),
                    label: const Text('Stiahnuť PDF'),
                  ),
                ],
              ),
            ),
          ),
        if (next != null)
          TextButton(
            onPressed: loading ? null : () => load(more: true),
            child: const Text('Načítať ďalšie doklady'),
          ),
      ],
    ),
  );
}

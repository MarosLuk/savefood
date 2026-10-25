import 'dart:async';
import 'package:flutter/material.dart';
import 'package:design_system/design_system.dart';
import '../state/app_store.dart';
import '../widgets/common.dart';
import 'merchant/editor.dart';

Future<Map<String, dynamic>?> showLegalConsent(BuildContext context) =>
    Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(builder: (_) => const LegalScreen(consent: true)),
    );

class LegalScreen extends StatefulWidget {
  const LegalScreen({super.key, this.consent = false, this.version});
  final bool consent;
  final int? version;
  @override
  State<LegalScreen> createState() => _LegalScreenState();
}

class _LegalScreenState extends State<LegalScreen> {
  Map<String, dynamic>? data;
  String? error;
  bool accepted = false, electronic = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(load());
    });
  }

  Future<void> load() async {
    try {
      final r = await StoreScope.of(context).api!.request(
        'GET',
        '/v1/legal${widget.version == null ? '' : '?version=${widget.version}'}',
      );
      if (mounted) {
        setState(() {
          data = r;
          error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) => ScreenScaffold(
    title: 'Podmienky a súkromie',
    bottom: !widget.consent
        ? null
        : PrimaryButton(
            'Súhlasím a pokračovať',
            onPressed: data?['configured'] == true && accepted && electronic
                ? () => Navigator.pop(context, {
                    'version': data!['version'],
                    'accepted': true,
                    'electronicInvoice': true,
                  })
                : null,
          ),
    child: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        if (error != null) ...[
          AppText(error!),
          TextButton(onPressed: load, child: const Text('Skúsiť znova')),
        ] else if (data == null)
          const LinearProgressIndicator()
        else if (data!['configured'] != true)
          const AppText(
            'Prevádzkovateľ zatiaľ nezverejnil podmienky. Registrácia a nákup budú dostupné po ich doplnení.',
          )
        else ...[
          if (data!['demo'] == true)
            const Padding(
              padding: EdgeInsets.only(bottom: 16),
              child: TagPill('DEMO · ilustračné podmienky'),
            ),
          AppText(
            data!['operator'] as String,
            style: context.text.headlineMedium,
          ),
          const SizedBox(height: 10),
          SelectableText(
            '${data!['address']}\nRegistrácia: ${data!['registration']}\n${data!['contact']}\nVerzia ${data!['version']} · ${data!['publishedAt']}',
          ),
          const SizedBox(height: 24),
          AppText('Obchodné podmienky', style: context.text.titleLarge),
          const SizedBox(height: 12),
          SelectableText(data!['terms'] as String),
          const SizedBox(height: 24),
          AppText('Ochrana osobných údajov', style: context.text.titleLarge),
          const SizedBox(height: 12),
          SelectableText(data!['privacy'] as String),
          if (widget.consent) ...[
            const SizedBox(height: 24),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: accepted,
              onChanged: (v) => setState(() => accepted = v ?? false),
              title: const AppText(
                'Súhlasím s obchodnými podmienkami a oboznámil/a som sa s informáciami o spracúvaní osobných údajov.',
              ),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: electronic,
              onChanged: (v) => setState(() => electronic = v ?? false),
              title: const AppText(
                'Súhlasím s vystavovaním a sprístupnením faktúr v elektronickej podobe.',
              ),
            ),
          ],
        ],
      ],
    ),
  );
}

class LegalAdminScreen extends StatefulWidget {
  const LegalAdminScreen({super.key});
  @override
  State<LegalAdminScreen> createState() => _LegalAdminScreenState();
}

class _LegalAdminScreenState extends State<LegalAdminScreen> {
  Map<String, dynamic>? data;
  String? error;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(load());
    });
  }

  Future<void> load() async {
    try {
      final r = await StoreScope.of(
        context,
      ).api!.request('GET', '/v1/platform/legal');
      if (mounted) {
        setState(() {
          data = r;
          error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  Future<void> edit() async {
    final d = data!, r = d['retention'] as Map? ?? {};
    await merchantEditor(
      context,
      title: 'Podmienky prevádzkovateľa',
      description:
          'Pred publikovaním vlož schválené texty a retenčné lehoty. Publikovaná verzia sa uchová a zákazníci potvrďujú konkrétnu verziu.',
      fields: [
        for (final e in const {
          'operator': 'Obchodné meno prevádzkovateľa',
          'registration': 'IČO / registrácia',
          'address': 'Sídlo',
          'contact': 'Kontakt pre osobné údaje',
          'terms': 'Obchodné podmienky',
          'privacy': 'Informácie o spracúvaní osobných údajov',
        }.entries)
          MerchantField(
            e.key,
            e.value,
            initial: d[e.key] as String? ?? '',
            type: {'terms', 'privacy'}.contains(e.key)
                ? MerchantFieldType.multiline
                : MerchantFieldType.text,
          ),
        for (final e in const {
          'orders': 'Údaje objednávok (dni)',
          'support': 'Uzavretá podpora (dni)',
          'accountAudit': 'Audit účtu (dni)',
          'mail': 'Doručené e-maily (dni)',
          'mediaDraftHours': 'Nezverejnené fotografie (hodiny)',
        }.entries)
          MerchantField(
            e.key,
            e.value,
            initial: '${r[e.key] ?? ''}',
            type: MerchantFieldType.number,
          ),
        const MerchantField(
          'mode',
          'Uloženie',
          initial: 'draft',
          options: {
            'draft': 'Uložiť koncept',
            'publish': 'Publikovať novú verziu',
          },
        ),
      ],
      submit: (b) => StoreScope.of(context).api!.request(
        'POST',
        '/v1/platform/legal',
        body: {
          ...b,
          'revision': d['revision'],
          'publish': b['mode'] == 'publish',
          'retention': {
            for (final k in [
              'orders',
              'support',
              'accountAudit',
              'mail',
              'mediaDraftHours',
            ])
              k: integerValue(b[k]),
          },
        },
      ),
    );
    if (mounted) await load();
  }

  @override
  Widget build(BuildContext context) => ScreenScaffold(
    title: 'Podmienky a prevádzkovateľ',
    child: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        AppText('Zverejnené pravidlá.', style: context.text.headlineMedium),
        const SizedBox(height: 16),
        if (error != null)
          AppText(error!)
        else if (data == null)
          const LinearProgressIndicator()
        else ...[
          AppText(
            'Publikovaná verzia: ${data!['publishedVersion']}\n${data!['operator'] ?? 'Údaje nie sú vyplnené'}',
          ),
          const SizedBox(height: 20),
          if (StoreScope.of(context).platformRole == 'admin')
            PrimaryButton('Upraviť koncept / publikovať', onPressed: edit),
          const SizedBox(height: 20),
          OutlinedButton(
            onPressed: () => pushPage(context, const LegalScreen()),
            child: const Text('Zobraziť zverejnenú verziu'),
          ),
        ],
      ],
    ),
  );
}

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:design_system/design_system.dart';
import '../../state/app_store.dart';
import '../../widgets/common.dart';
import '../account.dart';
import '../demo.dart';
import '../support/activity.dart';
import '../merchant/editor.dart';
import '../billing.dart';
import '../legal.dart';
import 'readiness.dart';

const platformSections = {
  'users': 'Používatelia',
  'organizations': 'Firmy',
  'stores': 'Pobočky',
  'offers': 'Ponuky',
  'reviews': 'Recenzie',
  'agents': 'Operátori',
  'audit': 'Audit',
  'mail': 'Doručovanie',
};

class PlatformAdminScreen extends StatefulWidget {
  const PlatformAdminScreen({super.key, this.onExit});
  final VoidCallback? onExit;
  @override
  State<PlatformAdminScreen> createState() => _PlatformAdminScreenState();
}

class _PlatformAdminScreenState extends State<PlatformAdminScreen> {
  Map<String, dynamic>? overview;
  List<Map<String, dynamic>> rows = [];
  String section = 'users', query = '';
  String? error, cursor, identity;
  bool loading = false, busy = false;
  int generation = 0;
  Timer? timer;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final store = StoreScope.of(context);
    if (identity != store.email) {
      identity = store.email;
      overview = null;
      rows = [];
      if (store.platformRole == 'moderator') section = 'offers';
      if (store.signedIn && store.platformRole != null) load();
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> load({bool more = false}) async {
    final store = StoreScope.of(context);
    if (!store.signedIn || store.platformRole == null) return;
    final version = ++generation;
    setState(() => loading = true);
    try {
      final api = store.api!;
      final info = await api.request('GET', '/v1/platform/overview');
      final params = Uri(
        queryParameters: {
          'query': query,
          if (more && cursor != null) 'before': cursor!,
        },
      ).query;
      final result = await api.request(
        'GET',
        '/v1/platform/resources/$section?$params',
      );
      if (mounted && version == generation) {
        setState(() {
          overview = info;
          rows = [
            if (more) ...rows,
            ...(result['rows'] as List).map(
              (r) => Map<String, dynamic>.from(r as Map),
            ),
          ];
          cursor = result['nextCursor'] as String?;
          error = null;
        });
      }
    } catch (e) {
      if (mounted && version == generation) {
        setState(() => error = e.toString());
      }
    } finally {
      if (mounted && version == generation) setState(() => loading = false);
    }
  }

  Future<void> change(
    Map<String, dynamic> row,
    String action, {
    String? role,
  }) async {
    final api = StoreScope.of(context).api!;
    final result = await merchantEditor(
      context,
      title: '${platformSections[section]} · potvrdenie zmeny',
      description:
          'Zmena sa uloží do auditu s tvojím účtom. Oprávnenia a aktuálna verzia sa overujú na serveri.',
      fields: [
        const MerchantField(
          'reason',
          'Dôvod zmeny',
          type: MerchantFieldType.multiline,
        ),
      ],
      submit: (body) => api.request(
        'POST',
        '/v1/platform/resources/$section/${Uri.encodeComponent(row['id'] as String)}',
        body: {
          ...body,
          'action': action,
          'role': ?role,
          'version': row['version'],
        },
      ),
    );
    if (result != null && mounted) {
      await StoreScope.of(context).refreshRemote();
      await load();
    }
  }

  List<Widget> actions(Map<String, dynamic> r) {
    final store = StoreScope.of(context);
    if (store.platformRole == 'auditor') return [];
    if (section == 'users' && r['deleted_at'] == null) {
      return [
        TextButton(
          onPressed: () => change(r, r['disabled'] == 1 ? 'enable' : 'disable'),
          child: Text(r['disabled'] == 1 ? 'Odblokovať' : 'Pozastaviť účet'),
        ),
        PopupMenuButton<String>(
          tooltip: 'Administrátorská rola',
          onSelected: (v) => change(r, 'role', role: v),
          itemBuilder: (_) => [
            for (final e in {
              'none': 'Bez administrácie',
              'admin': 'Správca',
              'moderator': 'Moderátor obsahu',
              'auditor': 'Audítor · iba čítanie',
            }.entries)
              PopupMenuItem(value: e.key, child: Text(e.value)),
          ],
          child: const Padding(
            padding: EdgeInsets.all(12),
            child: Text('Upraviť rolu'),
          ),
        ),
        TextButton(
          onPressed: () => change(r, 'support-on'),
          child: const Text('Pridať medzi operátorov'),
        ),
        TextButton(
          onPressed: () => change(r, 'support-off'),
          child: const Text('Odobrať podporu'),
        ),
      ];
    }
    if (section == 'organizations') {
      return [
        TextButton(
          onPressed: () =>
              change(r, r['status'] == 'suspended' ? 'activate' : 'suspend'),
          child: Text(
            r['status'] == 'suspended' ? 'Aktivovať firmu' : 'Pozastaviť firmu',
          ),
        ),
      ];
    }
    if (section == 'stores') {
      return [
        TextButton(
          onPressed: () => change(r, r['paused'] == 1 ? 'activate' : 'suspend'),
          child: Text(
            r['paused'] == 1
                ? 'Obnoviť predaj v pobočke'
                : 'Pozastaviť predaj v pobočke',
          ),
        ),
      ];
    }
    if (section == 'offers') {
      return [
        TextButton(
          onPressed: () => change(r, r['hidden'] == 1 ? 'show' : 'hide'),
          child: Text(r['hidden'] == 1 ? 'Zverejniť obsah' : 'Skryť obsah'),
        ),
      ];
    }
    if (section == 'reviews') {
      return [
        TextButton(
          onPressed: () =>
              change(r, r['moderation'] == 'hidden' ? 'show' : 'hide'),
          child: Text(
            r['moderation'] == 'hidden'
                ? 'Zobraziť recenziu'
                : 'Skryť recenziu',
          ),
        ),
      ];
    }
    return [];
  }

  String title(Map r) =>
      (r['name'] ??
              (r['payload'] as Map?)?['name'] ??
              (r['payload'] as Map?)?['title'] ??
              r['subject'] ??
              r['event'] ??
              r['comment'] ??
              r['id'])
          .toString();
  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context),
        compact = MediaQuery.sizeOf(context).width < 700;
    return ScreenScaffold(
      title: compact ? 'Administrácia' : 'Save Food · administrácia',
      actions: [
        if (compact &&
            (store.platformRole == 'admin' || store.platformRole == 'auditor'))
          PopupMenuButton<String>(
            tooltip: 'Správa platformy',
            icon: Icon(AppIcons.settings),
            onSelected: (value) => pushPage(context, switch (value) {
              'readiness' => const PlatformReadinessScreen(),
              'legal' => const LegalAdminScreen(),
              _ => const BillingScreen(platform: true),
            }),
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'readiness',
                child: Text('Prevádzka a pripravenosť'),
              ),
              PopupMenuItem(
                value: 'legal',
                child: Text('Podmienky a prevádzkovateľ'),
              ),
              PopupMenuItem(
                value: 'billing',
                child: Text('Účtovné doklady platformy'),
              ),
            ],
          ),

        if (!compact &&
            (store.platformRole == 'admin' || store.platformRole == 'auditor'))
          IconButton(
            tooltip: 'Prevádzka a pripravenosť',
            onPressed: () => pushPage(context, const PlatformReadinessScreen()),
            icon: Icon(AppIcons.dashboard),
          ),
        if (!compact &&
            (store.platformRole == 'admin' || store.platformRole == 'auditor'))
          IconButton(
            tooltip: 'Podmienky a prevádzkovateľ',
            onPressed: () => pushPage(context, const LegalAdminScreen()),
            icon: Icon(AppIcons.shield),
          ),
        if (!compact &&
            (store.platformRole == 'admin' || store.platformRole == 'auditor'))
          IconButton(
            tooltip: 'Účtovné doklady platformy',
            onPressed: () =>
                pushPage(context, const BillingScreen(platform: true)),
            icon: Icon(AppIcons.receipt),
          ),
        const SupportActivityButton(),
        PopupMenuButton<ThemeMode>(
          tooltip: 'Vzhľad',
          icon: Icon(AppIcons.device),
          onSelected: store.setTheme,
          itemBuilder: (_) => [
            const PopupMenuItem(
              value: ThemeMode.light,
              child: Text('Svetlý režim'),
            ),
            const PopupMenuItem(
              value: ThemeMode.dark,
              child: Text('Tmavý režim'),
            ),
            const PopupMenuItem(
              value: ThemeMode.system,
              child: Text('Podľa systému'),
            ),
          ],
        ),
        IconButton(
          tooltip: 'Obnoviť administráciu',
          onPressed: loading ? null : () => load(),
          icon: Icon(AppIcons.refresh),
        ),
      ],
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          AppText(
            'Dobrá platforma. Pod kontrolou.',
            style: context.text.headlineLarge,
          ),
          const SizedBox(height: 12),
          const AppText(
            'Správa partnerov, obsahu a prístupov s dohľadateľnou históriou.',
          ),
          const SizedBox(height: 24),
          if (!store.signedIn) ...[
            PrimaryButton(
              'Prihlásiť sa ako správca',
              onPressed: () => pushPage(context, const AuthScreen()),
            ),
            if (store.demoShowcase)
              TextButton(
                onPressed: () => showDemoPicker(context),
                child: const Text('Otvoriť pripravené demo'),
              ),
          ] else if (store.platformRole == null) ...[
            const AppText('Tvoj účet nemá administrátorskú rolu.'),
            if (store.demoShowcase)
              TextButton(
                onPressed: () => showDemoPicker(context),
                child: const Text('Prepnúť demo profil'),
              ),
          ] else ...[
            if (overview != null)
              LayoutBuilder(
                builder: (context, size) => Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final e in {
                      'users': 'Používatelia',
                      'organizations': 'Firmy',
                      'stores': 'Pobočky',
                      'offers': 'Ponuky',
                      'reviews': 'Recenzie',
                      'openTickets': 'Otvorená podpora',
                    }.entries)
                      SizedBox(
                        width: size.maxWidth < 600
                            ? (size.maxWidth - 12) / 2
                            : (size.maxWidth - 24) / 3,
                        child: SurfaceCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              AppText(
                                '${overview![e.key]}',
                                style: context.text.headlineMedium,
                              ),
                              const SizedBox(height: 8),
                              AppText(e.value),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final e in platformSections.entries)
                  if (store.platformRole != 'moderator' ||
                      {'offers', 'reviews'}.contains(e.key))
                    ChoiceChip(
                      label: Text(e.value),
                      selected: section == e.key,
                      onSelected: loading
                          ? null
                          : (_) {
                              setState(() {
                                section = e.key;
                                cursor = null;
                                rows = [];
                                query = '';
                              });
                              load();
                            },
                    ),
              ],
            ),
            const SizedBox(height: 20),
            TextField(
              key: ValueKey('platform-search-$section'),
              decoration: const InputDecoration(
                labelText: 'Hľadať v aktuálnej časti',
              ),
              onChanged: (value) {
                query = value;
                timer?.cancel();
                timer = Timer(const Duration(milliseconds: 350), () => load());
              },
            ),
            const SizedBox(height: 20),
            if (error != null)
              AppText(error!, style: TextStyle(color: context.colors.warning)),
            if (loading) const LinearProgressIndicator(),
            if (rows.isEmpty && !loading)
              const AppText('Pre tento výber nie sú záznamy.'),
            for (final row in rows)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: SurfaceCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AppText(
                        title(row),
                        style: context.text.titleMedium,
                        maxLines: 3,
                      ),
                      const SizedBox(height: 8),
                      if (row['email'] != null) AppText(row['email'] as String),
                      if (row['status'] != null)
                        TagPill(row['status'] as String),
                      if (row['role'] != null) TagPill(row['role'] as String),
                      if (row['moderation'] != null)
                        TagPill(row['moderation'] as String),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ...actions(row),
                          TextButton(
                            onPressed: () => showDialog<void>(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: const Text('Podrobnosti záznamu'),
                                content: SingleChildScrollView(
                                  child: SelectableText(
                                    const JsonEncoder.withIndent(
                                      '  ',
                                    ).convert(row),
                                  ),
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(context),
                                    child: const Text('Zavrieť'),
                                  ),
                                ],
                              ),
                            ),
                            child: const Text('Podrobnosti'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            if (cursor != null)
              OutlinedButton(
                onPressed: loading ? null : () => load(more: true),
                child: const Text('Načítať ďalšie záznamy'),
              ),
          ],
          if (widget.onExit != null)
            TextButton(
              onPressed: widget.onExit,
              child: const Text('Späť do aplikácie'),
            ),
        ],
      ),
    );
  }
}

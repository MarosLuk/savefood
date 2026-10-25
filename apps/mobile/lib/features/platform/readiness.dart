import 'dart:async';
import 'package:flutter/material.dart';
import 'package:design_system/design_system.dart';
import '../../state/app_store.dart';
import '../../widgets/common.dart';

class PlatformReadinessScreen extends StatefulWidget {
  const PlatformReadinessScreen({super.key});
  @override
  State<PlatformReadinessScreen> createState() =>
      _PlatformReadinessScreenState();
}

class _PlatformReadinessScreenState extends State<PlatformReadinessScreen> {
  Map<String, dynamic>? data;
  String? error;
  bool loading = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(load());
    });
  }

  Future<void> load() async {
    if (loading) return;
    setState(() => loading = true);
    try {
      final result = await StoreScope.of(
        context,
      ).api!.request('GET', '/v1/platform/readiness');
      if (mounted) {
        setState(() {
          data = result;
          error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => ScreenScaffold(
    title: 'Prevádzka a pripravenosť',
    actions: [
      IconButton(
        tooltip: 'Obnoviť kontroly',
        onPressed: loading ? null : load,
        icon: Icon(AppIcons.refresh),
      ),
    ],
    child: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        AppText('Prevádzka pod dohľadom.', style: context.text.headlineMedium),
        const SizedBox(height: 12),
        const AppText(
          'Kontroly konfigurácie a frontov. Aktiváciu externých služieb treba overiť aj doručovacím alebo integračným testom.',
        ),
        const SizedBox(height: 24),
        if (loading) const LinearProgressIndicator(),
        if (error != null) AppText(error!),
        if (data != null) ...[
          TagPill(
            data!['launchReady'] == true
                ? 'Produkčná konfigurácia je vyplnená'
                : 'Produkčná konfigurácia čaká na doplnenie',
          ),
          const SizedBox(height: 16),
          for (final c in data!['checks'] as List)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: SurfaceCard(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      c['ok'] == true ? AppIcons.checkCircle : AppIcons.info,
                      color: c['ok'] == true
                          ? context.colors.blue
                          : context.colors.warning,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: AppText(
                        '${c['label']}\n${c['ok'] == true
                            ? 'Vyplnené / dostupné'
                            : c['required'] == true
                            ? 'Vyžaduje doplnenie'
                            : 'Voliteľné alebo odložené'}',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 20),
          AppText('Fronty a dostupnosť', style: context.text.titleLarge),
          const SizedBox(height: 12),
          AppText(
            'Čakajúce doklady: ${data!['documentsPending']}\nRefundácie na kontrolu: ${data!['refundsPending']}\nPrevádzka: ${data!['uptimeSeconds']} s',
          ),
          for (final m in data!['mail'] as List)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: AppText('E-mail · ${m['status']}'),
              trailing: AppText('${m['count']}'),
            ),
          const SizedBox(height: 20),
          AppText('Požiadavky API od štartu', style: context.text.titleLarge),
          for (final e in (data!['requests'] as Map).entries)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: AppText(e.key as String),
              subtitle: AppText(
                '${e.value['count']} požiadaviek · priemer ${((e.value['totalMs'] as num) / (e.value['count'] as num)).toStringAsFixed(1)} ms · maximum ${(e.value['maxMs'] as num).toStringAsFixed(1)} ms',
              ),
            ),
        ],
      ],
    ),
  );
}

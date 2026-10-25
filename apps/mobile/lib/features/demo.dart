import 'package:flutter/material.dart';
import 'package:design_system/design_system.dart';
import 'package:marketplace_data/marketplace_data.dart';
import '../state/app_store.dart';
import '../widgets/common.dart';

/// The API advertises this entry only for an explicitly enabled sandbox.
Future<DemoPersona?> showDemoPicker(BuildContext context) {
  final store = StoreScope.of(context);
  return showModalBottomSheet<DemoPersona>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: 860),
    builder: (_) => _DemoPicker(store: store),
  );
}

class DemoAccessCard extends StatelessWidget {
  const DemoAccessCard({super.key, required this.onPressed});
  final VoidCallback onPressed;
  @override
  Widget build(BuildContext context) => SurfaceCard(
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
              AppText('Vyskúšaj plné demo.', style: context.text.titleLarge),
              const SizedBox(height: 8),
              const AppText(
                'Pripravené účty, fotografie a živý sklad. Vyber si zákazníčku, pekáreň, bistro, obchod alebo pracovisko podpory.',
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: onPressed,
                child: const Text('Otvoriť pripravené demo'),
              ),
              const SizedBox(height: 8),
              AppText(
                'Fiktívne údaje · bez skutočných platieb',
                style: context.text.bodySmall,
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _DemoPicker extends StatefulWidget {
  const _DemoPicker({required this.store});
  final AppStore store;
  @override
  State<_DemoPicker> createState() => _DemoPickerState();
}

class _DemoPickerState extends State<_DemoPicker> {
  String? busy, error;
  Future<void> choose(DemoPersona persona) async {
    if (busy != null) return;
    setState(() {
      busy = persona.id;
      error = null;
    });
    try {
      await widget.store.enterDemo(persona.id);
      if (mounted) Navigator.pop(context, persona);
    } catch (e) {
      if (mounted) {
        setState(() {
          error = e.toString();
          busy = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: busy == null,
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: AppText(
                  'Každá rola. Jedna druhá šanca.',
                  style: context.text.headlineSmall,
                ),
              ),
              IconButton(
                tooltip: 'Zavrieť',
                onPressed: busy == null ? () => Navigator.pop(context) : null,
                icon: Icon(AppIcons.close),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const AppText(
            'Otvor pripravený profil a prejdi si celý príbeh od ponuky až po výdaj. Zmeny sa ukladajú v spoločnom demo sklade.',
          ),
          const SizedBox(height: 20),
          LayoutBuilder(
            builder: (context, size) {
              final columns = size.maxWidth >= 580 ? 2 : 1;
              final width = (size.maxWidth - (columns - 1) * 16) / columns;
              return Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  for (final p in demoPersonas)
                    SizedBox(
                      width: width,
                      child: Semantics(
                        button: true,
                        label: 'Otvoriť demo: ${p.title}',
                        excludeSemantics: true,
                        child: Material(
                          color: context.colors.surface,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(22),
                            side: BorderSide(color: context.colors.line),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: busy == null ? () => choose(p) : null,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Stack(
                                  children: [
                                    FoodPhoto(
                                      p.image,
                                      width: width,
                                      height: 125,
                                    ),
                                    Positioned(
                                      left: 12,
                                      top: 12,
                                      child: TagPill(
                                        p.id == 'support'
                                            ? 'PODPORA'
                                            : p.merchant
                                            ? 'PREDAJCA'
                                            : 'ZÁKAZNÍK',
                                        background: const Color(0xFFF8FAFF),
                                        color: const Color(0xFF175DCE),
                                      ),
                                    ),
                                  ],
                                ),
                                Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: AppText(
                                              p.title,
                                              style: context.text.titleMedium,
                                            ),
                                          ),
                                          if (busy == p.id)
                                            const SizedBox(
                                              width: 18,
                                              height: 18,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                              ),
                                            )
                                          else
                                            Icon(
                                              AppIcons.arrowRight,
                                              color: context.colors.blue,
                                              size: 20,
                                            ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      AppText(
                                        p.description,
                                        style: context.text.bodySmall,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: AppText(
                error!,
                style: TextStyle(color: context.colors.warning),
              ),
            ),
          const SizedBox(height: 20),
          AppText(
            'DEMO · Fiktívne prevádzky a ilustračné fotografie. Žiadna platba sa nestrhne. Prepnutie profilu vyprázdni košík.',
            style: context.text.bodySmall,
          ),
        ],
      ),
    ),
  );
}

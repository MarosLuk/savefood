import 'package:flutter/material.dart';
import 'package:design_system/design_system.dart';
import '../state/app_store.dart';
import '../widgets/common.dart';
import 'account.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, this.replay = false});
  final bool replay;
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final controller = PageController();
  int index = 0;
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void finish() {
    if (widget.replay) {
      Navigator.pop(context);
    } else {
      StoreScope.of(context).completeOnboarding();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    const slides = [
      (
        image: 'bakery',
        eyebrow: 'DOBRÉ JEDLO. DRUHÁ ŠANCA.',
        title: 'Príliš dobré\nna vyhodenie.',
        body:
            'Objav chutné balíčky z miest v tvojom okolí. Za zlomok ceny a s dobrým pocitom navyše.',
        icon: 'bag',
      ),
      (
        image: 'toast',
        eyebrow: 'MALÝ KROK. VEĽKÁ CHUŤ.',
        title: 'Vyber. Vyzdvihni.\nVychutnaj.',
        body:
            'Rezervuj si balíček s prekvapením, príď v určenom čase a vezmi si dobroty so sebou.',
        icon: 'clock',
      ),
      (
        image: 'vegetables',
        eyebrow: 'DOBRÉ PRE TEBA AJ PLANÉTU.',
        title: 'Každá záchrana\nsa počíta.',
        body:
            'Menej vyhodeného jedla. Viac malých radostí. Začni už dnes — svojím prvým balíčkom.',
        icon: 'leaf',
      ),
    ];
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 580),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 14, 16, 18),
                  child: Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: c.blue,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          AppIcons.leaf,
                          size: 20,
                          color: Theme.of(context).brightness == Brightness.dark
                              ? const Color(0xFF10233E)
                              : Colors.white,
                        ),
                      ),
                      const SizedBox(width: 9),
                      AppText(
                        'Save Food',
                        style: context.text.titleLarge?.copyWith(
                          letterSpacing: -.8,
                        ),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: finish,
                        child: AppText(widget.replay ? 'Zavrieť' : 'Preskočiť'),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: PageView.builder(
                    controller: controller,
                    itemCount: slides.length,
                    onPageChanged: (i) => setState(() => index = i),
                    itemBuilder: (context, i) {
                      final slide = slides[i];
                      return SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(32),
                              child: SizedBox(
                                height: MediaQuery.sizeOf(context).height * .36,
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    FoodPhoto(slide.image),
                                    const DecoratedBox(
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          begin: Alignment.topCenter,
                                          end: Alignment.bottomCenter,
                                          colors: [
                                            Colors.transparent,
                                            Color(0x66172235),
                                          ],
                                        ),
                                      ),
                                    ),
                                    Positioned(
                                      left: 20,
                                      bottom: 20,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 14,
                                          vertical: 10,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius: BorderRadius.circular(
                                            30,
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            Icon(
                                              AppIcons.sparkle,
                                              size: 16,
                                              color: const Color(0xFF1765E8),
                                            ),
                                            const SizedBox(width: 8),
                                            const AppText(
                                              'Viac chuti. Menej plytvania.',
                                              style: TextStyle(
                                                color: Color(0xFF17243B),
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 28),
                            AppText(
                              slide.eyebrow,
                              style: TextStyle(
                                color: c.blue,
                                fontSize: 10,
                                letterSpacing: 1.3,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 12),
                            AppText(
                              slide.title,
                              style: context.text.displaySmall,
                            ),
                            const SizedBox(height: 16),
                            AppText(
                              slide.body,
                              style: context.text.bodyLarge?.copyWith(
                                color: c.muted,
                              ),
                            ),
                            const SizedBox(height: 18),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 14, 24, 20),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(
                          3,
                          (i) => AnimatedContainer(
                            duration: MediaQuery.disableAnimationsOf(context)
                                ? Duration.zero
                                : const Duration(milliseconds: 180),
                            margin: const EdgeInsets.symmetric(horizontal: 3),
                            width: i == index ? 24 : 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: i == index ? c.blue : c.line,
                              borderRadius: BorderRadius.circular(5),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 22),
                      PrimaryButton(
                        index == 2 ? 'Objaviť balíčky' : 'Ďalej',
                        icon: AppIcons.arrowRight,
                        onPressed: () {
                          if (index == 2) {
                            finish();
                          } else {
                            controller.nextPage(
                              duration: MediaQuery.disableAnimationsOf(context)
                                  ? Duration.zero
                                  : const Duration(milliseconds: 250),
                              curve: Curves.easeOutCubic,
                            );
                          }
                        },
                      ),
                      if (!widget.replay)
                        TextButton(
                          onPressed: () =>
                              pushPage(context, const AuthScreen()),
                          child: const AppText(
                            'Máš chuť sa najskôr prihlásiť?',
                          ),
                        ),
                      AppText(
                        StoreScope.of(context).isDemo
                            ? 'Ukážkový režim · Bez skutočných platieb'
                            : 'Dobré jedlo. Druhá šanca.',
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
    );
  }
}

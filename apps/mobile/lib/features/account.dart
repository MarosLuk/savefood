import 'package:flutter/material.dart';
import 'package:design_system/design_system.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:marketplace_domain/marketplace_domain.dart';
import '../state/app_store.dart';
import '../widgets/common.dart';
import 'commerce.dart';
import 'orders.dart';
import 'onboarding.dart';
import 'merchant/portal.dart';
import 'demo.dart';
import 'support/support.dart';
import 'account_security.dart';
import 'merchant/team.dart';
import 'platform/admin.dart';
import 'legal.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final c = context.colors;
    final initials = store.name
        .trim()
        .split(' ')
        .where((s) => s.isNotEmpty)
        .take(2)
        .map((s) => s[0])
        .join()
        .toUpperCase();
    return ScreenScaffold(
      title: 'Tvoj dobrý profil',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        children: [
          Row(
            children: [
              Container(
                width: 66,
                height: 66,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: c.tint,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: initials.isEmpty
                    ? Icon(AppIcons.user, size: 32, color: c.blue)
                    : AppText(
                        initials,
                        style: context.text.headlineMedium?.copyWith(
                          color: c.blue,
                        ),
                      ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppText(
                      store.signedIn ? store.name : 'Ahoj, záchranca.',
                      style: context.text.titleLarge,
                    ),
                    const SizedBox(height: 5),
                    AppText(
                      store.signedIn
                          ? store.email
                          : 'Niečo dobré začína pri tebe.',
                      style: context.text.bodySmall,
                    ),
                    const SizedBox(height: 6),
                    if (store.isMember)
                      TagPill('Člen Klubu', icon: AppIcons.crown),
                  ],
                ),
              ),
              if (store.signedIn)
                IconButton(
                  tooltip: context.tr('Upraviť profil'),
                  onPressed: () => pushPage(context, const AuthScreen()),
                  icon: Icon(AppIcons.edit, size: 20),
                ),
            ],
          ),
          const SizedBox(height: 24),
          if (!store.signedIn) ...[
            PrimaryButton(
              store.remoteEnabled
                  ? 'Prihlásiť sa alebo vytvoriť účet'
                  : 'Vytvoriť demo profil',
              onPressed: () => pushPage(context, const AuthScreen()),
            ),
            const SizedBox(height: 24),
          ],
          if (store.demoShowcase) ...[
            DemoAccessCard(
              onPressed: () async {
                final persona = await showDemoPicker(context);
                if (persona?.merchant == true && context.mounted) {
                  await pushPage(context, const MerchantPortalScreen());
                  await store.refreshRemote();
                } else if (persona?.id == 'support' && context.mounted) {
                  await pushPage(context, const SupportScreen());
                }
              },
            ),
            const SizedBox(height: 24),
          ],
          Row(
            children: [
              Expanded(
                child: _Stat(
                  value: '${store.rescued}',
                  label: 'zachránených balíčkov',
                  icon: AppIcons.bag,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _Stat(
                  value: euro(store.savedMoney),
                  label: 'ušetrené pri záchrane',
                  icon: AppIcons.wallet,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          SurfaceCard(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
            child: Column(
              children: [
                SettingsRow(
                  icon: AppIcons.bag,
                  title: 'Moje objednávky',
                  subtitle: '${store.activeOrders.length} aktívnych rezervácií',
                  onTap: () => pushPage(context, const OrdersScreen()),
                ),
                SettingsRow(
                  icon: AppIcons.wallet,
                  title: 'Môj kredit',
                  subtitle: euro(store.credit),
                  onTap: () => pushPage(context, const WalletScreen()),
                ),
                SettingsRow(
                  icon: AppIcons.crown,
                  title: 'Save Food Klub',
                  subtitle: store.isMember
                      ? 'Aktívne do ${shortDate(store.memberUntil!)}'
                      : 'Malé členstvo. Viac dobrého.',
                  accent: true,
                  onTap: () => pushPage(context, const ClubScreen()),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SurfaceCard(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
            child: Column(
              children: [
                SettingsRow(
                  icon: AppIcons.store,
                  title: 'Moja prevádzka',
                  subtitle: 'Ponuky, sklad a automatické balíčky',
                  onTap: () async {
                    await pushPage(context, const MerchantPortalScreen());
                    await store.refreshRemote();
                  },
                ),
                SettingsRow(
                  icon: AppIcons.settings,
                  title: 'Nastavenia',
                  onTap: () => pushPage(context, const SettingsScreen()),
                ),
                SettingsRow(
                  icon: AppIcons.receipt,
                  title: 'Fakturačné údaje',
                  onTap: () => pushPage(context, const InvoiceScreen()),
                ),
                SettingsRow(
                  icon: AppIcons.help,
                  title: 'Pomoc a odpovede',
                  onTap: () => pushPage(context, const HelpScreen()),
                ),
                SettingsRow(
                  icon: AppIcons.ticket,
                  title: 'Požiadavky a zákaznícka podpora',
                  subtitle: 'Správy, reklamácie a priebeh riešenia',
                  onTap: () => pushPage(context, const SupportScreen()),
                ),
                SettingsRow(
                  icon: AppIcons.language,
                  title: 'Jazyk aplikácie',
                  subtitle: store.language == 'sk' ? 'Slovenčina' : 'English',
                  onTap: () => showLanguageSheet(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          SurfaceCard(
            color: c.tint,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(AppIcons.leaf, color: c.blue, size: 20),
                    const SizedBox(width: 9),
                    AppText(
                      'Dobrý začiatok',
                      style: context.text.titleMedium?.copyWith(color: c.blue),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                const AppText(
                  'Zachrániť jedlo je jednoduchšie, než si myslíš. Stačia tri malé kroky.',
                ),
                TextButton(
                  onPressed: () =>
                      pushPage(context, const OnboardingScreen(replay: true)),
                  child: const AppText('Ako to funguje'),
                ),
              ],
            ),
          ),
          if (store.signedIn)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: TextButton(
                onPressed: () async {
                  await store.signOut();
                  if (!context.mounted) return;
                  notice(context, 'Profil je odhlásený.');
                },
                child: AppText(
                  store.remoteEnabled ? 'Odhlásiť sa' : 'Odhlásiť demo profil',
                ),
              ),
            ),
          const SizedBox(height: 24),
          AppText(
            StoreScope.of(context).isDemo
                ? 'Save Food 1.0 · Vytvorené pre druhé šance\nUkážkový režim bez skutočných platieb'
                : 'Save Food 1.0 · Vytvorené pre druhé šance',
            textAlign: TextAlign.center,
            style: context.text.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label, required this.icon});
  final String value, label;
  final IconData icon;
  @override
  Widget build(BuildContext context) => SurfaceCard(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: context.colors.blue, size: 20),
        const SizedBox(height: 14),
        AppText(value, style: context.text.titleLarge),
        const SizedBox(height: 5),
        AppText(label, style: context.text.bodySmall),
      ],
    ),
  );
}

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final en = store.language == 'en';
    return ScreenScaffold(
      title: en ? 'Settings' : 'Nastavenia',
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          AppText(
            en ? 'Make yourself at home.' : 'Nech sa ti tu páči.',
            style: context.text.headlineMedium,
          ),
          const SizedBox(height: 24),
          AppText(
            en ? 'Appearance' : 'Vzhľad aplikácie',
            style: context.text.titleLarge,
          ),
          const SizedBox(height: 12),
          SurfaceCard(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            child: RadioGroup<ThemeMode>(
              groupValue: store.themeMode,
              onChanged: (mode) {
                if (mode != null) store.setTheme(mode);
              },
              child: Column(
                children: [
                  for (final mode in ThemeMode.values)
                    RadioListTile<ThemeMode>(
                      value: mode,
                      title: Row(
                        children: [
                          Icon(
                            switch (mode) {
                              ThemeMode.system => AppIcons.device,
                              ThemeMode.light => AppIcons.sun,
                              ThemeMode.dark => AppIcons.moon,
                            },
                            size: 20,
                            color: context.colors.blue,
                          ),
                          const SizedBox(width: 12),
                          Flexible(
                            child: AppText(switch (mode) {
                              ThemeMode.system =>
                                en ? 'Use system setting' : 'Podľa systému',
                              ThemeMode.light => en ? 'Light' : 'Svetlý',
                              ThemeMode.dark => en ? 'Dark' : 'Tmavý',
                            }),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 28),
          AppText(
            en ? 'Good news, your way' : 'Dobré správy podľa teba',
            style: context.text.titleLarge,
          ),
          const SizedBox(height: 12),
          SurfaceCard(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            child: Column(
              children: [
                SwitchListTile.adaptive(
                  applyCupertinoTheme: true,
                  title: AppText(
                    en ? 'Favorites back in stock' : 'Obľúbené opäť v ponuke',
                  ),
                  subtitle: AppText(
                    en
                        ? 'Remember my preference'
                        : 'Keď sa objaví tvoj obľúbený balíček',
                  ),
                  value: store.favoriteAlerts,
                  onChanged: (v) => store.preferences(favorites: v),
                ),
                SwitchListTile.adaptive(
                  applyCupertinoTheme: true,
                  title: AppText(
                    en ? 'Support replies' : 'Správy zákazníckej podpory',
                  ),
                  subtitle: AppText(
                    en
                        ? 'Notifications about your requests'
                        : 'Upozornenie na odpoveď a priebeh požiadavky',
                  ),
                  value: store.supportAlerts,
                  onChanged: (v) => store.preferences(support: v),
                ),
                SwitchListTile.adaptive(
                  title: const AppText('E-maily o objednávkach a podpore'),
                  subtitle: const AppText(
                    'Bezpečnostné správy účtu sa posielajú vždy.',
                  ),
                  value: store.emailNotifications,
                  onChanged: (v) => store.preferences(emailUpdates: v),
                ),
                SwitchListTile.adaptive(
                  applyCupertinoTheme: true,
                  title: AppText(
                    en ? 'Pickup reminders' : 'Pripomienka vyzdvihnutia',
                  ),
                  value: store.pickupReminders,
                  onChanged: (v) => store.preferences(reminders: v),
                ),
                SwitchListTile.adaptive(
                  applyCupertinoTheme: true,
                  title: AppText(
                    en
                        ? 'News and special offers'
                        : 'Novinky a špeciálne ponuky',
                  ),
                  subtitle: AppText(
                    en
                        ? 'Optional marketing consent'
                        : 'Dobrovoľný marketingový súhlas',
                  ),
                  value: store.marketing,
                  onChanged: (v) => store.preferences(news: v),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          AppText(
            en
                ? 'Preferences are saved on this device. Push delivery needs a connected notification service.'
                : 'Voľby sa ukladajú do zariadenia. Doručovanie push upozornení potrebuje napojenú notifikačnú službu.',
            style: context.text.bodySmall,
          ),
          const SizedBox(height: 28),
          if (store.remoteEnabled && store.signedIn) ...[
            SettingsRow(
              icon: AppIcons.ticket,
              title: 'Prijať pozvánku do prevádzky',
              onTap: () => pushPage(context, const MerchantInviteScreen()),
            ),
            SettingsRow(
              icon: AppIcons.shield,
              title: 'Bezpečnosť a údaje účtu',
              subtitle: store.emailVerified
                  ? 'E-mail overený'
                  : 'Overenie e-mailu a správa účtu',
              onTap: () => pushPage(context, const AccountSecurityScreen()),
            ),
            const SizedBox(height: 20),
          ],
          AppText(en ? 'Privacy' : 'Súkromie', style: context.text.titleLarge),
          const SizedBox(height: 12),
          SurfaceCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                SwitchListTile.adaptive(
                  applyCupertinoTheme: true,
                  title: AppText(
                    en ? 'Help improve the app' : 'Pomôcť zlepšovať aplikáciu',
                  ),
                  subtitle: AppText(
                    en
                        ? 'Optional analytics preference'
                        : 'Dobrovoľné analytické údaje',
                  ),
                  value: store.analytics,
                  onChanged: (v) => store.preferences(statistics: v),
                ),
                SettingsRow(
                  icon: AppIcons.shield,
                  title: en
                      ? 'Privacy and local data'
                      : 'Ochrana súkromia a lokálne dáta',
                  onTap: () => pushPage(context, const PrivacyScreen()),
                ),
                if (store.platformRole != null)
                  SettingsRow(
                    icon: AppIcons.settings,
                    title: 'Administrácia platformy',
                    onTap: () => pushPage(context, const PlatformAdminScreen()),
                  ),
                SettingsRow(
                  icon: AppIcons.language,
                  title: en ? 'Language' : 'Jazyk',
                  subtitle: store.language == 'sk' ? 'Slovenčina' : 'English',
                  onTap: () => showLanguageSheet(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          AppText(
            en
                ? 'No analytics or advertising SDK is active in this demo.'
                : 'V tomto deme nie je aktívne analytické ani reklamné SDK.',
            style: context.text.bodySmall,
          ),
        ],
      ),
    );
  }
}

void showLanguageSheet(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  useSafeArea: true,
  builder: (context) {
    final store = StoreScope.of(context);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: RadioGroup<String>(
          groupValue: store.language,
          onChanged: (value) {
            if (value != null) store.setLanguage(value);
            Navigator.pop(context);
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SheetHeading('Jazyk / Language'),
              for (final entry in {'sk': 'Slovenčina', 'en': 'English'}.entries)
                RadioListTile<String>(
                  title: AppText(entry.value),
                  value: entry.key,
                ),
              const SizedBox(height: 8),
              AppText(
                'Ponuky prevádzok zostávajú v pôvodnom jazyku.',
                style: context.text.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  },
);

class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});
  @override
  Widget build(BuildContext context) => StoreScope.of(context).remoteEnabled
      ? const LegalScreen()
      : ScreenScaffold(
          title: 'Tvoje súkromie',
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Icon(AppIcons.shield, size: 48, color: context.colors.blue),
              const SizedBox(height: 24),
              AppText(
                'Tvoje dáta. Tvoja voľba.',
                style: context.text.headlineMedium,
              ),
              const SizedBox(height: 20),
              AppText(
                StoreScope.of(context).remoteEnabled
                    ? 'Profil, fakturačné údaje, objednávky, kredit a obľúbené sa synchronizujú s naším serverom. Prihlásenie je uložené v zabezpečenom úložisku zariadenia. Pri skutočnej platbe sa údaje spracúvajú cez Stripe; číslo tvojej karty aplikácia neukladá.'
                    : 'Toto je lokálna ukážka. Profil, fakturačné údaje, objednávky, kredit, obľúbené a nastavenia sa ukladajú do tohto zariadenia. Žiadne platby sa neúčtujú.',
              ),
              const SizedBox(height: 20),
              const AppText(
                'Poloha sa zisťuje iba po tvojom ťuknutí na „Použiť moju polohu“. Aplikácia nepoužíva sledovanie na pozadí. Mapové podklady sa načítavajú zo služby OpenStreetMap alebo nakonfigurovaného poskytovateľa; poskytovatelia pri tom spracúvajú bežné údaje sieťového pripojenia.',
              ),
              const SizedBox(height: 20),
              const AppText(
                'Analytické a marketingové súhlasy sú dobrovoľné a môžeš ich kedykoľvek zmeniť v nastaveniach. Analytické ani reklamné SDK sa nepoužíva. Ak zapneš upozornenia na obľúbené, nakonfigurovaná služba Firebase spracuje identifikátor zariadenia na doručovanie správ. Upozornenia môžeš vypnúť.',
              ),
              const SizedBox(height: 20),
              const AppText(
                'Pred produkčným spustením sa doplní prevádzkovateľ, konkrétni sprostredkovatelia, retenčné doby, právne základy a kontaktné údaje. Tento text nepredstavuje produkčné obchodné podmienky.',
              ),
            ],
          ),
        );
}

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final form = GlobalKey<FormState>();
  final name = TextEditingController(),
      email = TextEditingController(),
      password = TextEditingController();
  bool initialized = false, register = false, busy = false, obscure = true;
  String? error;
  @override
  void dispose() {
    name.dispose();
    email.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (!form.currentState!.validate()) return;
    final store = StoreScope.of(context);
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (store.remoteEnabled && store.signedIn) {
        await store.api!.updateProfile({'name': name.text.trim()});
        await store.refreshRemote();
      } else {
        Map<String, dynamic>? consent;
        if (register && store.remoteEnabled) {
          consent = await showLegalConsent(context);
          if (consent == null) return;
        }
        await store.authenticate(
          name: name.text,
          email: email.text,
          password: password.text,
          register: register,
          legalConsent: consent,
        );
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> oauth(String provider) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final store = StoreScope.of(context);
      if (store.firebaseProviderEnabled(provider)) {
        final completed = await store.authenticateSocial(
          provider,
          requestConsent: () async {
            if (!mounted) return null;
            return showLegalConsent(context);
          },
        );
        if (completed && mounted) Navigator.pop(context);
        return;
      }
      final url = await store.beginOAuth(provider);
      if (!await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      )) {
        throw StateError('Prihlásenie sa nepodarilo otvoriť.');
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final remote = store.remoteEnabled, editing = remote && store.signedIn;
    if (!initialized) {
      name.text = store.name;
      email.text = store.email;
      initialized = true;
    }
    return ScreenScaffold(
      title: editing
          ? 'Tvoj profil'
          : remote
          ? 'Vitaj medzi nami'
          : 'Tvoj demo profil',
      bottom: PrimaryButton(
        editing
            ? 'Uložiť profil'
            : !remote
            ? 'Uložiť demo profil'
            : register
            ? 'Vytvoriť účet'
            : 'Prihlásiť sa',
        busy: busy,
        onPressed: submit,
      ),
      child: Form(
        key: form,
        child: AutofillGroup(
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: const FoodPhoto('toast', height: 170),
              ),
              const SizedBox(height: 26),
              AppText(
                editing ? 'Tvoje dobré meno.' : 'Je dobré ťa tu mať.',
                style: context.text.headlineLarge,
              ),
              const SizedBox(height: 10),
              AppText(
                remote
                    ? 'Tvoje obľúbené miesta a záchrany s tebou pôjdu aj do ďalšieho zariadenia.'
                    : 'Na prezeranie nepotrebuješ účet. Demo profil zostane iba v tomto zariadení.',
                style: context.text.bodyLarge?.copyWith(
                  color: context.colors.muted,
                ),
              ),
              const SizedBox(height: 24),
              if (!remote || register || editing) ...[
                TextFormField(
                  controller: name,
                  autofillHints: const [AutofillHints.name],
                  decoration: InputDecoration(
                    labelText: context.tr('Meno a priezvisko'),
                  ),
                  validator: (v) =>
                      (v?.trim().length ?? 0) < 2 ? 'Zadaj svoje meno.' : null,
                ),
                const SizedBox(height: 16),
              ],
              TextFormField(
                controller: email,
                readOnly: editing,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                decoration: InputDecoration(labelText: context.tr('E-mail')),
                validator: (v) =>
                    RegExp(
                      r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                    ).hasMatch(v?.trim() ?? '')
                    ? null
                    : 'Zadaj platný e-mail.',
              ),
              if (remote && !editing) ...[
                const SizedBox(height: 16),
                TextFormField(
                  controller: password,
                  obscureText: obscure,
                  autofillHints: [
                    register
                        ? AutofillHints.newPassword
                        : AutofillHints.password,
                  ],
                  decoration: InputDecoration(
                    labelText: context.tr('Heslo'),
                    helperText: register ? 'Aspoň 12 znakov' : null,
                    suffixIcon: IconButton(
                      tooltip: obscure ? 'Zobraziť heslo' : 'Skryť heslo',
                      onPressed: () => setState(() => obscure = !obscure),
                      icon: Icon(
                        obscure ? AppIcons.eye : AppIcons.eyeClosed,
                        size: 20,
                      ),
                    ),
                  ),
                  validator: (v) => v == null || v.length < (register ? 12 : 1)
                      ? 'Skontroluj heslo.'
                      : null,
                ),
                const SizedBox(height: 12),
                if (!register)
                  TextButton(
                    onPressed: busy
                        ? null
                        : () => pushPage(
                            context,
                            const AccountActionScreen(purpose: 'reset'),
                          ),
                    child: const AppText('Zabudnuté heslo'),
                  ),
                TextButton(
                  onPressed: busy
                      ? null
                      : () => setState(() {
                          register = !register;
                          error = null;
                        }),
                  child: AppText(
                    register
                        ? 'Už mám účet. Prihlásiť sa'
                        : 'Ešte nemám účet. Vytvoriť účet',
                  ),
                ),
              ],
              if (error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: AppText(
                    error!,
                    style: TextStyle(color: context.colors.warning),
                  ),
                ),
              if (remote && !editing)
                for (final provider in ['apple', 'google', 'facebook'])
                  if (store.firebaseProviderEnabled(provider) ||
                      (store.serverConfig['providers'] as Map?)?[provider] ==
                          true)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: OutlinedButton(
                        onPressed: busy ? null : () => oauth(provider),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 52),
                        ),
                        child: AppText(
                          'Pokračovať cez ${provider[0].toUpperCase()}${provider.substring(1)}',
                        ),
                      ),
                    ),
              if (store.pendingOAuth != null) ...[
                const SizedBox(height: 16),
                PrimaryButton(
                  'Dokončiť prihlásenie',
                  secondary: true,
                  onPressed: () async {
                    try {
                      if (await store.finishOAuth()) {
                        if (context.mounted) Navigator.pop(context);
                      } else {
                        if (context.mounted) {
                          notice(
                            context,
                            'Najskôr dokonči prihlásenie v okne poskytovateľa.',
                          );
                        }
                      }
                    } catch (e) {
                      if (mounted) setState(() => error = e.toString());
                    }
                  },
                ),
              ],
              const SizedBox(height: 24),
              AppText(
                remote
                    ? 'Na prezeranie ponúk sa prihlasovať nemusíš.'
                    : 'Demo profil neoveruje tvoju identitu a nezakladá vzdialený účet.',
                style: context.text.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ClubScreen extends StatefulWidget {
  const ClubScreen({super.key});
  @override
  State<ClubScreen> createState() => _ClubScreenState();
}

class _ClubScreenState extends State<ClubScreen> {
  final coupon = TextEditingController();
  bool hasCoupon = false;
  String? error;
  @override
  void dispose() {
    coupon.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final c = context.colors;
    final plan = store.serverConfig['clubPlan'] as Map?;
    final price = plan == null
        ? ''
        : '${euro(plan['amount'] as int)} / ${plan['interval'] == 'year' ? 'rok' : 'mesiac'}';
    return ScreenScaffold(
      title: 'Save Food Klub',
      bottom: store.isMember
          ? PrimaryButton(
              'Klub je aktívny do ${shortDate(store.memberUntil!)}',
              secondary: true,
              icon: AppIcons.checkCircle,
              onPressed: () => Navigator.pop(context),
            )
          : PrimaryButton(
              store.trialUsed
                  ? (plan == null
                        ? 'Skúšobné členstvo už bolo využité'
                        : 'Aktivovať Klub · $price')
                  : 'Vyskúšať Klub bez platby',
              icon: AppIcons.crown,
              onPressed: store.trialUsed && plan == null
                  ? null
                  : () async {
                      if (store.remoteEnabled && !store.signedIn) {
                        await pushPage(context, const AuthScreen());
                        return;
                      }
                      if (store.trialUsed && plan != null) {
                        try {
                          final response = await store.api!.request(
                            'POST',
                            '/v1/club/checkout',
                            body: {},
                          );
                          await launchUrl(
                            Uri.parse(response['url'] as String),
                            mode: LaunchMode.externalApplication,
                          );
                        } catch (e) {
                          if (mounted) setState(() => error = e.toString());
                        }
                        return;
                      }
                      final result = await store.joinClub(
                        hasCoupon ? coupon.text : '',
                      );
                      if (!context.mounted) return;
                      setState(() => error = result);
                      if (result == null) notice(context, 'Vitaj v Klube!');
                    },
            ),
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF123873), Color(0xFF2B7BF2)],
              ),
              borderRadius: BorderRadius.circular(32),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(AppIcons.crown, size: 40, color: const Color(0xFFB8D5FF)),
                const SizedBox(height: 28),
                const AppText(
                  'Dobré sa ti\nvráti späť.',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 37,
                    fontWeight: FontWeight.w700,
                    height: 1.08,
                    letterSpacing: -1.4,
                  ),
                ),
                const SizedBox(height: 16),
                const AppText(
                  'Viac malých radostí.\nViac zachránených dobrôt.',
                  style: TextStyle(
                    color: Color(0xFFD3E4FF),
                    fontSize: 16,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const AppText(
                    '14 DNÍ DEMO ČLENSTVA',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 11,
                      letterSpacing: 1,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          _clubFeature(
            context,
            AppIcons.wallet,
            '10 % späť v kredite',
            'Za každú vyzdvihnutú objednávku. Kredit použiješ pri ďalšej záchrane.',
          ),
          _clubFeature(
            context,
            AppIcons.fork,
            'Klubové dobroty',
            'Osobitné ponuky od vybraných prevádzok.',
          ),
          _clubFeature(
            context,
            AppIcons.heart,
            'Viac druhých šancí',
            'Malé rozhodnutia, ktoré urobia veľký rozdiel.',
          ),
          const SizedBox(height: 12),
          SurfaceCard(
            color: c.tint,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppText(
                  'Bez karty. Bez záväzkov.',
                  style: context.text.titleMedium?.copyWith(color: c.blue),
                ),
                const SizedBox(height: 8),
                AppText(
                  store.isDemo
                      ? 'Toto je ukážka členstva. Nezapína sa platené predplatné a nič sa automaticky neobnoví. Kredit nemá peňažnú hodnotu.'
                      : 'Skúšobné členstvo je bez karty a automaticky sa neobnovuje. Platený plán si môžeš aktivovať samostatne. Kredit využiješ pri ďalšom nákupe.',
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          if (!store.isMember && !store.trialUsed) ...[
            TextButton(
              onPressed: () => setState(() => hasCoupon = !hasCoupon),
              child: const AppText('Mám klubový kupón'),
            ),
            if (hasCoupon)
              TextField(
                controller: coupon,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  labelText: context.tr('Klubový kupón'),
                  hintText: context.tr('KLUB30 · 30 dní v deme'),
                ),
              ),
          ],
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: AppText(error!, style: TextStyle(color: c.warning)),
            ),
          if (plan != null && !store.isMember)
            Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: SurfaceCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppText('Platený Klub', style: context.text.titleLarge),
                    const SizedBox(height: 8),
                    AppText(
                      price,
                      style: context.text.headlineMedium?.copyWith(
                        color: c.blue,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const AppText(
                      'Pravidelné predplatné. Obnovenie zrušíš kedykoľvek; výhody platia do konca uhradeného obdobia.',
                    ),
                  ],
                ),
              ),
            ),
          if (store.clubRenewalCancelled)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: AppText(
                'Automatické obnovenie je vypnuté. Členstvo platí do ${shortDate(store.memberUntil!)}.',
              ),
            ),
          if (store.remoteEnabled)
            TextButton(
              onPressed: store.refreshRemote,
              child: const AppText('Obnoviť stav členstva'),
            ),
          if (store.isMember && !store.clubRenewalCancelled)
            TextButton(
              onPressed: () async {
                final result = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: AppText(
                      store.isDemo
                          ? 'Ukončiť demo členstvo?'
                          : 'Zrušiť obnovenie členstva?',
                    ),
                    content: AppText(
                      store.isDemo
                          ? 'Klubové ponuky už nebudú dostupné. Získaný kredit zostane zachovaný.'
                          : 'Platené výhody zostanú aktívne do konca uhradeného obdobia. Skúšobné členstvo sa ukončí. Kredit zostane zachovaný.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const AppText('Ponechať Klub'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const AppText('Ukončiť'),
                      ),
                    ],
                  ),
                );
                if (result == true) {
                  try {
                    await store.endClub();
                  } catch (e) {
                    if (context.mounted) notice(context, e.toString());
                  }
                }
              },
              child: AppText(
                store.isDemo
                    ? 'Ukončiť demo členstvo'
                    : 'Zrušiť obnovenie členstva',
              ),
            ),
          const SizedBox(height: 20),
          AppText(
            '10 % z hodnoty balíčkov po zľave, bez servisného poplatku. Kredit sa pripíše až po potvrdení prevzatia celej objednávky. Jedna skúška na účet. Skúšobné členstvo sa automaticky neúčtuje.',
            style: context.text.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _clubFeature(
    BuildContext context,
    IconData icon,
    String title,
    String description,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 24),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: context.colors.tint,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(icon, color: context.colors.blue, size: 24),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppText(title, style: context.text.titleMedium),
              const SizedBox(height: 5),
              AppText(
                description,
                style: context.text.bodyMedium?.copyWith(
                  color: context.colors.muted,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class WalletScreen extends StatelessWidget {
  const WalletScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final history = store.orders
        .where(
          (o) =>
              o.status == OrderStatus.collected && o.cashback > 0 ||
              o.creditUsed > 0 && o.status != OrderStatus.cancelled,
        )
        .toList();
    return ScreenScaffold(
      title: 'Tvoj kredit',
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          SurfaceCard(
            color: context.colors.tint,
            padding: const EdgeInsets.all(28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(AppIcons.wallet, color: context.colors.blue, size: 32),
                const SizedBox(height: 24),
                AppText(
                  'Niečo dobré na ďalšíkrát',
                  style: context.text.bodyMedium?.copyWith(
                    color: context.colors.blue,
                  ),
                ),
                const SizedBox(height: 8),
                AppText(
                  euro(store.credit),
                  style: context.text.displaySmall?.copyWith(
                    fontSize: 44,
                    color: context.colors.blue,
                  ),
                ),
                const SizedBox(height: 12),
                const AppText('Demo kredit · bez peňažnej hodnoty'),
              ],
            ),
          ),
          const SizedBox(height: 24),
          AppText('Dobro sa vracia', style: context.text.titleLarge),
          const SizedBox(height: 10),
          AppText(
            'Členovia Klubu získajú 10 % z hodnoty zachránených balíčkov po vyzdvihnutí. Kredit sa dá použiť pri ďalšej rezervácii.',
            style: context.text.bodyLarge?.copyWith(
              color: context.colors.muted,
            ),
          ),
          const SizedBox(height: 24),
          if (!store.isMember)
            PrimaryButton(
              'Objaviť Klub',
              icon: AppIcons.crown,
              onPressed: () => pushPage(context, const ClubScreen()),
            ),
          const SizedBox(height: 28),
          AppText('Pohyby kreditu', style: context.text.titleLarge),
          const SizedBox(height: 12),
          if (history.isEmpty)
            const AppText(
              'Zatiaľ tu nič nie je. Prvý klubový balíček to zmení.',
            ),
          for (final o in history)
            SurfaceCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  if (o.status == OrderStatus.collected && o.cashback > 0)
                    _creditRow(
                      context,
                      'Odmena za záchranu',
                      '+${euro(o.cashback)}',
                      shortDate(o.createdAt),
                    ),
                  if (o.creditUsed > 0)
                    _creditRow(
                      context,
                      'Použitý kredit',
                      '−${euro(o.creditUsed)}',
                      shortDate(o.createdAt),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _creditRow(
    BuildContext context,
    String label,
    String amount,
    String date,
  ) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppText(label),
              AppText(date, style: context.text.bodySmall),
            ],
          ),
        ),
        AppText(
          amount,
          style: context.text.titleMedium?.copyWith(color: context.colors.blue),
        ),
      ],
    ),
  );
}

class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});
  @override
  Widget build(BuildContext context) => ScreenScaffold(
    title: 'Pomôžeme ti',
    child: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        AppText(
          'Dobré otázky.\nJednoduché odpovede.',
          style: context.text.headlineMedium,
        ),
        const SizedBox(height: 24),
        PrimaryButton(
          'Napísať podpore a moje požiadavky',
          icon: AppIcons.ticket,
          onPressed: () => pushPage(context, const SupportScreen()),
        ),
        const SizedBox(height: 24),
        for (final entry in {
          'Čo je balíček s prekvapením?':
              'Výber jedla, ktoré prevádzka v daný deň nepredala. Konkrétne zloženie je prekvapením a fotografia je ilustračná. Vďaka tomu dostane jedlo druhú šancu a ty lepšiu cenu.',
          'Ako si balíček vyzdvihnem?':
              'Vyber si ponuku, skontroluj čas a vytvor rezerváciu. Na mieste ukáž kód obsluhe a pred ňou potvrď prevzatie pre danú prevádzku. V ukážkovom režime sú objednávky skúšobné.',
          'Môžem si vybrať presný obsah?':
              'Nie. Obsah sa mení podľa dennej ponuky. Stravovacie filtre pomôžu pri výbere, pri silnej alergii sa vždy informuj priamo v prevádzke.',
          'Čo ak nestihnem vyzdvihnutie?':
              'Rezerváciu môžeš zrušiť v objednávkach pred začiatkom vyzdvihnutia. Použitý kredit sa vráti, platba kartou sa refunduje cez Stripe. Čiastočne vyzdvihnutú objednávku nemožno zrušiť naraz. Pripomienka ti pomôže prísť načas.',
          'Je platba v deme skutočná?':
              'Nie. Žiadne údaje karty sa nevyžadujú a žiadne peniaze sa neúčtujú. Všetky prevádzky, ceny, hodnotenia a skladové zásoby sú ukážkové.',
          'Ako funguje Klub a kredit?':
              'Skúšobný Klub sa aktivuje na 14 dní, s kódom KLUB30 na 30 dní, raz na účet. Po vyzdvihnutí celej objednávky získaš 10 % hodnoty balíčkov po zľave v kredite. Platené členstvo aktivuješ samostatne cez Stripe. Automatické obnovovanie môžeš vypnúť a výhody zostanú do konca zaplateného obdobia.',
          'Kde sa ukladajú moje údaje?':
              'Pri pripojení k serveru sa účet, objednávky, kredit a obľúbené synchronizujú medzi zariadeniami. V lokálnom ukážkovom režime zostávajú údaje v zariadení. Farby, jazyk a poloha sú uložené v nastaveniach aplikácie.',
        }.entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: SurfaceCard(
              padding: EdgeInsets.zero,
              child: ExpansionTile(
                shape: const Border(),
                collapsedShape: const Border(),
                trailing: Icon(AppIcons.chevronDown, size: 18),
                title: AppText(
                  entry.key,
                  style: context.text.titleMedium?.copyWith(fontSize: 15),
                ),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                    child: AppText(
                      entry.value,
                      style: context.text.bodyLarge?.copyWith(
                        color: context.colors.muted,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 16),
        SurfaceCard(
          color: context.colors.tint,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppText('Tvoríme niečo dobré.', style: context.text.titleMedium),
              const SizedBox(height: 8),
              const AppText(
                'V prihlásenom účte môžeš napísať podpore, sledovať odpovede a vyriešiť reklamáciu v jednej konverzácii. Demo používa fiktívne požiadavky.',
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

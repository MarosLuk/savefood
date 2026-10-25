import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:design_system/design_system.dart';
import '../state/app_store.dart';
import '../widgets/common.dart';
import '../services/file_export.dart';

class AccountSecurityScreen extends StatefulWidget {
  const AccountSecurityScreen({super.key});
  @override
  State<AccountSecurityScreen> createState() => _AccountSecurityScreenState();
}

class _AccountSecurityScreenState extends State<AccountSecurityScreen> {
  bool busy = false;
  String? error;
  Future<void> export() async {
    setState(() => busy = true);
    final who = StoreScope.of(context).email;
    try {
      final result = await StoreScope.of(
        context,
      ).api!.request('GET', '/v1/account/export');
      if (!mounted || StoreScope.of(context).email != who) return;
      final box = context.findRenderObject()! as RenderBox;
      await exportDataFile(
        'save-food-osobne-udaje.json',
        Uint8List.fromList(
          utf8.encode(const JsonEncoder.withIndent('  ').convert(result)),
        ),
        box.localToGlobal(Offset.zero) & box.size,
        mimeType: 'application/json',
      );
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    return ScreenScaffold(
      title: 'Bezpečnosť a údaje účtu',
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Icon(AppIcons.shield, size: 48, color: context.colors.blue),
          const SizedBox(height: 20),
          AppText(
            'Tvoj účet. Pod tvojou kontrolou.',
            style: context.text.headlineMedium,
          ),
          const SizedBox(height: 12),
          AppText(store.email),
          const SizedBox(height: 20),
          if (error != null) AppText(error!),
          if (!store.signedIn)
            const AppText('Prihlás sa na správu účtu.')
          else ...[
            SurfaceCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  SettingsRow(
                    icon: AppIcons.check,
                    title: store.emailVerified
                        ? 'E-mail je overený'
                        : 'Overiť e-mail',
                    onTap: store.emailVerified
                        ? null
                        : () => pushPage(
                            context,
                            const AccountActionScreen(purpose: 'verify'),
                          ),
                  ),
                  SettingsRow(
                    icon: AppIcons.shield,
                    title: 'Zmeniť heslo',
                    subtitle: 'Odhlási všetky zariadenia',
                    onTap: () => pushPage(
                      context,
                      const AccountActionScreen(purpose: 'password'),
                    ),
                  ),
                  SettingsRow(
                    icon: AppIcons.mail,
                    title: 'Zmeniť e-mail',
                    subtitle: 'Novú adresu potvrdíš kódom',
                    onTap: () => pushPage(
                      context,
                      const AccountActionScreen(purpose: 'email'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            PrimaryButton(
              'Stiahnuť moje údaje',
              busy: busy,
              secondary: true,
              onPressed: export,
            ),
            const SizedBox(height: 12),
            const AppText(
              'Export obsahuje profil, objednávky, kredit, recenzie a verejnú komunikáciu podpory vrátane dostupných fotografií. Heslá a prihlasovacie tokeny sa neexportujú.',
            ),
            const SizedBox(height: 24),
            SettingsRow(
              icon: AppIcons.trash,
              title: 'Vymazať účet',
              subtitle: 'Odstránenie profilu a anonymizácia',
              onTap: () => pushPage(
                context,
                const AccountActionScreen(purpose: 'delete'),
              ),
            ),
            if (store.demoShowcase)
              SettingsRow(
                icon: AppIcons.mail,
                title: 'Demo e-mailová schránka',
                subtitle: 'Iba vlastné fiktívne správy',
                onTap: () => pushPage(context, const DemoMailScreen()),
              ),
          ],
        ],
      ),
    );
  }
}

class AccountActionScreen extends StatefulWidget {
  const AccountActionScreen({
    super.key,
    required this.purpose,
    this.challengeId,
    this.initialCode,
  });
  final String purpose;
  final String? challengeId, initialCode;
  @override
  State<AccountActionScreen> createState() => _AccountActionScreenState();
}

class _AccountActionScreenState extends State<AccountActionScreen> {
  final email = TextEditingController(),
      password = TextEditingController(),
      current = TextEditingController(),
      code = TextEditingController(),
      repeat = TextEditingController();
  String? challenge, grant, error, info;
  bool busy = false, authorized = false, accept = false, done = false;
  bool get reset => widget.purpose == 'reset';
  String get title => switch (widget.purpose) {
    'verify' => 'Overenie e-mailu',
    'reset' => 'Obnova hesla',
    'password' => 'Zmena hesla',
    'email' => 'Zmena e-mailu',
    'authorize' => 'Potvrdenie prístupu',
    _ => 'Vymazanie účtu',
  };
  @override
  void initState() {
    super.initState();
    challenge = widget.challengeId;
    code.text = widget.initialCode ?? '';
  }

  @override
  void dispose() {
    for (final c in [email, password, current, code, repeat]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> run(Future<void> Function() action) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
      info = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Map<String, dynamic> get credential =>
      grant == null ? {'currentPassword': current.text} : {'grant': grant};
  Future<void> authorize() async {
    final api = StoreScope.of(context).api!;
    if (!authorized) {
      final result = await api.request(
        'POST',
        '/v1/account/challenges',
        body: {'purpose': 'authorize'},
      );
      if (!mounted) return;
      setState(() {
        challenge = result['challengeId'] as String;
        authorized = true;
        info = 'Kód sme odoslali na aktuálny e-mail.';
      });
    } else {
      final result = await api.request(
        'POST',
        '/v1/account/challenges/confirm',
        body: {'challengeId': challenge, 'code': code.text},
      );
      if (!mounted) return;
      setState(() {
        grant = result['grant'] as String;
        authorized = false;
        challenge = null;
        code.clear();
        info = 'Prístup je overený na 5 minút.';
      });
    }
  }

  Future<void> submit() async {
    final store = StoreScope.of(context), api = store.api!;
    if ((widget.purpose == 'password' || reset && challenge != null) &&
        (password.text.length < 12 || password.text != repeat.text)) {
      throw StateError('Zadaj rovnaké nové heslo s aspoň 12 znakmi.');
    }
    if (widget.purpose == 'password') {
      await api.request(
        'POST',
        '/v1/account/password',
        body: {...credential, 'password': password.text},
      );
      await store.signOut();
      if (mounted) setState(() => done = true);
      return;
    }
    if (widget.purpose == 'delete') {
      if (!accept) throw StateError('Potvrď, že rozumieš následkom vymazania.');
      final confirm = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const AppText('Naozaj vymazať účet?'),
          content: const AppText(
            'Profil a prihlasovanie sa odstránia. Tento krok nemožno vrátiť.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Ponechať účet'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Vymazať účet'),
            ),
          ],
        ),
      );
      if (confirm != true) return;
      await api.request('POST', '/v1/account/delete', body: credential);
      await store.signOut();
      if (mounted) setState(() => done = true);
      return;
    }
    if (challenge == null) {
      final result = await api.request(
        'POST',
        reset ? '/v1/auth/recovery' : '/v1/account/challenges',
        body: {
          'purpose': widget.purpose,
          if (reset || widget.purpose == 'email') 'email': email.text.trim(),
          if (widget.purpose == 'email') ...credential,
        },
      );
      if (!mounted) return;
      setState(() {
        challenge = result['challengeId'] as String;
        info = reset
            ? 'Ak účet existuje, poslali sme kód na uvedenú adresu.'
            : 'Kód sme odoslali e-mailom.';
      });
      return;
    }
    final confirmation = await api.request(
      'POST',
      reset ? '/v1/auth/recovery/confirm' : '/v1/account/challenges/confirm',
      body: {
        'challengeId': challenge,
        'code': code.text,
        if (reset) 'password': password.text,
      },
    );
    if (widget.purpose == 'authorize') {
      if (mounted) Navigator.pop(context, confirmation['grant'] as String);
      return;
    }
    if (reset || widget.purpose == 'email') {
      await store.signOut();
    } else {
      await store.refreshRemote();
    }
    if (mounted) setState(() => done = true);
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final sensitive = {'password', 'email', 'delete'}.contains(widget.purpose);
    return ScreenScaffold(
      title: title,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Icon(AppIcons.shield, size: 48, color: context.colors.blue),
          const SizedBox(height: 20),
          AppText(done ? 'Hotovo.' : title, style: context.text.headlineMedium),
          const SizedBox(height: 16),
          if (done) ...[
            AppText(
              widget.purpose == 'verify'
                  ? 'Tvoj e-mail je overený.'
                  : widget.purpose == 'delete'
                  ? 'Účet bol anonymizovaný. Dokončené objednávky a finančné záznamy sa uchovávajú podľa retenčnej politiky.'
                  : 'Zmena bola uložená. Prihlás sa znova novými údajmi.',
            ),
            const SizedBox(height: 20),
            PrimaryButton('Späť', onPressed: () => Navigator.pop(context)),
          ] else if (!reset && !store.signedIn)
            const AppText(
              'Túto zmenu dokonči v aplikácii po prihlásení do pôvodného účtu. Jednorazový kód môžeš opísať z e-mailu.',
            )
          else ...[
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: AppText(
                  error!,
                  style: TextStyle(color: context.colors.warning),
                ),
              ),
            if (info != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: AppText(info!),
              ),
            if (widget.purpose == 'verify')
              AppText('Overujeme adresu ${store.email}. Kód platí 15 minút.'),
            if ((reset || widget.purpose == 'email') && challenge == null)
              TextField(
                controller: email,
                enabled: !busy,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  labelText: widget.purpose == 'email'
                      ? 'Nový e-mail'
                      : 'E-mail účtu',
                ),
              ),
            if (sensitive && challenge == null && grant == null) ...[
              const SizedBox(height: 16),
              if (store.hasPassword)
                TextField(
                  controller: current,
                  enabled: !busy,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Aktuálne heslo',
                  ),
                ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: busy ? null : () => run(authorize),
                child: const Text('Overiť prístup e-mailovým kódom'),
              ),
            ],
            if (challenge != null) ...[
              const SizedBox(height: 16),
              TextField(
                controller: code,
                enabled: !busy,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(8),
                ],
                decoration: const InputDecoration(
                  labelText: 'Jednorazový 8-miestny kód',
                ),
              ),
              if (authorized)
                TextButton(
                  onPressed: busy ? null : () => run(authorize),
                  child: const Text('Potvrdiť prístup k účtu'),
                ),
            ],
            if (widget.purpose == 'password' || reset && challenge != null) ...[
              const SizedBox(height: 16),
              TextField(
                controller: password,
                enabled: !busy,
                obscureText: true,
                autofillHints: const [AutofillHints.newPassword],
                decoration: const InputDecoration(
                  labelText: 'Nové heslo',
                  helperText: 'Aspoň 12 znakov',
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: repeat,
                enabled: !busy,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Zopakovať nové heslo',
                ),
              ),
            ],
            if (widget.purpose == 'delete') ...[
              const SizedBox(height: 20),
              const AppText(
                'Vymaže sa profil, prihlasovanie, recenzie a tvoje fotografie podpory. Aktívne objednávky treba najprv dokončiť; vlastník firmy musí odovzdať vlastníctvo. Dokončené objednávky a finančné záznamy ostávajú oddelene podľa retenčnej politiky prevádzkovateľa.',
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: accept,
                onChanged: busy
                    ? null
                    : (v) => setState(() => accept = v ?? false),
                title: const Text('Rozumiem a chcem vymazať účet'),
              ),
            ],
            const SizedBox(height: 24),
            PrimaryButton(
              authorized
                  ? 'Najprv potvrď prístup'
                  : widget.purpose == 'delete'
                  ? 'Vymazať účet'
                  : challenge == null && widget.purpose != 'password'
                  ? 'Poslať overovací kód'
                  : 'Potvrdiť zmenu',
              busy: busy,
              onPressed: authorized ? null : () => run(submit),
            ),
            if (challenge != null && !authorized)
              TextButton(
                onPressed: busy
                    ? null
                    : () => setState(() {
                        challenge = null;
                        code.clear();
                        grant = null;
                      }),
                child: const Text('Vyžiadať nový kód'),
              ),
            if (store.demoShowcase && store.signedIn)
              TextButton(
                onPressed: () => pushPage(context, const DemoMailScreen()),
                child: const Text('Otvoriť demo e-mailovú schránku'),
              ),
          ],
        ],
      ),
    );
  }
}

class DemoMailScreen extends StatefulWidget {
  const DemoMailScreen({super.key});
  @override
  State<DemoMailScreen> createState() => _DemoMailScreenState();
}

class _DemoMailScreenState extends State<DemoMailScreen> {
  List<Map> messages = [];
  String? error;
  bool loaded = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!loaded) {
      loaded = true;
      load();
    }
  }

  Future<void> load() async {
    try {
      final result = await StoreScope.of(
        context,
      ).api!.request('GET', '/v1/account/demo-mail');
      if (mounted) {
        setState(() => messages = (result['messages'] as List).cast<Map>());
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) => ScreenScaffold(
    title: 'Demo e-mailová schránka',
    actions: [
      IconButton(
        tooltip: 'Obnoviť schránku',
        onPressed: load,
        icon: Icon(AppIcons.refresh),
      ),
    ],
    child: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const AppText(
          'Fiktívne správy iba pre aktuálny demo účet. V produkcii táto schránka neexistuje.',
        ),
        const SizedBox(height: 20),
        if (error != null) AppText(error!),
        if (messages.isEmpty) const AppText('Zatiaľ žiadne e-maily.'),
        for (final m in messages)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: SurfaceCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppText(
                    m['subject'] as String,
                    style: context.text.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  SelectableText(m['body'] as String),
                ],
              ),
            ),
          ),
      ],
    ),
  );
}

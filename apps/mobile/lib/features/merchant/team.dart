import 'package:flutter/material.dart';
import 'package:design_system/design_system.dart';
import 'package:marketplace_api/marketplace_api.dart';
import '../../state/app_store.dart';
import '../../widgets/common.dart';
import '../account.dart';
import '../account_security.dart';
import 'controller.dart';

class MerchantTeamScreen extends StatefulWidget {
  const MerchantTeamScreen({super.key, required this.controller});
  final MerchantController controller;
  @override
  State<MerchantTeamScreen> createState() => _MerchantTeamScreenState();
}

class _MerchantTeamScreenState extends State<MerchantTeamScreen> {
  Map<String, dynamic>? data;
  String? error;
  bool busy = false;
  MerchantController get c => widget.controller;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final result = await c.api.request(
        'GET',
        '/v1/merchant/access?organizationId=${Uri.encodeComponent(c.organization!.id)}',
      );
      if (mounted) setState(() => data = result);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  Future<void> edit({Map? member}) async {
    final email = TextEditingController(
      text: member?['email'] as String? ?? '',
    );
    var role = member?['role'] as String? ?? 'staff';
    var all = member?['storeIds'] == null;
    final selected = (member?['storeIds'] as List? ?? [])
        .cast<String>()
        .toSet();
    final stores = c.workspace.stores
        .where((s) => s.organizationId == c.organization!.id)
        .toList();
    String? localError;
    bool saving = false;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      constraints: const BoxConstraints(maxWidth: 700),
      builder: (context) => StatefulBuilder(
        builder: (context, set) => Padding(
          padding: EdgeInsets.fromLTRB(
            24,
            24,
            24,
            24 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                AppText(
                  member == null ? 'Pozvať kolegu' : 'Upraviť prístup',
                  style: context.text.titleLarge,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: email,
                  readOnly: member != null,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'E-mail kolegu'),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: role,
                  decoration: const InputDecoration(labelText: 'Rola'),
                  items: const [
                    DropdownMenuItem(
                      value: 'staff',
                      child: Text('Personál · sklad a výdaj'),
                    ),
                    DropdownMenuItem(
                      value: 'manager',
                      child: Text('Manažér · ponuky a kvalita'),
                    ),
                  ],
                  onChanged: saving ? null : (v) => set(() => role = v!),
                ),
                SwitchListTile(
                  value: all,
                  onChanged: saving ? null : (v) => set(() => all = v),
                  title: const Text('Všetky pobočky firmy'),
                ),
                if (!all)
                  for (final store in stores)
                    CheckboxListTile(
                      value: selected.contains(store.id),
                      onChanged: saving
                          ? null
                          : (v) => set(
                              () => v == true
                                  ? selected.add(store.id)
                                  : selected.remove(store.id),
                            ),
                      title: Text(store.name),
                    ),
                if (localError != null)
                  AppText(
                    localError!,
                    style: TextStyle(color: context.colors.warning),
                  ),
                const SizedBox(height: 16),
                PrimaryButton(
                  member == null ? 'Poslať pozvánku' : 'Uložiť prístup',
                  busy: saving,
                  onPressed: () async {
                    if (!all && selected.isEmpty) {
                      set(() => localError = 'Vyber aspoň jednu pobočku.');
                      return;
                    }
                    set(() => saving = true);
                    try {
                      await c.mutate(member == null ? 'invites' : 'members', {
                        'organizationId': c.organization!.id,
                        'email': email.text.trim(),
                        'role': role,
                        'storeIds': all ? null : selected.toList(),
                      });
                      if (context.mounted) Navigator.pop(context);
                    } catch (e) {
                      if (context.mounted) set(() => localError = e.toString());
                    } finally {
                      if (context.mounted) set(() => saving = false);
                    }
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
    email.dispose();
    if (mounted) await load();
  }

  Future<void> transfer() async {
    final members = (data?['members'] as List? ?? [])
        .cast<Map>()
        .where((m) => m['role'] != 'owner')
        .toList();
    if (members.isEmpty) {
      notice(context, 'Najprv pozvi a over nového člena tímu.');
      return;
    }
    String? target = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Nový vlastník firmy'),
        children: [
          for (final m in members)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, m['email'] as String),
              child: Text('${m['name']} · ${m['email']}'),
            ),
        ],
      ),
    );
    if (target == null || !mounted) return;
    final grant = await pushPage<String>(
      context,
      const AccountActionScreen(purpose: 'authorize'),
    );
    if (grant == null || !mounted) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const AppText('Odovzdať vlastníctvo?'),
        content: AppText(
          '$target bude vlastníkom firmy. Tvoj účet zostane manažérom.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Ponechať'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Odovzdať'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await c.mutate('ownership', {
        'organizationId': c.organization!.id,
        'email': target,
        'grant': grant,
      });
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) => ScreenScaffold(
    title: 'Tím a prístupy pobočiek',
    actions: [
      IconButton(
        tooltip: 'Obnoviť tím',
        onPressed: load,
        icon: Icon(AppIcons.refresh),
      ),
    ],
    child: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        AppText(
          'Správni ľudia. Správne pobočky.',
          style: context.text.headlineMedium,
        ),
        const SizedBox(height: 12),
        const AppText(
          'Pozvánku prijme iba prihlásený kolega s overenou e-mailovou adresou. Obmedzený prístup platí aj na serveri.',
        ),
        const SizedBox(height: 20),
        if (error != null) AppText(error!),
        if (data == null) const LinearProgressIndicator(),
        PrimaryButton('Pozvať kolegu e-mailom', onPressed: () => edit()),
        const SizedBox(height: 20),
        for (final m in data?['members'] as List? ?? [])
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(m['name'] as String),
            subtitle: Text(
              '${m['email']} · ${m['role']}\n${m['storeIds'] == null ? 'Všetky pobočky' : '${(m['storeIds'] as List).length} pridelených pobočiek'}',
            ),
            isThreeLine: true,
            trailing: m['role'] == 'owner'
                ? null
                : IconButton(
                    tooltip: 'Upraviť prístup',
                    icon: Icon(AppIcons.edit),
                    onPressed: () => edit(member: m as Map),
                  ),
          ),
        const SizedBox(height: 20),
        AppText('Pozvánky', style: context.text.titleLarge),
        for (final i in data?['invites'] as List? ?? [])
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(i['email'] as String),
            subtitle: Text(
              i['accepted_by'] != null
                  ? 'Prijatá'
                  : i['revoked'] == 1
                  ? 'Odvolaná'
                  : 'Platí do ${shortDate(DateTime.parse(i['expires'] as String))}',
            ),
            trailing: i['accepted_by'] == null && i['revoked'] == 0
                ? TextButton(
                    onPressed: () async {
                      try {
                        await c.api.merchantAction(
                          'invites/${i['id']}/revoke',
                          {},
                        );
                        await load();
                      } catch (e) {
                        if (mounted) setState(() => error = e.toString());
                      }
                    },
                    child: const Text('Odvolať'),
                  )
                : null,
          ),
        const SizedBox(height: 24),
        OutlinedButton(
          onPressed: transfer,
          child: const Text('Odovzdať vlastníctvo firmy'),
        ),
      ],
    ),
  );
}

class MerchantInviteScreen extends StatefulWidget {
  const MerchantInviteScreen({super.key, this.inviteId, this.token});
  final String? inviteId, token;
  @override
  State<MerchantInviteScreen> createState() => _MerchantInviteScreenState();
}

class _MerchantInviteScreenState extends State<MerchantInviteScreen> {
  late final id = TextEditingController(text: widget.inviteId ?? ''),
      token = TextEditingController(text: widget.token ?? '');
  String? error;
  bool busy = false, done = false;
  @override
  void dispose() {
    id.dispose();
    token.dispose();
    super.dispose();
  }

  Future<void> accept() async {
    setState(() => busy = true);
    try {
      await StoreScope.of(context).api!.merchantAction('invites/accept', {
        'inviteId': id.text.trim(),
        'token': token.text.trim(),
      });
      if (mounted) setState(() => done = true);
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
      title: 'Pozvánka do tímu',
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          AppText(
            done ? 'Vitaj v tíme.' : 'Pridaj sa k dobrej veci.',
            style: context.text.headlineMedium,
          ),
          const SizedBox(height: 16),
          if (done)
            const AppText(
              'Prístup bol pridelený. Prevádzky nájdeš v predajcovskej časti.',
            )
          else ...[
            const AppText(
              'Prihlás sa účtom s e-mailom, na ktorý prišla pozvánka. Adresa musí byť overená.',
            ),
            if (error != null) AppText(error!),
            const SizedBox(height: 20),
            TextField(
              controller: id,
              decoration: const InputDecoration(
                labelText: 'Identifikátor pozvánky',
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: token,
              decoration: const InputDecoration(labelText: 'Kód pozvánky'),
            ),
            const SizedBox(height: 24),
            if (!store.signedIn)
              PrimaryButton(
                'Prihlásiť sa alebo vytvoriť účet',
                onPressed: () => pushPage(context, const AuthScreen()),
              )
            else if (!store.emailVerified)
              PrimaryButton(
                'Overiť môj e-mail',
                onPressed: () => pushPage(
                  context,
                  const AccountActionScreen(purpose: 'verify'),
                ),
              )
            else
              PrimaryButton('Prijať pozvánku', busy: busy, onPressed: accept),
          ],
        ],
      ),
    );
  }
}

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:design_system/design_system.dart';
import 'package:marketplace_api/marketplace_api.dart';
import '../../state/app_store.dart';
import '../../widgets/common.dart';
import 'support.dart';

class SupportActivityButton extends StatefulWidget {
  const SupportActivityButton({super.key, this.round = false});
  final bool round;
  @override
  State<SupportActivityButton> createState() => _SupportActivityButtonState();
}

class _SupportActivityButtonState extends State<SupportActivityButton> {
  String? email;
  int unread = 0, version = -1, request = 0;
  Timer? timer;
  bool loading = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final store = StoreScope.of(context);
    if (email != store.email || version != store.supportActivityVersion) {
      email = store.email;
      version = store.supportActivityVersion;
      unread = 0;
      load();
    }
    timer ??= Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted && !loading && ModalRoute.of(context)?.isCurrent == true) {
        load();
      }
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> load() async {
    final store = StoreScope.of(context);
    if (!store.signedIn || store.api == null) return;
    final identity = email, epoch = ++request;
    loading = true;
    try {
      final j = await store.api!.request('GET', '/v1/support/notifications');
      if (mounted && email == identity && request == epoch) {
        setState(() => unread = j['unread'] as int? ?? 0);
      }
    } catch (_) {
      /* Manual entry remains available when offline. */
    } finally {
      if (mounted && request == epoch) loading = false;
    }
  }

  Future<void> open() async {
    await pushPage(context, const SupportActivityScreen());
    if (mounted) await load();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.round) {
      return RoundButton(
        icon: AppIcons.bell,
        label: 'Podpora a upozornenia',
        badge: unread,
        onPressed: open,
      );
    }
    return IconButton(
      tooltip: 'Podpora a upozornenia',
      onPressed: open,
      icon: Badge(
        isLabelVisible: unread > 0,
        label: Text(unread > 99 ? '99+' : '$unread'),
        child: Icon(AppIcons.bell),
      ),
    );
  }
}

class SupportActivityScreen extends StatefulWidget {
  const SupportActivityScreen({super.key});
  @override
  State<SupportActivityScreen> createState() => _SupportActivityScreenState();
}

class _SupportActivityScreenState extends State<SupportActivityScreen> {
  List<Map<String, dynamic>> events = [];
  String? error, email;
  int? next;
  int through = 0;
  bool loading = true, agent = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final identity = StoreScope.of(context).email;
    if (email != identity) {
      email = identity;
      events = [];
      through = 0;
      next = null;
      load();
    }
  }

  Future<void> load({bool more = false}) async {
    final store = StoreScope.of(context), identity = email;
    if (store.api == null || !store.signedIn) {
      setState(() => loading = false);
      return;
    }
    setState(() => loading = true);
    try {
      final j = await store.api!.request(
        'GET',
        '/v1/support/notifications${more && next != null ? '?before=$next' : ''}',
      );
      if (!mounted || email != identity) return;
      setState(() {
        events = [
          if (more) ...events,
          ...(j['notifications'] as List? ?? []).map(
            (e) => Map<String, dynamic>.from(e as Map),
          ),
        ];
        next = j['nextCursor'] as int?;
        if (!more) through = j['through'] as int? ?? 0;
        agent = j['isAgent'] == true;
        error = null;
      });
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> readAll() async {
    setState(() => loading = true);
    try {
      await StoreScope.of(
        context,
      ).api!.supportAction('notifications/read', {'through': through});
      if (mounted) await load();
    } catch (e) {
      if (mounted) {
        setState(() {
          error = e.toString();
          loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    return ScreenScaffold(
      title: 'Podpora a upozornenia',
      actions: [
        IconButton(
          tooltip: 'Obnoviť upozornenia',
          onPressed: loading ? null : () => load(),
          icon: Icon(AppIcons.refresh),
        ),
      ],
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          SurfaceCard(
            color: context.colors.tint,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TagPill('ZOSTAŇME V KONTAKTE', icon: AppIcons.bell),
                const SizedBox(height: 18),
                AppText(
                  'Každá odpoveď.\nNa jednom mieste.',
                  style: context.text.headlineLarge,
                ),
                const SizedBox(height: 12),
                const AppText(
                  'Správy a priebeh požiadaviek nájdeš tu aj bez zapnutých push upozornení.',
                ),
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: () async {
                    await pushPage(context, const SupportScreen());
                    if (mounted) await load();
                  },
                  icon: Icon(AppIcons.help, size: 20),
                  label: Text(
                    agent
                        ? 'Pracovná fronta podpory'
                        : 'Všetky moje požiadavky',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          if (store.remoteEnabled && store.signedIn)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const AppText('Push upozornenia podpory'),
              subtitle: AppText(
                store.serverConfig['pushEnabled'] == true
                    ? 'Upozorni ma na odpoveď aj mimo aplikácie.'
                    : 'V tomto prostredí nie je pripojené doručovanie push.',
              ),
              value: store.supportAlerts,
              onChanged: (v) => store.preferences(support: v),
            ),
          if (through > 0)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: loading ? null : readAll,
                child: const Text('Označiť načítané ako prečítané'),
              ),
            ),
          if (error != null)
            SurfaceCard(color: context.colors.warm, child: AppText(error!)),
          if (loading) const LinearProgressIndicator(),
          if (!loading && events.isEmpty)
            const SurfaceCard(
              child: AppText(
                'Zatiaľ žiadne nové udalosti. Keď podpora odpovie, uvidíš to tu.',
              ),
            ),
          for (final e in events)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: InkWell(
                borderRadius: BorderRadius.circular(24),
                onTap: () async {
                  await pushPage(
                    context,
                    TicketScreen(ticketId: e['ticketId'] as String),
                  );
                  if (mounted) await load();
                },
                child: SurfaceCard(
                  color: e['read'] == true
                      ? context.colors.surface
                      : context.colors.tint,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          TagPill(e['number'] as String),
                          if (e['read'] != true) const TagPill('Nová správa'),
                          if (e['internal'] == true)
                            const TagPill('Interná poznámka'),
                        ],
                      ),
                      const SizedBox(height: 12),
                      AppText(
                        e['subject'] as String,
                        style: context.text.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      AppText(
                        shortDate(
                          DateTime.parse(e['createdAt'] as String).toLocal(),
                        ),
                        style: context.text.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (next != null)
            TextButton(
              onPressed: loading ? null : () => load(more: true),
              child: const Text('Načítať staršie upozornenia'),
            ),
        ],
      ),
    );
  }
}

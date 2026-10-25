import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:design_system/design_system.dart';
import 'package:marketplace_api/marketplace_api.dart';
import 'package:marketplace_domain/marketplace_domain.dart';
import '../../state/app_store.dart';
import '../../widgets/common.dart';
import '../merchant/editor.dart';
import 'photo.dart';

String ticketCategory(TicketCategory value) => switch (value) {
  TicketCategory.payment => 'Platba',
  TicketCategory.pickup => 'Vyzdvihnutie',
  TicketCategory.cancellation => 'Storno a vrátenie platby',
  TicketCategory.foodQuality => 'Kvalita balíčka',
  TicketCategory.merchant => 'Moja prevádzka',
  TicketCategory.other => 'Iná otázka',
};
String ticketStatus(TicketStatus value) => switch (value) {
  TicketStatus.open => 'Nová požiadavka',
  TicketStatus.waitingCustomer => 'Čakáme na odpoveď',
  TicketStatus.inProgress => 'Riešime',
  TicketStatus.resolved => 'Vyriešené',
  TicketStatus.closed => 'Uzavreté',
};

class SupportScreen extends StatefulWidget {
  const SupportScreen({super.key, this.orderId});
  final String? orderId;
  @override
  State<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends State<SupportScreen> {
  List<SupportTicket> tickets = [];
  bool loading = true, isAgent = false, inbox = false;
  String? error, email, status;
  int? next;
  String search = '', assignment = 'all';
  String? priority;
  bool unread = false;
  Timer? searchTimer;
  int loadVersion = 0;
  MarketplaceApi? get api => StoreScope.of(context).api;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final identity = StoreScope.of(context).email;
    if (email != identity) {
      email = identity;
      tickets = [];
      inbox = false;
      isAgent = false;
      assignment = 'all';
      unawaited(load());
    }
  }

  @override
  void dispose() {
    searchTimer?.cancel();
    super.dispose();
  }

  Future<void> load({bool more = false}) async {
    if (api == null || !StoreScope.of(context).signedIn) {
      setState(() => loading = false);
      return;
    }
    final identity = email;
    final version = ++loadVersion;
    setState(() => loading = true);
    try {
      var result = await api!.supportTickets(
        inbox: inbox,
        status: status,
        before: more ? next : null,
        search: search,
        priority: priority,
        assignment: inbox ? assignment : 'all',
        unread: unread,
      );
      if (!mounted || email != identity || version != loadVersion) return;
      if (result['isAgent'] == true && !isAgent) {
        inbox = true;
        result = await api!.supportTickets(
          inbox: true,
          status: status,
          search: search,
          priority: priority,
          assignment: assignment,
          unread: unread,
        );
      }
      if (!mounted || email != identity || version != loadVersion) return;
      setState(() {
        isAgent = result['isAgent'] == true;
        next = result['nextCursor'] as int?;
        final page = (result['tickets'] as List)
            .map(
              (t) =>
                  SupportTicket.fromJson(Map<String, dynamic>.from(t as Map)),
            )
            .toList();
        tickets = more ? [...tickets, ...page] : page;
        error = null;
      });
    } catch (e) {
      if (mounted && email == identity) setState(() => error = e.toString());
    } finally {
      if (mounted && email == identity && version == loadVersion) {
        setState(() => loading = false);
      }
    }
  }

  Future<void> create() async {
    final store = StoreScope.of(context);
    final result = await merchantEditor(
      context,
      title: 'Ako ti pomôžeme?',
      description:
          'Fotografie môžeš priložiť v konverzácii po vytvorení požiadavky. Správa sa uloží do podpory. Číslo karty, heslá ani prístupové kľúče sem neposielaj.',
      fields: [
        const MerchantField('subject', 'Predmet'),
        MerchantField(
          'category',
          'Téma',
          initial: 'other',
          options: {
            for (final c in TicketCategory.values) c.name: ticketCategory(c),
          },
        ),
        MerchantField(
          'orderId',
          'Objednávka',
          initial: widget.orderId ?? '',
          optional: true,
          options: {
            '': 'Bez konkrétnej objednávky',
            for (final o in store.orders)
              o.id:
                  '${o.items.first.store} · ${shortDate(o.createdAt)} · ${euro(o.total)}',
          },
        ),
        const MerchantField(
          'message',
          'Čo sa stalo?',
          type: MerchantFieldType.multiline,
        ),
      ],
      submit: (b) => api!.supportAction('tickets', {
        ...b,
        'orderId': b['orderId'] == '' ? null : b['orderId'],
      }),
    );
    if (result != null && mounted) {
      await pushPage(context, TicketScreen(ticketId: result['id'] as String));
      await load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context), c = context.colors;
    return ScreenScaffold(
      title: isAgent && inbox ? 'Pracovná fronta podpory' : 'Tvoja podpora',
      actions: [
        if (store.remoteEnabled && store.signedIn)
          IconButton(
            tooltip: 'Obnoviť požiadavky',
            onPressed: loading ? null : () => load(),
            icon: Icon(AppIcons.refresh),
          ),
      ],
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          SurfaceCard(
            color: c.tint,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TagPill('SME TU PRE TEBA', icon: AppIcons.help),
                const SizedBox(height: 20),
                AppText(
                  isAgent && inbox
                      ? 'Každá otázka\nsi zaslúži odpoveď.'
                      : 'Niečo sa nepodarilo?\nVyriešime to spolu.',
                  style: context.text.headlineLarge,
                ),
                const SizedBox(height: 12),
                AppText(
                  isAgent && inbox
                      ? 'Prehľad požiadaviek, naliehavé reklamácie a rozhovory so zákazníkmi na jednom mieste.'
                      : 'Napíš nám k platbe, vyzdvihnutiu alebo kvalite balíčka. Odpovede aj priebeh riešenia nájdeš priamo tu.',
                ),
                const SizedBox(height: 18),
                if (store.remoteEnabled && store.signedIn)
                  FilledButton.icon(
                    key: const ValueKey('support-create-ticket'),
                    onPressed: create,
                    icon: Icon(AppIcons.plus, size: 20),
                    label: const Text('Nová požiadavka'),
                  )
                else
                  const AppText(
                    'Pre odoslanie správy sa prihlás do aplikácie pripojenej k serveru.',
                  ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          if (isAgent)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const AppText('Pracovná fronta všetkých požiadaviek'),
              value: inbox,
              onChanged: loading
                  ? null
                  : (v) {
                      setState(() => inbox = v);
                      unawaited(load());
                    },
            ),
          if (store.remoteEnabled && store.signedIn) ...[
            TextField(
              decoration: InputDecoration(
                labelText: 'Hľadať predmet, číslo alebo objednávku',
                prefixIcon: Icon(AppIcons.search),
              ),
              onChanged: (v) {
                search = v;
                searchTimer?.cancel();
                searchTimer = Timer(
                  const Duration(milliseconds: 350),
                  () => load(),
                );
              },
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const AppText('Iba neprečítané'),
              value: unread,
              onChanged: loading
                  ? null
                  : (v) {
                      setState(() => unread = v);
                      load();
                    },
            ),
            if (isAgent && inbox) ...[
              DropdownButtonFormField<String>(
                initialValue: assignment,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Priradenie'),
                items: const [
                  DropdownMenuItem(
                    value: 'all',
                    child: Text('Všetci operátori'),
                  ),
                  DropdownMenuItem(value: 'mine', child: Text('Moje prípady')),
                  DropdownMenuItem(
                    value: 'unassigned',
                    child: Text('Nepriradené'),
                  ),
                ],
                onChanged: loading
                    ? null
                    : (v) {
                        setState(() => assignment = v ?? 'all');
                        load();
                      },
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: priority ?? '',
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Priorita'),
                items: const [
                  DropdownMenuItem(value: '', child: Text('Všetky priority')),
                  DropdownMenuItem(value: 'normal', child: Text('Bežné')),
                  DropdownMenuItem(value: 'urgent', child: Text('Naliehavé')),
                ],
                onChanged: loading
                    ? null
                    : (v) {
                        setState(() => priority = v == '' ? null : v);
                        load();
                      },
              ),
              const SizedBox(height: 16),
            ],
            DropdownButtonFormField<String>(
              key: ValueKey(status),
              initialValue: status ?? '',
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Stav požiadaviek'),
              icon: Icon(AppIcons.chevronDown, size: 20),
              items: [
                const DropdownMenuItem(value: '', child: Text('Všetky stavy')),
                for (final v in TicketStatus.values)
                  DropdownMenuItem(value: v.name, child: Text(ticketStatus(v))),
              ],
              onChanged: loading
                  ? null
                  : (v) {
                      setState(() => status = v == '' ? null : v);
                      unawaited(load());
                    },
            ),
            const SizedBox(height: 20),
          ],
          if (error != null) SurfaceCard(color: c.warm, child: AppText(error!)),
          if (loading)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (!loading && tickets.isEmpty && error == null)
            SurfaceCard(
              child: Column(
                children: [
                  Icon(AppIcons.checkCircle, color: c.blue, size: 40),
                  const SizedBox(height: 12),
                  AppText(
                    'Zatiaľ žiadne požiadavky',
                    style: context.text.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  const AppText('Keď budeš niečo potrebovať, ozvi sa nám.'),
                ],
              ),
            ),
          for (final t in tickets)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: InkWell(
                borderRadius: BorderRadius.circular(24),
                onTap: () async {
                  await pushPage(context, TicketScreen(ticketId: t.id));
                  await load();
                },
                child: SurfaceCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            t.priority == 'urgent'
                                ? AppIcons.shield
                                : AppIcons.ticket,
                            color: c.blue,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: AppText(
                              t.number,
                              style: context.text.bodySmall,
                            ),
                          ),
                          Icon(AppIcons.chevronRight, size: 18),
                        ],
                      ),
                      const SizedBox(height: 14),
                      AppText(t.subject, style: context.text.titleLarge),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (t.unread) const TagPill('Nová správa'),
                          TagPill(ticketStatus(t.status)),
                          TagPill(ticketCategory(t.category)),
                          if (t.priority == 'urgent')
                            const TagPill('Naliehavé'),
                        ],
                      ),
                      const SizedBox(height: 12),
                      AppText(
                        'Aktualizované ${shortDate(t.updatedAt.toLocal())}',
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
              child: const Text('Načítať ďalšie požiadavky'),
            ),
        ],
      ),
    );
  }
}

class TicketScreen extends StatefulWidget {
  const TicketScreen({super.key, required this.ticketId, this.photoPicker});
  final String ticketId;
  final Future<List<XFile>> Function(bool camera)? photoPicker;
  @override
  State<TicketScreen> createState() => _TicketScreenState();
}

class _TicketScreenState extends State<TicketScreen> {
  SupportTicket? ticket;
  String? error, email;
  bool busy = false, loading = true, internal = false;
  final message = TextEditingController();
  String replyKey = MarketplaceApi.newIdempotencyKey();
  Timer? timer;
  int readCursor = 0;
  bool historyLoading = false;
  final photos = <SupportPhoto>[];
  List<Map<String, dynamic>> audit = [];
  int? nextAudit;
  bool auditLoading = false;
  MarketplaceApi get api => StoreScope.of(context).api!;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final identity = StoreScope.of(context).email;
    if (email != identity) {
      email = identity;
      ticket = null;
      readCursor = 0;
      message.clear();
      photos.clear();
      audit = [];
      unawaited(
        load().then((_) {
          if (mounted) recoverPhotos();
        }),
      );
    }
    timer ??= Timer.periodic(const Duration(seconds: 8), (_) {
      if (mounted &&
          !busy &&
          !historyLoading &&
          ModalRoute.of(context)?.isCurrent == true) {
        unawaited(load(quiet: true));
      }
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    message.dispose();
    super.dispose();
  }

  Future<void> load({bool quiet = false, bool more = false}) async {
    final identity = email;
    final previous = ticket;
    if (!quiet && mounted) setState(() => loading = true);
    if (more) setState(() => historyLoading = true);
    try {
      final t = await api.supportTicket(
        widget.ticketId,
        before: more ? previous?.nextMessagesCursor : null,
        after: !more && previous != null && previous.lastMessageCursor > 0
            ? previous.lastMessageCursor
            : null,
      );
      if (!mounted || identity != email) return;
      final all =
          <String, SupportMessage>{
            for (final m in previous?.messages ?? <SupportMessage>[]) m.id: m,
            for (final m in t.messages) m.id: m,
          }.values.toList()..sort(
            (a, b) => a.cursor == 0 || b.cursor == 0
                ? a.createdAt.compareTo(b.createdAt)
                : a.cursor.compareTo(b.cursor),
          );
      final cursor = t.lastMessageCursor > (previous?.lastMessageCursor ?? 0)
          ? t.lastMessageCursor
          : previous?.lastMessageCursor ?? 0;
      setState(() {
        ticket = SupportTicket(
          id: t.id,
          number: t.number,
          subject: t.subject,
          category: t.category,
          status: t.status,
          priority: t.priority,
          createdAt: t.createdAt,
          updatedAt: t.updatedAt,
          messages: all,
          orderId: t.orderId,
          assignee: t.assignee,
          assigneeName: t.assigneeName,
          canManage: t.canManage,
          version: t.version,
          unread: t.unread,
          lastMessageCursor: cursor,
          nextMessagesCursor: more
              ? t.nextMessagesCursor
              : previous?.nextMessagesCursor ?? t.nextMessagesCursor,
          hasMoreMessages: t.hasMoreMessages,
          draftAttachments: t.draftAttachments,
        );
        photos
          ..clear()
          ..addAll(t.draftAttachments);
        error = null;
      });
      if (cursor > readCursor && !more) {
        await api.supportAction('tickets/${widget.ticketId}/read', {
          'through': cursor,
        });
        readCursor = cursor;
      }
    } catch (e) {
      if (mounted && email == identity) setState(() => error = e.toString());
    } finally {
      if (mounted && email == identity) {
        setState(() {
          loading = false;
          historyLoading = false;
        });
      }
    }
  }

  Future<void> uploadPhotos(List<XFile> files) async {
    for (final file in files.take(3 - photos.length)) {
      final p = await api.uploadSupportPhoto(
        widget.ticketId,
        await file.readAsBytes(),
      );
      if (!mounted) return;
      setState(() {
        if (!photos.any((photo) => photo.id == p.id)) photos.add(p);
        replyKey = MarketplaceApi.newIdempotencyKey();
      });
    }
  }

  Future<void> pickPhotos({bool camera = false}) async {
    if (busy || photos.length >= 3) return;
    final store = StoreScope.of(context);
    setState(() => busy = true);
    try {
      await store.rememberPhotoTicket(widget.ticketId);
      final picker = ImagePicker();
      final files = <XFile>[];
      if (widget.photoPicker != null) {
        files.addAll(await widget.photoPicker!(camera));
      } else if (camera) {
        final f = await picker.pickImage(
          source: ImageSource.camera,
          maxWidth: 2048,
          maxHeight: 2048,
          imageQuality: 85,
          requestFullMetadata: false,
        );
        if (f != null) files.add(f);
      } else {
        files.addAll(
          await picker.pickMultiImage(
            maxWidth: 2048,
            maxHeight: 2048,
            imageQuality: 85,
            requestFullMetadata: false,
            limit: 3 - photos.length,
          ),
        );
      }
      if (mounted) await uploadPhotos(files);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      await store.rememberPhotoTicket(null);
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> recoverPhotos() async {
    final store = StoreScope.of(context);
    if (kIsWeb ||
        defaultTargetPlatform != TargetPlatform.android ||
        store.pendingSupportPhotoTicket != widget.ticketId) {
      return;
    }
    setState(() => busy = true);
    try {
      final response = await ImagePicker().retrieveLostData();
      if (response.files != null) await uploadPhotos(response.files!);
      if (response.exception != null) throw response.exception!;
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      await store.rememberPhotoTicket(null);
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> discardPhoto(SupportPhoto p) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await api.supportAction('photos/${p.id}/discard', {});
      if (mounted) {
        setState(() {
          photos.removeWhere((v) => v.id == p.id);
          replyKey = MarketplaceApi.newIdempotencyKey();
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> manage() async {
    if (busy || ticket == null) return;
    final t = ticket!;
    try {
      final agents = await api.request('GET', '/v1/support/agents');
      if (!mounted) return;
      final result = await merchantEditor(
        context,
        title: 'Správa požiadavky',
        fields: [
          MerchantField(
            'status',
            'Stav',
            initial: t.status.name,
            options: {
              for (final status in TicketStatus.values)
                status.name: ticketStatus(status),
            },
          ),
          MerchantField(
            'priority',
            'Priorita',
            initial: t.priority,
            options: const {'normal': 'Bežná', 'urgent': 'Naliehavá'},
          ),
          MerchantField(
            'assigneeId',
            'Operátor',
            optional: true,
            initial: t.assignee ?? '',
            options: {
              '': 'Nepriradené',
              for (final a in agents['agents'] as List)
                a['id'] as String: a['name'] as String,
            },
          ),
        ],
        submit: (b) => api.supportAction('tickets/${widget.ticketId}/status', {
          ...b,
          'assigneeId': b['assigneeId'] == '' ? null : b['assigneeId'],
          'expectedVersion': t.version,
        }),
      );
      if (result != null && mounted) await load(quiet: true);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  Future<void> loadAudit({bool more = false}) async {
    if (auditLoading) return;
    setState(() => auditLoading = true);
    try {
      final result = await api.request(
        'GET',
        '/v1/support/tickets/${widget.ticketId}/audit${more && nextAudit != null ? '?before=$nextAudit' : ''}',
      );
      if (mounted) {
        setState(() {
          audit = [
            if (more) ...audit,
            ...(result['events'] as List).map(
              (e) => Map<String, dynamic>.from(e as Map),
            ),
          ];
          nextAudit = result['nextCursor'] as int?;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => auditLoading = false);
    }
  }

  Future<void> send() async {
    if (busy || (message.text.trim().isEmpty && photos.isEmpty)) return;
    setState(() => busy = true);
    try {
      await api.supportAction('tickets/${widget.ticketId}/messages', {
        'message': message.text.trim(),
        'internal': internal,
        'attachments': photos.map((p) => p.id).toList(),
        'idempotencyKey': replyKey,
      });
      message.clear();
      replyKey = MarketplaceApi.newIdempotencyKey();
      await load(quiet: true);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> update({TicketStatus? status, bool assign = false}) async {
    if (busy || ticket == null) return;
    setState(() => busy = true);
    try {
      await api.supportAction('tickets/${widget.ticketId}/status', {
        'status': (status ?? ticket!.status).name,
        'priority': ticket!.priority,
        'assignToMe': assign,
        'expectedVersion': ticket!.version,
      });
      await load(quiet: true);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> releaseFinance() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await api.supportAction('tickets/${widget.ticketId}/release-finance', {});
      if (mounted) {
        notice(context, 'Kontrola prešla. Vyúčtovanie môže pokračovať.');
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> refund() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final order = await api.supportOrder(widget.ticketId);
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        constraints: const BoxConstraints(maxWidth: 700),
        builder: (_) => RefundSheet(
          order: order,
          submit: (b) =>
              api.supportAction('tickets/${widget.ticketId}/refund', b),
          reconcile: (job, provider) => api.supportAction(
            'tickets/${widget.ticketId}/transfers/$job/reconcile',
            {'providerId': provider},
          ),
          verifyOperation: (path, provider) => api.supportAction(
            'tickets/${widget.ticketId}/refunds/$path',
            {'providerId': provider},
          ),
          retry: (id) => api.supportAction(
            'tickets/${widget.ticketId}/refunds/$id/retry',
            {},
          ),
        ),
      );
      await load(quiet: true);
      if (mounted) await StoreScope.of(context).refreshRemote();
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ticket, c = context.colors;
    return ScreenScaffold(
      title: t?.number ?? 'Požiadavka',
      actions: [
        IconButton(
          tooltip: 'Obnoviť konverzáciu',
          onPressed: busy ? null : () => load(),
          icon: Icon(AppIcons.refresh),
        ),
      ],
      child: loading && t == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(24),
              children: [
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: SurfaceCard(color: c.warm, child: AppText(error!)),
                  ),
                if (t != null) ...[
                  AppText(t.subject, style: context.text.headlineMedium),
                  if (t.canManage) ...[
                    const SizedBox(height: 8),
                    AppText('Operátor: ${t.assigneeName ?? "Nepriradené"}'),
                  ],
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      TagPill(ticketStatus(t.status)),
                      TagPill(ticketCategory(t.category)),
                      if (t.priority == 'urgent') const TagPill('Naliehavé'),
                    ],
                  ),
                  if (t.orderId != null) ...[
                    const SizedBox(height: 12),
                    AppText(
                      'Objednávka ${t.orderId!.substring(0, 8).toUpperCase()}',
                      style: context.text.bodySmall,
                    ),
                  ],
                  if (t.canManage) ...[
                    const SizedBox(height: 18),
                    SurfaceCard(
                      color: c.tint,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          AppText(
                            'Pracovisko operátora',
                            style: context.text.titleMedium,
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              OutlinedButton(
                                onPressed: busy ? null : manage,
                                child: const Text('Stav, priorita a operátor'),
                              ),
                              OutlinedButton(
                                onPressed: busy
                                    ? null
                                    : () => update(
                                        status: TicketStatus.inProgress,
                                        assign: true,
                                      ),
                                child: const Text('Prevziať požiadavku'),
                              ),
                              OutlinedButton(
                                onPressed: busy
                                    ? null
                                    : () =>
                                          update(status: TicketStatus.resolved),
                                child: const Text('Označiť ako vyriešené'),
                              ),
                              if (t.orderId != null)
                                FilledButton.icon(
                                  onPressed: busy ? null : refund,
                                  icon: Icon(AppIcons.wallet, size: 20),
                                  label: const Text('Reklamácia a refundácia'),
                                ),
                              if (t.orderId != null)
                                OutlinedButton(
                                  onPressed: busy ? null : releaseFinance,
                                  child: const Text(
                                    'Overiť a uvoľniť vyúčtovanie',
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  if (t.nextMessagesCursor != null)
                    TextButton(
                      onPressed: busy || historyLoading
                          ? null
                          : () => load(quiet: true, more: true),
                      child: const Text('Načítať staršie správy'),
                    ),
                  for (final m in t.messages)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: Align(
                        alignment: m.author == 'customer'
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 610),
                          child: SurfaceCard(
                            color: m.author == 'customer'
                                ? c.tint
                                : m.internal
                                ? c.warm
                                : c.surface,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      m.author == 'assistant'
                                          ? AppIcons.sparkle
                                          : m.author == 'agent'
                                          ? AppIcons.help
                                          : AppIcons.user,
                                      size: 18,
                                      color: c.blue,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: AppText(
                                        m.internal
                                            ? 'Interná poznámka'
                                            : m.author == 'assistant'
                                            ? 'Automatický asistent'
                                            : m.author == 'agent'
                                            ? 'Zákaznícka podpora'
                                            : 'Zákazník',
                                        style: context.text.labelLarge,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                if (m.body.isNotEmpty)
                                  SelectableText(
                                    m.body,
                                    style: context.text.bodyLarge,
                                  ),
                                if (m.attachments.isNotEmpty) ...[
                                  const SizedBox(height: 12),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      for (final p in m.attachments)
                                        SupportPhotoView(
                                          key: ValueKey('${email}_${p.id}'),
                                          id: p.id,
                                        ),
                                    ],
                                  ),
                                ],
                                const SizedBox(height: 10),
                                AppText(
                                  '${shortDate(m.createdAt.toLocal())} · ${m.createdAt.toLocal().hour.toString().padLeft(2, '0')}:${m.createdAt.toLocal().minute.toString().padLeft(2, '0')}',
                                  style: context.text.bodySmall,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (t.hasMoreMessages)
                    TextButton(
                      onPressed: busy ? null : () => load(quiet: true),
                      child: const Text('Načítať ďalšie nové správy'),
                    ),
                  if (t.canManage)
                    ExpansionTile(
                      title: const AppText('Audit riešenia'),
                      onExpansionChanged: (open) {
                        if (open) loadAudit();
                      },
                      children: [
                        for (final event in audit)
                          ListTile(
                            title: AppText(
                              '${event['event']} · ${event['actor'] ?? ''}',
                            ),
                            subtitle: AppText(
                              '${event['detail']}\n${shortDate(DateTime.parse(event['created_at'] as String))}',
                            ),
                          ),
                        if (nextAudit != null)
                          TextButton(
                            onPressed: auditLoading
                                ? null
                                : () => loadAudit(more: true),
                            child: const Text('Staršie udalosti'),
                          ),
                      ],
                    ),
                  const SizedBox(height: 18),
                  if (photos.isNotEmpty)
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        for (final p in photos)
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SupportPhotoView(
                                key: ValueKey('${email}_${p.id}'),
                                id: p.id,
                              ),
                              TextButton(
                                onPressed: busy ? null : () => discardPhoto(p),
                                child: const Text('Odstrániť'),
                              ),
                            ],
                          ),
                      ],
                    ),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      OutlinedButton.icon(
                        onPressed: busy || photos.length >= 3
                            ? null
                            : () => pickPhotos(),
                        icon: Icon(AppIcons.photo, size: 20),
                        label: const Text('Priložiť fotografie'),
                      ),
                      if (!kIsWeb &&
                          {
                            TargetPlatform.iOS,
                            TargetPlatform.android,
                          }.contains(defaultTargetPlatform))
                        OutlinedButton.icon(
                          onPressed: busy || photos.length >= 3
                              ? null
                              : () => pickPhotos(camera: true),
                          icon: Icon(AppIcons.camera, size: 20),
                          label: const Text('Odfotiť'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const AppText(
                    'Najviac 3 fotografie JPEG/PNG na správu, každá do 5 MB. Uvidia ich iba účastníci požiadavky.',
                  ),
                  if (busy) const LinearProgressIndicator(),
                  const SizedBox(height: 12),
                  TextField(
                    key: const ValueKey('support-reply-message'),
                    controller: message,
                    enabled: !busy,
                    minLines: 3,
                    maxLines: 7,
                    maxLength: 5000,
                    onChanged: (_) =>
                        replyKey = MarketplaceApi.newIdempotencyKey(),
                    decoration: const InputDecoration(
                      labelText: 'Tvoja správa',
                      hintText: 'Napíš ďalšie podrobnosti…',
                    ),
                  ),
                  if (t.canManage)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const AppText(
                        'Interná poznámka · zákazník ju neuvidí',
                      ),
                      value: internal,
                      onChanged: busy
                          ? null
                          : (v) => setState(() {
                              internal = v ?? false;
                              replyKey = MarketplaceApi.newIdempotencyKey();
                            }),
                    ),
                  const SizedBox(height: 12),
                  PrimaryButton(
                    internal ? 'Uložiť internú poznámku' : 'Odoslať správu',
                    busy: busy,
                    onPressed: send,
                    icon: AppIcons.mail,
                  ),
                  if (!t.canManage && t.status != TicketStatus.closed) ...[
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: busy
                          ? null
                          : () async {
                              setState(() => busy = true);
                              try {
                                await api.supportAction(
                                  'tickets/${t.id}/close',
                                  {},
                                );
                                await load(quiet: true);
                              } catch (e) {
                                if (mounted) {
                                  setState(() => error = e.toString());
                                }
                              } finally {
                                if (mounted) setState(() => busy = false);
                              }
                            },
                      child: const Text('Môj problém je vyriešený'),
                    ),
                  ],
                ],
              ],
            ),
    );
  }
}

class RefundSheet extends StatefulWidget {
  const RefundSheet({
    super.key,
    required this.order,
    required this.submit,
    this.retry,
    this.reconcile,
    this.verifyOperation,
  });
  final Future<Map<String, dynamic>> Function(String)? retry;
  final Future<Map<String, dynamic>> Function(String, String)? reconcile;
  final Future<Map<String, dynamic>> Function(String, String)? verifyOperation;
  final Map<String, dynamic> order;
  final Future<Map<String, dynamic>> Function(Map<String, dynamic>) submit;
  @override
  State<RefundSheet> createState() => _RefundSheetState();
}

class _RefundSheetState extends State<RefundSheet> {
  final selected = <String>{};
  final quantities = <String, int>{};
  final reason = TextEditingController();
  final key = MarketplaceApi.newIdempotencyKey();
  bool busy = false;
  String? error;
  @override
  void dispose() {
    reason.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (busy) return;
    if (selected.isEmpty || reason.text.trim().length < 3) {
      setState(() => error = 'Vyber položky a uveď dôvod refundácie.');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.submit({
        'offerIds': selected.toList(),
        'quantities': {for (final id in selected) id: quantities[id] ?? 1},
        'reason': reason.text.trim(),
        'idempotencyKey': key,
      });
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> retry(String id) async {
    if (busy || widget.retry == null) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.retry!(id);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> reconcile(String job) async {
    if (busy || widget.reconcile == null) return;
    final result = await merchantEditor(
      context,
      title: 'Overenie existujúceho prevodu',
      description:
          'Vlož identifikátor prevodu zo Stripe. Server overí príjemcu, sumu a väzbu na túto objednávku; nevytvorí ďalší prevod.',
      fields: const [
        MerchantField('providerId', 'Stripe ID prevodu', hint: 'tr_…'),
      ],
      submit: (b) => widget.reconcile!(job, b['providerId'] as String),
    );
    if (result != null && mounted) Navigator.pop(context);
  }

  Future<void> verify(String path, String title, String hint) async {
    if (busy || widget.verifyOperation == null) return;
    final result = await merchantEditor(
      context,
      title: title,
      description:
          'Vlož identifikátor už existujúcej operácie zo Stripe. Server overí sumu, menu a väzbu na pôvodnú refundáciu.',
      fields: [MerchantField('providerId', 'Stripe ID operácie', hint: hint)],
      submit: (b) => widget.verifyOperation!(path, b['providerId'] as String),
    );
    if (result != null && mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final items = (widget.order['items'] as List).cast<Map>(),
        c = context.colors;
    final chosen = items.where((i) => selected.contains(i['offerId']));
    (int, int) share(Map i) {
      final q = i['quantity'] as int,
          start = i['refundedQuantity'] as int? ?? 0,
          count = quantities[i['offerId']] ?? q - start;
      if (i.containsKey('gross')) {
        final part = OrderAllocation.fromJson(
          Map<String, dynamic>.from(i),
        ).unitSlice(q, start, count);
        return (part.external, part.credit);
      }
      return (
        allocateCents(
          i['external'] as int,
          List.filled(q, 1),
        ).skip(start).take(count).fold(0, (a, b) => a + b),
        allocateCents(
          i['credit'] as int,
          List.filled(q, 1),
        ).skip(start).take(count).fold(0, (a, b) => a + b),
      );
    }

    final external = chosen.fold(0, (n, i) => n + share(i).$1),
        credit = chosen.fold(0, (n, i) => n + share(i).$2);
    return PopScope(
      canPop: !busy,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
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
                      'Reklamácia a refundácia',
                      style: context.text.headlineSmall,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Zavrieť',
                    onPressed: busy ? null : () => Navigator.pop(context),
                    icon: Icon(AppIcons.close),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const AppText(
                'Vyber položky a počet kusov. Suma zahŕňa presný podiel zľavy, poplatku a kreditu. Vydané potraviny sa nevracajú do predajného skladu; prevod predajcovi sa vyrovná v potrebnej výške.',
              ),
              const SizedBox(height: 16),
              for (final job
                  in (widget.order['transfers'] as List? ?? [])
                      .cast<Map>()
                      .where((j) => j['status'] == 'review')) ...[
                SurfaceCard(
                  color: c.warm,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AppText(
                        'Prevod vyžaduje zosúladenie',
                        style: context.text.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      AppText(
                        job['error'] as String? ??
                            'Over existujúcu operáciu v Stripe.',
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton(
                        onPressed: busy || widget.reconcile == null
                            ? null
                            : () => reconcile(job['id'] as String),
                        child: const Text('Spárovať existujúci Stripe prevod'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
              for (final r
                  in (widget.order['reversals'] as List? ?? [])
                      .cast<Map>()
                      .where((r) => r['status'] == 'pending'))
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: OutlinedButton(
                    onPressed: busy || widget.verifyOperation == null
                        ? null
                        : () => verify(
                            '${r['refund_id']}/reversals/${r['transfer_id']}',
                            'Overenie existujúcej reverzie',
                            'trr_…',
                          ),
                    child: Text(
                      'Spárovať reverziu ${euro(r['amount'] as int)}',
                    ),
                  ),
                ),
              for (final r
                  in (widget.order['refunds'] as List? ?? []).cast<Map>().where(
                    (r) => r['status'] != 'completed',
                  )) ...[
                SurfaceCard(
                  color: c.warm,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AppText(
                        'Nedokončená refundácia',
                        style: context.text.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      AppText(
                        r['error'] as String? ??
                            'Obnov stav existujúcej operácie. Nevytváraj druhú refundáciu.',
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton(
                        onPressed: busy || widget.retry == null
                            ? null
                            : () => retry(r['id'] as String),
                        child: const Text('Obnoviť existujúcu refundáciu'),
                      ),
                      TextButton(
                        onPressed: busy || widget.verifyOperation == null
                            ? null
                            : () => verify(
                                '${r['id']}/provider',
                                'Overenie refundácie v Stripe',
                                're_…',
                              ),
                        child: const Text(
                          'Spárovať existujúcu Stripe refundáciu',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
              for (final i in items)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: AppText('${i['quantity']} × ${i['title']}'),
                      subtitle: AppText(
                        i['refunded'] == true
                            ? 'Už refundované'
                            : '${i['collected'] == true ? 'Vydané' : 'Nevydané'} · už refundované ${i['refundedQuantity'] ?? 0} ks',
                      ),
                      value: selected.contains(i['offerId']),
                      onChanged: busy || i['refunded'] == true
                          ? null
                          : (v) => setState(() {
                              if (v == true) {
                                selected.add(i['offerId'] as String);
                                quantities[i['offerId'] as String] =
                                    (i['quantity'] as int) -
                                    (i['refundedQuantity'] as int? ?? 0);
                              } else {
                                selected.remove(i['offerId']);
                              }
                            }),
                    ),
                    if (selected.contains(i['offerId']))
                      Padding(
                        padding: const EdgeInsets.only(left: 16, bottom: 16),
                        child: DropdownButtonFormField<int>(
                          key: ValueKey('refund-quantity-${i['offerId']}'),
                          initialValue: quantities[i['offerId']],
                          decoration: const InputDecoration(
                            labelText: 'Počet refundovaných kusov',
                          ),
                          items: [
                            for (
                              var n = 1;
                              n <=
                                  (i['quantity'] as int) -
                                      (i['refundedQuantity'] as int? ?? 0);
                              n++
                            )
                              DropdownMenuItem(value: n, child: Text('$n ks')),
                          ],
                          onChanged: busy
                              ? null
                              : (n) => setState(
                                  () => quantities[i['offerId'] as String] = n!,
                                ),
                        ),
                      ),
                  ],
                ),
              const SizedBox(height: 16),
              TextField(
                controller: reason,
                enabled: !busy,
                minLines: 2,
                maxLines: 4,
                maxLength: 500,
                decoration: const InputDecoration(
                  labelText: 'Dôvod refundácie',
                ),
              ),
              const SizedBox(height: 16),
              SurfaceCard(
                color: c.tint,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppText(
                      'Vráti sa ${euro(external + credit)}',
                      style: context.text.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    AppText(
                      '${euro(external)} pôvodnou platobnou metódou\n${euro(credit)} do peňaženky zákazníka',
                    ),
                  ],
                ),
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: AppText(error!, style: TextStyle(color: c.warning)),
                ),
              const SizedBox(height: 20),
              PrimaryButton(
                'Potvrdiť vrátenie platby',
                busy: busy,
                onPressed: save,
                icon: AppIcons.wallet,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

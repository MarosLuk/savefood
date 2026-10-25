import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:design_system/design_system.dart';
import '../../state/app_store.dart';
import '../../widgets/common.dart';

class MerchantMediaScreen extends StatefulWidget {
  const MerchantMediaScreen({
    super.key,
    required this.organizationId,
    this.select = true,
    this.recover = false,
  });
  final String organizationId;
  final bool select, recover;
  @override
  State<MerchantMediaScreen> createState() => _MerchantMediaScreenState();
}

class _MerchantMediaScreenState extends State<MerchantMediaScreen> {
  List<Map> photos = [];
  String? cursor, error, identity;
  bool loading = false, busy = false;
  int generation = 0;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final user = StoreScope.of(context).email;
    if (identity != user) {
      identity = user;
      photos = [];
      cursor = null;
      generation++;
      loading = false;
      busy = false;
      error = null;
      load();
      if (widget.recover) recover();
    }
  }

  Future<void> recover() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    final store = StoreScope.of(context), who = identity;
    try {
      final result = await ImagePicker().retrieveLostData();
      if (result.exception != null) throw result.exception!;
      if (!mounted || who != identity) return;
      for (final file in result.files ?? <XFile>[]) {
        await upload(file);
      }
    } catch (e) {
      if (mounted && who == identity) setState(() => error = e.toString());
    } finally {
      if (mounted && who == identity) {
        await store.rememberMediaOrganization(null);
      }
    }
  }

  Future<void> load({bool more = false}) async {
    if (loading) return;
    setState(() => loading = true);
    final who = identity, g = ++generation;
    try {
      final query = Uri(
        queryParameters: {
          'organizationId': widget.organizationId,
          if (more && cursor != null) 'before': cursor!,
        },
      ).query;
      final data = await StoreScope.of(
        context,
      ).api!.request('GET', '/v1/merchant/media?$query');
      if (mounted && who == identity && g == generation) {
        setState(() {
          photos = [
            if (more) ...photos,
            ...(data['photos'] as List).cast<Map>(),
          ];
          cursor = data['nextCursor'] as String?;
          error = null;
        });
      }
    } catch (e) {
      if (mounted && who == identity && g == generation) {
        setState(() => error = e.toString());
      }
    } finally {
      if (mounted && who == identity && g == generation) {
        setState(() => loading = false);
      }
    }
  }

  Future<void> upload(XFile file) async {
    final who = identity, api = StoreScope.of(context).api!;
    final bytes = await file.readAsBytes();
    if (bytes.length > 5 * 1024 * 1024) {
      throw StateError('Fotografia môže mať najviac 5 MB.');
    }
    if (!mounted || who != identity) return;
    final result = await api.binary(
      'POST',
      '/v1/merchant/media?${Uri(queryParameters: {'organizationId': widget.organizationId}).query}',
      bytes: Uint8List.fromList(bytes),
    );
    final data = jsonDecode(utf8.decode(result.bodyBytes)) as Map;
    if (mounted && who == identity) {
      setState(
        () => photos = [data, ...photos.where((p) => p['id'] != data['id'])],
      );
    }
  }

  Future<void> pick(bool camera) async {
    if (busy) return;
    setState(() => busy = true);
    final store = StoreScope.of(context), who = identity;
    await store.rememberMediaOrganization(widget.organizationId);
    try {
      final picker = ImagePicker();
      if (camera) {
        final file = await picker.pickImage(
          source: ImageSource.camera,
          maxWidth: 2048,
          maxHeight: 2048,
          imageQuality: 85,
          requestFullMetadata: false,
        );
        if (file != null && mounted && who == identity) await upload(file);
      } else {
        for (final file in await picker.pickMultiImage(
          maxWidth: 2048,
          maxHeight: 2048,
          imageQuality: 85,
          limit: 10,
          requestFullMetadata: false,
        )) {
          if (mounted && who == identity) await upload(file);
        }
      }
    } catch (e) {
      if (mounted && who == identity) setState(() => error = e.toString());
    } finally {
      if (mounted && who == identity) {
        await store.rememberMediaOrganization(null);
      }
      if (mounted && who == identity) setState(() => busy = false);
    }
  }

  Future<void> remove(Map photo) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const AppText('Odstrániť fotografiu?'),
        content: const AppText(
          'Používanú fotografiu treba najprv nahradiť pri produkte alebo ponuke.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Ponechať'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Odstrániť'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    try {
      await StoreScope.of(context).api!.request(
        'POST',
        '/v1/merchant/media/${photo['id']}/delete',
        body: {},
      );
      if (mounted) {
        setState(() => photos.removeWhere((p) => p['id'] == photo['id']));
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) => ScreenScaffold(
    title: 'Fotografie prevádzky',
    actions: [
      IconButton(
        tooltip: 'Obnoviť fotografie',
        onPressed: loading ? null : () => load(),
        icon: Icon(AppIcons.refresh),
      ),
    ],
    child: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        AppText(
          'Tvoje jedlo. V najlepšom svetle.',
          style: context.text.headlineMedium,
        ),
        const SizedBox(height: 12),
        const AppText(
          'Fotografie produktov sú určené na verejné zobrazenie. JPEG/PNG do 5 MB; polohové a ostatné metadáta automaticky odstránime.',
        ),
        const SizedBox(height: 20),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            FilledButton.icon(
              onPressed: busy ? null : () => pick(false),
              icon: Icon(AppIcons.photo, size: 20),
              label: const Text('Vybrať z galérie'),
            ),
            if (!kIsWeb)
              OutlinedButton.icon(
                onPressed: busy ? null : () => pick(true),
                icon: Icon(AppIcons.camera, size: 20),
                label: const Text('Odfotiť'),
              ),
          ],
        ),
        if (busy || loading)
          const Padding(
            padding: EdgeInsets.all(16),
            child: LinearProgressIndicator(),
          ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: AppText(
              error!,
              style: TextStyle(color: context.colors.warning),
            ),
          ),
        const SizedBox(height: 20),
        if (photos.isEmpty && !loading)
          const AppText('Nahraj prvú fotografiu svojej prevádzky.'),
        for (final photo in photos)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: SurfaceCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: FoodPhoto(photo['url'] as String, height: 190),
                  ),
                  const SizedBox(height: 12),
                  AppText('${photo['width']} × ${photo['height']} px'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 12,
                    children: [
                      if (widget.select)
                        FilledButton(
                          onPressed: busy
                              ? null
                              : () => Navigator.pop(
                                  context,
                                  photo['url'] as String,
                                ),
                          child: const Text('Použiť fotografiu'),
                        ),
                      TextButton.icon(
                        onPressed: busy ? null : () => remove(photo),
                        icon: Icon(AppIcons.trash, size: 20),
                        label: const Text('Odstrániť'),
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
            child: const Text('Načítať ďalšie fotografie'),
          ),
      ],
    ),
  );
}

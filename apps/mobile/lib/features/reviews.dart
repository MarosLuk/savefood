import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:design_system/design_system.dart';
import 'package:marketplace_domain/marketplace_domain.dart';
import '../state/app_store.dart';
import '../widgets/common.dart';

const reviewDimensions = {
  'quality': 'Kvalita jedla',
  'value': 'Hodnota za peniaze',
  'quantity': 'Množstvo',
  'pickup': 'Vyzdvihnutie',
};

class ReviewPhoto extends StatefulWidget {
  const ReviewPhoto({super.key, required this.id, this.size = 100});
  final String id;
  final double size;
  @override
  State<ReviewPhoto> createState() => _ReviewPhotoState();
}

class _ReviewPhotoState extends State<ReviewPhoto> {
  Future<Uint8List>? bytes;
  String? identity;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final store = StoreScope.of(context);
    if (bytes == null || identity != store.email) {
      identity = store.email;
      bytes = store.api!
          .binary('GET', '/v1/media/${Uri.encodeComponent(widget.id)}.jpg')
          .then((r) => r.bodyBytes);
    }
  }

  @override
  void didUpdateWidget(covariant ReviewPhoto old) {
    super.didUpdateWidget(old);
    if (old.id != widget.id) {
      bytes = StoreScope.of(context).api!
          .binary('GET', '/v1/media/${Uri.encodeComponent(widget.id)}.jpg')
          .then((r) => r.bodyBytes);
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List>(
    future: bytes,
    builder: (context, snapshot) => SizedBox(
      width: widget.size,
      height: widget.size,
      child: snapshot.hasData
          ? Semantics(
              label: 'Fotografia zákazníka',
              button: true,
              child: InkWell(
                onTap: () => showDialog<void>(
                  context: context,
                  builder: (context) => Dialog(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Align(
                          alignment: Alignment.centerRight,
                          child: IconButton(
                            tooltip: 'Zavrieť fotografiu',
                            onPressed: () => Navigator.pop(context),
                            icon: Icon(AppIcons.close),
                          ),
                        ),
                        Flexible(
                          child: InteractiveViewer(
                            child: Image.memory(
                              snapshot.data!,
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.memory(snapshot.data!, fit: BoxFit.cover),
                ),
              ),
            )
          : snapshot.hasError
          ? IconButton(
              tooltip: 'Skúsiť fotografiu znova',
              icon: Icon(AppIcons.refresh),
              onPressed: () => setState(
                () => bytes = StoreScope.of(context).api!
                    .binary(
                      'GET',
                      '/v1/media/${Uri.encodeComponent(widget.id)}.jpg',
                    )
                    .then((r) => r.bodyBytes),
              ),
            )
          : const Center(child: CircularProgressIndicator()),
    ),
  );
}

class ReviewsSheet extends StatefulWidget {
  const ReviewsSheet({super.key, this.offer, this.offerId})
    : assert(offer != null || offerId != null);
  final FoodOffer? offer;
  final String? offerId;
  @override
  State<ReviewsSheet> createState() => _ReviewsSheetState();
}

class _ReviewsSheetState extends State<ReviewsSheet> {
  String get offerId => widget.offer?.id ?? widget.offerId!;
  List<Map<String, dynamic>> reviews = [], attachments = [];
  Map<String, dynamic>? summary, own;
  final dimensions = {for (final k in reviewDimensions.keys) k: 5};
  String? error, cursor, identity;
  int rating = 5;
  bool sending = false, loading = false, started = false, populated = false;
  bool? canReview;
  int requestGeneration = 0;
  final comment = TextEditingController();
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final store = StoreScope.of(context);
    if (!started || identity != store.email) {
      started = true;
      identity = store.email;
      reviews = [];
      attachments = [];
      populated = false;
      own = null;
      summary = null;
      canReview = null;
      cursor = null;
      comment.clear();
      rating = 5;
      for (final key in dimensions.keys) {
        dimensions[key] = 5;
      }
      requestGeneration++;
      loading = false;
      sending = false;
      error = null;
      load();
      if (store.pendingReviewOffer == offerId) recover();
    }
  }

  Future<void> recover() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    final store = StoreScope.of(context), who = identity;
    try {
      final lost = await ImagePicker().retrieveLostData();
      if (lost.exception != null) throw lost.exception!;
      if (!mounted || who != identity) return;
      for (final f in lost.files ?? <XFile>[]) {
        if (attachments.length < 3) await upload(f);
      }
    } catch (e) {
      if (mounted && who == identity) setState(() => error = e.toString());
    } finally {
      if (mounted && who == identity) await store.rememberReviewOffer(null);
    }
  }

  Future<void> load({bool more = false}) async {
    if (loading) return;
    loading = true;
    final who = identity, generation = ++requestGeneration;
    try {
      final result = await StoreScope.of(context).api!.request(
        'GET',
        '/v1/offers/${Uri.encodeComponent(offerId)}/reviews${more && cursor != null ? '?before=${Uri.encodeComponent(cursor!)}' : ''}',
      );
      if (mounted && who == identity && generation == requestGeneration) {
        setState(() {
          reviews = [
            if (more) ...reviews,
            ...(result['reviews'] as List).map(
              (r) => Map<String, dynamic>.from(r as Map),
            ),
          ];
          cursor = result['nextCursor'] as String?;
          summary = result['summary'] == null
              ? null
              : Map<String, dynamic>.from(result['summary'] as Map);
          own = result['ownReview'] == null
              ? null
              : Map<String, dynamic>.from(result['ownReview'] as Map);
          canReview = result['eligible'] as bool?;
          error = null;
          if (own != null && !populated) {
            populated = true;
            rating = own!['rating'] as int;
            comment.text = own!['comment'] as String;
            for (final k in dimensions.keys) {
              dimensions[k] = own![k] as int? ?? rating;
            }
            attachments = (own!['attachments'] as List? ?? [])
                .map((p) => Map<String, dynamic>.from(p as Map))
                .toList();
          }
        });
      }
    } catch (e) {
      if (mounted && who == identity && generation == requestGeneration) {
        setState(() => error = e.toString());
      }
    } finally {
      if (mounted && who == identity && generation == requestGeneration) {
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
      '/v1/offers/${Uri.encodeComponent(offerId)}/review-photos',
      bytes: Uint8List.fromList(bytes),
    );
    if (mounted && who == identity) {
      setState(
        () => attachments.add(
          Map<String, dynamic>.from(
            jsonDecode(utf8.decode(result.bodyBytes)) as Map,
          ),
        ),
      );
    }
  }

  Future<void> pick(bool camera) async {
    if (sending || attachments.length >= 3) return;
    setState(() => sending = true);
    final store = StoreScope.of(context), who = identity;
    await store.rememberReviewOffer(offerId);
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
          limit: 3 - attachments.length,
          maxWidth: 2048,
          maxHeight: 2048,
          imageQuality: 85,
          requestFullMetadata: false,
        )) {
          if (mounted && who == identity && attachments.length < 3) {
            await upload(file);
          }
        }
      }
    } catch (e) {
      if (mounted && who == identity) setState(() => error = e.toString());
    } finally {
      if (mounted && who == identity) await store.rememberReviewOffer(null);
      if (mounted && who == identity) setState(() => sending = false);
    }
  }

  Future<void> submit() async {
    setState(() => sending = true);
    final store = StoreScope.of(context), who = identity;
    try {
      await store.api!.request(
        'POST',
        '/v1/offers/${Uri.encodeComponent(offerId)}/reviews',
        body: {
          'rating': rating,
          'comment': comment.text.trim(),
          'dimensions': dimensions,
          'attachments': attachments.map((p) => p['id']).toList(),
          if (own != null) 'version': own!['version'],
        },
      );
      if (!mounted || who != identity) return;
      await load();
      await store.refreshRemote();
      if (mounted && who == identity) {
        notice(context, 'Ďakujeme za hodnotenie.');
      }
    } catch (e) {
      if (mounted && who == identity) setState(() => error = e.toString());
    } finally {
      if (mounted && who == identity) setState(() => sending = false);
    }
  }

  Future<void> remove() async {
    final who = identity;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const AppText('Odstrániť vlastnú recenziu?'),
        content: const AppText(
          'Odstráni sa text, hodnotenie aj priložené fotografie.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Ponechať'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Odstrániť'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted || who != identity) return;
    setState(() => sending = true);
    try {
      await StoreScope.of(context).api!.request(
        'POST',
        '/v1/offers/${Uri.encodeComponent(offerId)}/reviews/delete',
        body: {},
      );
      if (!mounted || who != identity) return;
      attachments = [];
      comment.clear();
      own = null;
      populated = false;
      await load();
      if (mounted && who == identity) {
        await StoreScope.of(context).refreshRemote();
      }
    } catch (e) {
      if (mounted && who == identity) setState(() => error = e.toString());
    } finally {
      if (mounted && who == identity) setState(() => sending = false);
    }
  }

  Widget stars(String label, int value, ValueChanged<int> changed) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      AppText(label, style: context.text.titleSmall),
      Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(
          5,
          (i) => IconButton(
            tooltip: '$label: ${i + 1} z 5',
            onPressed: sending ? null : () => changed(i + 1),
            icon: Icon(
              AppIcons.star,
              color: i < value ? context.colors.warning : context.colors.muted,
            ),
          ),
        ),
      ),
    ],
  );
  @override
  void dispose() {
    comment.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context),
        count = summary?['count'] as int? ?? reviews.length;
    final average =
        (summary?['average'] as num?)?.toDouble() ??
        (reviews.isEmpty
            ? 0.0
            : reviews.fold<int>(0, (sum, r) => sum + (r['rating'] as int)) /
                  reviews.length);
    final eligible =
        canReview ??
        store.orders.any(
          (o) => o.items.any(
            (i) =>
                i.offerId == offerId &&
                (i.collected || o.status == OrderStatus.collected),
          ),
        );
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 30),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SheetHeading('Dobré skúsenosti'),
            const SizedBox(height: 20),
            if (error != null) ...[
              AppText(error!, style: TextStyle(color: context.colors.warning)),
              TextButton(
                onPressed: () => load(),
                child: const Text('Skúsiť znova'),
              ),
            ],
            if (loading) const LinearProgressIndicator(),
            AppText(
              count == 0
                  ? 'Zatiaľ bez hodnotení'
                  : '${average.toStringAsFixed(1)} / 5',
              style: context.text.headlineLarge,
            ),
            const SizedBox(height: 8),
            AppText(
              '$count overených hodnotení',
              style: context.text.bodySmall,
            ),
            const SizedBox(height: 20),
            for (final k in reviewDimensions.keys)
              if (summary?[k] != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Expanded(child: AppText(reviewDimensions[k]!)),
                      AppText('${(summary![k] as num).toStringAsFixed(1)} / 5'),
                    ],
                  ),
                ),
            const SizedBox(height: 12),
            for (final star in [5, 4, 3, 2, 1])
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    AppText('$star'),
                    const SizedBox(width: 8),
                    Icon(
                      AppIcons.star,
                      size: 16,
                      color: context.colors.warning,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: LinearProgressIndicator(
                        value: count == 0
                            ? 0
                            : ((summary?['stars'] as Map?)?[star.toString()]
                                          as int? ??
                                      reviews
                                          .where((r) => r['rating'] == star)
                                          .length) /
                                  count,
                        backgroundColor: context.colors.tint,
                        color: context.colors.blue,
                      ),
                    ),
                    const SizedBox(width: 12),
                    AppText(
                      '${(summary?['stars'] as Map?)?[star.toString()] ?? reviews.where((r) => r['rating'] == star).length}',
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 16),
            for (final r in reviews)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: SurfaceCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            AppIcons.star,
                            size: 16,
                            color: context.colors.warning,
                          ),
                          const SizedBox(width: 6),
                          AppText('${r['rating']} / 5'),
                          const Spacer(),
                          AppText(
                            shortDate(
                              DateTime.parse(
                                r['created_at'] as String,
                              ).toLocal(),
                            ),
                            style: context.text.bodySmall,
                          ),
                        ],
                      ),
                      if ((r['comment'] as String).isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Text(r['comment'] as String),
                      ],
                      if ((r['attachments'] as List? ?? []).isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final p in r['attachments'] as List)
                              ReviewPhoto(id: p['id'] as String),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            if (cursor != null)
              OutlinedButton(
                onPressed: loading ? null : () => load(more: true),
                child: const Text('Načítať staršie recenzie'),
              ),
            if (eligible && store.signedIn) ...[
              const SizedBox(height: 24),
              AppText(
                own == null ? 'Ako ti chutilo?' : 'Tvoja recenzia',
                style: context.text.titleLarge,
              ),
              if (own?['moderation'] == 'hidden')
                const AppText(
                  'Recenzia je skrytá moderátorom. Úprava sama neobnoví jej zverejnenie.',
                ),
              stars(
                'Celkové hodnotenie',
                rating,
                (v) => setState(() => rating = v),
              ),
              for (final k in dimensions.keys)
                stars(
                  reviewDimensions[k]!,
                  dimensions[k]!,
                  (v) => setState(() => dimensions[k] = v),
                ),
              TextField(
                controller: comment,
                maxLength: 1000,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Tvoja skúsenosť (nepovinné)',
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final p in attachments)
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ReviewPhoto(id: p['id'] as String),
                        TextButton(
                          onPressed: sending
                              ? null
                              : () => setState(
                                  () => attachments.removeWhere(
                                    (v) => v['id'] == p['id'],
                                  ),
                                ),
                          child: const Text('Odobrať'),
                        ),
                      ],
                    ),
                ],
              ),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  OutlinedButton.icon(
                    onPressed: sending || attachments.length >= 3
                        ? null
                        : () => pick(false),
                    icon: Icon(AppIcons.photo, size: 20),
                    label: const Text('Fotografia balíčka'),
                  ),
                  if (!kIsWeb)
                    OutlinedButton.icon(
                      onPressed: sending || attachments.length >= 3
                          ? null
                          : () => pick(true),
                      icon: Icon(AppIcons.camera, size: 20),
                      label: const Text('Odfotiť'),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              const AppText(
                'Najviac 3 fotografie JPEG/PNG do 5 MB. Zverejnia sa spolu s recenziou; metadáta odstránime.',
              ),
              const SizedBox(height: 16),
              PrimaryButton(
                own == null ? 'Odoslať hodnotenie' : 'Uložiť hodnotenie',
                busy: sending,
                onPressed: submit,
              ),
              if (own != null)
                TextButton(
                  onPressed: sending ? null : remove,
                  child: const Text('Odstrániť moju recenziu'),
                ),
            ] else ...[
              const SizedBox(height: 16),
              const AppText(
                'Hodnotenie môže pridať zákazník po vyzdvihnutí balíčka.',
              ),
            ],
          ],
        ),
      ),
    );
  }
}

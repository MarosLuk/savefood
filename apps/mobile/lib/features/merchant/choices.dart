import 'dart:async';
import 'package:flutter/material.dart';
import 'package:design_system/design_system.dart';

class MerchantChoice {
  const MerchantChoice(this.id, this.label, {this.payload = const {}});
  final String id, label;
  final Map<String, dynamic> payload;
}

class MerchantChoicePage {
  const MerchantChoicePage(this.rows, this.next);
  final List<MerchantChoice> rows;
  final String? next;
}

typedef MerchantLookup =
    Future<MerchantChoicePage> Function(String query, String? before);
Future<MerchantChoice?> chooseMerchantItem(
  BuildContext context,
  String title,
  MerchantLookup lookup,
) => showModalBottomSheet<MerchantChoice>(
  context: context,
  useSafeArea: true,
  isScrollControlled: true,
  constraints: const BoxConstraints(maxWidth: 700),
  builder: (_) => _ChoiceSheet(title, lookup),
);

class _ChoiceSheet extends StatefulWidget {
  const _ChoiceSheet(this.title, this.lookup);
  final String title;
  final MerchantLookup lookup;
  @override
  State<_ChoiceSheet> createState() => _ChoiceSheetState();
}

class _ChoiceSheetState extends State<_ChoiceSheet> {
  List<MerchantChoice> rows = [];
  String query = '';
  String? next, error;
  bool loading = false;
  int generation = 0;
  Timer? timer;
  @override
  void initState() {
    super.initState();
    unawaited(load());
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> load({bool more = false}) async {
    final g = ++generation;
    setState(() => loading = true);
    try {
      final p = await widget.lookup(query, more ? next : null);
      if (!mounted || g != generation) return;
      setState(() {
        rows = [if (more) ...rows, ...p.rows];
        next = p.next;
        error = null;
      });
    } catch (e) {
      if (mounted && g == generation) setState(() => error = e.toString());
    } finally {
      if (mounted && g == generation) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    height: MediaQuery.sizeOf(context).height * .85,
    child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 12, 12),
          child: Row(
            children: [
              Expanded(
                child: AppText(widget.title, style: context.text.titleLarge),
              ),
              IconButton(
                tooltip: 'Zavrieť výber',
                onPressed: () => Navigator.pop(context),
                icon: Icon(AppIcons.close),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: TextField(
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'Názov, SKU / EAN alebo šarža',
              prefixIcon: Icon(AppIcons.search),
            ),
            onChanged: (v) {
              query = v;
              generation++;
              timer?.cancel();
              timer = Timer(
                const Duration(milliseconds: 300),
                () => unawaited(load()),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        if (loading) const LinearProgressIndicator(),
        if (error != null)
          Padding(padding: const EdgeInsets.all(16), child: AppText(error!)),
        Expanded(
          child: ListView(
            children: [
              if (!loading && rows.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: AppText('Žiadne položky pre tento výber.'),
                ),
              for (final r in rows)
                ListTile(
                  title: AppText(r.label),
                  trailing: Icon(AppIcons.chevronRight),
                  onTap: () => Navigator.pop(context, r),
                ),
              if (next != null)
                TextButton(
                  onPressed: loading ? null : () => load(more: true),
                  child: const Text('Načítať ďalšie položky'),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}

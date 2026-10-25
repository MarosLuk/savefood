import 'choices.dart';
import 'package:flutter/material.dart';
import 'package:design_system/design_system.dart';
import 'package:marketplace_api/marketplace_api.dart';
import 'package:marketplace_domain/marketplace_domain.dart';
import '../../widgets/common.dart';
import 'media_library.dart';

enum MerchantFieldType { text, number, money, multiline, dateTime, photo }

class MerchantField {
  const MerchantField(
    this.key,
    this.label, {
    this.initial = '',
    this.options,
    this.type = MerchantFieldType.text,
    this.optional = false,
    this.hint,
    this.mediaOrganizationId,
    this.lookup,
  });
  final String key, label, initial;
  final Map<String, String>? options;
  final MerchantFieldType type;
  final bool optional;
  final String? hint;
  final String? mediaOrganizationId;
  final MerchantLookup? lookup;
}

Future<Map<String, dynamic>?> merchantEditor(
  BuildContext context, {
  required String title,
  required List<MerchantField> fields,
  required Future<Map<String, dynamic>> Function(Map<String, dynamic>) submit,
  String description = '',
  List<StockProduct>? recipeProducts,
  MerchantLookup? productLookup,
}) => showModalBottomSheet<Map<String, dynamic>>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  constraints: const BoxConstraints(maxWidth: 700),
  builder: (_) => MerchantEditor(
    title: title,
    fields: fields,
    submit: submit,
    description: description,
    recipeProducts: recipeProducts,
    productLookup: productLookup,
  ),
);

class MerchantEditor extends StatefulWidget {
  const MerchantEditor({
    super.key,
    required this.title,
    required this.fields,
    required this.submit,
    this.description = '',
    this.recipeProducts,
    this.productLookup,
  });
  final String title, description;
  final List<MerchantField> fields;
  final List<StockProduct>? recipeProducts;
  final MerchantLookup? productLookup;
  final Future<Map<String, dynamic>> Function(Map<String, dynamic>) submit;
  @override
  State<MerchantEditor> createState() => _MerchantEditorState();
}

class _MerchantEditorState extends State<MerchantEditor> {
  final form = GlobalKey<FormState>();
  final mutationKey = MarketplaceApi.newIdempotencyKey();
  late final controllers = {
    for (final f in widget.fields)
      f.key: TextEditingController(
        text: f.initial.isEmpty && f.options != null
            ? f.options!.keys.first
            : f.initial,
      ),
  };
  final recipeIds = <String>[];
  late final recipeCatalog = [...?widget.recipeProducts];
  final choiceLabels = <String, String>{};
  final recipeQuantities = <TextEditingController>[];
  bool busy = false;
  String? error;
  @override
  void initState() {
    super.initState();
    if (widget.recipeProducts?.isNotEmpty ?? false) {
      recipeIds.add(recipeCatalog.first.id);
      recipeQuantities.add(TextEditingController(text: '1'));
    }
  }

  @override
  void dispose() {
    for (final c in [...controllers.values, ...recipeQuantities]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> pickRecipe(int? index) async {
    final item = await chooseMerchantItem(
      context,
      'Vybrať obsah balíčka',
      widget.productLookup!,
    );
    if (item == null || !mounted) return;
    final product = StockProduct.fromJson(item.payload);
    setState(() {
      if (!recipeCatalog.any((p) => p.id == product.id)) {
        recipeCatalog.add(product);
      }
      if (index == null) {
        recipeIds.add(product.id);
        recipeQuantities.add(TextEditingController(text: '1'));
      } else {
        recipeIds[index] = product.id;
        recipeQuantities[index].text = '1';
      }
    });
  }

  Future<void> save() async {
    if (busy || !form.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final values = <String, dynamic>{
        for (final e in controllers.entries) e.key: e.value.text.trim(),
        'idempotencyKey': mutationKey,
      };
      if (widget.recipeProducts != null) {
        if (recipeIds.toSet().length != recipeIds.length) {
          throw StateError('Každú položku receptúry pridaj iba raz.');
        }
        values['recipe'] = {
          for (var i = 0; i < recipeIds.length; i++)
            recipeIds[i]: recipeCatalog
                .firstWhere((p) => p.id == recipeIds[i])
                .unit
                .parseAmount(recipeQuantities[i].text),
        };
      }
      final result = await widget.submit(values);
      if (mounted) Navigator.pop(context, result);
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is StateError ? e.message.toString() : e.toString(),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget photoField(MerchantField f) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (controllers[f.key]!.text.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: FoodPhoto(controllers[f.key]!.text, height: 170),
          ),
        ),
      OutlinedButton.icon(
        onPressed: busy || f.mediaOrganizationId == null
            ? null
            : () async {
                final url = await pushPage<String>(
                  context,
                  MerchantMediaScreen(organizationId: f.mediaOrganizationId!),
                );
                if (mounted && url != null) {
                  setState(() => controllers[f.key]!.text = url);
                }
              },
        icon: Icon(AppIcons.photo, size: 20),
        label: const Text('Vybrať alebo nahrať fotografiu'),
      ),
      const SizedBox(height: 12),
      TextFormField(
        key: ValueKey('merchant-${f.key}'),
        controller: controllers[f.key],
        enabled: !busy,
        decoration: InputDecoration(
          labelText: f.label,
          hintText: 'Alebo vlož vlastnú HTTPS adresu fotografie',
        ),
        validator: (v) =>
            (v?.trim().isEmpty ?? true) ? 'Vyber fotografiu.' : null,
      ),
      if (f.options != null)
        Wrap(
          spacing: 8,
          children: [
            for (final e in f.options!.entries)
              TextButton(
                onPressed: busy
                    ? null
                    : () => setState(() => controllers[f.key]!.text = e.key),
                child: Text(e.value),
              ),
          ],
        ),
    ],
  );

  Future<void> chooseDate(MerchantField f) async {
    final initial =
        DateTime.tryParse(controllers[f.key]!.text) ??
        DateTime.now().add(const Duration(days: 1));
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: initial.isBefore(now) ? now : initial,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 3),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null || !mounted) return;
    setState(
      () => controllers[f.key]!.text = localDateTime(
        DateTime(date.year, date.month, date.day, time.hour, time.minute),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .9,
        ),
        child: Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 12, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: AppText(
                        widget.title,
                        style: context.text.titleLarge,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Zavrieť',
                      onPressed: busy ? null : () => Navigator.pop(context),
                      icon: Icon(AppIcons.close),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (widget.description.isNotEmpty) ...[
                        AppText(
                          widget.description,
                          style: context.text.bodySmall,
                        ),
                        const SizedBox(height: 20),
                      ],
                      for (final f in widget.fields)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: f.lookup != null
                              ? FormField<String>(
                                  validator: (_) =>
                                      controllers[f.key]!.text.isEmpty
                                      ? 'Vyber položku.'
                                      : null,
                                  builder: (state) => InkWell(
                                    onTap: busy
                                        ? null
                                        : () async {
                                            final choice =
                                                await chooseMerchantItem(
                                                  context,
                                                  f.label,
                                                  f.lookup!,
                                                );
                                            if (choice == null || !mounted) {
                                              return;
                                            }
                                            setState(() {
                                              controllers[f.key]!.text =
                                                  choice.id;
                                              choiceLabels[f.key] =
                                                  choice.label;
                                            });
                                            state.didChange(choice.id);
                                          },
                                    child: InputDecorator(
                                      decoration: InputDecoration(
                                        labelText: f.label,
                                        errorText: state.errorText,
                                        suffixIcon: Icon(AppIcons.search),
                                      ),
                                      child: Text(
                                        choiceLabels[f.key] ??
                                            f.options?[controllers[f.key]!
                                                .text] ??
                                            (controllers[f.key]!.text.isEmpty
                                                ? 'Vybrať položku'
                                                : controllers[f.key]!.text),
                                      ),
                                    ),
                                  ),
                                )
                              : f.type == MerchantFieldType.photo
                              ? photoField(f)
                              : f.options != null
                              ? DropdownButtonFormField<String>(
                                  icon: Icon(AppIcons.chevronDown, size: 20),
                                  key: ValueKey('merchant-${f.key}'),
                                  initialValue: controllers[f.key]!.text.isEmpty
                                      ? f.options!.keys.first
                                      : controllers[f.key]!.text,
                                  isExpanded: true,
                                  decoration: InputDecoration(
                                    labelText: f.label,
                                  ),
                                  items: f.options!.entries
                                      .map(
                                        (e) => DropdownMenuItem(
                                          value: e.key,
                                          child: Text(
                                            e.value,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: busy
                                      ? null
                                      : (v) {
                                          controllers[f.key]!.text = v ?? '';
                                        },
                                )
                              : TextFormField(
                                  key: ValueKey('merchant-${f.key}'),
                                  controller: controllers[f.key],
                                  enabled: !busy,
                                  readOnly:
                                      f.type == MerchantFieldType.dateTime,
                                  onTap: f.type == MerchantFieldType.dateTime
                                      ? () => chooseDate(f)
                                      : null,
                                  maxLines:
                                      f.type == MerchantFieldType.multiline
                                      ? 4
                                      : 1,
                                  keyboardType:
                                      {
                                        MerchantFieldType.number,
                                        MerchantFieldType.money,
                                      }.contains(f.type)
                                      ? const TextInputType.numberWithOptions(
                                          decimal: true,
                                          signed: true,
                                        )
                                      : TextInputType.text,
                                  decoration: InputDecoration(
                                    labelText: f.label,
                                    hintText: f.hint,
                                    suffixIcon:
                                        f.type == MerchantFieldType.dateTime
                                        ? Icon(AppIcons.clock)
                                        : null,
                                  ),
                                  validator: (v) {
                                    final value = v?.trim() ?? '';
                                    if (!f.optional && value.isEmpty) {
                                      return 'Vyplň toto pole.';
                                    }
                                    if (value.isNotEmpty &&
                                        {
                                          MerchantFieldType.money,
                                          MerchantFieldType.number,
                                        }.contains(f.type) &&
                                        num.tryParse(
                                              value.replaceAll(',', '.'),
                                            ) ==
                                            null) {
                                      return 'Zadaj číslo.';
                                    }
                                    if (f.type == MerchantFieldType.dateTime &&
                                        DateTime.tryParse(value) == null) {
                                      return 'Vyber dátum a čas.';
                                    }
                                    return null;
                                  },
                                ),
                        ),
                      if (widget.recipeProducts != null) ...[
                        AppText(
                          'Obsah jedného balíčka',
                          style: context.text.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        const AppText(
                          'Množstvo je v jednotke uvedenej pri položke. Sklad sa pridelí podľa najbližšieho termínu.',
                        ),
                        const SizedBox(height: 12),
                        for (var i = 0; i < recipeIds.length; i++)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Column(
                              children: [
                                if (widget.productLookup != null)
                                  OutlinedButton.icon(
                                    key: ValueKey('recipe-product-$i'),
                                    onPressed: busy
                                        ? null
                                        : () => pickRecipe(i),
                                    icon: Icon(AppIcons.search, size: 18),
                                    label: Text(
                                      recipeCatalog
                                          .firstWhere(
                                            (p) => p.id == recipeIds[i],
                                          )
                                          .name,
                                    ),
                                  )
                                else
                                  DropdownButtonFormField<String>(
                                    icon: Icon(AppIcons.chevronDown, size: 20),
                                    key: ValueKey('recipe-product-$i'),
                                    initialValue: recipeIds[i],
                                    isExpanded: true,
                                    decoration: const InputDecoration(
                                      labelText: 'Položka receptúry',
                                    ),
                                    items: recipeCatalog
                                        .map(
                                          (p) => DropdownMenuItem(
                                            value: p.id,
                                            child: Text(
                                              '${p.name} · ${p.unit.label}',
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        )
                                        .toList(),
                                    onChanged: busy
                                        ? null
                                        : (v) =>
                                              setState(() => recipeIds[i] = v!),
                                  ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextFormField(
                                        key: ValueKey('recipe-quantity-$i'),
                                        controller: recipeQuantities[i],
                                        keyboardType:
                                            const TextInputType.numberWithOptions(
                                              decimal: true,
                                            ),
                                        decoration: const InputDecoration(
                                          labelText:
                                              'Množstvo v jednom balíčku',
                                        ),
                                        validator: (v) {
                                          final unit = recipeCatalog
                                              .firstWhere(
                                                (p) => p.id == recipeIds[i],
                                              )
                                              .unit;
                                          try {
                                            final n = unit.parseAmount(v ?? '');
                                            return n < 1 ||
                                                    n > 1000 * unit.scale
                                                ? 'Zadaj kladné množstvo do 1000 ${unit.label}.'
                                                : null;
                                          } on FormatException catch (e) {
                                            return e.message;
                                          }
                                        },
                                      ),
                                    ),
                                    if (recipeIds.length > 1)
                                      IconButton(
                                        tooltip: 'Odobrať položku',
                                        onPressed: busy
                                            ? null
                                            : () {
                                                setState(() {
                                                  recipeIds.removeAt(i);
                                                  recipeQuantities
                                                      .removeAt(i)
                                                      .dispose();
                                                });
                                              },
                                        icon: Icon(AppIcons.trash),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        if (recipeIds.length < 30 &&
                            (widget.productLookup != null ||
                                recipeIds.length < recipeCatalog.length))
                          TextButton.icon(
                            onPressed: busy
                                ? null
                                : () {
                                    if (widget.productLookup != null) {
                                      pickRecipe(null);
                                      return;
                                    }
                                    setState(() {
                                      recipeIds.add(
                                        recipeCatalog
                                            .firstWhere(
                                              (p) => !recipeIds.contains(p.id),
                                            )
                                            .id,
                                      );
                                      recipeQuantities.add(
                                        TextEditingController(text: '1'),
                                      );
                                    });
                                  },
                            icon: Icon(AppIcons.plus),
                            label: const Text('Pridať položku obsahu'),
                          ),
                      ],
                      if (error != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: AppText(
                            error!,
                            style: TextStyle(color: context.colors.warning),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
                child: PrimaryButton(
                  'Uložiť',
                  busy: busy,
                  onPressed: busy ? null : save,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

String localDateTime(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
int moneyValue(Object? v) {
  final n = double.tryParse((v as String).replaceAll(',', '.'));
  if (n == null || !n.isFinite) throw StateError('Zadaj platnú cenu.');
  return (n * 100).round();
}

int integerValue(Object? v) {
  final n = int.tryParse(v as String);
  if (n == null) throw StateError('Zadaj celé číslo.');
  return n;
}

String utcValue(Object? v) =>
    DateTime.parse(v as String).toUtc().toIso8601String();

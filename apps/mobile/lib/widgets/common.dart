import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:design_system/design_system.dart';
import 'package:marketplace_domain/marketplace_domain.dart';

Future<T?> pushPage<T>(BuildContext context, Widget page) =>
    Navigator.of(context).push<T>(CupertinoPageRoute(builder: (_) => page));

void notice(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: AppText(message)));
}

String pickupDay(DateTime date, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(date.year, date.month, date.day);
  if (day == today) return 'Dnes';
  if (day == today.add(const Duration(days: 1))) return 'Zajtra';
  return '${date.day}. ${date.month}.';
}

String offerCount(int count, {bool accusative = false}) => count == 1
    ? (accusative ? '1 ponuku' : '1 ponuka')
    : count >= 2 && count <= 4
    ? '$count ponuky'
    : '$count ponúk';

String bagCount(int count) => count == 1
    ? '1 balíček'
    : count >= 2 && count <= 4
    ? '$count balíčky'
    : '$count balíčkov';

String shortDate(DateTime date) => '${date.day}. ${date.month}. ${date.year}';

class FoodPhoto extends StatelessWidget {
  const FoodPhoto(
    this.name, {
    super.key,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.label,
  });
  final String name;
  final double? width, height;
  final BoxFit fit;
  final String? label;
  @override
  Widget build(BuildContext context) {
    Widget fallback(BuildContext _, Object error, StackTrace? stack) =>
        Container(
          width: width,
          height: height,
          color: context.colors.tint,
          child: Icon(AppIcons.bread, color: context.colors.blue, size: 40),
        );
    if (Uri.tryParse(name)?.scheme == 'https') {
      return Image.network(
        name,
        width: width,
        height: height,
        fit: fit,
        semanticLabel: label,
        excludeFromSemantics: label == null,
        errorBuilder: fallback,
      );
    }
    return Image.asset(
      'assets/images/$name.jpg',
      width: width,
      height: height,
      fit: fit,
      semanticLabel: label,
      excludeFromSemantics: label == null,
      cacheWidth: 1000,
      errorBuilder: fallback,
    );
  }
}

class ScreenScaffold extends StatelessWidget {
  const ScreenScaffold({
    super.key,
    required this.title,
    required this.child,
    this.bottom,
    this.actions,
    this.onBack,
  });
  final String title;
  final Widget child;
  final Widget? bottom;
  final List<Widget>? actions;
  final VoidCallback? onBack;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: AppText(title),
      leading: Navigator.canPop(context) || onBack != null
          ? IconButton(
              tooltip: context.tr('Späť'),
              icon: Icon(AppIcons.back),
              onPressed: onBack ?? () => Navigator.maybePop(context),
            )
          : null,
      actions: actions,
    ),
    body: Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: child,
      ),
    ),
    bottomNavigationBar: bottom == null
        ? null
        : Container(
            color: context.colors.canvas,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
                child: bottom,
              ),
            ),
          ),
  );
}

class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
    this.trailing,
    this.accent = false,
  });
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;
  final bool accent;
  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
    onTap: onTap,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    leading: Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: context.colors.tint,
        borderRadius: BorderRadius.circular(13),
      ),
      child: Icon(icon, size: 20, color: context.colors.blue),
    ),
    title: AppText(
      title,
      style: context.text.titleMedium?.copyWith(
        fontSize: 15,
        color: accent ? context.colors.blue : null,
      ),
    ),
    subtitle: subtitle == null
        ? null
        : AppText(subtitle!, style: context.text.bodySmall),
    trailing:
        trailing ??
        Icon(AppIcons.chevronRight, size: 16, color: context.colors.muted),
  );
}

class QuantityControl extends StatelessWidget {
  const QuantityControl({
    super.key,
    required this.value,
    required this.onChanged,
    this.max = 99,
    this.min = 0,
  });
  final int value, max, min;
  final ValueChanged<int> onChanged;
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: context.colors.tint,
      borderRadius: BorderRadius.circular(30),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: value == 1 && min == 0 ? 'Odstrániť' : 'Menej',
          onPressed: value > min ? () => onChanged(value - 1) : null,
          icon: Icon(
            value == 1 && min == 0 ? AppIcons.trash : AppIcons.minus,
            size: 16,
          ),
        ),
        AppText('$value', style: context.text.titleMedium),
        IconButton(
          tooltip: context.tr('Viac'),
          onPressed: value < max ? () => onChanged(value + 1) : null,
          icon: Icon(AppIcons.plus, size: 16),
        ),
      ],
    ),
  );
}

class PriceText extends StatelessWidget {
  const PriceText({
    super.key,
    required this.price,
    required this.original,
    this.large = false,
  });
  final int price, original;
  final bool large;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      AppText(
        euro(original),
        style: context.text.bodySmall?.copyWith(
          decoration: TextDecoration.lineThrough,
          color: context.colors.muted,
        ),
      ),
      AppText(
        euro(price),
        style: TextStyle(
          fontSize: large ? 28 : 21,
          fontWeight: FontWeight.w700,
          letterSpacing: -.7,
          color: context.colors.blue,
        ),
      ),
    ],
  );
}

class SheetHeading extends StatelessWidget {
  const SheetHeading(this.title, {super.key, this.onReset});
  final String title;
  final VoidCallback? onReset;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(child: AppText(title, style: context.text.titleLarge)),
      if (onReset != null)
        TextButton(onPressed: onReset, child: const AppText('Vymazať')),
      IconButton(
        tooltip: context.tr('Zavrieť'),
        onPressed: () => Navigator.pop(context),
        icon: Icon(AppIcons.close, size: 20),
      ),
    ],
  );
}

import 'package:flutter/material.dart';

/// Shared components depend on a text resolver, not on an application's locale catalog.
class UiLanguage extends InheritedWidget {
  const UiLanguage({
    super.key,
    required this.language,
    required this.resolve,
    required super.child,
  });
  final String language;
  final String Function(String) resolve;
  @override
  bool updateShouldNotify(UiLanguage oldWidget) =>
      language != oldWidget.language;
}

extension UiTranslation on BuildContext {
  String tr(String text) =>
      dependOnInheritedWidgetOfExactType<UiLanguage>()?.resolve(text) ?? text;
}

class AppText extends StatelessWidget {
  const AppText(
    this.data, {
    super.key,
    this.style,
    this.textAlign,
    this.maxLines,
    this.overflow,
    this.softWrap,
    this.semanticsLabel,
  });
  final String data;
  final TextStyle? style;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;
  final bool? softWrap;
  final String? semanticsLabel;
  @override
  Widget build(BuildContext context) => Text(
    context.tr(data),
    style: style,
    textAlign: textAlign,
    maxLines: maxLines,
    overflow: overflow,
    softWrap: softWrap,
    semanticsLabel: semanticsLabel == null ? null : context.tr(semanticsLabel!),
  );
}

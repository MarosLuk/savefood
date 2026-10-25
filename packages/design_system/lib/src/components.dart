import 'localization.dart';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'icons.dart';
import 'theme.dart';

class PrimaryButton extends StatelessWidget {
  const PrimaryButton(
    this.label, {
    super.key,
    this.onPressed,
    this.icon,
    this.busy = false,
    this.secondary = false,
  });
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool busy, secondary;
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: busy ? null : onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: secondary ? c.tint : c.blue,
          foregroundColor: secondary
              ? c.blue
              : (Theme.of(context).brightness == Brightness.dark
                    ? const Color(0xFF10233E)
                    : Colors.white),
          minimumSize: const Size(44, 56),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          textStyle: context.text.labelLarge?.copyWith(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
          shape: const StadiumBorder(),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (busy)
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            if (icon != null && !busy) Icon(icon, size: 20),
            if (busy || icon != null) const SizedBox(width: 10),
            Flexible(child: AppText(label, textAlign: TextAlign.center)),
          ],
        ),
      ),
    );
  }
}

class RoundButton extends StatelessWidget {
  const RoundButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.color,
    this.background,
    this.badge,
  });
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final Color? color, background;
  final int? badge;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 46,
    height: 46,
    child: Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: IconButton(
            tooltip: context.tr(label),
            onPressed: onPressed,
            style: IconButton.styleFrom(
              backgroundColor: background ?? context.colors.surface,
              foregroundColor: color ?? context.colors.ink,
              side: BorderSide(
                color: context.colors.line.withValues(alpha: .6),
              ),
            ),
            icon: Icon(icon, size: 22),
          ),
        ),
        if ((badge ?? 0) > 0)
          Positioned(
            top: -2,
            right: -2,
            child: IgnorePointer(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                constraints: const BoxConstraints(minWidth: 19, minHeight: 19),
                decoration: BoxDecoration(
                  color: context.colors.blue,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: context.colors.canvas, width: 2),
                ),
                child: AppText(
                  '$badge',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 10,
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

class SurfaceCard extends StatelessWidget {
  const SurfaceCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.color,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: color ?? context.colors.surface,
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: context.colors.line.withValues(alpha: .65)),
    ),
    child: child,
  );
}

class TagPill extends StatelessWidget {
  const TagPill(
    this.label, {
    super.key,
    this.icon,
    this.color,
    this.background,
  });
  final String label;
  final IconData? icon;
  final Color? color, background;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: background ?? context.colors.tint,
      borderRadius: BorderRadius.circular(30),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 14, color: color ?? context.colors.blue),
          const SizedBox(width: 5),
        ],
        Flexible(
          child: AppText(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color ?? context.colors.blue,
            ),
          ),
        ),
      ],
    ),
  );
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    this.action,
    this.onAction,
  });
  final IconData icon;
  final String title, description;
  final String? action;
  final VoidCallback? onAction;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(32),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 88,
          height: 88,
          decoration: BoxDecoration(
            color: context.colors.tint,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 40, color: context.colors.blue),
        ),
        const SizedBox(height: 24),
        AppText(
          title,
          style: context.text.titleLarge,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 10),
        AppText(
          description,
          textAlign: TextAlign.center,
          style: context.text.bodyLarge?.copyWith(color: context.colors.muted),
        ),
        if (action != null) ...[
          const SizedBox(height: 24),
          PrimaryButton(action!, onPressed: onAction),
        ],
      ],
    ),
  );
}

class GlassSurface extends StatelessWidget {
  const GlassSurface({super.key, required this.child, this.radius = 32});
  final Widget child;
  final double radius;
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(radius),
    child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
      child: Container(
        decoration: BoxDecoration(
          color: context.colors.surface.withValues(alpha: .92),
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: context.colors.line.withValues(alpha: .85)),
        ),
        child: child,
      ),
    ),
  );
}

class SectionHeading extends StatelessWidget {
  const SectionHeading(
    this.title, {
    super.key,
    this.subtitle,
    this.action,
    this.onAction,
  });
  final String title;
  final String? subtitle, action;
  final VoidCallback? onAction;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 0, 18, 14),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppText(title, style: context.text.titleLarge),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                AppText(
                  subtitle!,
                  style: context.text.bodyMedium?.copyWith(
                    color: context.colors.muted,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (action != null)
          TextButton(
            onPressed: onAction,
            child: Row(
              children: [
                AppText(action!),
                const SizedBox(width: 5),
                Icon(AppIcons.arrowRight, size: 16),
              ],
            ),
          ),
      ],
    ),
  );
}

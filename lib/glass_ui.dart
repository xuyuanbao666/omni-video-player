import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// Frosted surfaces are clipped to their own bounds. The video texture is
/// intentionally outside the blur layer so video pixels remain sharp.
class GlassPanel extends StatelessWidget {
  const GlassPanel({super.key, required this.child, this.enabled = true,
    this.radius = 24, this.padding = EdgeInsets.zero, this.blur = true});
  final Widget child;
  final bool enabled, blur;
  final double radius;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final corners = BorderRadius.circular(radius);
    final scheme = Theme.of(context).colorScheme;
    final surface = Material(
      type: MaterialType.transparency,
      child: Ink(
        decoration: BoxDecoration(
          borderRadius: corners,
          color: enabled ? null : scheme.surfaceContainer,
          gradient: enabled ? LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: dark ? [
              const Color(0xffdae8ff).withValues(alpha: .16),
              const Color(0xff15233c).withValues(alpha: .57),
            ] : [
              Colors.white.withValues(alpha: .84),
              const Color(0xffe3edff).withValues(alpha: .63),
            ],
          ) : null,
          border: Border.all(color: enabled
            ? (dark ? Colors.white.withValues(alpha: .20) : Colors.white.withValues(alpha: .90))
            : scheme.outlineVariant),
        ),
        child: Padding(padding: padding, child: child),
      ),
    );
    return ClipRRect(
      borderRadius: corners,
      child: enabled && blur
        ? BackdropFilter(filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12), child: surface)
        : surface,
    );
  }
}

/// App-local aurora background. No image fetching or wallpaper access.
class GlassBackdrop extends StatelessWidget {
  const GlassBackdrop({super.key, required this.child, this.enabled = true});
  final Widget child;
  final bool enabled;
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return DecoratedBox(
      decoration: BoxDecoration(gradient: LinearGradient(
        begin: Alignment.topLeft, end: Alignment.bottomRight,
        colors: !enabled ? const [Colors.transparent, Colors.transparent] : dark ? const [Color(0xff0b1429), Color(0xff1c2449), Color(0xff102d37)]
          : const [Color(0xffe4eeff), Color(0xfff1e9ff), Color(0xffe1f7f4)],
      )),
      child: Stack(fit: StackFit.expand, children: [
        Positioned.fill(child: IgnorePointer(child: DecoratedBox(
          decoration: BoxDecoration(gradient: RadialGradient(
            center: const Alignment(-.94, -.85), radius: .95,
            colors: !enabled ? const [Colors.transparent, Colors.transparent] : dark ? const [Color(0xff394e86), Color(0x00394e86)]
              : const [Color(0xffadc9fa), Color(0x00adc9fa)],
          )),
        ))),
        Positioned.fill(child: IgnorePointer(child: DecoratedBox(
          decoration: BoxDecoration(gradient: RadialGradient(
            center: const Alignment(.95, .95), radius: .85,
            colors: !enabled ? const [Colors.transparent, Colors.transparent] : dark ? const [Color(0xff1c5a62), Color(0x001c5a62)]
              : const [Color(0xff9edbd4), Color(0x009edbd4)],
          )),
        ))),
        child,
      ]),
    );
  }
}

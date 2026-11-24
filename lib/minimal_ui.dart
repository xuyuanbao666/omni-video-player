import 'package:flutter/material.dart';
import 'glass_ui.dart';

/// New in-app brand mark, scalable without bundled image assets.
class OmniMark extends StatelessWidget {
  const OmniMark({super.key, this.size = 48, this.animate = false});
  final double size;
  final bool animate;
  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    final mark = Container(width: size, height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * .30),
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [const Color(0xffb8d6ff), color, const Color(0xff45547b)]),
        border: Border.all(color: Colors.white.withValues(alpha: .55)),
      ),
      child: Icon(Icons.play_arrow_rounded, color: const Color(0xff10182a), size: size*.65));
    if (!animate || MediaQuery.disableAnimationsOf(context)) return mark;
    return TweenAnimationBuilder<double>(tween: Tween(begin: .88,end: 1), duration: const Duration(milliseconds: 360),
      curve: Curves.easeOutCubic, child: mark,
      builder: (_, value, child) => Opacity(opacity: ((value-.88)/.12).clamp(0.0,1.0).toDouble(), child: Transform.scale(scale:value,child:child)));
  }
}

class FloatingDock extends StatelessWidget {
  const FloatingDock({super.key, required this.visible, required this.glass, required this.child});
  final bool visible, glass;
  final Widget child;
  @override
  Widget build(BuildContext context) => IgnorePointer(
    ignoring: !visible,
    child: ExcludeSemantics(excluding: !visible,
      child: ExcludeFocus(excluding: !visible, child: AnimatedOpacity(
        duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 220),
        curve: Curves.easeOut, opacity: visible ? 1 : 0,
        // No expensive live blur on the video texture. The tint remains readable.
        child: DecoratedBox(decoration: BoxDecoration(color: const Color(0xb810182a), borderRadius: BorderRadius.circular(28)),
          child: GlassPanel(enabled: glass, blur: false, radius: 28, padding: const EdgeInsets.fromLTRB(8,4,8,6), child: child)),
      )),
    ),
  );
}

/// Video controls use a thin edge gradient, never a frosted card over the film.
class CinemaControls extends StatelessWidget {
  const CinemaControls({super.key, required this.visible, required this.fullscreen, required this.child});
  final bool visible, fullscreen;
  final Widget child;
  @override
  Widget build(BuildContext context) => IgnorePointer(ignoring: !visible,
    child: ExcludeSemantics(excluding: !visible,
      child: ExcludeFocus(excluding: !visible, child: AnimatedOpacity(
        duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 160),
        opacity: visible ? 1 : 0,
        child: DecoratedBox(decoration: BoxDecoration(
          gradient: fullscreen ? const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [Colors.transparent, Color(0x99000000), Color(0xd9000000)]) : null),
          child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: child),
        ),
      )),
    ));
}

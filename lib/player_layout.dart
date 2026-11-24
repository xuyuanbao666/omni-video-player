import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

enum ScreenDirection { automatic, landscape, portrait }
List<DeviceOrientation> orientationsFor(ScreenDirection direction, {required bool fullscreen}) {
  if (fullscreen || direction == ScreenDirection.landscape) {
    return const [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight];
  }
  if (direction == ScreenDirection.portrait) return const [DeviceOrientation.portraitUp];
  return const [];
}

/// Full-width 16:9 surface on narrow portrait layouts. The footer has a
/// separate scroll region; it can never shrink the video to its text width.
class PlayerStage extends StatelessWidget {
  const PlayerStage({super.key, required this.surface, required this.footer, required this.fill, this.empty = false});
  final Widget surface, footer;
  final bool fill, empty;
  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, constraints) {
    final portrait = !fill && constraints.maxWidth < 700 && constraints.maxHeight > constraints.maxWidth;
    final width = constraints.maxWidth;
    final height = portrait
        ? math.min(width * 9 / 16, constraints.maxHeight).toDouble()
        : (fill ? constraints.maxHeight : math.max(0.0, constraints.maxHeight - (empty ? math.min(240.0, constraints.maxHeight * .48) : 64.0)).toDouble());
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SizedBox(width: width, height: height, child: surface),
      if (!fill) Expanded(child: SingleChildScrollView(child: footer)),
    ]);
  });
}

/// Dragging changes only this widget. The seek callback is invoked once on
/// release, rather than rebuilding the texture or issuing seeks on each tick.
class PlaybackScrubber extends StatefulWidget {
  const PlaybackScrubber({super.key, required this.position, required this.duration,
    required this.initialPosition, required this.initialDuration, required this.enabled,
    required this.onScrubbing, required this.onSeek, required this.formatTime});
  final Stream<Duration> position, duration;
  final Duration initialPosition, initialDuration;
  final bool enabled;
  final ValueChanged<bool> onScrubbing;
  final Future<void> Function(double) onSeek;
  final String Function(int) formatTime;
  @override
  State<PlaybackScrubber> createState() => _PlaybackScrubberState();
}
class _PlaybackScrubberState extends State<PlaybackScrubber> {
  double? preview;
  bool dragging = false;
  bool committing = false;
  int generation = 0;
  @override
  void dispose() {
    // Parent owns the dock timer and clears it when the source changes.
    generation++;
    super.dispose();
  }
  Future<void> commit(double value) async {
    if (!dragging || committing) return;
    final token = ++generation;
    setState(() { dragging = false; committing = true; preview = value; });
    try { await widget.onSeek(value); }
    finally {
      if (mounted && token == generation) {
        setState(() { preview = null; committing = false; });
        widget.onScrubbing(false);
      }
    }
  }
  @override
  Widget build(BuildContext context) => StreamBuilder<Duration>(
    stream: widget.duration, initialData: widget.initialDuration,
    builder: (context, duration) => StreamBuilder<Duration>(
      stream: widget.position, initialData: widget.initialPosition,
      builder: (context, position) {
        final total = (duration.data ?? Duration.zero).inMilliseconds.toDouble();
        final value = (preview ?? (position.data ?? Duration.zero).inMilliseconds.toDouble())
          .clamp(0.0, math.max(0.0, total)).toDouble();
        return Column(mainAxisSize: MainAxisSize.min, children: [
          SliderTheme(data: SliderTheme.of(context).copyWith(trackHeight: 3),
            child: Slider(value: value, max: total > 0 ? total : 1,
              onChangeStart: widget.enabled && !committing && total > 0 ? (v) {
                widget.onScrubbing(true);
                setState(() { dragging = true; preview = v; });
              } : null,
              onChanged: widget.enabled && !committing && total > 0 ? (v) => setState(() => preview = v) : null,
              onChangeEnd: widget.enabled && !committing && total > 0 ? (v) => unawaited(commit(v)) : null)),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 14), child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text(widget.formatTime(value.round()), style: const TextStyle(fontSize: 11)),
              Text(total > 0 ? widget.formatTime(total.round()) : '--:--', style: const TextStyle(fontSize: 11)),
            ])),
        ]);
      }));
}

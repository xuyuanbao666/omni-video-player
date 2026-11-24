import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'playback_history.dart';

bool canCachePreview(String source) => canRemember(source) && Uri.parse(source).scheme == 'file';

class VideoPreview {
  const VideoPreview(this.bytes, this.accent);
  final Uint8List bytes;
  final Color accent;
}

/// Small bounded cache. Only replayable local media may be persisted.
class PreviewCache {
  static const limit = 24;
  static const maxBytes = 64 * 1024;
  final Map<String, VideoPreview> _items = {};
  VideoPreview? operator [](String key) => _items[key];
  void put(String source, VideoPreview preview) {
    if (!canCachePreview(source) || preview.bytes.isEmpty || preview.bytes.length > maxBytes) return;
    _items.remove(source);
    _items[source] = preview;
    while (_items.length > limit) { _items.remove(_items.keys.first); }
  }
  void remove(String key) => _items.remove(key);
  void clear() => _items.clear();
  String encode() => jsonEncode([for (final e in _items.entries)
    {'source': e.key, 'image': base64Encode(e.value.bytes), 'accent': e.value.accent.toARGB32()}]);
  static PreviewCache decode(String? input) {
    final cache = PreviewCache();
    if (input == null || input.length > 2200000) return cache;
    try {
      final data = jsonDecode(input);
      if (data is List) {
        for (final e in data.take(limit)) {
          if (e is! Map || e['source'] is! String || e['image'] is! String || e['accent'] is! int) continue;
          try {
            final source = e['source'] as String;
            final encoded = e['image'] as String;
            if (!canCachePreview(source) || encoded.length > 90000) continue;
            final bytes = base64Decode(encoded);
            if (bytes.length < 8 || bytes[0] != 137 || bytes[1] != 80 || bytes[2] != 78 || bytes[3] != 71) continue;
            cache.put(source, VideoPreview(bytes, Color(e['accent'] as int)));
          } catch (_) { /* Ignore invalid entries. */ }
        }
      }
    } catch (_) { /* Ignore invalid cache. */ }
    return cache;
  }
}

/// Resize the actual video frame and sample a restrained accent from it.
Future<VideoPreview?> makePreview(Uint8List bytes) async {
  if (bytes.isEmpty || bytes.length > 40 * 1024 * 1024) return null;
  final codec = await ui.instantiateImageCodec(bytes, targetWidth: 160, allowUpscaling: false);
  try {
    final frame = await codec.getNextFrame();
    final image = frame.image;
    try {
      final rgba = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      if (rgba == null || png == null || png.lengthInBytes > PreviewCache.maxBytes) return null;
      var red = 0.0, green = 0.0, blue = 0.0, weight = 0.0;
      for (var i = 0; i + 3 < rgba.lengthInBytes; i += 16) {
        final r = rgba.getUint8(i), g = rgba.getUint8(i+1), b = rgba.getUint8(i+2);
        final hsv = HSVColor.fromColor(Color.fromARGB(255,r,g,b));
        if (hsv.value < .15 || hsv.value > .96 || hsv.saturation < .12) continue;
        final w = hsv.saturation;
        red += r*w; green += g*w; blue += b*w; weight += w;
      }
      var accent = const Color(0xff789dff);
      if (weight > 0) {
        final hsv = HSVColor.fromColor(Color.fromARGB(255,(red/weight).round(),(green/weight).round(),(blue/weight).round()));
        accent = hsv.withSaturation(hsv.saturation.clamp(.35,.72).toDouble()).withValue(.88).toColor();
      }
      return VideoPreview(png.buffer.asUint8List(png.offsetInBytes,png.lengthInBytes), accent);
    } finally { image.dispose(); }
  } finally { codec.dispose(); }
}

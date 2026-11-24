import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_player/preview_cache.dart';

void main() {
  final preview = VideoPreview(Uint8List.fromList([137,80,78,71,13,10,26,10]),const Color(0xff789dff));
  test('preview cache is bounded, local-only and round-trips', () {
    final cache = PreviewCache();
    for(var i=0;i<30;i++){cache.put('file:///video$i.mp4',preview);}
    cache.put('https://example.com/video.mp4',preview);
    expect(cache['file:///video0.mp4'],isNull);
    expect(cache['https://example.com/video.mp4'],isNull);
    final decoded = PreviewCache.decode(cache.encode());
    expect(decoded['file:///video29.mp4']?.accent,preview.accent);
    decoded.clear();
    expect(decoded['file:///video29.mp4'],isNull);
  });
  test('oversize and corrupt cache ignored', () {
    final cache = PreviewCache();
    cache.put('file:///large.mp4',VideoPreview(Uint8List(PreviewCache.maxBytes+1),Colors.red));
    expect(cache['file:///large.mp4'],isNull);
    expect(PreviewCache.decode('bad')['file:///large.mp4'],isNull);
    expect(canCachePreview('blob:temporary'),isFalse);
  });
}

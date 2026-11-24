import 'package:flutter_test/flutter_test.dart';
import 'package:omni_player/playback_history.dart';

void main() {
  test('retains only replayable sources without URL credentials or query', () {
    expect(canRemember('https://example.com/video.mp4'), isTrue);
    expect(canRemember('file:///tmp/video.mp4'), isTrue);
    for (final uri in ['blob:abc','content://a/b','https://a:b@example.com/a','https://example.com/a?token=x','https://example.com/a#secret']) {
      expect(canRemember(uri), isFalse);
    }
  });
  test('stores latest position and restores history', () {
    final h = PlaybackHistory();
    h.remember(const HistoryEntry('file:///a.mp4', 'a', 6000, 60000, 1));
    h.remember(const HistoryEntry('file:///a.mp4', 'a', 12000, 60000, 2));
    final restored = PlaybackHistory.decode(h.encode());
    expect(restored.entries.length, 1);
    expect(restored.entries.first.resumeAt, const Duration(seconds: 12));
    restored.remove('file:///a.mp4');
    expect(restored.entries, isEmpty);
  });
  test('skips resume near beginning, end, or unknown duration', () {
    expect(const HistoryEntry('file:///a', 'a', 4000, 60000, 1).resumeAt, isNull);
    expect(const HistoryEntry('file:///a', 'a', 58000, 60000, 1).resumeAt, isNull);
    expect(const HistoryEntry('file:///a', 'a', 0, 0, 1).resumeAt, isNull);
  });
  test('history is bounded and corrupt preferences are ignored', () {
    final h = PlaybackHistory();
    for (var i = 0; i < 130; i++) {
      h.remember(HistoryEntry('file:///$i.mp4', '$i', 10000, 60000, i));
    }
    expect(h.entries.length, 100);
    expect(h.entries.first.title, '129');
    expect(PlaybackHistory.decode('broken json').entries, isEmpty);
    h.clear();
    expect(h.entries, isEmpty);
  });
}

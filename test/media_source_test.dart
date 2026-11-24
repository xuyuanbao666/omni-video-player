import 'package:flutter_test/flutter_test.dart';
import 'package:omni_player/media_source.dart';
void main() {
  test('accepts http and https media URLs', () {
    expect(parseNetworkSource(' https://example.com/video.mp4 ')?.host, 'example.com');
    expect(parseNetworkSource('http://example.com/stream.m3u8'), isNotNull);
  });
  test('rejects malformed URLs and unintended protocols', () {
    for (final value in ['', 'file:///etc/passwd', 'javascript:alert(1)', 'https://', 'https://user:pass@example.com/a.mp4']) {
      expect(parseNetworkSource(value), isNull, reason: value);
    }
  });
}

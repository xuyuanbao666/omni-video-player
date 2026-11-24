import 'dart:convert';
import 'package:http/http.dart' as http;

const currentVersion = '0.3.0';
const releasesPage = 'https://github.com/xuyuanbao666/omni-video-player/releases';
final _version = RegExp(r'^v?([0-9]{1,6})\.([0-9]{1,6})\.([0-9]{1,6})$');

bool isNewerVersion(String candidate, String current) {
  final a = _version.firstMatch(candidate), b = _version.firstMatch(current);
  if (a == null || b == null) return false;
  for (var i = 1; i <= 3; i++) {
    final x = int.parse(a.group(i)!), y = int.parse(b.group(i)!);
    if (x != y) return x > y;
  }
  return false;
}

/// No binary download, token, device identifier or media metadata is sent.
Future<String?> checkForUpdate({http.Client? client}) async {
  final own = client == null;
  final c = client ?? http.Client();
  try {
    final response = await c.get(Uri.https('api.github.com',
      '/repos/xuyuanbao666/omni-video-player/releases/latest'),
      headers: {'Accept': 'application/vnd.github+json'}).timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) throw StateError('Update service unavailable');
    final data = jsonDecode(response.body);
    if (data is! Map || data['draft'] != false || data['prerelease'] != false ||
        data['tag_name'] is! String) throw FormatException('Invalid release response');
    final tag = data['tag_name'] as String;
    return isNewerVersion(tag, currentVersion) ? tag : null;
  } finally { if (own) c.close(); }
}

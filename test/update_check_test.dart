import 'package:flutter_test/flutter_test.dart';
import 'package:omni_player/update_check.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('compares stable semantic versions numerically', () {
    expect(isNewerVersion('v0.10.0','0.3.0'),isTrue);
    expect(isNewerVersion('v0.3.0','0.3.0'),isFalse);
    expect(isNewerVersion('v0.2.0','0.3.0'),isFalse);
    expect(isNewerVersion('preview-v1.0.0','0.3.0'),isFalse);
    expect(isNewerVersion('v1.0.0-beta','0.3.0'),isFalse);
  });
  test('only accepts stable GitHub release responses', () async {
    final client = MockClient((request) async {
      expect(request.url.host,'api.github.com');
      return http.Response('{"tag_name":"v0.6.0","draft":false,"prerelease":false}',200);
    });
    expect(await checkForUpdate(client: client),'v0.6.0');
    final preview = MockClient((_) async => http.Response('{"tag_name":"v9.0.0","draft":false,"prerelease":true}',200));
    await expectLater(checkForUpdate(client: preview),throwsFormatException);
  });
}

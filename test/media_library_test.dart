import 'package:flutter_test/flutter_test.dart';
import 'package:omni_player/media_library.dart';

void main() {
  test('deduplicates and searches imported media', () {
    final library = MediaLibrary();
    expect(library.add('file:///a.mp4','Movie A'), isTrue);
    expect(library.add('file:///a.mp4','A'), isFalse);
    library.add('file:///b.mp4','Movie B');
    library.toggle('file:///a.mp4');
    expect(library.search('movie', favoritesOnly: true).single.title,'Movie A');
    final decoded = MediaLibrary.decode(library.encode());
    expect(decoded.search('A', favoritesOnly: true).single.favorite,isTrue);
    decoded.remove('file:///a.mp4');
    expect(decoded.items.length,1);
  });
  test('does not persist ephemeral or credential-bearing sources', () {
    final library = MediaLibrary();
    library.add('blob:temporary','Temporary');
    library.add('https://example.com/a?token=private','Private');
    library.add('file:///a.mp4','Movie');
    expect(MediaLibrary.decode(library.encode()).items.single.title,'Movie');
    expect(MediaLibrary.decode('not json').items,isEmpty);
  });
}

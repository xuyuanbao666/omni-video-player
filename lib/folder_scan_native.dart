import 'dart:io';

const extensions = {'mp4','mkv','mov','avi','webm','m4v','mp3','flac','wav','ogg','ts','m4a','aac','mpeg','mpg'};
/// Scan only a directory the user explicitly selected. Never follow symlinks.
Future<List<Uri>> scanFolder(String path) async {
  final result = <Uri>[];
  final pending = <Directory>[Directory(path)];
  var inspected = 0;
  while (pending.isNotEmpty && result.length < 1000 && inspected < 10000) {
    final directory = pending.removeLast();
    try {
      await for (final entry in directory.list(followLinks: false)) {
        if (++inspected > 10000 || result.length >= 1000) break;
        if (entry is Directory && pending.length < 500) {
          pending.add(entry);
        } else if (entry is File && extensions.contains(entry.path.split('.').last.toLowerCase())) {
          result.add(entry.uri);
        }
      }
    } on FileSystemException { /* inaccessible subtree */ }
  }
  return result;
}

import 'dart:convert';
import 'playback_history.dart';

class LibraryItem {
  final String source;
  final String title;
  final bool favorite;
  const LibraryItem(this.source, this.title, {this.favorite = false});
  Map<String, Object> toJson() => {'source': source, 'title': title, 'favorite': favorite};
}

class MediaLibrary {
  static const maxItems = 2000;
  final List<LibraryItem> _items = [];
  List<LibraryItem> get items => List.unmodifiable(_items);
  bool add(String source, String title) {
    if (source.isEmpty || source.length > 4096 || _items.length >= maxItems ||
        _items.any((v) => v.source == source)) return false;
    _items.insert(0, LibraryItem(source, title));
    return true;
  }
  void remove(String source) => _items.removeWhere((v) => v.source == source);
  void toggle(String source) {
    final index = _items.indexWhere((v) => v.source == source);
    if (index < 0) return;
    final v = _items[index];
    _items[index] = LibraryItem(v.source, v.title, favorite: !v.favorite);
  }
  List<LibraryItem> search(String query, {bool favoritesOnly = false}) {
    final q = query.trim().toLowerCase();
    return _items.where((v) => (!favoritesOnly || v.favorite) &&
      v.title.toLowerCase().contains(q)).toList();
  }
  String encode() => jsonEncode(_items.where((v) => canRemember(v.source))
    .map((v) => v.toJson()).toList());
  static MediaLibrary decode(String? input) {
    final result = MediaLibrary();
    try {
      final values = jsonDecode(input ?? '[]');
      if (values is List) {
        for (final v in values.take(maxItems).toList().reversed) {
          if (v is Map && v['source'] is String && v['title'] is String &&
              canRemember(v['source'] as String)) {
            final source = v['source'] as String;
            if (result.add(source, v['title'] as String) && v['favorite'] == true) result.toggle(source);
          }
        }
      }
    } catch (_) { /* Ignore corrupt local state. */ }
    return result;
  }
}

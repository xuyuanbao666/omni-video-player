import 'dart:convert';

/// Only persist replayable sources. Blob/content URIs are temporary; URL query
/// strings may contain credentials and are deliberately not retained.
bool canRemember(String source) {
  final uri = Uri.tryParse(source);
  if (uri == null || source.isEmpty || source.length > 4096) return false;
  if (uri.scheme == 'file') return !uri.hasQuery && !uri.hasFragment;
  if (uri.scheme == 'http' || uri.scheme == 'https') {
    return uri.host.isNotEmpty && uri.userInfo.isEmpty && !uri.hasQuery && !uri.hasFragment;
  }
  return false;
}

class HistoryEntry {
  final String source;
  final String title;
  final int positionMs;
  final int durationMs;
  final int updatedMs;
  const HistoryEntry(this.source, this.title, this.positionMs, this.durationMs, this.updatedMs);

  Duration? get resumeAt {
    if (positionMs < 5000 || durationMs <= 0 ||
        positionMs >= durationMs - 5000) return null;
    return Duration(milliseconds: positionMs);
  }

  Map<String, Object> toJson() => {
    'source': source, 'title': title, 'position': positionMs,
    'duration': durationMs, 'updated': updatedMs,
  };

  static HistoryEntry? parse(Object? value) {
    if (value is! Map) return null;
    final source = value['source'];
    final title = value['title'];
    final position = value['position'];
    final duration = value['duration'];
    final updated = value['updated'];
    if (source is! String || !canRemember(source) || title is! String ||
        position is! int || duration is! int || updated is! int ||
        position < 0 || duration < 0 || position > duration || updated < 0) return null;
    return HistoryEntry(source, title, position, duration, updated);
  }
}

class PlaybackHistory {
  static const limit = 100;
  final List<HistoryEntry> _entries = [];
  List<HistoryEntry> get entries => List.unmodifiable(_entries);

  HistoryEntry? find(String source) {
    for (final entry in _entries) {
      if (entry.source == source) return entry;
    }
    return null;
  }

  void remember(HistoryEntry entry) {
    if (!canRemember(entry.source) || entry.durationMs <= 0 ||
        entry.positionMs < 0 || entry.positionMs > entry.durationMs) return;
    _entries.removeWhere((v) => v.source == entry.source);
    _entries.insert(0, entry);
    if (_entries.length > limit) _entries.removeRange(limit, _entries.length);
  }

  void remove(String source) => _entries.removeWhere((v) => v.source == source);
  void clear() => _entries.clear();
  String encode() => jsonEncode(_entries.map((v) => v.toJson()).toList());
  static PlaybackHistory decode(String? input) {
    final history = PlaybackHistory();
    if (input == null) return history;
    try {
      final data = jsonDecode(input);
      if (data is List) {
        for (final item in data.take(limit).toList().reversed) {
          final entry = HistoryEntry.parse(item);
          if (entry != null) history.remember(entry);
        }
      }
    } catch (_) { /* Ignore corrupted local preferences. */ }
    return history;
  }
}

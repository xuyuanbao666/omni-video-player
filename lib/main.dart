import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart' show Share;
import 'package:file_selector/file_selector.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'media_source.dart';
import 'playback_history.dart';
import 'media_library.dart';
import 'folder_scan.dart';
import 'update_check.dart';
import 'glass_ui.dart';
import 'minimal_ui.dart';
import 'preview_cache.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:url_launcher/url_launcher.dart';

late final SharedPreferences preferences;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  preferences = await SharedPreferences.getInstance();
  runApp(const OmniPlayerApp());
}

class OmniPlayerApp extends StatefulWidget {
  const OmniPlayerApp({super.key});
  @override
  State<OmniPlayerApp> createState() => _OmniPlayerAppState();
}

class _OmniPlayerAppState extends State<OmniPlayerApp> {
  late bool english = preferences.getBool('english') ?? false;
  late bool light = preferences.getBool('lightTheme') ?? false;
  late bool glass = preferences.getBool('glassTheme') ?? true;
  Color? videoAccent;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Omni Player', debugShowCheckedModeBanner: false,
    locale: Locale(english ? 'en' : 'zh'),
    supportedLocales: const [Locale('en'), Locale('zh')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    theme: ThemeData(useMaterial3: true, brightness: light ? Brightness.light : Brightness.dark,
      colorSchemeSeed: videoAccent ?? (glass ? const Color(0xff729cde) : const Color(0xff38bca0)),
      scaffoldBackgroundColor: glass ? (light ? const Color(0xffe4eeff) : const Color(0xff0b1429)) : (light ? const Color(0xffedf2f5) : const Color(0xff10141b)),
      appBarTheme: const AppBarTheme(elevation: 0, scrolledUnderElevation: 0, surfaceTintColor: Colors.transparent),
      dialogTheme: DialogThemeData(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28))),
      inputDecorationTheme: InputDecorationTheme(filled: true, fillColor: light ? Colors.white54 : const Color(0x25232f50), border: OutlineInputBorder(borderRadius: BorderRadius.circular(20)), contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12)),
    ),
    home: PlayerScreen(english: english, light: light, glass: glass,
      onAccent: (color) { if (mounted && videoAccent != color) setState(() => videoAccent = color); },
      onAppearance: (e, l, g) {
        setState(() { english = e; light = l; glass = g; });
        unawaited(preferences.setBool('english', e));
        unawaited(preferences.setBool('lightTheme', l));
        unawaited(preferences.setBool('glassTheme', g));
      }),
  );
}

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key, required this.english, required this.light, required this.glass, required this.onAppearance, required this.onAccent});
  final bool english, light, glass;
  final void Function(bool, bool, bool) onAppearance;
  final ValueChanged<Color?> onAccent;
  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> with WidgetsBindingObserver {
  late final Player player;
  late final VideoController controller;
  final List<StreamSubscription<dynamic>> subscriptions = [];
  Playlist playlist = const Playlist([]);
  bool busy = false;
  bool buffering = false;
  bool playing = false;
  double rate = 1;
  double volume = 100;
  PlaylistMode mode = PlaylistMode.none;
  String? error;
  final Map<String, String> labels = {};
  late final PlaybackHistory history;
  late bool rememberHistory;
  late bool resumePlayback;
  late bool hardwareAcceleration;
  late final Timer historyTimer;
  Future<void> historyWrite = Future.value();
  static const pipChannel = MethodChannel('omni_player/pip');
  bool pipAvailable = false;
  bool inPip = false;
  bool compact = false;
  bool immersive = false;
  late final MediaLibrary library;
  String libraryQuery = '';
  bool favoritesOnly = false;
  bool libraryTab = false;
  bool sortAscending = false;
  bool gridLibrary = true;
  int mobilePage = 0;
  bool dockVisible = true;
  bool autoHide = true;
  bool thumbnailsEnabled = true;
  bool dynamicAccent = true;
  bool previewBusy = false;
  bool dockHovered = false;
  bool foreground = true;
  Timer? dockTimer;
  late final PreviewCache previews;
  String? attemptedPreview;
  Future<void> previewWrite = Future.value();
  BoxFit videoFit = BoxFit.contain;
  double dim = 0;
  double? seekPreview;
  double? gestureTarget;
  double gestureRate = 1;
  Future<void>? rateGesture;
  int gestureSide = 0;
  String? gestureMessage;
  Timer? gestureTimer;
  bool checkingUpdates = false;
  String? availableUpdate;
  late bool autoUpdate;
  double lastVolume = 100;
  Future<void> libraryWrite = Future.value();
  final keyboardFocus = FocusNode();
  bool get mobile => !kIsWeb && [TargetPlatform.android, TargetPlatform.iOS].contains(defaultTargetPlatform);
  bool get hasMedia => playlist.medias.isNotEmpty && playlist.index >= 0 && playlist.index < playlist.medias.length;
  String tr(String zh, String en) => widget.english ? en : zh;
  String get nowPlaying => hasMedia ? title(playlist.medias[playlist.index]) : tr('尚未选择媒体', 'No media selected');
  bool get android => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  bool get desktop => !kIsWeb && [TargetPlatform.windows, TargetPlatform.macOS, TargetPlatform.linux].contains(defaultTargetPlatform);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    history = PlaybackHistory.decode(preferences.getString('history'));
    library = MediaLibrary.decode(preferences.getString('library'));
    previews = PreviewCache.decode(preferences.getString('previews'));
    thumbnailsEnabled = preferences.getBool('thumbnailsEnabled') ?? true;
    dynamicAccent = preferences.getBool('dynamicAccent') ?? true;
    autoHide = preferences.getBool('autoHide') ?? true;
    gridLibrary = preferences.getBool('gridLibrary') ?? true;
    autoUpdate = preferences.getBool('autoUpdate') ?? true;
    WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted && autoUpdate) unawaited(checkUpdates(silent: true)); });
    rememberHistory = preferences.getBool('rememberHistory') ?? true;
    resumePlayback = preferences.getBool('resumePlayback') ?? true;
    hardwareAcceleration = preferences.getBool('hardwareAcceleration') ?? true;
    player = Player();
    controller = VideoController(player, configuration: VideoControllerConfiguration(
      enableHardwareAcceleration: hardwareAcceleration,
      hwdec: hardwareAcceleration ? null : 'no',
    ));
    historyTimer = Timer.periodic(const Duration(seconds: 5), (_) { savePosition(); if (foreground) unawaited(capturePreview()); });
    if (android) {
      pipChannel.setMethodCallHandler((call) async {
        if (call.method == 'changed' && mounted) {
          setState(() => inPip = call.arguments == true);
        }
      });
      unawaited(checkPip());
    }
    subscriptions.add(player.stream.playlist.listen((v) {
      if (!mounted) return;
      final before = currentSource;
      setState(() => playlist = v);
      if (before != currentSource) {
        attemptedPreview = null;
        final key = currentSource;
        widget.onAccent(dynamicAccent && key != null ? previews[key]?.accent : null);
        revealDock();
      }
    }));
    subscriptions.add(player.stream.buffering.listen((v) { if (mounted) setState(() => buffering = v); }));
    subscriptions.add(player.stream.playing.listen((v) { if (mounted) { setState(() => playing = v); if (!v) savePosition(); revealDock(); } }));
    subscriptions.add(player.stream.rate.listen((v) { if (mounted) setState(() => rate = v); }));
    subscriptions.add(player.stream.volume.listen((v) { if (mounted) setState(() => volume = v); }));
    subscriptions.add(player.stream.playlistMode.listen((v) { if (mounted) setState(() => mode = v); }));
    subscriptions.add(player.stream.error.listen((_) { if (mounted) setState(() => error = tr('无法播放此媒体，请检查格式、网络或文件权限。', 'Cannot play media. Check format, network or file access.')); }));
  }

  String? get currentSource => hasMedia ? playlist.medias[playlist.index].uri : null;

  void revealDock() {
    dockTimer?.cancel();
    if (!mounted) return;
    if (!dockVisible) setState(() => dockVisible = true);
    if (!autoHide || !playing || dockHovered || busy || !foreground ||
        MediaQuery.maybeOf(context)?.accessibleNavigation == true) return;
    dockTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && playing && !busy && !dockHovered && seekPreview == null && foreground) {
        setState(() => dockVisible = false);
      }
    });
  }

  void persistPreviews() {
    final data = previews.encode();
    previewWrite = previewWrite.then((_) async {
      try { await preferences.setString('previews', data); } catch (_) {}
    });
  }

  Future<void> capturePreview() async {
    final source = currentSource;
    if (!mounted || !foreground || !thumbnailsEnabled || previewBusy || busy || buffering ||
        inPip || !playing || source == null || !canCachePreview(source) ||
        !library.items.any((v) => v.source == source) || previews[source] != null ||
        attemptedPreview == source || player.state.position.inSeconds < 3) return;
    attemptedPreview = source;
    previewBusy = true;
    try {
      final bytes = await player.screenshot(format: 'image/png');
      if (bytes == null || !mounted || currentSource != source) return;
      final preview = await makePreview(bytes);
      if (!mounted || !foreground || !thumbnailsEnabled || currentSource != source || preview == null ||
          !library.items.any((v) => v.source == source)) return;
      setState(() => previews.put(source, preview));
      persistPreviews();
      if (dynamicAccent) widget.onAccent(preview.accent);
    } catch (_) { /* Unsupported capture, audio-only or restricted video: placeholder remains. */ }
    finally { previewBusy = false; }
  }

  void removeFromLibrary(String source) {
    setState(() { library.remove(source); previews.remove(source); });
    persistLibrary(); persistPreviews();
    if (currentSource == source) widget.onAccent(null);
  }

  void persistLibrary() {
    final data = library.encode();
    libraryWrite = libraryWrite.then((_) async {
      try { await preferences.setString('library', data); } catch (_) { /* local storage unavailable */ }
    });
  }

  void addLibrary(String source, String name) {
    if (library.add(source, name)) persistLibrary();
  }

  Future<void> importFolder() => run(() async {
    final directory = await getDirectoryPath();
    if (directory == null || !mounted) return;
    final sources = await scanFolder(directory);
    if (!mounted) return;
    for (final source in sources) {
      addLibrary(source.toString(), source.pathSegments.last);
    }
    setState(() { libraryTab = true; mobilePage = 1; });
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(tr('扫描到 ${sources.length} 个媒体文件（最多 1000）', 'Found ${sources.length} media files (max 1000)'))));
  });

  Future<void> openLibrary(LibraryItem item) => run(() async {
    final media = mediaFor(item.source);
    labels[media.uri] = item.title;
    await player.open(media);
    if (mounted) setState(() { libraryTab = false; mobilePage = 0; });
  });

  Future<void> checkUpdates({bool silent = false}) async {
    if (checkingUpdates || !mounted) return;
    setState(() => checkingUpdates = true);
    try {
      final tag = await checkForUpdate();
      if (!mounted) return;
      setState(() => availableUpdate = tag);
      if (!silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tag == null
          ? tr('已是最新正式版本', 'You have the latest stable release')
          : tr('发现新版本 $tag', 'New release $tag'))));
      }
    } catch (_) {
      if (!silent && mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('更新检查失败，请稍后重试', 'Update check failed. Try again later.'))));
    } finally { if (mounted) setState(() => checkingUpdates = false); }
  }

  Future<void> openReleasePage() async {
    try {
      if (!await launchUrl(Uri.parse(releasesPage), mode: LaunchMode.externalApplication)) {
        throw StateError('Cannot open releases');
      }
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(releasesPage)));
    }
  }

  Future<void> audioTracks() async {
    if (busy || !hasMedia) return;
    final tracks = player.state.tracks.audio;
    final selected = await showDialog<AudioTrack>(context: context, builder: (context) => SimpleDialog(
      title: Text(tr('音频轨道', 'Audio tracks')),
      children: [
        SimpleDialogOption(onPressed: () => Navigator.pop(context, AudioTrack.auto()), child: Text(tr('自动选择', 'Auto'))),
        SimpleDialogOption(onPressed: () => Navigator.pop(context, AudioTrack.no()), child: Text(tr('关闭音轨', 'Disable audio'))),
        for (final track in tracks)
          if (track.id != 'auto' && track.id != 'no')
            SimpleDialogOption(onPressed: () => Navigator.pop(context, track), child: Text(track.title ?? track.language ?? track.id)),
      ],
    ));
    if (selected != null && mounted) await run(() => player.setAudioTrack(selected));
  }

  Future<void> seekBy(int seconds) => run(() async {
    final state = player.state;
    if (state.duration.inMilliseconds <= 0) return;
    final target = (state.position.inMilliseconds + seconds * 1000).clamp(0, state.duration.inMilliseconds).toInt();
    await player.seek(Duration(milliseconds: target));
  });

  Future<void> seekTo(double ms) => run(() async {
    final duration = player.state.duration.inMilliseconds;
    if (duration <= 0) return;
    await player.seek(Duration(milliseconds: ms.clamp(0, duration).round()));
  });

  Future<void> changeVolume(double value) => run(() async {
    final v = value.clamp(0.0, 100.0).toDouble();
    if (v > 0) lastVolume = v;
    await player.setVolume(v);
  });

  Future<void> toggleMute() => changeVolume(volume == 0 ? lastVolume : 0);

  Future<void> toggleImmersive() async {
    if (!mounted || inPip) return;
    setState(() { immersive = !immersive; compact = immersive; });
    if (mobile) {
      try { await SystemChrome.setEnabledSystemUIMode(immersive ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge); } catch (_) {}
    }
  }

  void hint(String text) {
    gestureTimer?.cancel();
    if (mounted) setState(() => gestureMessage = text);
    gestureTimer = Timer(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => gestureMessage = null);
    });
  }

  Widget touchSurface() => LayoutBuilder(builder: (context, size) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: revealDock,
    onDoubleTapDown: (d) {
      gestureSide = d.localPosition.dx < size.maxWidth / 2 ? -1 : 1;
    },
    onDoubleTap: () { if (hasMedia) unawaited(seekBy(gestureSide * 10)); },
    onHorizontalDragStart: (_) {
      if (!hasMedia || busy || player.state.duration.inMilliseconds <= 0) return;
      gestureTarget = player.state.position.inMilliseconds.toDouble();
    },
    onHorizontalDragUpdate: (d) {
      if (gestureTarget == null || !hasMedia) return;
      final duration = player.state.duration.inMilliseconds;
      if (duration <= 0) { gestureTarget = null; return; }
      gestureTarget = (gestureTarget! + d.delta.dx * 300).clamp(0, duration).toDouble();
      hint(formatTime(gestureTarget!.round()));
    },
    onHorizontalDragEnd: (_) {
      final target = gestureTarget;
      gestureTarget = null;
      if (target != null) unawaited(seekTo(target));
    },
    onHorizontalDragCancel: () { gestureTarget = null; },
    onVerticalDragStart: (d) {
      gestureSide = d.localPosition.dx < size.maxWidth / 2 ? -1 : 1;
      gestureTarget = gestureSide == -1 ? dim : volume;
    },
    onVerticalDragUpdate: (d) {
      if (!hasMedia || gestureTarget == null || busy) return;
      if (gestureSide == -1) {
        dim = (dim + d.delta.dy / 250).clamp(0.0, 0.75).toDouble();
        gestureTarget = dim;
        hint(tr('画面亮度 ${((1-dim)*100).round()}%', 'Video brightness ${((1-dim)*100).round()}%'));
      } else {
        gestureTarget = (gestureTarget! - d.delta.dy / 2).clamp(0.0,100.0).toDouble();
        hint(tr('音量 ${gestureTarget!.round()}%', 'Volume ${gestureTarget!.round()}%'));
      }
    },
    onVerticalDragEnd: (_) {
      final target = gestureTarget; gestureTarget = null;
      if (gestureSide == 1 && target != null) unawaited(changeVolume(target));
    },
    onVerticalDragCancel: () { gestureTarget = null; },
    onLongPressStart: (_) {
      if (!hasMedia || busy) return;
      gestureRate = rate;
      rateGesture = run(() => player.setRate(2));
      hint('2.0×');
    },
    onLongPressEnd: (_) => unawaited(restoreGestureRate()),
    onLongPressCancel: () => unawaited(restoreGestureRate()),
    child: const SizedBox.expand(),
  ));

  Future<void> restoreGestureRate() async {
    final pending = rateGesture;
    if (pending == null) return;
    rateGesture = null;
    await pending;
    if (mounted && hasMedia) await run(() => player.setRate(gestureRate));
  }

  KeyEventResult handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || busy || !hasMedia || FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<EditableText>() != null || FocusManager.instance.primaryFocus?.context?.widget is EditableText) return KeyEventResult.ignored;
    revealDock();
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.space) { unawaited(run(player.playOrPause)); }
    else if (key == LogicalKeyboardKey.arrowLeft) { unawaited(seekBy(-10)); }
    else if (key == LogicalKeyboardKey.arrowRight) { unawaited(seekBy(10)); }
    else if (key == LogicalKeyboardKey.arrowUp) { unawaited(changeVolume(volume + 5)); }
    else if (key == LogicalKeyboardKey.arrowDown) { unawaited(changeVolume(volume - 5)); }
    else if (key == LogicalKeyboardKey.keyM) { unawaited(toggleMute()); }
    else if (key == LogicalKeyboardKey.keyF || (key == LogicalKeyboardKey.escape && compact)) { unawaited(toggleImmersive()); }
    else if (key == LogicalKeyboardKey.keyS) { unawaited(screenshot()); }
    else return KeyEventResult.ignored;
    return KeyEventResult.handled;
  }

  Future<void> checkPip() async {
    try {
      final supported = await pipChannel.invokeMethod<bool>('supported') ?? false;
      if (mounted) setState(() => pipAvailable = supported);
    } catch (_) { /* Not available on this platform. */ }
  }

  Future<void> enterPip() => run(() async {
    final entered = await pipChannel.invokeMethod<bool>('enter');
    if (entered != true) throw StateError('Picture-in-picture unavailable');
  });

  void flushHistory() {
    final value = history.encode();
    historyWrite = historyWrite.then((_) async {
      try { await preferences.setString('history', value); } catch (_) { /* Storage unavailable. */ }
    });
  }

  void savePosition() {
    if (!rememberHistory || busy) return;
    final state = player.state;
    final list = state.playlist;
    if (list.index < 0 || list.index >= list.medias.length) return;
    final media = list.medias[list.index];
    final duration = state.duration.inMilliseconds;
    final position = state.position.inMilliseconds;
    if (duration <= 0 || position < 0 || position > duration || !canRemember(media.uri)) return;
    if (position == 0 && history.find(media.uri) != null) return;
    history.remember(HistoryEntry(media.uri, title(media), position, duration,
      DateTime.now().millisecondsSinceEpoch));
    flushHistory();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    if (!foreground) dockTimer?.cancel(); else revealDock();
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) savePosition();
  }

  Media mediaFor(String source, {bool? resume}) {
    final canonical = Media(source).uri;
    final start = (resume ?? (rememberHistory && resumePlayback)) ? history.find(canonical)?.resumeAt : null;
    return Media(source, start: start);
  }

  String formatTime(int milliseconds) {
    final d = Duration(milliseconds: milliseconds);
    final h = d.inHours;
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  Future<void> showHistory() async {
    if (busy) return;
    savePosition();
    final choice = await showDialog<HistoryEntry>(context: context, builder: (context) =>
      StatefulBuilder(builder: (context, refresh) => AlertDialog(
        title: Text(tr('播放历史', 'Playback history')),
        content: SizedBox(width: 520, height: 320, child: history.entries.isEmpty
          ? Center(child: Text(tr('暂无历史记录', 'No history')))
          : ListView(children: [for (final item in history.entries)
            ListTile(title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text('${formatTime(item.positionMs)} / ${formatTime(item.durationMs)}'),
              onTap: () => Navigator.pop(context, item),
              trailing: IconButton(tooltip: tr('删除记录', 'Delete entry'), icon: const Icon(Icons.delete_outline), onPressed: () {
                refresh(() => history.remove(item.source)); flushHistory();
              }))])),
        actions: [
          TextButton(onPressed: history.entries.isEmpty ? null : () {
            refresh(history.clear); flushHistory();
          }, child: Text(tr('清空', 'Clear'))),
          TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('关闭', 'Close'))),
        ],
      )));
    if (choice == null || !mounted) return;
    await run(() async {
      final media = mediaFor(choice.source);
      labels[media.uri] = choice.title;
      await player.open(media);
      if (mounted) setState(() => mobilePage = 0);
    });
  }

  Future<void> showSettings() async {
    if (busy) return;
    var remember = rememberHistory, resume = resumePlayback, hardware = hardwareAcceleration;
    var english = widget.english, light = widget.light, updates = autoUpdate, glass = widget.glass;
    var hide = autoHide, thumbnails = thumbnailsEnabled, accent = dynamicAccent;
    var section = 0;
    final saved = await showDialog<bool>(context: context, builder: (context) =>
      StatefulBuilder(builder: (context, refresh) => AlertDialog(
        title: Text(tr('设置', 'Settings')),
        content: SizedBox(width: 460, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          Wrap(spacing: 6, runSpacing: 4, children: [
            for (final e in [tr('外观','Appearance'),tr('播放','Playback'),tr('隐私与更新','Privacy & updates')].asMap().entries)
              ChoiceChip(label: Text(e.value), selected: section == e.key, onSelected: (_) => refresh(() => section = e.key)),
          ]),
          const SizedBox(height: 12),
          if (section == 0) ...[
            SwitchListTile(title: const Text('English / 中文'), value: english, onChanged: (v) => refresh(() => english = v)),
            SwitchListTile(title: Text(tr('浅色主题','Light theme')), value: light, onChanged: (v) => refresh(() => light = v)),
            SwitchListTile(title: Text(tr('玻璃效果','Glass effect')), subtitle: Text(tr('关闭以降低渲染开销','Disable to reduce rendering cost')), value: glass, onChanged: (v) => refresh(() => glass = v)),
            SwitchListTile(title: Text(tr('视频动态取色','Video accent color')), subtitle: Text(tr('从已播放的本地视频缩略图取色','Sample local playback previews')), value: accent && thumbnails, onChanged: thumbnails ? (v) => refresh(() => accent = v) : null),
          ],
          if (section == 1) ...[
            SwitchListTile(title: Text(tr('自动隐藏控制栏','Auto-hide controls')), subtitle: Text(tr('播放中 4 秒无操作隐藏','Hide after 4 seconds during playback')), value: hide, onChanged: (v) => refresh(() => hide = v)),
            SwitchListTile(title: Text(tr('自动断点续播','Resume playback')), value: resume, onChanged: remember ? (v) => refresh(() => resume = v) : null),
            if (!kIsWeb) SwitchListTile(title: Text(tr('硬件加速','Hardware acceleration')), subtitle: Text(tr('重启后生效','Restart required')), value: hardware, onChanged: (v) => refresh(() => hardware = v)),
          ],
          if (section == 2) ...[
            SwitchListTile(title: Text(tr('保存播放历史','Save playback history')), subtitle: Text(tr('关闭会清空记录','Disabling clears history')), value: remember, onChanged: (v) => refresh(() => remember = v)),
            SwitchListTile(title: Text(tr('缓存视频缩略图','Cache video thumbnails')), subtitle: Text(tr('仅缓存本地已播放视频，关闭会清除缓存','Local played videos only; disabling clears cache')), value: thumbnails, onChanged: (v) => refresh(() => thumbnails = v)),
            SwitchListTile(title: Text(tr('启动时检查更新','Check for updates at startup')), subtitle: Text(tr('仅连接 GitHub，不自动安装','Contacts GitHub; never auto-installs')), value: updates, onChanged: (v) => refresh(() => updates = v)),
          ],
        ]))),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('取消', 'Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(tr('保存', 'Save')))],
      )));
    if (saved != true || !mounted) return;
    await run(() async {
      await preferences.setBool('rememberHistory', remember);
      await preferences.setBool('resumePlayback', resume);
      await preferences.setBool('hardwareAcceleration', hardware);
      await preferences.setBool('autoUpdate', updates);
      await preferences.setBool('autoHide', hide);
      await preferences.setBool('thumbnailsEnabled', thumbnails);
      await preferences.setBool('dynamicAccent', accent);
      if (!mounted) return;
      setState(() { rememberHistory = remember; resumePlayback = resume; hardwareAcceleration = hardware; autoUpdate = updates; autoHide = hide; thumbnailsEnabled = thumbnails; dynamicAccent = accent; attemptedPreview = null; });
      if (!thumbnails) { previews.clear(); persistPreviews(); }
      final source = currentSource;
      widget.onAccent(accent && thumbnails && source != null ? previews[source]?.accent : null);
      revealDock();
      widget.onAppearance(english, light, glass);
      if (!remember) { history.clear(); flushHistory(); }
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('设置已保存，硬件加速将在下次启动时生效')));
    });
  }

  Future<void> subtitles() async {
    if (busy || playlist.medias.isEmpty) return;
    final tracks = player.state.tracks.subtitle;
    final selected = await showDialog<int>(context: context, builder: (context) => SimpleDialog(
      title: Text(tr('字幕轨道', 'Subtitle tracks')),
      children: [
        SimpleDialogOption(onPressed: () => Navigator.pop(context, -1), child: Text(tr('自动选择', 'Auto'))),
        SimpleDialogOption(onPressed: () => Navigator.pop(context, -2), child: Text(tr('关闭字幕', 'Disable subtitles'))),
        SimpleDialogOption(onPressed: () => Navigator.pop(context, -3), child: Text(tr('加载本地字幕（UTF-8 SRT / VTT / ASS）', 'Load local subtitles (UTF-8 SRT / VTT / ASS)'))),
        for (var i = 0; i < tracks.length; i++)
          if (tracks[i].id != 'auto' && tracks[i].id != 'no')
            SimpleDialogOption(onPressed: () => Navigator.pop(context, i),
              child: Text(tracks[i].title ?? tracks[i].language ?? tr('轨道 ${i + 1}', 'Track ${i + 1}'))),
      ],
    ));
    if (selected == null || !mounted) return;
    await run(() async {
      if (selected == -1) { await player.setSubtitleTrack(SubtitleTrack.auto()); return; }
      if (selected == -2) { await player.setSubtitleTrack(SubtitleTrack.no()); return; }
      if (selected >= 0) { await player.setSubtitleTrack(tracks[selected]); return; }
      final group = XTypeGroup(label: tr('字幕','Subtitles'), extensions: ['srt','vtt','ass','ssa'],
        uniformTypeIdentifiers: ['public.text','public.data'], mimeTypes: ['text/*','application/octet-stream']);
      final file = await openFile(acceptedTypeGroups: [group]);
      if (file == null || !mounted) return;
      if (await file.length() > 2 * 1024 * 1024) throw StateError('Subtitle too large');
      final text = await file.readAsString();
      await player.setSubtitleTrack(SubtitleTrack.data(text, title: file.name));
    });
  }

  Future<void> screenshot() => run(() async {
    final bytes = await player.screenshot(format: 'image/png');
    if (bytes == null || bytes.isEmpty) throw StateError('No video frame');
    if (!mounted) return;
    final name = 'OmniPlayer-${DateTime.now().millisecondsSinceEpoch}.png';
    final file = XFile.fromData(bytes, name: name, mimeType: 'image/png');
    if (desktop) {
      final destination = await getSaveLocation(suggestedName: name);
      if (destination == null) return;
      await file.saveTo(destination.path);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('截图已保存')));
    } else {
      final box = context.findRenderObject() as RenderBox?;
      await Share.shareXFiles([file], fileNameOverrides: [name],
        sharePositionOrigin: box == null ? null : box.localToGlobal(Offset.zero) & box.size);
    }
  });

  Future<void> run(Future<void> Function() action) async {
    if (busy || !mounted) return;
    revealDock();
    savePosition();
    setState(() { busy = true; error = null; });
    try { await action(); }
    catch (_) { if (mounted) setState(() => error = tr('操作失败，请检查文件、网络和平台支持。', 'Operation failed. Check files, network and platform support.')); }
    finally { if (mounted) { setState(() => busy = false); revealDock(); } }
  }

  Future<void> append(List<Media> items) async {
    if (items.isEmpty || !mounted) return;
    if (player.state.playlist.medias.isEmpty) {
      await player.open(Playlist(items));
    } else {
      for (final media in items) { await player.add(media); }
    }
  }

  Future<void> pickFiles() => run(() async {
    final group = XTypeGroup(label: tr('视频和音频','Video and audio'),
      extensions: ['mp4','mkv','mov','avi','webm','m4v','mp3','flac','wav','ogg','ts'],
      uniformTypeIdentifiers: ['public.movie','public.audio'],
      mimeTypes: ['video/*','audio/*']);
    final files = await openFiles(acceptedTypeGroups: [group]);
    if (!mounted) return;
    final items = <Media>[];
    for (final file in files) {
      // On web, file_selector supplies a browser Blob URL; on native, a file path.
      final source = kIsWeb ? file.path : Uri.file(file.path, windows: defaultTargetPlatform == TargetPlatform.windows).toString();
      final media = mediaFor(source);
      labels[media.uri] = file.name;
      addLibrary(media.uri, file.name);
      items.add(media);
    }
    await append(items);
    if (mounted && items.isNotEmpty) setState(() => mobilePage = 0);
  });

  Future<void> pickUrl() async {
    if (busy) return;
    var input = '';
    final source = await showDialog<Uri>(context: context, builder: (context) {
      String? validation;
      return StatefulBuilder(builder: (context, refresh) => AlertDialog(
        title: Text(tr('打开网络视频', 'Open network media')),
        content: TextField(autofocus: true, keyboardType: TextInputType.url,
          decoration: InputDecoration(hintText: 'https://example.com/video.mp4', errorText: validation),
          onChanged: (value) => input = value),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('取消', 'Cancel'))),
          FilledButton(onPressed: () {
            final uri = parseNetworkSource(input);
            if (uri == null) { refresh(() => validation = tr('请输入有效的 HTTP(S) 视频地址', 'Enter a valid HTTP(S) media URL')); return; }
            Navigator.pop(context, uri);
          }, child: Text(tr('加入播放列表', 'Add to queue')))],
      ));
    });
    if (source == null || !mounted) return;
    await run(() async {
      final media = mediaFor(source.toString());
      labels[media.uri] = source.pathSegments.isEmpty ? source.host : source.pathSegments.last;
      if (canRemember(media.uri)) addLibrary(media.uri, labels[media.uri]!);
      await append([media]);
      if (mounted) setState(() => mobilePage = 0);
    });
  }

  String title(Media media) => labels[media.uri] ?? tr('媒体文件', 'Media file');

  Future<void> clear() => run(() async {
    await player.stop();
    // stop() may already clear the queue; take current size after stop.
    while (player.state.playlist.medias.isNotEmpty) {
      final before = player.state.playlist.medias.length;
      await player.remove(before - 1);
      if (player.state.playlist.medias.length >= before) break;
    }
    labels.clear();
  });

  @override
  void dispose() {
    savePosition();
    historyTimer.cancel();
    dockTimer?.cancel();
    gestureTimer?.cancel();
    keyboardFocus.dispose();
    if (mobile && immersive) unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    WidgetsBinding.instance.removeObserver(this);
    if (android) pipChannel.setMethodCallHandler(null);
    for (final sub in subscriptions) { unawaited(sub.cancel()); }
    unawaited(player.dispose());
    super.dispose();
  }

  Widget queue() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    Padding(padding: const EdgeInsets.fromLTRB(12, 8, 12, 4), child: Row(children: [
      const Icon(Icons.queue_music_rounded), const SizedBox(width: 8),
      Expanded(child: Text(tr('播放队列','Queue'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
      Text('${playlist.medias.length}'), IconButton(tooltip: tr('清空','Clear'), onPressed: busy || !hasMedia ? null : clear, icon: const Icon(Icons.delete_outline)),
    ])),
    Expanded(child: playlist.medias.isEmpty ? Center(child: Text(tr('打开本地文件或网络视频','Open files or a network video'))) : ListView.builder(
      itemCount: playlist.medias.length, itemBuilder: (context, index) {
        final media = playlist.medias[index];
        final active = index == playlist.index;
        return ListTile(selected: active, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          leading: Icon(active && playing ? Icons.graphic_eq : Icons.video_file_outlined),
          title: Text(title(media), maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(active ? tr('正在播放','Now playing') : tr('待播放','Up next')),
          onTap: busy ? null : () => run(() async { await player.jump(index); await player.play(); if (mounted) setState(() => mobilePage = 0); }),
          trailing: IconButton(tooltip: tr('移除','Remove'), onPressed: busy ? null : () => run(() => player.remove(index)), icon: const Icon(Icons.close)));
      },
    )),
  ]);

  Widget previewImage(LibraryItem item) {
    final preview = previews[item.source];
    return ClipRRect(borderRadius: BorderRadius.circular(14), child: ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: preview == null ? Center(child: Icon(Icons.movie_outlined, color: Theme.of(context).colorScheme.primary))
        : Image.memory(preview.bytes, fit: BoxFit.cover, gaplessPlayback: true,
          errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.movie_outlined))),
    ));
  }

  Widget libraryMenu(LibraryItem item) => PopupMenuButton<String>(
    tooltip: tr('媒体选项','Media options'),
    onSelected: (value) {
      if (value == 'star') { setState(() => library.toggle(item.source)); persistLibrary(); }
      if (value == 'remove') removeFromLibrary(item.source);
    },
    itemBuilder: (_) => [
      PopupMenuItem(value: 'star', child: Text(item.favorite ? tr('取消收藏','Unfavorite') : tr('收藏','Favorite'))),
      PopupMenuItem(value: 'remove', child: Text(tr('移除','Remove'))),
    ],
  );

  Widget libraryPane() {
    final items = library.search(libraryQuery, favoritesOnly: favoritesOnly);
    if (sortAscending) items.sort((a,b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(padding: const EdgeInsets.fromLTRB(12,4,12,8), child: TextField(
        decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: tr('搜索媒体','Search media')),
        onChanged: (v) => setState(() => libraryQuery = v),
      )),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Wrap(spacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
        FilterChip(label: Text(tr('收藏','Favorites')), selected: favoritesOnly, onSelected: (v) => setState(() => favoritesOnly = v)),
        IconButton(tooltip: tr('名称排序','Sort by name'), isSelected: sortAscending, icon: const Icon(Icons.sort_by_alpha), onPressed: () => setState(() => sortAscending = !sortAscending)),
        IconButton(tooltip: tr('切换网格/列表','Toggle grid/list'), icon: Icon(gridLibrary ? Icons.view_list_rounded : Icons.grid_view_rounded), onPressed: () { setState(() => gridLibrary = !gridLibrary); unawaited(preferences.setBool('gridLibrary', gridLibrary)); }),
        if (desktop) IconButton(tooltip: tr('导入目录','Import folder'), icon: const Icon(Icons.create_new_folder_outlined), onPressed: busy ? null : importFolder),
      ])),
      Expanded(child: items.isEmpty ? Center(child: Padding(padding: const EdgeInsets.all(16), child: Text(tr('导入媒体，创建你的收藏','Import media to start your collection'), textAlign: TextAlign.center))) :
        gridLibrary ? GridView.builder(
          padding: const EdgeInsets.all(12),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 220, mainAxisExtent: 160, crossAxisSpacing: 10, mainAxisSpacing: 10),
          itemCount: items.length, itemBuilder: (context, index) {
            final item = items[index];
            final entry = history.find(item.source);
            return Material(color: Colors.transparent, child: InkWell(
              borderRadius: BorderRadius.circular(16), onTap: busy ? null : () => openLibrary(item),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Expanded(child: Stack(fit: StackFit.expand, children: [
                  previewImage(item),
                  if (item.favorite) const Positioned(top: 8, left: 8, child: Icon(Icons.star_rounded, color: Colors.amber, size: 20)),
                  Positioned(top: 0,right: 0,child: Material(color: Theme.of(context).colorScheme.surface.withValues(alpha:.88),shape: const CircleBorder(),child: libraryMenu(item))),
                  if (entry != null && entry.durationMs > 0) Positioned(left: 8,right: 8,bottom: 5,
                    child: LinearProgressIndicator(value: (entry.positionMs/entry.durationMs).clamp(0.0,1.0).toDouble(),borderRadius:BorderRadius.circular(4))),
                ])),
                Padding(padding: const EdgeInsets.only(top: 7), child: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600))),
              ]),
            ));
          }) :
        ListView.builder(itemCount: items.length, itemBuilder: (context,index) {
          final item = items[index];
          final entry = history.find(item.source);
          return ListTile(
            leading: SizedBox(width: 64, height: 40, child: previewImage(item)),
            title: Text(item.title, maxLines:1,overflow:TextOverflow.ellipsis),
            subtitle: Text(entry == null ? (item.source.startsWith('http') ? tr('网络媒体','Network media') : tr('本地媒体','Local media')) : '${formatTime(entry.positionMs)} / ${formatTime(entry.durationMs)}'),
            trailing: libraryMenu(item), onTap: busy ? null : () => openLibrary(item));
        })),
    ]);
  }

  Widget progress() => StreamBuilder<Duration>(stream: player.stream.duration, initialData: player.state.duration, builder: (context, duration) =>
    StreamBuilder<Duration>(stream: player.stream.position, initialData: player.state.position, builder: (context, position) {
      final max = (duration.data ?? Duration.zero).inMilliseconds.toDouble();
      final current = (seekPreview ?? (position.data ?? Duration.zero).inMilliseconds.toDouble()).clamp(0.0, max > 0 ? max : 0.0).toDouble();
      return Column(mainAxisSize: MainAxisSize.min, children: [
        Slider(value: current, max: max > 0 ? max : 1, onChanged: busy || max <= 0 ? null : (v) => setState(() => seekPreview = v),
          onChangeEnd: (v) { setState(() => seekPreview = null); unawaited(seekTo(v)); }),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(formatTime(current.round())), Text(max > 0 ? formatTime(max.round()) : '--:--'),
        ])),
      ]);
    }));

  Future<void> playbackOptions() async {
    revealDock();
    dockTimer?.cancel();
    await showModalBottomSheet<void>(context: context, showDragHandle: true, isScrollControlled: true,
      builder: (sheet) => SafeArea(child: StatefulBuilder(builder: (sheet, refresh) => Padding(
        padding: const EdgeInsets.fromLTRB(18,0,18,16),
        child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(tr('播放选项','Playback options'), style: Theme.of(sheet).textTheme.titleLarge),
          ListTile(leading: const Icon(Icons.speed), title: Text(tr('播放速度','Speed')),
            trailing: DropdownButton<double>(value: [0.5,0.75,1.0,1.25,1.5,2.0].contains(rate) ? rate : 1.0,
              items: [for(final v in [0.5,0.75,1.0,1.25,1.5,2.0]) DropdownMenuItem(value:v,child:Text('${v}×'))],
              onChanged: (v) async { if(v != null) { await run(() => player.setRate(v)); if (sheet.mounted) refresh(() {}); } })),
          ListTile(leading: const Icon(Icons.aspect_ratio), title: Text(tr('视频比例','Video fit')),
            trailing: DropdownButton<BoxFit>(value:videoFit,items:[
              DropdownMenuItem(value:BoxFit.contain,child:Text(tr('原始比例','Fit'))),
              DropdownMenuItem(value:BoxFit.cover,child:Text(tr('裁剪','Crop'))),
              DropdownMenuItem(value:BoxFit.fill,child:Text(tr('拉伸','Stretch'))),
            ],onChanged:(v){if(v!=null){setState(()=>videoFit=v);refresh((){});}})),
          Row(children:[
            IconButton(tooltip:tr('静音','Mute'),icon:Icon(volume==0?Icons.volume_off:Icons.volume_up),onPressed:()async{await toggleMute();if(sheet.mounted)refresh((){});}),
            Expanded(child:Slider(value:volume.clamp(0.0,100.0).toDouble(),max:100,onChanged:(v){setState(()=>volume=v);refresh((){});},onChangeEnd:(v)async{await changeVolume(v);if(sheet.mounted)refresh((){});})),
          ]),
          ListTile(leading:const Icon(Icons.repeat), title:Text(tr('循环模式','Repeat')),
            subtitle:Text(mode==PlaylistMode.none?tr('关闭','Off'):mode==PlaylistMode.loop?tr('列表循环','Queue'):tr('单曲循环','One')),
            onTap:()async{await run(()=>player.setPlaylistMode(mode==PlaylistMode.none?PlaylistMode.loop:mode==PlaylistMode.loop?PlaylistMode.single:PlaylistMode.none));if(sheet.mounted)refresh((){});}),
          ListTile(leading:const Icon(Icons.audiotrack),title:Text(tr('音轨','Audio track')),onTap:!hasMedia?null:(){Navigator.pop(sheet);unawaited(audioTracks());}),
          ListTile(leading:const Icon(Icons.subtitles_outlined),title:Text(tr('字幕','Subtitles')),onTap:!hasMedia?null:(){Navigator.pop(sheet);unawaited(subtitles());}),
          ListTile(leading:const Icon(Icons.camera_alt_outlined),title:Text(tr('截图','Screenshot')),onTap:!hasMedia?null:(){Navigator.pop(sheet);unawaited(screenshot());}),
          if(pipAvailable) ListTile(leading:const Icon(Icons.picture_in_picture_alt),title:Text(tr('画中画','Picture-in-picture')),onTap:!hasMedia?null:(){Navigator.pop(sheet);unawaited(enterPip());}),
        ])),
      ))));
    if (mounted) revealDock();
  }

  Widget dock() => Theme(
    data: ThemeData(useMaterial3:true,brightness:Brightness.dark,colorSchemeSeed:Theme.of(context).colorScheme.primary),
    child: MouseRegion(onEnter: (_) { dockHovered = true; revealDock(); }, onExit: (_) { dockHovered = false; revealDock(); },
      child: Listener(onPointerDown: (_) => revealDock(), onPointerMove: (_) => revealDock(),
        child: FloatingDock(visible: dockVisible || !playing || busy || !autoHide, glass: widget.glass,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            progress(),
            SizedBox(height: 46, child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              IconButton(tooltip:tr('上一项','Previous'),onPressed:busy||!hasMedia?null:()=>run(player.previous),icon:const Icon(Icons.skip_previous_rounded)),
              IconButton(tooltip:tr('后退10秒','Back 10 seconds'),onPressed:busy||!hasMedia?null:()=>seekBy(-10),icon:const Icon(Icons.replay_10_rounded)),
              IconButton.filled(tooltip:playing?tr('暂停','Pause'):tr('播放','Play'),onPressed:busy||!hasMedia?null:()=>run(player.playOrPause),icon:Icon(playing?Icons.pause_rounded:Icons.play_arrow_rounded)),
              IconButton(tooltip:tr('前进10秒','Forward 10 seconds'),onPressed:busy||!hasMedia?null:()=>seekBy(10),icon:const Icon(Icons.forward_10_rounded)),
              IconButton(tooltip:tr('下一项','Next'),onPressed:busy||!hasMedia?null:()=>run(player.next),icon:const Icon(Icons.skip_next_rounded)),
              IconButton(tooltip:tr('更多播放选项','Playback options'),onPressed:busy?null:playbackOptions,icon:const Icon(Icons.more_horiz_rounded)),
            ]))),
          ]))),
    ));

  Widget videoPane() => Column(children: [
    Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(compact || inPip ? 0 : 28),
      child: ColoredBox(color: Colors.black, child: MouseRegion(onHover: (_) => revealDock(),
        child: Listener(onPointerDown: (_) => revealDock(), child: Stack(alignment: Alignment.center, children: [
          Positioned.fill(child: Video(controller:controller,fit:videoFit,controls:NoVideoControls)),
          if(dim>0) Positioned.fill(child:IgnorePointer(child:ColoredBox(color:Colors.black.withValues(alpha:dim)))),
          if(hasMedia && !inPip) Positioned.fill(child:touchSurface()),
          if(!hasMedia) IgnorePointer(child:Column(mainAxisSize:MainAxisSize.min,children:[
            const OmniMark(size:60,animate:true),
            const SizedBox(height:12),
            const Text('Omni Player',style:TextStyle(color:Colors.white,fontSize:22,fontWeight:FontWeight.w600)),
            Text(tr('打开媒体，开始播放','Open media to begin'),style:const TextStyle(color:Colors.white70)),
          ])),
          if(buffering && hasMedia) const IgnorePointer(child:CircularProgressIndicator()),
          if(gestureMessage!=null&&!inPip) IgnorePointer(child:DecoratedBox(decoration:BoxDecoration(color:Colors.black87,borderRadius:BorderRadius.circular(16)),child:Padding(padding:const EdgeInsets.all(14),child:Text(gestureMessage!,style:const TextStyle(color:Colors.white))))),
          if(!inPip) Positioned(top:8,right:8,child:IconButton.filledTonal(
            tooltip:compact?tr('退出沉浸模式','Exit immersive mode'):tr('沉浸模式','Immersive mode'),
            onPressed:toggleImmersive,icon:Icon(compact?Icons.fullscreen_exit_rounded:Icons.fullscreen_rounded))),
          if(!inPip && hasMedia) Positioned(bottom:8,left:0,right:0,child:Center(child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:540),child:Padding(padding:const EdgeInsets.symmetric(horizontal:8),child:dock())))),
        ])),
      ),
    ))),
    if(!inPip&&!compact) Padding(padding:const EdgeInsets.fromLTRB(8,10,8,4),child:Row(children:[
      Expanded(child:Text(nowPlaying,maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(fontSize:16,fontWeight:FontWeight.w600))),
      Text(playing?tr('播放中','Playing'):tr('已暂停','Paused'),style:TextStyle(color:Theme.of(context).colorScheme.primary)),
    ])),
    if(!inPip&&!compact&&error!=null) Padding(padding:const EdgeInsets.all(4),child:Row(children:[
      Expanded(child:Text(error!,maxLines:2,overflow:TextOverflow.ellipsis,style:TextStyle(color:Theme.of(context).colorScheme.error))),
      IconButton(onPressed:()=>setState(()=>error=null),icon:const Icon(Icons.close)),
    ])),
  ]);

  Widget browserPane() => GlassPanel(enabled:widget.glass,radius:24,child:Column(children:[
    Padding(padding:const EdgeInsets.all(10),child:SegmentedButton<bool>(
      segments:[ButtonSegment(value:false,icon:const Icon(Icons.queue_music),label:Text(tr('队列','Queue'))),ButtonSegment(value:true,icon:const Icon(Icons.video_library_outlined),label:Text(tr('媒体库','Library')))],
      selected:{libraryTab},onSelectionChanged:(v)=>setState(()=>libraryTab=v.first))),
    Expanded(child:libraryTab?libraryPane():queue()),
  ]));

  Widget mobileNavigation() => Padding(padding:const EdgeInsets.fromLTRB(12,6,12,8),child:GlassPanel(enabled:widget.glass,radius:28,child:Row(mainAxisAlignment:MainAxisAlignment.spaceEvenly,children:[
    for(final e in [(Icons.play_circle_outline,tr('播放','Player')),(Icons.video_library_outlined,tr('媒体库','Library')),(Icons.queue_music,tr('队列','Queue'))].asMap().entries)
      Expanded(child:InkWell(borderRadius:BorderRadius.circular(24),onTap:(){setState(()=>mobilePage=e.key);revealDock();},child:Padding(padding:const EdgeInsets.symmetric(vertical:8),child:Column(mainAxisSize:MainAxisSize.min,children:[
        Icon(e.value.$1,color:mobilePage==e.key?Theme.of(context).colorScheme.primary:null),
        Text(e.value.$2,style:TextStyle(fontSize:11,fontWeight:mobilePage==e.key?FontWeight.w700:FontWeight.w400)),
      ])))),
  ])));

  @override
  Widget build(BuildContext context) => Focus(focusNode:keyboardFocus,autofocus:true,onKeyEvent:handleKey,child:Scaffold(
    appBar:inPip||compact?null:AppBar(backgroundColor:Colors.transparent,title:Row(children:[
      const OmniMark(size:34),const SizedBox(width:10),const Flexible(child:Text('Omni',overflow:TextOverflow.ellipsis,style:TextStyle(fontWeight:FontWeight.w700))),
    ]),actions:[
      IconButton(tooltip:tr('打开文件','Open files'),onPressed:busy?null:pickFiles,icon:const Icon(Icons.add_rounded)),
      IconButton(tooltip:tr('打开网址','Open URL'),onPressed:busy?null:pickUrl,icon:const Icon(Icons.link_rounded)),
      PopupMenuButton<String>(tooltip:tr('更多','More'),onSelected:(value){
        if(value=='history') unawaited(showHistory());
        if(value=='settings') unawaited(showSettings());
        if(value=='check') unawaited(checkUpdates());
        if(value=='release') unawaited(openReleasePage());
      },itemBuilder:(_)=>[
        PopupMenuItem(value:'history',child:Text(tr('播放历史','History'))),
        PopupMenuItem(value:'settings',child:Text(tr('设置','Settings'))),
        PopupMenuItem(value:'check',enabled:!checkingUpdates,child:Text(tr('检查更新','Check updates'))),
        PopupMenuItem(value:'release',child:Text(availableUpdate==null?tr('发行页面','Releases'):tr('新版本 $availableUpdate','New version $availableUpdate'))),
        const PopupMenuItem(enabled:false,child:Text('v$currentVersion')),
      ]),
    ]),
    body:GlassBackdrop(enabled:widget.glass&&!compact&&!inPip,child:SafeArea(child:LayoutBuilder(builder:(context,size){
      final wide=size.maxWidth>=880 && size.maxHeight>=300;
      final minimal=inPip||compact||size.maxHeight<220;
      // Keep one Video widget mounted through page changes and breakpoint changes.
      return Column(children:[
        if(busy&&!minimal) const LinearProgressIndicator(),
        Expanded(child:Padding(padding:EdgeInsets.all(minimal?0:10),child:Row(children:[
          Expanded(child:IndexedStack(index:wide||minimal?0:mobilePage,children:[
            videoPane(),
            if(!wide&&!minimal) GlassPanel(enabled:widget.glass,child:libraryPane()) else const SizedBox.shrink(),
            if(!wide&&!minimal) GlassPanel(enabled:widget.glass,child:queue()) else const SizedBox.shrink(),
          ])),
          if(wide&&!minimal) ...[const SizedBox(width:12),SizedBox(width:320,child:browserPane())],
        ]))),
        if(!wide&&!minimal) mobileNavigation(),
      ]);
    }))),
  ));
}

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

late final SharedPreferences preferences;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  preferences = await SharedPreferences.getInstance();
  runApp(const OmniPlayerApp());
}

class OmniPlayerApp extends StatelessWidget {
  const OmniPlayerApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Omni Player', debugShowCheckedModeBanner: false,
    theme: ThemeData(useMaterial3: true, brightness: Brightness.dark,
      colorSchemeSeed: const Color(0xff6ce5c5), scaffoldBackgroundColor: const Color(0xff10141b)),
    home: const PlayerScreen(),
  );
}

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key});
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
  bool get android => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  bool get desktop => !kIsWeb && [TargetPlatform.windows, TargetPlatform.macOS, TargetPlatform.linux].contains(defaultTargetPlatform);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    history = PlaybackHistory.decode(preferences.getString('history'));
    rememberHistory = preferences.getBool('rememberHistory') ?? true;
    resumePlayback = preferences.getBool('resumePlayback') ?? true;
    hardwareAcceleration = preferences.getBool('hardwareAcceleration') ?? true;
    player = Player();
    controller = VideoController(player, configuration: VideoControllerConfiguration(
      enableHardwareAcceleration: hardwareAcceleration,
      hwdec: hardwareAcceleration ? null : 'no',
    ));
    historyTimer = Timer.periodic(const Duration(seconds: 5), (_) => savePosition());
    if (android) {
      pipChannel.setMethodCallHandler((call) async {
        if (call.method == 'changed' && mounted) {
          setState(() => inPip = call.arguments == true);
        }
      });
      unawaited(checkPip());
    }
    subscriptions.add(player.stream.playlist.listen((v) { if (mounted) setState(() => playlist = v); }));
    subscriptions.add(player.stream.buffering.listen((v) { if (mounted) setState(() => buffering = v); }));
    subscriptions.add(player.stream.playing.listen((v) { if (mounted) setState(() => playing = v); }));
    subscriptions.add(player.stream.rate.listen((v) { if (mounted) setState(() => rate = v); }));
    subscriptions.add(player.stream.volume.listen((v) { if (mounted) setState(() => volume = v); }));
    subscriptions.add(player.stream.playlistMode.listen((v) { if (mounted) setState(() => mode = v); }));
    subscriptions.add(player.stream.error.listen((_) { if (mounted) setState(() => error = '无法播放此媒体，请检查格式、网络或文件权限。'); }));
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
    if (duration <= 0 || position <= 0 || position > duration || !canRemember(media.uri)) return;
    history.remember(HistoryEntry(media.uri, title(media), position, duration,
      DateTime.now().millisecondsSinceEpoch));
    flushHistory();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
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
        title: const Text('播放历史'),
        content: SizedBox(width: 520, height: 320, child: history.entries.isEmpty
          ? const Center(child: Text('暂无历史记录'))
          : ListView(children: [for (final item in history.entries)
            ListTile(title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text('${formatTime(item.positionMs)} / ${formatTime(item.durationMs)}'),
              onTap: () => Navigator.pop(context, item),
              trailing: IconButton(tooltip: '删除记录', icon: const Icon(Icons.delete_outline), onPressed: () {
                refresh(() => history.remove(item.source)); flushHistory();
              }))])),
        actions: [
          TextButton(onPressed: history.entries.isEmpty ? null : () {
            refresh(history.clear); flushHistory();
          }, child: const Text('清空')),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('关闭')),
        ],
      )));
    if (choice == null || !mounted) return;
    await run(() async {
      final media = mediaFor(choice.source);
      labels[media.uri] = choice.title;
      await player.open(media);
    });
  }

  Future<void> showSettings() async {
    if (busy) return;
    var remember = rememberHistory, resume = resumePlayback, hardware = hardwareAcceleration;
    final saved = await showDialog<bool>(context: context, builder: (context) =>
      StatefulBuilder(builder: (context, refresh) => AlertDialog(
        title: const Text('播放设置'),
        content: SizedBox(width: 420, child: Column(mainAxisSize: MainAxisSize.min, children: [
          SwitchListTile(title: const Text('保存播放历史'), subtitle: const Text('仅保存到本设备；关闭会清除记录'),
            value: remember, onChanged: (v) => refresh(() => remember = v)),
          SwitchListTile(title: const Text('自动断点续播'), value: resume,
            onChanged: remember ? (v) => refresh(() => resume = v) : null),
          if (!kIsWeb) SwitchListTile(title: const Text('硬件加速'), subtitle: const Text('重启播放器后生效，关闭可尝试解决兼容问题'),
            value: hardware, onChanged: (v) => refresh(() => hardware = v)),
          if (kIsWeb) const Text('Web 的硬件解码由浏览器控制。'),
        ])),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('保存'))],
      )));
    if (saved != true || !mounted) return;
    await run(() async {
      await preferences.setBool('rememberHistory', remember);
      await preferences.setBool('resumePlayback', resume);
      await preferences.setBool('hardwareAcceleration', hardware);
      if (!mounted) return;
      setState(() { rememberHistory = remember; resumePlayback = resume; hardwareAcceleration = hardware; });
      if (!remember) { history.clear(); flushHistory(); }
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('设置已保存，硬件加速将在下次启动时生效')));
    });
  }

  Future<void> subtitles() async {
    if (busy || playlist.medias.isEmpty) return;
    final tracks = player.state.tracks.subtitle;
    final selected = await showDialog<int>(context: context, builder: (context) => SimpleDialog(
      title: const Text('字幕轨道'),
      children: [
        SimpleDialogOption(onPressed: () => Navigator.pop(context, -1), child: const Text('自动选择')),
        SimpleDialogOption(onPressed: () => Navigator.pop(context, -2), child: const Text('关闭字幕')),
        SimpleDialogOption(onPressed: () => Navigator.pop(context, -3), child: const Text('加载本地字幕（UTF-8 SRT / VTT / ASS）')),
        for (var i = 0; i < tracks.length; i++)
          if (tracks[i].id != 'auto' && tracks[i].id != 'no')
            SimpleDialogOption(onPressed: () => Navigator.pop(context, i),
              child: Text(tracks[i].title ?? tracks[i].language ?? '轨道 ${i + 1}')),
      ],
    ));
    if (selected == null || !mounted) return;
    await run(() async {
      if (selected == -1) { await player.setSubtitleTrack(SubtitleTrack.auto()); return; }
      if (selected == -2) { await player.setSubtitleTrack(SubtitleTrack.no()); return; }
      if (selected >= 0) { await player.setSubtitleTrack(tracks[selected]); return; }
      const group = XTypeGroup(label: '字幕', extensions: ['srt','vtt','ass','ssa'],
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
    savePosition();
    setState(() { busy = true; error = null; });
    try { await action(); }
    catch (_) { if (mounted) setState(() => error = '操作失败，请检查文件、网络和平台支持。'); }
    finally { if (mounted) setState(() => busy = false); }
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
    const group = XTypeGroup(label: '视频和音频',
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
      items.add(media);
    }
    await append(items);
  });

  Future<void> pickUrl() async {
    if (busy) return;
    var input = '';
    final source = await showDialog<Uri>(context: context, builder: (context) {
      String? validation;
      return StatefulBuilder(builder: (context, refresh) => AlertDialog(
        title: const Text('打开网络视频'),
        content: TextField(autofocus: true, keyboardType: TextInputType.url,
          decoration: InputDecoration(hintText: 'https://example.com/video.mp4', errorText: validation),
          onChanged: (value) => input = value),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(onPressed: () {
            final uri = parseNetworkSource(input);
            if (uri == null) { refresh(() => validation = '请输入有效的 HTTP(S) 视频地址'); return; }
            Navigator.pop(context, uri);
          }, child: const Text('加入播放列表'))],
      ));
    });
    if (source == null || !mounted) return;
    await run(() async {
      final media = mediaFor(source.toString());
      labels[media.uri] = source.pathSegments.isEmpty ? source.host : source.pathSegments.last;
      await append([media]);
    });
  }

  String title(Media media) => labels[media.uri] ?? '媒体文件';

  Future<void> clear() => run(() async {
    await player.stop();
    for (var i = player.state.playlist.medias.length - 1; i >= 0; i--) {
      await player.remove(i);
    }
    labels.clear();
  });

  @override
  void dispose() {
    savePosition();
    historyTimer.cancel();
    WidgetsBinding.instance.removeObserver(this);
    if (android) pipChannel.setMethodCallHandler(null);
    for (final sub in subscriptions) { unawaited(sub.cancel()); }
    unawaited(player.dispose());
    super.dispose();
  }

  Widget queue() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    Padding(padding: const EdgeInsets.fromLTRB(16, 8, 8, 8), child: Row(children: [
      const Icon(Icons.queue_music), const SizedBox(width: 8), const Expanded(child: Text('播放列表', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
      Text('${playlist.medias.length} 项'), IconButton(tooltip: '清空列表', onPressed: busy || playlist.medias.isEmpty ? null : clear, icon: const Icon(Icons.delete_outline)),
    ])),
    const Divider(height: 1),
    Expanded(child: playlist.medias.isEmpty ? const Center(child: Text('打开本地文件或网络视频')) : ListView.builder(
      itemCount: playlist.medias.length, itemBuilder: (context, index) {
        final media = playlist.medias[index];
        final active = index == playlist.index;
        return ListTile(selected: active, leading: Icon(active && playing ? Icons.graphic_eq : Icons.video_file_outlined),
          title: Text(title(media), maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(active ? '当前媒体' : '待播放'),
          onTap: busy ? null : () => run(() async { await player.jump(index); await player.play(); }),
          trailing: IconButton(tooltip: '移除', onPressed: busy ? null : () => run(() => player.remove(index)), icon: const Icon(Icons.close)));
      },
    )),
  ]);

  Widget videoPane() => Column(children: [
    Expanded(child: Container(color: Colors.black, alignment: Alignment.center,
      child: Stack(alignment: Alignment.center, children: [
        Positioned.fill(child: Video(controller: controller)),
        if (playlist.medias.isEmpty) const IgnorePointer(child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.play_circle_outline, size: 72, color: Colors.white38), SizedBox(height: 10), Text('Omni Player', style: TextStyle(color: Colors.white70, fontSize: 24)), Text('选择媒体开始播放', style: TextStyle(color: Colors.white54)),
        ])),
        if (buffering && playlist.medias.isNotEmpty) const IgnorePointer(child: CircularProgressIndicator()),
      ]),
    )),
    if (!inPip && !compact && error != null) MaterialBanner(content: Text(error!), actions: [TextButton(onPressed: () => setState(() => error = null), child: const Text('关闭'))]),
    if (!inPip && !compact) Padding(padding: const EdgeInsets.all(8), child: Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
      IconButton(tooltip: '上一项', onPressed: busy || playlist.medias.isEmpty ? null : () => run(player.previous), icon: const Icon(Icons.skip_previous)),
      IconButton(tooltip: playing ? '暂停' : '播放', onPressed: busy || playlist.medias.isEmpty ? null : () => run(player.playOrPause), icon: Icon(playing ? Icons.pause_circle_filled : Icons.play_circle_filled, size: 32)),
      IconButton(tooltip: '下一项', onPressed: busy || playlist.medias.isEmpty ? null : () => run(player.next), icon: const Icon(Icons.skip_next)),
      IconButton(tooltip: '后退10秒', onPressed: busy || playlist.medias.isEmpty ? null : () => run(() async { final ms = (player.state.position.inMilliseconds - 10000).clamp(0, player.state.duration.inMilliseconds).toInt(); await player.seek(Duration(milliseconds: ms)); }), icon: const Icon(Icons.replay_10)),
      IconButton(tooltip: '前进10秒', onPressed: busy || playlist.medias.isEmpty ? null : () => run(() async { final ms = (player.state.position.inMilliseconds + 10000).clamp(0, player.state.duration.inMilliseconds).toInt(); await player.seek(Duration(milliseconds: ms)); }), icon: const Icon(Icons.forward_10)),
      PopupMenuButton<double>(tooltip: '播放速度', onSelected: (v) => run(() => player.setRate(v)), itemBuilder: (_) => [for(final v in [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]) PopupMenuItem(value: v, child: Text('${v}x'))], child: Padding(padding: const EdgeInsets.all(10), child: Text('${rate}x'))),
      IconButton(tooltip: '字幕', onPressed: busy || playlist.medias.isEmpty ? null : subtitles, icon: const Icon(Icons.subtitles_outlined)),
      IconButton(tooltip: '截图', onPressed: busy || playlist.medias.isEmpty ? null : screenshot, icon: const Icon(Icons.camera_alt_outlined)),
      if (pipAvailable) IconButton(tooltip: '系统画中画', onPressed: busy || playlist.medias.isEmpty ? null : enterPip, icon: const Icon(Icons.picture_in_picture_alt)),
      if (desktop) IconButton(tooltip: '应用内精简模式', onPressed: () => setState(() => compact = true), icon: const Icon(Icons.fit_screen)),
      IconButton(tooltip: '切换循环模式', onPressed: busy ? null : () => run(() => player.setPlaylistMode(mode == PlaylistMode.none ? PlaylistMode.loop : mode == PlaylistMode.loop ? PlaylistMode.single : PlaylistMode.none)), icon: Icon(mode == PlaylistMode.single ? Icons.repeat_one : Icons.repeat, color: mode == PlaylistMode.none ? Colors.white54 : Theme.of(context).colorScheme.primary)),
      IconButton(tooltip: volume == 0 ? '取消静音' : '静音', onPressed: busy ? null : () => run(() => player.setVolume(volume == 0 ? 100 : 0)), icon: Icon(volume == 0 ? Icons.volume_off : Icons.volume_up)),
    ])),
  ]);

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: inPip ? null : AppBar(title: const Row(children: [Icon(Icons.play_circle_fill, color: Color(0xff6ce5c5)), SizedBox(width: 9), Text('Omni Player')]), actions: [
      if (compact) IconButton(tooltip: '退出精简模式', onPressed: () => setState(() => compact = false), icon: const Icon(Icons.fullscreen_exit)),
      IconButton(tooltip: '播放历史', onPressed: busy ? null : showHistory, icon: const Icon(Icons.history)),
      IconButton(tooltip: '设置', onPressed: busy ? null : showSettings, icon: const Icon(Icons.settings_outlined)),
    ]),
    body: SafeArea(child: Column(children: [
      if (!inPip && !compact) Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), child: Wrap(spacing: 8, runSpacing: 8, children: [
        FilledButton.icon(onPressed: busy ? null : pickFiles, icon: const Icon(Icons.folder_open), label: const Text('打开文件')),
        OutlinedButton.icon(onPressed: busy ? null : pickUrl, icon: const Icon(Icons.link), label: const Text('打开网址')),
      ])),
      if (busy && !inPip && !compact) const LinearProgressIndicator(),
      Expanded(child: LayoutBuilder(builder: (context, constraints) => inPip || compact ? videoPane() : constraints.maxWidth >= 840
        ? Row(children: [Expanded(child: videoPane()), const VerticalDivider(width: 1), SizedBox(width: 300, child: queue())])
        : Column(children: [Expanded(flex: 3, child: videoPane()), const Divider(height: 1), Expanded(flex: 2, child: queue())]))),
    ])),
  );
}

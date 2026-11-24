import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:file_selector/file_selector.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'media_source.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
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

class _PlayerScreenState extends State<PlayerScreen> {
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

  @override
  void initState() {
    super.initState();
    player = Player();
    controller = VideoController(player);
    subscriptions.add(player.stream.playlist.listen((v) { if (mounted) setState(() => playlist = v); }));
    subscriptions.add(player.stream.buffering.listen((v) { if (mounted) setState(() => buffering = v); }));
    subscriptions.add(player.stream.playing.listen((v) { if (mounted) setState(() => playing = v); }));
    subscriptions.add(player.stream.rate.listen((v) { if (mounted) setState(() => rate = v); }));
    subscriptions.add(player.stream.volume.listen((v) { if (mounted) setState(() => volume = v); }));
    subscriptions.add(player.stream.playlistMode.listen((v) { if (mounted) setState(() => mode = v); }));
    subscriptions.add(player.stream.error.listen((_) { if (mounted) setState(() => error = '无法播放此媒体，请检查格式、网络或文件权限。'); }));
  }

  Future<void> run(Future<void> Function() action) async {
    if (busy || !mounted) return;
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
      final media = Media(source);
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
      final media = Media(source.toString());
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
    if (error != null) MaterialBanner(content: Text(error!), actions: [TextButton(onPressed: () => setState(() => error = null), child: const Text('关闭'))]),
    Padding(padding: const EdgeInsets.all(8), child: Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
      IconButton(tooltip: '上一项', onPressed: busy || playlist.medias.isEmpty ? null : () => run(player.previous), icon: const Icon(Icons.skip_previous)),
      IconButton(tooltip: playing ? '暂停' : '播放', onPressed: busy || playlist.medias.isEmpty ? null : () => run(player.playOrPause), icon: Icon(playing ? Icons.pause_circle_filled : Icons.play_circle_filled, size: 32)),
      IconButton(tooltip: '下一项', onPressed: busy || playlist.medias.isEmpty ? null : () => run(player.next), icon: const Icon(Icons.skip_next)),
      IconButton(tooltip: '后退10秒', onPressed: busy || playlist.medias.isEmpty ? null : () => run(() async { final ms = (player.state.position.inMilliseconds - 10000).clamp(0, player.state.duration.inMilliseconds).toInt(); await player.seek(Duration(milliseconds: ms)); }), icon: const Icon(Icons.replay_10)),
      IconButton(tooltip: '前进10秒', onPressed: busy || playlist.medias.isEmpty ? null : () => run(() async { final ms = (player.state.position.inMilliseconds + 10000).clamp(0, player.state.duration.inMilliseconds).toInt(); await player.seek(Duration(milliseconds: ms)); }), icon: const Icon(Icons.forward_10)),
      PopupMenuButton<double>(tooltip: '播放速度', onSelected: (v) => run(() => player.setRate(v)), itemBuilder: (_) => [for(final v in [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]) PopupMenuItem(value: v, child: Text('${v}x'))], child: Padding(padding: const EdgeInsets.all(10), child: Text('${rate}x'))),
      IconButton(tooltip: '切换循环模式', onPressed: busy ? null : () => run(() => player.setPlaylistMode(mode == PlaylistMode.none ? PlaylistMode.loop : mode == PlaylistMode.loop ? PlaylistMode.single : PlaylistMode.none)), icon: Icon(mode == PlaylistMode.single ? Icons.repeat_one : Icons.repeat, color: mode == PlaylistMode.none ? Colors.white54 : Theme.of(context).colorScheme.primary)),
      IconButton(tooltip: volume == 0 ? '取消静音' : '静音', onPressed: busy ? null : () => run(() => player.setVolume(volume == 0 ? 100 : 0)), icon: Icon(volume == 0 ? Icons.volume_off : Icons.volume_up)),
    ])),
  ]);

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Row(children: [Icon(Icons.play_circle_fill, color: Color(0xff6ce5c5)), SizedBox(width: 9), Text('Omni Player')])),
    body: SafeArea(child: Column(children: [
      Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), child: Wrap(spacing: 8, runSpacing: 8, children: [
        FilledButton.icon(onPressed: busy ? null : pickFiles, icon: const Icon(Icons.folder_open), label: const Text('打开文件')),
        OutlinedButton.icon(onPressed: busy ? null : pickUrl, icon: const Icon(Icons.link), label: const Text('打开网址')),
      ])),
      if (busy) const LinearProgressIndicator(),
      Expanded(child: LayoutBuilder(builder: (context, constraints) => constraints.maxWidth >= 840
        ? Row(children: [Expanded(child: videoPane()), const VerticalDivider(width: 1), SizedBox(width: 300, child: queue())])
        : Column(children: [Expanded(flex: 3, child: videoPane()), const Divider(height: 1), Expanded(flex: 2, child: queue())]))),
    ])),
  );
}

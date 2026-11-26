import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_player/player_layout.dart';

void main() {
  testWidgets('portrait player fills width with a 16:9 canvas', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Center(child: SizedBox(
      width: 360, height: 680, child: IndexedStack(sizing: StackFit.expand, children: [
        PlayerStage(fill: false, empty: true, surface: ColoredBox(key: Key('surface'),color: Colors.black),footer: Text('Open file')),
        SizedBox.shrink(),
      ]))))));
    expect(tester.getSize(find.byKey(const Key('surface'))), const Size(360,202.5));
    expect(find.text('Open file'),findsOneWidget);
    expect(tester.takeException(),isNull);
  });
  testWidgets('portrait controls remain below the video at phone widths', (tester) async {
    for (final width in [320.0, 360.0, 430.0]) {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: Center(child: SizedBox(width:width,height:560,
        child:const PlayerStage(fill:false,surface:ColoredBox(key:Key('canvas'),color:Colors.black),controls:ColoredBox(key:Key('controls'),color:Colors.blue),footer:Text('Details')))))));
      final canvas = tester.getRect(find.byKey(const Key('canvas')));
      final controls = tester.getRect(find.byKey(const Key('controls')));
      expect(canvas.width,width);
      expect(canvas.height,closeTo(width*9/16,.01));
      expect(controls.top,greaterThanOrEqualTo(canvas.bottom));
      expect(tester.takeException(),isNull);
    }
  });
  testWidgets('landscape fullscreen fills the available viewport', (tester) async {
    await tester.pumpWidget(const MaterialApp(home:Scaffold(body:Center(child:SizedBox(
      width:640,height:320,child:PlayerStage(fill:true,surface:ColoredBox(key:Key('surface'),color:Colors.black),footer:Text('Footer')))))));
    expect(tester.getSize(find.byKey(const Key('surface'))),const Size(640,320));
    expect(find.text('Footer'),findsNothing);
    expect(tester.takeException(),isNull);
  });
  test('fullscreen uses landscape and normal mode restores chosen orientation', () {
    expect(orientationsFor(ScreenDirection.portrait,fullscreen:true), [DeviceOrientation.landscapeLeft,DeviceOrientation.landscapeRight]);
    expect(orientationsFor(ScreenDirection.portrait,fullscreen:false), [DeviceOrientation.portraitUp]);
    expect(orientationsFor(ScreenDirection.automatic,fullscreen:false), isEmpty);
  });
  testWidgets('drag previews locally and seeks once on release', (tester) async {
    // Empty streams suffice: this test asserts gesture behavior with initial values.
    // Avoid awaiting controller.close() in the widget test's fake async zone.
    const positions = Stream<Duration>.empty();
    const durations = Stream<Duration>.empty();
    final calls = <double>[];
    final scrubbing = <bool>[];
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:PlaybackScrubber(
      position:positions,duration:durations,initialPosition:const Duration(seconds:10),
      initialDuration:const Duration(seconds:100),enabled:true,onScrubbing:scrubbing.add,
      onSeek:(v)async{calls.add(v);},formatTime:(ms)=>ms.toString(),
    ))));
    final slider=find.byType(Slider);
    final gesture=await tester.startGesture(tester.getCenter(slider));
    await gesture.moveBy(const Offset(30,0));
    await tester.pump();
    await gesture.moveBy(const Offset(30,0));
    await tester.pump();
    expect(calls,isEmpty);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(calls,hasLength(1));
    expect(scrubbing,[true,false]);
    expect(tester.takeException(),isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}

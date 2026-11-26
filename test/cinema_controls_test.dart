import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_player/minimal_ui.dart';
void main() {
  testWidgets('hidden fullscreen controls cannot receive taps', (tester) async {
    var taps = 0;
    Widget app(bool visible) => MaterialApp(home:Scaffold(body:Center(child:CinemaControls(
      fullscreen:true,visible:visible,child:TextButton(onPressed:()=>taps++,child:const Text('Play'))))));
    await tester.pumpWidget(app(true));
    await tester.tap(find.text('Play'));
    expect(taps,1);
    await tester.pumpWidget(app(false));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Play'),warnIfMissed:false);
    expect(taps,1);
    expect(tester.takeException(),isNull);
  });
}

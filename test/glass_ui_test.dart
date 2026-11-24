import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_player/glass_ui.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('glass panels render in ${brightness.name} theme', (tester) async {
      await tester.pumpWidget(MaterialApp(theme: ThemeData(brightness: brightness),
        home: const Scaffold(body: GlassBackdrop(child: Center(child: GlassPanel(child: Text('Omni')))))));
      expect(find.text('Omni'), findsOneWidget);
      expect(find.byType(BackdropFilter), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('performance mode disables backdrop blur', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: GlassBackdrop(enabled: false,
      child: Center(child: GlassPanel(enabled: false, child: Text('Omni')))))));
    expect(find.text('Omni'), findsOneWidget);
    expect(find.byType(BackdropFilter), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

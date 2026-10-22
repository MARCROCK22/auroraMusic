import 'dart:convert';

import 'package:aurora_music/ui/studio/studio_navigation.dart';
import 'package:aurora_music/ui/studio/studio_symbols.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// PNG de 1x1 px.
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

void main() {
  Future<void> mount(WidgetTester tester, {required bool photo}) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StudioTitleBar(
            onNavigate: (_) {},
            sessionText: 'Sin Jam',
            avatar: photo ? _png : null,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Finder inProfileButton(Finder what) =>
      find.descendant(of: find.byTooltip('Perfil y ajustes'), matching: what);

  testWidgets('the profile button shows the photo when there is one', (
    tester,
  ) async {
    await mount(tester, photo: true);
    expect(inProfileButton(find.byType(Image)), findsOneWidget);
    expect(inProfileButton(find.byIcon(StudioSymbols.person)), findsNothing);
  });

  testWidgets('without a photo it keeps the person icon', (tester) async {
    await mount(tester, photo: false);
    expect(inProfileButton(find.byType(Image)), findsNothing);
    expect(inProfileButton(find.byIcon(StudioSymbols.person)), findsOneWidget);
  });
}

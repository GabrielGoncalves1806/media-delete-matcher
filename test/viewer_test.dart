import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_swipe/media/media_file.dart';
import 'package:media_swipe/media/native_bridge.dart';
import 'package:media_swipe/screens/viewer_screen.dart';
import 'package:media_swipe/theme.dart';

/// PNG de 1×1 pixel, só pra ter um arquivo de imagem de verdade.
const _png = [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x60, 0x00, 0x02, 0x00,
  0x00, 0x05, 0x00, 0x01, 0xE9, 0xFA, 0xDC, 0xD8, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44,
  0xAE, 0x42, 0x60, 0x82,
];

void main() {
  late Directory dir;
  late MediaFile photo;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('media_swipe_viewer');
    final file = File('${dir.path}/IMG_1.png')..writeAsBytesSync(_png);
    photo = MediaFile(path: file.path, size: _png.length, modified: DateTime(2025), isVideo: false);
  });
  tearDown(() => dir.deleteSync(recursive: true));

  Future<void> pumpViewer(WidgetTester tester, {required bool decisions}) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      home: ViewerScreen(file: photo, thumbnails: Thumbnails(NativeBridge()), showDecisions: decisions),
    ));
    await tester.pump();
  }

  testWidgets('no swipe tem Apagar e Manter', (tester) async {
    await pumpViewer(tester, decisions: true);
    expect(find.text('Apagar'), findsOneWidget);
    expect(find.text('Manter'), findsOneWidget);
  });

  testWidgets('nos duplicados é só pra ver', (tester) async {
    await pumpViewer(tester, decisions: false);
    expect(find.text('Apagar'), findsNothing);
    expect(find.text('Manter'), findsNothing);
    expect(find.text('IMG_1.png'), findsOneWidget);
  });
}

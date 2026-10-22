import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:aurora_music/app_controller.dart';
import 'package:aurora_music/core/models.dart';
import 'package:aurora_music/ui/playlist_shelf.dart';
import 'package:aurora_music/ui/playlist_views/playlist_view_mode.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

/// Selector falso: devuelve lo que se le indique (vacío = el usuario canceló).
class _FakePicker extends FilePickerPlatform {
  List<PlatformFile> next = [];
  FileType? lastType;
  int calls = 0;
  @override
  Future<List<PlatformFile>> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    DarwinOptions darwinOptions = const DarwinOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    calls++;
    lastType = type;
    return next;
  }
}

base class _FakeFile extends PlatformFile {
  _FakeFile(this.file);
  final File file;
  @override
  String get name => file.uri.pathSegments.last;
  @override
  Uri get uri => file.uri;
  @override
  get xFile => throw UnimplementedError();
  @override
  int? lengthSync() => file.lengthSync();
  @override
  Future<int?> length() async => file.length();
  @override
  Future<Uint8List> readAsBytes() => file.readAsBytes();
  @override
  Stream<Uint8List> readAsByteStream() =>
      file.openRead().map(Uint8List.fromList);
}

final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
);

/// E/S real y microtareas falsas se alternan: varias vueltas bastan.
Future<void> settleIo(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 50 && !done(); i++) {
    await tester.runAsync(
      () => Future.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
  }
}

void main() {
  late AppController controller;
  late _FakePicker picker;
  late FilePickerPlatform original;
  late File image;
  late MusicPlaylist beta;

  setUp(() async {
    original = FilePickerPlatform.instance;
    picker = _FakePicker();
    FilePickerPlatform.instance = picker;
    controller = await createTestController(
      tracks: const [Track(id: 'one', title: 'Uno', artist: 'A')],
      playlists: const [
        MusicPlaylist(id: 'b', name: 'Beta', trackIds: ['one']),
      ],
    );
    beta = controller.playlists.single;
    image = File('${controller.supportDirectory.path}/foto.png')
      ..writeAsBytesSync(_png);
  });
  tearDown(() async {
    FilePickerPlatform.instance = original;
    playlistViewMode.value = PlaylistViewMode.normal;
    await closeTestController(controller);
  });

  PlatformFile pf(File f) => _FakeFile(f);

  test('elegir, cancelar, archivo inválido y quitar', () async {
    picker.next = [];
    expect(await controller.pickPlaylistPhoto(beta), isNull);
    expect(controller.playlists.single.photoPath, isNull);

    picker.next = [pf(image)];
    expect(await controller.pickPlaylistPhoto(beta), isNull);
    expect(picker.lastType, FileType.image);
    final path = controller.playlists.single.photoPath;
    expect(path, isNotNull);
    expect(File(path!).existsSync(), isTrue);

    final bad = File('${controller.supportDirectory.path}/x.png')
      ..writeAsStringSync('no soy imagen');
    picker.next = [pf(bad)];
    expect(await controller.pickPlaylistPhoto(beta), contains('imagen'));
    expect(controller.playlists.single.photoPath, path);

    await controller.setPlaylistPhoto(controller.playlists.single, null);
    expect(controller.playlists.single.photoPath, isNull);
    expect(File(path).existsSync(), isFalse);
  });

  for (final mode in PlaylistViewMode.values) {
    testWidgets('menú contextual cambia y quita la foto (${mode.name})', (
      tester,
    ) async {
      playlistViewMode.value = mode;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: PlaylistShelf(controller: controller, onOpen: (_) {}),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      picker.next = [pf(image)];

      await tester.tap(find.text('Beta'), buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();
      expect(find.text('Quitar foto'), findsNothing);
      await tester.tap(find.text('Cambiar foto'));
      await tester.pumpAndSettle();
      await settleIo(
        tester,
        () => controller.playlists.single.photoPath != null,
      );
      expect(picker.calls, 1);
      expect(controller.playlists.single.photoPath, isNotNull);

      // Pulsación larga (móvil) ofrece ahora también «Quitar foto».
      await tester.longPress(find.text('Beta'));
      await tester.pumpAndSettle();
      expect(find.text('Quitar foto'), findsOneWidget);
      await tester.tap(find.text('Quitar foto'));
      await settleIo(
        tester,
        () => controller.playlists.single.photoPath == null,
      );
      expect(controller.playlists.single.photoPath, isNull);
    });
  }
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_swipe/media/media_file.dart';
import 'package:media_swipe/media/media_filter.dart';
import 'package:media_swipe/media/media_library.dart';
import 'package:media_swipe/media/trash_bin.dart';

void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('media_swipe_storage'));
  tearDown(() => root.deleteSync(recursive: true));

  File put(String relative, {int size = 10}) =>
      File('${root.path}/$relative')
        ..createSync(recursive: true)
        ..writeAsBytesSync(List.filled(size, 7));

  group('scanStorage', () {
    test('acha mídia mesmo em pasta com .nomedia', () {
      put('Android/media/com.whatsapp/WhatsApp/Media/.nomedia', size: 0);
      put('Android/media/com.whatsapp/WhatsApp/Media/WhatsApp Video/VID-1.mp4', size: 500);
      put('DCIM/Camera/IMG_1.JPG', size: 300);

      final files = scanStorage(root.path).media;
      final names = files.map((f) => f.name).toSet();

      expect(names, {'VID-1.mp4', 'IMG_1.JPG'});
      expect(files.firstWhere((f) => f.name == 'VID-1.mp4').isVideo, isTrue);
      expect(files.firstWhere((f) => f.name == 'IMG_1.JPG').size, 300);
    });

    test('pula ocultos, lixeira do Android, Android/data, vazios e não-mídia', () {
      put('DCIM/.thumbnails/t.jpg', size: 3);
      put('DCIM/Camera/.trashed-1700000000-IMG_2.jpg', size: 5);
      put('Android/data/com.app/cache/x.jpg', size: 1000);
      put('Download/vazio.mp4', size: 0);
      put('Download/doc.pdf', size: 7);
      put('Lixo/skip.jpg', size: 1000);
      put('Download/ok.webp', size: 11);

      final scan = scanStorage(root.path, skip: {'${root.path}/Lixo'});
      expect(scan.media.map((f) => f.name), ['ok.webp']);
      // ocultos e não-mídia contam como "outros"; Android/data e skip não
      expect(scan.otherBytes, 3 + 5 + 7);
    });
  });

  group('TrashBin', () {
    late List<List<String>> notified;
    late TrashBin trash;

    setUp(() {
      notified = [];
      trash = TrashBin(
        '${root.path}/.media_swipe_trash',
        onFilesChanged: (paths) async => notified.add(paths),
      );
    });

    MediaFile media(File f, {bool video = false}) => MediaFile(
          path: f.path,
          size: f.lengthSync(),
          modified: f.lastModifiedSync(),
          isVideo: video,
        );

    test('mover, persistir e restaurar', () async {
      final original = put('DCIM/Camera/a.jpg', size: 100);

      final moved = await trash.moveIn([media(original)]);
      expect(moved, [original.path]);
      expect(original.existsSync(), isFalse);
      expect(File('${trash.directory}/.nomedia').existsSync(), isTrue);
      expect(trash.bytes, 100);
      expect(notified.single, [original.path]);

      // outra instância lê o índice do disco
      final reopened = TrashBin(trash.directory, onFilesChanged: (_) async {});
      await reopened.load();
      expect(reopened.entries.single.originalPath, original.path);

      expect(await reopened.restore(reopened.entries.single), isTrue);
      expect(original.readAsBytesSync().length, 100);
      expect(reopened.entries, isEmpty);
    });

    test('não restaura por cima de outro arquivo', () async {
      final original = put('DCIM/Camera/a.jpg');
      await trash.moveIn([media(original)]);
      put('DCIM/Camera/a.jpg'); // apareceu outro com o mesmo nome

      expect(await trash.restore(trash.entries.single), isFalse);
      expect(trash.entries, hasLength(1));
    });

    test('esvaziar apaga de vez e devolve o espaço', () async {
      final a = put('x/a.mp4', size: 40);
      final b = put('x/b.mp4', size: 60);
      await trash.moveIn([media(a, video: true), media(b, video: true)]);

      expect(await trash.empty(), 100);
      expect(trash.entries, isEmpty);
      final left = Directory(trash.directory).listSync().map((e) => e.path.split('/').last);
      expect(left.toSet(), {'.nomedia', 'index.json'});
    });

    test('expira depois de 30 dias', () async {
      final now = DateTime(2026, 10, 2);
      await trash.moveIn([media(put('x/velho.jpg'))], now: now.subtract(const Duration(days: 31)));
      await trash.moveIn([media(put('x/novo.jpg'))], now: now.subtract(const Duration(days: 2)));

      await trash.purgeExpired(now: now);
      expect(trash.entries.map((e) => e.originalName), ['novo.jpg']);
    });

    test('arquivo que sumiu é ignorado', () async {
      final ghost = MediaFile(
        path: '${root.path}/nao/existe.jpg',
        size: 1,
        modified: DateTime(2024),
        isVideo: false,
      );
      expect(await trash.moveIn([ghost]), isEmpty);
      expect(trash.entries, isEmpty);
    });
  });

  group('MediaLibrary.albums', () {
    test('só pastas com algo pra revisar, maiores primeiro', () async {
      put('DCIM/Camera/a.jpg', size: 100);
      put('DCIM/Camera/b.jpg', size: 50);
      put('WhatsApp Video/v.mp4', size: 400);
      put('Screenshots/s.png', size: 10);

      final library = MediaLibrary(root: root.path, dataDir: '${root.path}/.app');
      await library.scan();
      expect(library.files.first.name, 'v.mp4'); // do maior pro menor

      // tudo da pasta de screenshots já decidido, e um item da câmera também
      final decided = {'${root.path}/Screenshots/s.png', '${root.path}/DCIM/Camera/a.jpg'};
      final albums = library.albums(MediaFilter.none, isDecided: decided.contains);

      expect(albums.map((a) => a.name), ['WhatsApp Video', 'Camera']);
      expect(albums.last.bytes, 50); // só o que falta revisar
      expect(library.all(MediaFilter.none, isDecided: decided.contains).files, hasLength(2));
    });
  });
}


import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_swipe/media/media_file.dart';
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

      final files = scanStorage(root.path);
      final names = files.map((f) => f.name).toSet();

      expect(names, {'VID-1.mp4', 'IMG_1.JPG'});
      expect(files.firstWhere((f) => f.name == 'VID-1.mp4').isVideo, isTrue);
      expect(files.firstWhere((f) => f.name == 'IMG_1.JPG').size, 300);
    });

    test('pula ocultos, lixeira do Android, Android/data, vazios e não-mídia', () {
      put('DCIM/.thumbnails/t.jpg');
      put('DCIM/Camera/.trashed-1700000000-IMG_2.jpg');
      put('Android/data/com.app/cache/x.jpg');
      put('Download/vazio.mp4', size: 0);
      put('Download/doc.pdf');
      put('Lixo/skip.jpg');
      put('Download/ok.webp');

      final files = scanStorage(root.path, skip: {'${root.path}/Lixo'});
      expect(files.map((f) => f.name), ['ok.webp']);
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
}

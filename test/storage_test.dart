import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_swipe/media/media_file.dart';
import 'package:media_swipe/media/media_filter.dart';
import 'package:media_swipe/media/media_library.dart';
import 'package:media_swipe/media/native_bridge.dart';
import 'package:media_swipe/media/trash_bin.dart';

/// Não fala com o Android: no computador não tem canal nativo.
class _QuietNative extends NativeBridge {
  @override
  Future<void> scanFiles(List<String> paths) async {}
}

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

  group('scanStorage incremental', () {
    /// Joga a data de todas as pastas pro passado: simula pastas que já
    /// existiam antes, em vez de criadas no mesmo instante do teste.
    void ageDirs() {
      final dirs = [root, ...root.listSync(recursive: true).whereType<Directory>()];
      for (final d in dirs) {
        Process.runSync('touch', ['-m', '-t', '202001010000', d.path]);
      }
    }

    test('pasta mexida agora sempre é relistada', () {
      put('DCIM/Camera/a.jpg', size: 100);
      final first = scanStorage(root.path);
      final second = scanStorage(root.path, previous: first.snapshots);
      expect(second.listedDirs, first.listedDirs);
    });

    test('sem mudança, nada é relistado e o resultado é o mesmo', () {
      put('DCIM/Camera/a.jpg', size: 100);
      put('WhatsApp Video/v.mp4', size: 400);
      put('WhatsApp Video/.Statuses/s.jpg', size: 9);
      ageDirs();

      final first = scanStorage(root.path);
      expect(first.listedDirs, greaterThan(0));

      final second = scanStorage(root.path, previous: first.snapshots);
      expect(second.listedDirs, 0);
      expect(second.media.map((f) => f.path).toSet(), first.media.map((f) => f.path).toSet());
      expect(second.otherBytes, first.otherBytes);
    });

    test('só relista a pasta que mudou', () {
      put('DCIM/Camera/a.jpg', size: 100);
      put('WhatsApp Video/v.mp4', size: 400);
      ageDirs();
      final first = scanStorage(root.path);

      put('WhatsApp Video/novo.mp4', size: 50);
      File('${root.path}/DCIM/Camera/a.jpg').deleteSync();
      final second = scanStorage(root.path, previous: first.snapshots);

      expect(second.listedDirs, 2); // WhatsApp Video e DCIM/Camera
      expect(second.media.map((f) => f.name).toSet(), {'v.mp4', 'novo.mp4'});
    });

    test('progresso: lista, depois mede até 100%; incremental sem mudança não mede nada', () {
      for (var i = 0; i < 5; i++) {
        put('DCIM/Camera/IMG_$i.jpg', size: 10);
      }
      put('Download/doc.pdf', size: 3);
      ageDirs();

      final first = <ScanProgress>[];
      final scan = scanStorage(root.path, onProgress: first.add);
      expect(first.last.phase, ScanPhase.measuring);
      expect(first.last.files, 6);
      expect(first.last.measured, 6);
      expect(first.last.fraction, 1.0);

      final second = <ScanProgress>[];
      scanStorage(root.path, previous: scan.snapshots, onProgress: second.add);
      expect(second.last.files, 0); // tudo veio do cache
    });

    test('o retrato sobrevive ao JSON', () {
      put('DCIM/Camera/IMG 1.jpg', size: 100);
      put('DCIM/Camera/.hidden/x.bin', size: 3);
      final scan = scanStorage(root.path);
      final dir = '${root.path}/DCIM/Camera';

      final back = DirSnapshot.fromJson(dir, jsonDecode(jsonEncode(scan.snapshots[dir]!.toJson())));
      expect(back.media.single.path, '$dir/IMG 1.jpg');
      expect(back.media.single.size, 100);
      expect(back.subdirs, ['$dir/.hidden']);
      expect(back.modified, scan.snapshots[dir]!.modified);
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

  group('MediaLibrary cache', () {
    test('abre do cache e não traz de volta o que saiu durante a varredura', () async {
      put('DCIM/Camera/a.jpg', size: 100);
      put('DCIM/Camera/b.jpg', size: 50);
      final dataDir = '${root.path}/.app';

      final library = MediaLibrary(root: root.path, dataDir: dataDir);
      expect(await library.loadCached(), isFalse); // primeira vez
      await library.scan();

      final reopened = MediaLibrary(root: root.path, dataDir: dataDir);
      expect(await reopened.loadCached(), isTrue);
      expect(reopened.files.map((f) => f.name), ['a.jpg', 'b.jpg']);

      // varredura começa, e no meio um arquivo vai pra lixeira
      final scanning = reopened.scan(full: true);
      reopened.forget(['${root.path}/DCIM/Camera/a.jpg']);
      await scanning;
      expect(reopened.files.map((f) => f.name), ['b.jpg']);
    });
  });

  group('cartão SD', () {
    // root = armazenamento interno; sd = o cartão, num diretório irmão
    late Directory sd;

    setUp(() => sd = Directory.systemTemp.createTempSync('media_swipe_sd'));
    tearDown(() => sd.deleteSync(recursive: true));

    File putSd(String relative, {int size = 10}) =>
        File('${sd.path}/$relative')
          ..createSync(recursive: true)
          ..writeAsBytesSync(List.filled(size, 7));

    test('varre os dois volumes e separa por volume', () async {
      put('DCIM/Camera/a.jpg', size: 100);
      putSd('DCIM/Camera/b.mp4', size: 300);
      putSd('Musica/x.mp3', size: 9);

      final library = MediaLibrary(root: root.path, dataDir: '${root.path}/.app', extraRoots: [sd.path]);
      await library.scan();

      expect(library.files.map((f) => f.name), ['b.mp4', 'a.jpg']);
      expect(library.filesIn(sd.path).single.name, 'b.mp4');
      expect(library.isRemovable('${sd.path}/DCIM/Camera/b.mp4'), isTrue);
      expect(library.isRemovable('${root.path}/DCIM/Camera/a.jpg'), isFalse);
      expect(library.otherBytesIn(sd.path), 9);
      expect(library.otherBytesIn(root.path), 0);
    });

    test('álbuns e "tudo" separados por volume', () async {
      put('DCIM/Camera/a.jpg', size: 100);
      putSd('DCIM/Camera/b.jpg', size: 300);
      putSd('Fotos/c.jpg', size: 50);
      final library = MediaLibrary(root: root.path, dataDir: '${root.path}/.app', extraRoots: [sd.path]);
      await library.scan();

      final internal = library.albums(MediaFilter.none, volume: root.path);
      final card = library.albums(MediaFilter.none, volume: sd.path);

      expect(internal.map((a) => a.folder), ['${root.path}/DCIM/Camera']);
      expect(card.map((a) => a.folder), ['${sd.path}/DCIM/Camera', '${sd.path}/Fotos']);
      expect(library.all(MediaFilter.none, volume: sd.path).bytes, 350);
      expect(library.all(MediaFilter.none).files, hasLength(3)); // sem volume = tudo
    });

    test('cada arquivo vai pra lixeira do próprio volume', () async {
      put('DCIM/a.jpg', size: 100);
      putSd('DCIM/b.jpg', size: 50);
      final library = MediaLibrary(
        root: root.path,
        dataDir: '${root.path}/.app',
        extraRoots: [sd.path],
        native: _QuietNative(),
      );
      await library.scan();

      final moved = await library.trash.moveIn(library.files);

      expect(moved, hasLength(2));
      expect(library.trash.bytesIn(root.path), 100);
      expect(library.trash.bytesIn(sd.path), 50);
      expect(Directory('${sd.path}/.media_swipe_trash').listSync().any((e) => e.path.endsWith('_b.jpg')), isTrue);

      // restaurar devolve pro cartão
      final sdEntry = library.trash.entries.firstWhere((e) => e.originalName == 'b.jpg');
      expect(library.trash.pathOf(sdEntry), startsWith(sd.path));
      expect(await library.trash.restore(sdEntry), isTrue);
      expect(File('${sd.path}/DCIM/b.jpg').existsSync(), isTrue);

      // a varredura não lista a mídia que tá dentro das lixeiras
      await library.scan(full: true);
      expect(library.files.map((f) => f.name), ['b.jpg']);
    });

    test('cartão tirado: o cache não traz as pastas dele de volta', () async {
      put('DCIM/a.jpg', size: 100);
      putSd('DCIM/b.jpg', size: 50);
      final dataDir = '${root.path}/.app';
      await MediaLibrary(root: root.path, dataDir: dataDir, extraRoots: [sd.path]).scan();

      final withoutSd = MediaLibrary(root: root.path, dataDir: dataDir); // só o interno
      expect(await withoutSd.loadCached(), isTrue);
      expect(withoutSd.files.map((f) => f.name), ['a.jpg']);
    });
  });
}


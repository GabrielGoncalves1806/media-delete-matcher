import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_swipe/media/media_library.dart';
import 'package:media_swipe/media/media_mover.dart';
import 'package:media_swipe/media/native_bridge.dart';

/// Diz que o cartão tem [cardFree] bytes livres e não fala com o Android.
class _FakeNative extends NativeBridge {
  _FakeNative(this.cardPath, {this.cardFree = 1 << 40});

  final String cardPath;
  final int cardFree;
  final scanned = <String>[];

  @override
  Future<List<StorageVolume>> storageVolumes() async => [
        StorageVolume(
          path: cardPath,
          label: 'Cartão SD',
          removable: true,
          primary: false,
          total: 8000000000,
          free: cardFree,
        ),
      ];

  @override
  Future<void> scanFiles(List<String> paths) async => scanned.addAll(paths);
}

void main() {
  late Directory phone;
  late Directory card;

  setUp(() {
    phone = Directory.systemTemp.createTempSync('media_swipe_phone');
    card = Directory.systemTemp.createTempSync('media_swipe_card');
  });
  tearDown(() {
    phone.deleteSync(recursive: true);
    card.deleteSync(recursive: true);
  });

  Future<MediaLibrary> libraryWith(_FakeNative native) async {
    final library = MediaLibrary(
      root: phone.path,
      dataDir: '${phone.path}/.app',
      extraRoots: [card.path],
      native: native,
    );
    await library.scan();
    return library;
  }

  File put(String relative, List<int> bytes) => File('${phone.path}/$relative')
    ..createSync(recursive: true)
    ..writeAsBytesSync(bytes)
    ..setLastModifiedSync(DateTime(2023, 3, 4));

  test('move pro cartão: copia, confere, mantém a data e apaga do celular', () async {
    final bytes = List.generate(300000, (i) => i % 251);
    final original = put('DCIM/Camera/v.mp4', bytes);
    final native = _FakeNative(card.path);
    final library = await libraryWith(native);
    final target = Directory('${card.path}/Videos')..createSync();
    final progress = <double>[];

    final result = await MediaMover(library).move(
      library.byPath(original.path)!,
      target.path,
      onProgress: progress.add,
    );

    expect(result.ok, isTrue);
    final moved = File('${target.path}/v.mp4');
    expect(moved.readAsBytesSync(), bytes);
    expect(moved.lastModifiedSync(), DateTime(2023, 3, 4));
    expect(original.existsSync(), isFalse);
    expect(progress.last, 1.0);
    expect(library.contains(original.path), isFalse);
    expect(library.byPath(moved.path)!.size, bytes.length);
    expect(native.scanned, containsAll([original.path, moved.path]));
    // nenhum temporário sobrando
    expect(target.listSync().map((e) => e.path.split('/').last), ['v.mp4']);
  });

  test('nome repetido no destino ganha (2)', () async {
    final original = put('DCIM/a.jpg', [1, 2, 3]);
    final library = await libraryWith(_FakeNative(card.path));
    File('${card.path}/a.jpg').writeAsBytesSync([9]);

    final result = await MediaMover(library).move(library.byPath(original.path)!, card.path);

    expect(result.newFile!.path, '${card.path}/a (2).jpg');
    expect(File('${card.path}/a.jpg').readAsBytesSync(), [9]); // intocado
  });

  test('sem espaço no cartão: nada muda', () async {
    final original = put('DCIM/a.jpg', List.filled(1000, 1));
    final library = await libraryWith(_FakeNative(card.path, cardFree: 5000));

    final result = await MediaMover(library).move(library.byPath(original.path)!, card.path);

    expect(result.ok, isFalse);
    expect(result.error, contains('Não cabe'));
    expect(original.existsSync(), isTrue);
    expect(card.listSync(), isEmpty);
  });

  test('pasta de destino que não existe: falha sem apagar o original', () async {
    final original = put('DCIM/a.jpg', [1, 2, 3]);
    final library = await libraryWith(_FakeNative(card.path));

    final result = await MediaMover(library).move(library.byPath(original.path)!, '${card.path}/nao/existe');

    expect(result.ok, isFalse);
    expect(original.existsSync(), isTrue);
  });
}

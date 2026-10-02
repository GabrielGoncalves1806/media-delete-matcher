import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_swipe/media/duplicate_finder.dart';
import 'package:media_swipe/media/file_hash.dart';
import 'package:photo_manager/photo_manager.dart';

AssetEntity asset(String id, {String? path, int? created}) => AssetEntity(
      id: id,
      typeInt: 1,
      width: 1,
      height: 1,
      relativePath: path,
      createDateSecond: created,
    );

void main() {
  group('file_hash', () {
    late Directory dir;

    setUp(() => dir = Directory.systemTemp.createTempSync('media_swipe_test'));
    tearDown(() => dir.deleteSync(recursive: true));

    String write(String name, Uint8List bytes) {
      final file = File('${dir.path}/$name')..writeAsBytesSync(bytes);
      return file.path;
    }

    test('cópias idênticas têm o mesmo hash parcial e completo', () {
      final bytes = Uint8List.fromList(List.generate(300 * 1024, (i) => i % 251));
      final a = write('a.mp4', bytes);
      final b = write('b.mp4', bytes);

      expect(partialHash(a), partialHash(b));
      expect(fullHash(a), fullHash(b));
    });

    test('mesmo tamanho, mesmas bordas, miolo diferente: só o completo separa', () {
      final bytes = Uint8List.fromList(List.generate(300 * 1024, (i) => i % 251));
      final changed = Uint8List.fromList(bytes)..[150 * 1024] ^= 0xFF;
      final a = write('a.mp4', bytes);
      final b = write('b.mp4', changed);

      expect(partialHash(a), partialHash(b)); // o funil deixa passar...
      expect(fullHash(a), isNot(fullHash(b))); // ...e o hash completo barra
    });

    test('arquivo menor que 64 KB e arquivo vazio', () {
      final rng = Random(1);
      final small = write('s.jpg', Uint8List.fromList(List.generate(1000, (_) => rng.nextInt(256))));
      final empty = write('e.jpg', Uint8List(0));

      expect(partialHash(small), isNotNull);
      expect(fullHash(small), isNotNull);
      expect(fullHash(empty), isNotNull);
    });

    test('arquivo inexistente devolve null', () {
      expect(partialHash('${dir.path}/nao_existe'), isNull);
      expect(fullHash(''), isNull);
    });
  });

  group('groupsOf', () {
    test('só grupos com 2+ itens, ignorando chave null', () {
      final groups = groupsOf(
        ['a1', 'a2', 'b1', 'c1', 'c2', 'c3', 'x'],
        (s) => s == 'x' ? null : s[0],
      );
      expect(groups, [
        ['a1', 'a2'],
        ['c1', 'c2', 'c3'],
      ]);
    });
  });

  group('chooseKeeper', () {
    test('prefere a cópia da câmera', () {
      final keeper = chooseKeeper([
        asset('wpp', path: 'Android/media/com.whatsapp/WhatsApp/Media/WhatsApp Video/', created: 100),
        asset('cam', path: 'DCIM/Camera/', created: 200),
      ]);
      expect(keeper.id, 'cam');
    });

    test('sem câmera, fica a mais antiga', () {
      final keeper = chooseKeeper([
        asset('novo', path: 'WhatsApp Video/', created: 300),
        asset('velho', path: 'WhatsApp Video/Sent/', created: 100),
      ]);
      expect(keeper.id, 'velho');
    });

    test('grupo calcula o desperdício', () {
      final group = DuplicateGroup([asset('a'), asset('b'), asset('c')], 10);
      expect(group.wastedBytes, 20);
      expect(group.copies.length, 2);
    });
  });
}

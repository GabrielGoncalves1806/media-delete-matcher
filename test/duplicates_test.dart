import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_swipe/media/duplicate_finder.dart';
import 'package:media_swipe/media/file_hash.dart';
import 'package:media_swipe/media/media_file.dart';

MediaFile media(String path, {int modified = 0, int size = 10}) => MediaFile(
      path: path,
      size: size,
      modified: DateTime.fromMillisecondsSinceEpoch(modified),
      isVideo: false,
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
        media('/s/Android/media/com.whatsapp/WhatsApp/Media/WhatsApp Video/a.mp4', modified: 100),
        media('/s/DCIM/Camera/a.mp4', modified: 200),
      ]);
      expect(keeper.path, '/s/DCIM/Camera/a.mp4');
    });

    test('sem câmera, fica a mais antiga', () {
      final keeper = chooseKeeper([
        media('/s/WhatsApp Video/novo.mp4', modified: 300),
        media('/s/WhatsApp Video/Sent/velho.mp4', modified: 100),
      ]);
      expect(keeper.path, '/s/WhatsApp Video/Sent/velho.mp4');
    });

    test('grupo calcula o desperdício', () {
      final group = DuplicateGroup([media('/a'), media('/b'), media('/c')]);
      expect(group.wastedBytes, 20);
      expect(group.copies.length, 2);
    });

    test('apagar todas: nenhuma fica', () {
      final group = DuplicateGroup([media('/a'), media('/b')]);
      expect(group.deleteAll, isFalse);
      expect(group.bytesToFree, 10);

      group.keeperPath = null;
      expect(group.deleteAll, isTrue);
      expect(group.copies.map((f) => f.path), ['/a', '/b']);
      expect(group.bytesToFree, 20);
      expect(group.wastedBytes, 10); // a ordem dos grupos não muda
    });
  });
}

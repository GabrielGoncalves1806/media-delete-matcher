import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_swipe/format.dart';
import 'package:media_swipe/media/decision_store.dart';
import 'package:media_swipe/media/json_file.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('format', () {
    test('formatBytes', () {
      expect(formatBytes(500 * 1000), '500 KB');
      expect(formatBytes(151 * 1000 * 1000), '151 MB');
      expect(formatBytes(1500 * 1000 * 1000), '1,5 GB');
      expect(formatBytes(128 * 1000 * 1000 * 1000), '128 GB');
    });

    test('formatCount e plural', () {
      expect(formatCount(11402), '11.402');
      expect(formatCount(999), '999');
      expect(plural(1, 'item', 'itens'), '1 item');
      expect(plural(3286, 'vídeo', 'vídeos'), '3.286 vídeos');
    });

    test('formatDate e formatDuration', () {
      expect(formatDate(DateTime(2024, 5, 12)), '12 mai 2024');
      expect(formatDuration(const Duration(minutes: 4, seconds: 2)), '4:02');
      expect(formatDuration(const Duration(hours: 1, minutes: 2, seconds: 33)), '1:02:33');
    });
  });

  group('DecisionStore', () {
    late Directory dir;
    late JsonFile file;
    late DecisionStore store;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      dir = Directory.systemTemp.createTempSync('media_swipe_store');
      file = JsonFile(File('${dir.path}/decisions.json'));
      store = DecisionStore(file);
      await store.load();
    });

    tearDown(() => dir.deleteSync(recursive: true));

    test('marcar, manter e desfazer', () {
      store.markForDeletion('a', 100);
      store.markForDeletion('b', 50);
      store.keep('c');

      expect(store.markedCount, 2);
      expect(store.markedBytes, 150);
      expect(store.isDecided('c'), isTrue);

      store.forget('b');
      expect(store.markedBytes, 100);
      expect(store.isDecided('b'), isFalse);
    });

    test('forgetAll devolve vários pro swipe de uma vez', () {
      store.keep('a');
      store.keep('b');
      store.markForDeletion('c', 10);

      store.forgetAll(['a', 'c']);
      expect(store.kept, {'b'});
      expect(store.markedCount, 0);
    });

    test('desmarcar e remarcar na revisão', () {
      store.markForDeletion('a', 100);

      store.toggleInReview('a');
      expect(store.markedCount, 0);
      expect(store.isDecided('a'), isTrue); // virou "mantido"
      expect(store.unmarkedInReview['a'], 100);

      store.toggleInReview('a');
      expect(store.marked['a'], 100);
    });

    test('confirmar lixeira soma no total liberado', () {
      store.markForDeletion('a', 100);
      store.markForDeletion('b', 50);

      store.confirmTrashed(['a']);
      expect(store.freedBytes, 100);
      expect(store.marked.keys, ['b']);
    });

    test('persiste entre aberturas', () async {
      store.markForDeletion('a', 100);
      store.keep('k');
      store.confirmTrashed(['x']); // id desconhecido não soma nada

      await store.flush();
      final reopened = DecisionStore(file);
      await reopened.load();
      expect(reopened.marked, {'a': 100});
      expect(reopened.isDecided('k'), isTrue);
      expect(reopened.freedBytes, 0);
    });
  });

  group('DecisionStore: gravação', () {
    late Directory dir;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('media_swipe_store2');
    });
    tearDown(() => dir.deleteSync(recursive: true));

    test('agrupa vários swipes numa gravação só', () async {
      SharedPreferences.setMockInitialValues({});
      final file = JsonFile(File('${dir.path}/d.json'));
      final store = DecisionStore(file, saveDelay: const Duration(milliseconds: 50));
      await store.load();
      final writesBefore = file.file.lastModifiedSync();

      for (var i = 0; i < 200; i++) {
        store.keep('/p/$i');
      }
      expect(file.file.lastModifiedSync(), writesBefore); // ainda não gravou
      await Future<void>.delayed(const Duration(milliseconds: 120));

      final saved = await file.read() as Map;
      expect((saved['kept'] as List).length, 200);
    });

    test('migra da v2 (shared_preferences) e limpa as chaves', () async {
      SharedPreferences.setMockInitialValues({
        'v2.kept': ['/a'],
        'v2.marked': ['/b:/c.mp4:50'], // caminho com ":" no meio
        'freedBytes': 7,
      });
      final store = DecisionStore(JsonFile(File('${dir.path}/d.json')));
      await store.load();

      expect(store.isDecided('/a'), isTrue);
      expect(store.marked, {'/b:/c.mp4': 50});
      expect(store.freedBytes, 7);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys(), isEmpty);
    });
  });
}


import 'package:flutter_test/flutter_test.dart';
import 'package:media_swipe/media/duplicate_finder.dart';
import 'package:media_swipe/media/media_file.dart';
import 'package:media_swipe/media/similar_finder.dart';

MediaFile video(String path, int size) =>
    MediaFile(path: path, size: size, modified: DateTime(2025), isVideo: true);
MediaFile photo(String path, int size) =>
    MediaFile(path: path, size: size, modified: DateTime(2025), isVideo: false);

/// Muda [bits] bits de um hash (pra simular recompressão).
int flip(int hash, int bits) {
  var h = hash;
  for (var i = 0; i < bits; i++) {
    h ^= 1 << (i * 7 % 64);
  }
  return h;
}

const a = 0x0F0F_3C3C_A5A5_5A5A;
const b = 0x7E81_6699_C3C3_1E1E;
const c = 0x1234_5678_9ABC_DEF0;

void main() {
  test('hamming', () {
    expect(hamming(0, 0), 0);
    expect(hamming(0, 1), 1);
    expect(hamming(a, a), 0);
    expect(hamming(a, flip(a, 5)), 5);
    expect(hamming(0, -1), 64); // todos os bits, inclusive o de sinal
  });

  test('duração: até 1 s ou 2%', () {
    expect(sameDuration(10000, 10900), isTrue);
    expect(sameDuration(10000, 11500), isFalse);
    expect(sameDuration(300000, 305000), isTrue); // 2% de 5 min = 6 s
  });

  test('vídeo recomprimido parece; outro vídeo da mesma duração não', () {
    const original = Fingerprint(60000, [a, b, c]);
    final recomprimido = Fingerprint(60400, [flip(a, 4), flip(b, 6), flip(c, 3)]);
    const outro = Fingerprint(60000, [c, a, b]);

    expect(similarVideos(original, recomprimido), isTrue);
    expect(similarVideos(original, outro), isFalse);
  });

  test('quadros chapados não contam: precisa de 2 quadros de verdade', () {
    const pretoA = Fingerprint(30000, [flatFrame, flatFrame, a]);
    const pretoB = Fingerprint(30000, [flatFrame, flatFrame, a]);
    expect(similarVideos(pretoA, pretoB), isFalse);

    const doisDeVerdade = Fingerprint(30000, [flatFrame, b, a]);
    expect(similarVideos(doisDeVerdade, doisDeVerdade), isTrue);
  });

  test('foto: limite mais apertado e chapada nunca bate', () {
    expect(similarPhotos(Fingerprint(0, [a]), Fingerprint(0, [flip(a, 5)])), isTrue);
    expect(similarPhotos(Fingerprint(0, [a]), Fingerprint(0, [flip(a, 9)])), isFalse);
    expect(similarPhotos(const Fingerprint(0, [flatFrame]), const Fingerprint(0, [flatFrame])), isFalse);
  });

  test('agrupa em cadeia, separa vídeo de foto e ignora cópia idêntica', () {
    final v1 = video('/v/original.mp4', 50);
    final v2 = video('/v/whatsapp.mp4', 12);
    final v3 = video('/v/sent.mp4', 11);
    final v4 = video('/v/outro.mp4', 30);
    final p1 = photo('/p/a.jpg', 9);
    final p2 = photo('/p/a-copia.jpg', 9); // mesmo tamanho: idêntica, outra aba
    final p3 = photo('/p/rajada1.jpg', 8);
    final p4 = photo('/p/rajada2.jpg', 7);

    final prints = {
      v1.path: const Fingerprint(60000, [a, b, c]),
      v2.path: Fingerprint(60200, [flip(a, 3), flip(b, 3), flip(c, 3)]),
      v3.path: Fingerprint(60300, [flip(a, 6), flip(b, 5), flip(c, 6)]),
      v4.path: const Fingerprint(60000, [c, a, b]),
      p1.path: const Fingerprint(0, [b]),
      p2.path: const Fingerprint(0, [b]),
      p3.path: const Fingerprint(0, [c]),
      p4.path: Fingerprint(0, [flip(c, 4)]),
    };

    final groups = groupSimilar([v1, v2, v3, v4, p1, p2, p3, p4], prints)
        .map((g) => [for (final f in g) f.path])
        .toList();

    // (Set == Set em Dart compara identidade, não conteúdo; daí o unorderedEquals.)
    expect(
      groups,
      unorderedEquals([
        unorderedEquals([v1.path, v2.path, v3.path]),
        unorderedEquals([p3.path, p4.path]),
      ]),
    );
  });

  test('nos parecidos fica o maior, e o desperdício soma os tamanhos reais', () {
    final group = DuplicateGroup(
      [video('/w/zap.mp4', 12), video('/DCIM/cam.mp4', 50), video('/w/sent.mp4', 11)],
      similar: true,
    );
    expect(group.keeperPath, '/DCIM/cam.mp4');
    expect(group.bytesToFree, 23);
    expect(group.wastedBytes, 23);

    group.keeperPath = null; // apagar todos
    expect(group.bytesToFree, 73);
  });
}

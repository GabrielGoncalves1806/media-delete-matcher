import 'dart:isolate';

import 'duplicate_finder.dart';
import 'json_file.dart';
import 'media_file.dart';
import 'native_bridge.dart';

/// Quadro chapado (tela preta, branca...) ou que não abriu. Vem do Kotlin
/// (Long.MIN_VALUE) e é ignorado na comparação: senão todo vídeo que começa
/// preto "pareceria" com todo outro.
const flatFrame = -9223372036854775808;

/// Até quantos bits de 64 podem mudar num quadro de vídeo parecido.
/// Recompressão e mudança de resolução mexem pouco; cena diferente, muito.
const maxVideoFrameDistance = 12;

/// Média dos quadros comparados de um vídeo tem que ficar abaixo disso.
const maxVideoAverageDistance = 8;

/// Foto é um quadro só, então o limite é mais apertado.
const maxPhotoDistance = 6;

/// Impressão digital de um arquivo: a duração (0 pra foto) e um hash de 64
/// bits por quadro (3 por vídeo, 1 por foto). Ver MainActivity.fingerprint.
class Fingerprint {
  const Fingerprint(this.durationMs, this.hashes);

  final int durationMs;
  final List<int> hashes;
}

/// Quantos bits diferem entre dois hashes.
int hamming(int a, int b) {
  var x = a ^ b;
  var count = 0;
  while (x != 0) {
    x &= x - 1; // apaga o bit 1 mais baixo
    count++;
  }
  return count;
}

/// Duração "igual" pra vídeo: até 1 s ou 2%, o que for maior (o WhatsApp
/// às vezes corta uns milissegundos ao recomprimir).
bool sameDuration(int a, int b) {
  final tolerance = (a > b ? a : b) * 0.02;
  return (a - b).abs() <= (tolerance > 1000 ? tolerance : 1000);
}

bool similarVideos(Fingerprint a, Fingerprint b) {
  if (!sameDuration(a.durationMs, b.durationMs)) return false;
  var compared = 0;
  var total = 0;
  for (var i = 0; i < a.hashes.length && i < b.hashes.length; i++) {
    if (a.hashes[i] == flatFrame || b.hashes[i] == flatFrame) continue;
    final distance = hamming(a.hashes[i], b.hashes[i]);
    if (distance > maxVideoFrameDistance) return false;
    compared++;
    total += distance;
  }
  // Precisa de pelo menos 2 quadros de verdade pra afirmar alguma coisa.
  return compared >= 2 && total / compared <= maxVideoAverageDistance;
}

bool similarPhotos(Fingerprint a, Fingerprint b) {
  final x = a.hashes.first;
  final y = b.hashes.first;
  if (x == flatFrame || y == flatFrame) return false;
  return hamming(x, y) <= maxPhotoDistance;
}

/// Agrupa o que é parecido (se A parece com B e B com C, os três ficam
/// juntos). Grupos em que todo mundo tem o mesmo tamanho ficam de fora:
/// quase certo que são cópias idênticas, que já aparecem na outra aba.
List<List<MediaFile>> groupSimilar(List<MediaFile> files, Map<String, Fingerprint> prints) {
  final parent = <String, String>{};
  String find(String p) {
    var root = p;
    while (parent[root] != root) {
      root = parent[root]!;
    }
    parent[p] = root;
    return root;
  }

  void union(String a, String b) => parent[find(a)] = find(b);

  final videos = [for (final f in files) if (f.isVideo && prints[f.path] != null) f]
    ..sort((a, b) => prints[a.path]!.durationMs.compareTo(prints[b.path]!.durationMs));
  final photos = [for (final f in files) if (!f.isVideo && prints[f.path] != null) f];
  for (final f in [...videos, ...photos]) {
    parent[f.path] = f.path;
  }

  // Vídeo: ordenado por duração, só compara com os vizinhos de duração parecida.
  for (var i = 0; i < videos.length; i++) {
    final a = prints[videos[i].path]!;
    for (var j = i + 1; j < videos.length; j++) {
      final b = prints[videos[j].path]!;
      if (!sameDuration(a.durationMs, b.durationMs)) break;
      if (similarVideos(a, b)) union(videos[i].path, videos[j].path);
    }
  }
  // Foto: um quadro só, compara todas com todas (num isolate, é rápido).
  for (var i = 0; i < photos.length; i++) {
    final a = prints[photos[i].path]!;
    for (var j = i + 1; j < photos.length; j++) {
      if (similarPhotos(a, prints[photos[j].path]!)) union(photos[i].path, photos[j].path);
    }
  }

  final groups = <String, List<MediaFile>>{};
  for (final f in [...videos, ...photos]) {
    groups.putIfAbsent(find(f.path), () => []).add(f);
  }
  return [
    for (final g in groups.values)
      if (g.length > 1 && g.map((f) => f.size).toSet().length > 1) g,
  ];
}

enum SimilarStage { reading, comparing }

/// Acha fotos e vídeos parecidos (não idênticos): o mesmo vídeo recomprimido
/// pelo WhatsApp, a cópia em resolução menor, rajada de fotos...
class SimilarFinder {
  SimilarFinder(this._native, this._cacheFile);

  final NativeBridge _native;
  final JsonFile _cacheFile;

  static const _batch = 16;

  /// Lotes em paralelo (o Kotlin tem 3 threads de trabalho).
  static const _parallel = 3;

  /// caminho -> "tamanho:modificadoMs:duração:h1,h2,h3"
  final _cache = <String, String>{};

  Future<List<DuplicateGroup>> scan(
    List<MediaFile> files, {
    required void Function(SimilarStage stage, int done, int total) onProgress,
    required bool Function() isCancelled,
  }) async {
    final saved = await _cacheFile.read();
    if (saved is Map) _cache.addAll(saved.cast<String, String>());

    final prints = <String, Fingerprint>{};
    final pending = <MediaFile>[];
    for (final f in files) {
      final cached = _cached(f);
      cached == null ? pending.add(f) : prints[f.path] = cached;
    }

    var done = prints.length;
    onProgress(SimilarStage.reading, done, files.length);
    final batches = [
      for (var i = 0; i < pending.length; i += _batch) pending.skip(i).take(_batch).toList(),
    ];
    for (var i = 0; i < batches.length; i += _parallel) {
      if (isCancelled()) return [];
      final round = batches.skip(i).take(_parallel).toList();
      final results = await Future.wait(round.map(_native.fingerprints));
      for (var r = 0; r < round.length; r++) {
        for (var k = 0; k < round[r].length; k++) {
          final fp = results[r][k];
          if (fp == null) continue;
          prints[round[r][k].path] = fp;
          _store(round[r][k], fp);
        }
        done += round[r].length;
      }
      onProgress(SimilarStage.reading, done, files.length);
    }
    await _cacheFile.write(_cache);
    if (isCancelled()) return [];

    onProgress(SimilarStage.comparing, 0, 0);
    final groups = await _groupInIsolate(files, prints);
    return groups.map((g) => DuplicateGroup(g, similar: true)).toList()
      ..sort((a, b) => b.wastedBytes.compareTo(a.wastedBytes));
  }

  static Future<List<List<MediaFile>>> _groupInIsolate(
    List<MediaFile> files,
    Map<String, Fingerprint> prints,
  ) =>
      Isolate.run(() => groupSimilar(files, prints));

  Fingerprint? _cached(MediaFile f) {
    final parts = _cache[f.path]?.split(':');
    if (parts == null || parts.length != 4) return null;
    if (parts[0] != '${f.size}' || parts[1] != '${f.modified.millisecondsSinceEpoch}') return null;
    return Fingerprint(int.parse(parts[2]), [for (final h in parts[3].split(',')) int.parse(h)]);
  }

  void _store(MediaFile f, Fingerprint fp) {
    _cache[f.path] =
        '${f.size}:${f.modified.millisecondsSinceEpoch}:${fp.durationMs}:${fp.hashes.join(',')}';
  }
}

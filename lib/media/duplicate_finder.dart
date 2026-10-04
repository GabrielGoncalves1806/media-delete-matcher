import 'dart:isolate';

import 'file_hash.dart';
import 'json_file.dart';
import 'media_file.dart';

enum ScanStage { partial, full }

typedef ScanProgress = void Function(ScanStage stage, int done, int total);

/// Um conjunto de arquivos idênticos byte a byte.
class DuplicateGroup {
  DuplicateGroup(this.items) : keeperPath = chooseKeeper(items).path;

  final List<MediaFile> items;

  /// Qual cópia fica. O resto pode ir pra lixeira.
  /// Null = nenhuma fica (as duas eram lixo, tipo o mesmo meme em dois grupos).
  String? keeperPath;

  bool get deleteAll => keeperPath == null;

  /// O usuário já olhou esse grupo (escolheu, apagou todas ou aceitou a
  /// sugestão). Só pro progresso da tela; não muda o que sai.
  bool reviewed = false;
  int get bytesEach => items.first.size;

  /// O que vai pra lixeira: todas menos a que fica (ou todas).
  Iterable<MediaFile> get copies => items.where((f) => f.path != keeperPath);

  /// Quanto a duplicação desperdiça (fixo, pra ordenar os grupos).
  int get wastedBytes => bytesEach * (items.length - 1);

  /// Quanto sai de fato com a escolha atual.
  int get bytesToFree => bytesEach * copies.length;
}

/// Prefere a cópia da câmera (DCIM) e, empatando, a mais antiga:
/// normalmente é o original, e as outras são reenvios.
MediaFile chooseKeeper(List<MediaFile> items) {
  int rank(MediaFile f) => f.path.contains('/DCIM/') ? 0 : 1;
  final sorted = [...items]..sort((a, b) {
      final byFolder = rank(a).compareTo(rank(b));
      return byFolder != 0 ? byFolder : a.modified.compareTo(b.modified);
    });
  return sorted.first;
}

/// Agrupa por [key] e devolve só os grupos com 2 ou mais itens.
/// Itens com chave null ficam de fora.
List<List<T>> groupsOf<T>(Iterable<T> items, Object? Function(T) key) {
  final groups = <Object, List<T>>{};
  for (final item in items) {
    final k = key(item);
    if (k != null) groups.putIfAbsent(k, () => []).add(item);
  }
  return groups.values.where((g) => g.length > 1).toList();
}

/// Acha duplicados exatos num funil:
///   1. mesmo tamanho em bytes (grátis, já vem da varredura)
///   2. mesmo hash parcial (primeiros + últimos 64 KB)
///   3. mesmo SHA-1 do arquivo inteiro
/// Os hashes ficam salvos; a próxima varredura só calcula o que mudou.
class DuplicateFinder {
  DuplicateFinder(this._cacheFile);

  final JsonFile _cacheFile;
  static const _batch = 24;

  /// caminho -> "tamanho:modificadoMs:parcial:completo"
  final _cache = <String, String>{};

  Future<List<DuplicateGroup>> scan(
    List<MediaFile> files, {
    required ScanProgress onProgress,
    required bool Function() isCancelled,
  }) async {
    final saved = await _cacheFile.read();
    if (saved is Map) _cache.addAll(saved.cast<String, String>());

    final sameSize = groupsOf(files, (f) => f.size).expand((g) => g).toList();
    final partials = await _hashAll(
      sameSize,
      stage: ScanStage.partial,
      onProgress: onProgress,
      isCancelled: isCancelled,
    );
    if (isCancelled()) return [];

    final samePartial = groupsOf(
      sameSize,
      (f) => partials[f.path] == null ? null : '${f.size}:${partials[f.path]}',
    ).expand((g) => g).toList();
    final fulls = await _hashAll(
      samePartial,
      stage: ScanStage.full,
      onProgress: onProgress,
      isCancelled: isCancelled,
    );
    if (isCancelled()) return [];

    await _cacheFile.write(_cache);

    return groupsOf(samePartial, (f) => fulls[f.path]).map(DuplicateGroup.new).toList()
      ..sort((a, b) => b.wastedBytes.compareTo(a.wastedBytes));
  }

  /// Calcula (ou reaproveita do cache) o hash de cada arquivo, num isolate.
  Future<Map<String, String?>> _hashAll(
    List<MediaFile> files, {
    required ScanStage stage,
    required ScanProgress onProgress,
    required bool Function() isCancelled,
  }) async {
    final full = stage == ScanStage.full;
    final result = <String, String?>{};
    final pending = <MediaFile>[];

    for (final f in files) {
      final cached = _cached(f);
      final hash = cached == null ? null : (full ? cached.$2 : cached.$1);
      hash == null ? pending.add(f) : result[f.path] = hash;
    }
    onProgress(stage, result.length, files.length);

    for (var start = 0; start < pending.length; start += _batch) {
      if (isCancelled()) return result;
      final batch = pending.skip(start).take(_batch).toList();
      final hashes = await _hashInIsolate([for (final f in batch) f.path], full: full);
      for (var i = 0; i < batch.length; i++) {
        result[batch[i].path] = hashes[i];
        if (hashes[i] != null) _store(batch[i], hashes[i]!, full: full);
      }
      onProgress(stage, result.length, files.length);
    }
    return result;
  }

  /// Estático de propósito: a closure não pode capturar o `this`.
  static Future<List<String?>> _hashInIsolate(List<String> paths, {required bool full}) =>
      Isolate.run(() => full ? fullHashes(paths) : partialHashes(paths));

  /// (parcial, completo) se o cache ainda vale pra esse arquivo.
  (String?, String?)? _cached(MediaFile f) {
    final entry = _cache[f.path];
    if (entry == null) return null;
    final parts = entry.split(':');
    if (parts.length != 4) return null;
    if (parts[0] != '${f.size}' || parts[1] != '${f.modified.millisecondsSinceEpoch}') return null;
    String? orNull(String s) => s.isEmpty ? null : s;
    return (orNull(parts[2]), orNull(parts[3]));
  }

  void _store(MediaFile f, String hash, {required bool full}) {
    final old = _cached(f);
    final partial = full ? (old?.$1 ?? '') : hash;
    final complete = full ? hash : (old?.$2 ?? '');
    _cache[f.path] = '${f.size}:${f.modified.millisecondsSinceEpoch}:$partial:$complete';
  }
}

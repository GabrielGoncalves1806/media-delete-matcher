import 'dart:convert';
import 'dart:isolate';

import 'package:photo_manager/photo_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'file_hash.dart';
import 'media_library.dart';

enum ScanStage { sizes, partial, full }

typedef ScanProgress = void Function(ScanStage stage, int done, int total);

/// Um conjunto de arquivos idênticos byte a byte.
class DuplicateGroup {
  DuplicateGroup(this.items, this.bytesEach) : keeperId = chooseKeeper(items).id;

  final List<AssetEntity> items;
  final int bytesEach;

  /// Qual cópia fica. O resto pode ir pra lixeira.
  String keeperId;

  Iterable<AssetEntity> get copies => items.where((a) => a.id != keeperId);
  int get wastedBytes => bytesEach * (items.length - 1);
}

/// Prefere a cópia da câmera (DCIM) e, empatando, a mais antiga:
/// normalmente é o original, e as outras são reenvios.
AssetEntity chooseKeeper(List<AssetEntity> items) {
  int rank(AssetEntity a) => (a.relativePath ?? '').contains('DCIM') ? 0 : 1;
  final sorted = [...items]..sort((a, b) {
      final byFolder = rank(a).compareTo(rank(b));
      if (byFolder != 0) return byFolder;
      return (a.createDateSecond ?? 0).compareTo(b.createDateSecond ?? 0);
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
///   1. mesmo tamanho em bytes (grátis, vem do MediaStore)
///   2. mesmo hash parcial (primeiros + últimos 64 KB)
///   3. mesmo SHA-1 do arquivo inteiro
/// Os hashes ficam salvos; a próxima varredura só calcula o que mudou.
class DuplicateFinder {
  DuplicateFinder(this.library);

  final MediaLibrary library;

  static const _cacheKey = 'hashCache';
  static const _batch = 24;

  /// id -> "tamanho:modificado:parcial:completo"
  final _cache = <String, String>{};
  late SharedPreferences _prefs;

  Future<List<DuplicateGroup>> scan({
    required ScanProgress onProgress,
    required bool Function() isCancelled,
  }) async {
    _prefs = await SharedPreferences.getInstance();
    _cache.addAll(
      (jsonDecode(_prefs.getString(_cacheKey) ?? '{}') as Map).cast<String, String>(),
    );

    // 1. Tamanhos
    final all = (await library.albums()).where((p) => p.isAll).firstOrNull;
    if (all == null) return [];
    final count = await all.assetCountAsync;
    final sizes = <String, int>{};
    final assets = <AssetEntity>[];
    for (var start = 0; start < count; start += 300) {
      if (isCancelled()) return [];
      final page = await all.getAssetListRange(start: start, end: start + 300);
      final pageSizes = await Future.wait(page.map(library.sizeOf));
      for (var i = 0; i < page.length; i++) {
        if (pageSizes[i] == 0) continue; // arquivo quebrado
        assets.add(page[i]);
        sizes[page[i].id] = pageSizes[i];
      }
      onProgress(ScanStage.sizes, assets.length, count);
    }

    // 2. Hash parcial só de quem divide tamanho com alguém
    final sameSize = groupsOf(assets, (a) => sizes[a.id]).expand((g) => g).toList();
    final partials = await _hashAll(
      sameSize,
      stage: ScanStage.partial,
      sizes: sizes,
      onProgress: onProgress,
      isCancelled: isCancelled,
    );
    if (isCancelled()) return [];

    // 3. Hash completo só de quem bateu tamanho + parcial
    final samePartial = groupsOf(
      sameSize,
      (a) => partials[a.id] == null ? null : '${sizes[a.id]}:${partials[a.id]}',
    ).expand((g) => g).toList();
    final fulls = await _hashAll(
      samePartial,
      stage: ScanStage.full,
      sizes: sizes,
      onProgress: onProgress,
      isCancelled: isCancelled,
    );
    if (isCancelled()) return [];

    await _prefs.setString(_cacheKey, jsonEncode(_cache));

    final groups = groupsOf(samePartial, (a) => fulls[a.id])
        .map((g) => DuplicateGroup(g, sizes[g.first.id]!))
        .toList()
      ..sort((a, b) => b.wastedBytes.compareTo(a.wastedBytes));
    return groups;
  }

  /// Calcula (ou reaproveita do cache) o hash de cada item, num isolate.
  Future<Map<String, String?>> _hashAll(
    List<AssetEntity> items, {
    required ScanStage stage,
    required Map<String, int> sizes,
    required ScanProgress onProgress,
    required bool Function() isCancelled,
  }) async {
    final full = stage == ScanStage.full;
    final result = <String, String?>{};
    final pending = <AssetEntity>[];

    for (final a in items) {
      final cached = _cached(a, sizes[a.id]!);
      final hash = cached == null ? null : (full ? cached.$2 : cached.$1);
      hash == null ? pending.add(a) : result[a.id] = hash;
    }
    onProgress(stage, result.length, items.length);

    for (var start = 0; start < pending.length; start += _batch) {
      if (isCancelled()) return result;
      final batch = pending.skip(start).take(_batch).toList();
      final files = await Future.wait(batch.map((a) => a.originFile));
      final paths = [for (final f in files) f?.path ?? ''];
      final hashes = await _hashInIsolate(paths, full: full);
      for (var i = 0; i < batch.length; i++) {
        result[batch[i].id] = hashes[i];
        if (hashes[i] != null) _store(batch[i], sizes[batch[i].id]!, hashes[i]!, full: full);
      }
      onProgress(stage, result.length, items.length);
    }
    return result;
  }

  /// Estático de propósito: a closure não pode capturar o `this`,
  /// senão o isolate tenta copiar o SharedPreferences junto e quebra.
  static Future<List<String?>> _hashInIsolate(List<String> paths, {required bool full}) =>
      Isolate.run(() => full ? fullHashes(paths) : partialHashes(paths));

  /// (parcial, completo) se o cache ainda vale pra esse arquivo.
  (String?, String?)? _cached(AssetEntity a, int size) {
    final parts = _cache[a.id]?.split(':');
    if (parts == null || parts.length != 4) return null;
    if (parts[0] != '$size' || parts[1] != '${a.modifiedDateSecond}') return null;
    String? orNull(String s) => s.isEmpty ? null : s;
    return (orNull(parts[2]), orNull(parts[3]));
  }

  void _store(AssetEntity a, int size, String hash, {required bool full}) {
    final old = _cached(a, size);
    final partial = full ? (old?.$1 ?? '') : hash;
    final complete = full ? hash : (old?.$2 ?? '');
    _cache[a.id] = '$size:${a.modifiedDateSecond}:$partial:$complete';
  }
}

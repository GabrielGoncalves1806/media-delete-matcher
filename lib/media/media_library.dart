import 'dart:io';
import 'dart:isolate';

import 'json_file.dart';
import 'media_file.dart';
import 'media_filter.dart';
import 'native_bridge.dart';
import 'trash_bin.dart';

/// Um "álbum" é uma pasta. [folder] null = tudo.
class Album {
  Album({required this.name, required this.folder, required this.files})
      : bytes = files.fold(0, (sum, f) => sum + f.size);

  final String name;
  final String? folder;

  /// Do maior pro menor.
  final List<MediaFile> files;
  final int bytes;
}

/// Toda a mídia do armazenamento, lida direto do sistema de arquivos.
///
/// Não usa o MediaStore de propósito: ele esconde o que está em pastas com
/// `.nomedia` (como a do WhatsApp quando a "visibilidade de mídia" está
/// desligada), e lá costuma estar a maior parte do espaço.
class MediaLibrary {
  MediaLibrary({
    required this.dataDir,
    NativeBridge? native,
    this.root = '/storage/emulated/0',
  }) : native = native ?? NativeBridge();

  final String root;

  /// Pasta privada do app (caches e decisões).
  final String dataDir;
  final NativeBridge native;

  /// Cache dos hashes da busca de duplicados.
  late final hashCache = JsonFile(File('$dataDir/hashes.json'));

  /// Retrato de cada pasta da última varredura (ver [DirSnapshot]).
  late final _scanCache = JsonFile(File('$dataDir/scan.json'));
  var _snapshots = <String, DirSnapshot>{};

  /// Caminhos que saíram enquanto uma varredura rodava: ela pode ter listado
  /// a pasta antes, e não pode trazer o arquivo de volta.
  final _forgottenDuringScan = <String>{};
  bool _scanning = false;

  late final trash = TrashBin('$root/.media_swipe_trash', onFilesChanged: native.scanFiles);
  late final thumbnails = Thumbnails(native);

  var _files = <MediaFile>[];
  var _byPath = <String, MediaFile>{};

  /// O que não é mídia no armazenamento compartilhado (ver [StorageScan]).
  int otherBytes = 0;

  /// Tudo, do maior pro menor.
  List<MediaFile> get files => _files;

  MediaFile? byPath(String path) => _byPath[path];
  bool contains(String path) => _byPath.containsKey(path);

  /// Mostra o resultado da última varredura sem tocar no armazenamento.
  /// False se não tem cache (primeira abertura).
  Future<bool> loadCached() async {
    final data = await _scanCache.read();
    if (data is! Map<String, dynamic>) return false;
    try {
      _snapshots = {
        for (final MapEntry(:key, :value) in (data['dirs'] as Map<String, dynamic>).entries)
          key: DirSnapshot.fromJson(key, value as Map<String, dynamic>),
      };
    } on Object {
      return false; // formato antigo ou corrompido: faz a varredura completa
    }
    otherBytes = _snapshots.values.fold(0, (sum, s) => sum + s.otherBytes);
    _set(_sorted(_snapshots.values.expand((s) => s.media)));
    return true;
  }

  /// Lê o armazenamento. Por padrão só relista as pastas que mudaram desde a
  /// última vez; [full] ignora o cache.
  /// Devolve quantas pastas foram listadas de verdade.
  Future<int> scan({bool full = false}) async {
    _scanning = true;
    _forgottenDuringScan.clear();
    final result = await _scanInIsolate(root, {trash.directory}, full ? const {} : _snapshots);
    _scanning = false;

    _snapshots = result.snapshots;
    otherBytes = result.otherBytes;
    final gone = Set.of(_forgottenDuringScan);
    _set(_sorted(result.media.where((f) => !gone.contains(f.path))));
    await _scanCache.write({
      'dirs': {for (final e in _snapshots.entries) e.key: e.value.toJson()},
    });
    return result.listedDirs;
  }

  /// Estático pra closure do isolate não capturar o `this`.
  static Future<StorageScan> _scanInIsolate(
    String root,
    Set<String> skip,
    Map<String, DirSnapshot> previous,
  ) =>
      Isolate.run(() => scanStorage(root, skip: skip, previous: previous));

  static List<MediaFile> _sorted(Iterable<MediaFile> files) =>
      files.toList()..sort((a, b) => b.size.compareTo(a.size));

  /// Tira da lista arquivos que saíram (pra lixeira, por exemplo).
  void forget(Iterable<String> paths) {
    final gone = paths.toSet();
    if (_scanning) _forgottenDuringScan.addAll(gone);
    _set(_files.where((f) => !gone.contains(f.path)).toList());
  }

  void _set(List<MediaFile> files) {
    _files = files;
    _byPath = {for (final f in files) f.path: f};
  }

  /// Tudo que bate com o filtro e ainda não foi decidido ([isDecided]).
  Album all(MediaFilter filter, {bool Function(String path)? isDecided}) =>
      Album(name: 'Tudo', folder: null, files: _pending(filter, isDecided).toList());

  /// Pastas com algo ainda pra revisar, da mais pesada pra mais leve.
  /// Pasta onde tudo já foi decidido (apagado ou mantido) não aparece.
  List<Album> albums(MediaFilter filter, {bool Function(String path)? isDecided}) {
    final byFolder = <String, List<MediaFile>>{};
    for (final file in _pending(filter, isDecided)) {
      byFolder.putIfAbsent(file.folder, () => []).add(file);
    }

    // Duas pastas com o mesmo nome ("Sent" do vídeo e "Sent" da imagem)
    // ganham o nome da pasta de cima junto.
    final nameCount = <String, int>{};
    for (final folder in byFolder.keys) {
      final name = _lastSegments(folder, 1);
      nameCount[name] = (nameCount[name] ?? 0) + 1;
    }

    return [
      for (final MapEntry(key: folder, value: files) in byFolder.entries)
        Album(
          name: nameCount[_lastSegments(folder, 1)]! > 1
              ? _lastSegments(folder, 2)
              : _lastSegments(folder, 1),
          folder: folder,
          files: files,
        ),
    ]..sort((a, b) => b.bytes.compareTo(a.bytes));
  }

  Iterable<MediaFile> _pending(MediaFilter filter, bool Function(String path)? isDecided) =>
      _files.where((f) => filter.matches(f) && !(isDecided?.call(f.path) ?? false));

  /// O ano do arquivo mais antigo, pra montar a lista de anos do filtro.
  int get oldestYear => _files.isEmpty
      ? DateTime.now().year
      : _files.map((f) => f.modified.year).reduce((a, b) => a < b ? a : b);

  static String _lastSegments(String path, int n) {
    final parts = path.split('/').where((p) => p.isNotEmpty).toList();
    return parts.sublist(parts.length - n < 0 ? 0 : parts.length - n).join('/');
  }
}

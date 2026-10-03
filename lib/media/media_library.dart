import 'dart:io';
import 'dart:isolate';

import 'compression.dart';
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
    List<String> extraRoots = const [],
  })  : native = native ?? NativeBridge(),
        _extraRoots = extraRoots;

  /// Armazenamento interno.
  final String root;

  /// Cartões SD montados.
  List<String> _extraRoots;
  List<String> get roots => [root, ..._extraRoots];

  /// Volumes como o Android descreve (nome, espaço). Vazio até [setVolumes].
  List<StorageVolume> volumes = const [];

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

  late final MultiTrash trash = MultiTrash(onFilesChanged: native.scanFiles)..useVolumes(roots);
  late final thumbnails = Thumbnails(native);

  var _files = <MediaFile>[];
  var _byPath = <String, MediaFile>{};

  /// Tudo, do maior pro menor.
  List<MediaFile> get files => _files;

  MediaFile? byPath(String path) => _byPath[path];
  bool contains(String path) => _byPath.containsKey(path);

  /// Usa os volumes montados agora (interno + cartões). Chamar antes de
  /// [loadCached]/[scan] pra cartão removido não aparecer com dado velho.
  Future<void> setVolumes(List<StorageVolume> mounted) async {
    volumes = mounted;
    _extraRoots = [for (final v in mounted) if (!v.primary && v.path != root) v.path];
    trash.useVolumes(roots);
    await trash.load();
  }

  /// Raiz do volume onde o arquivo está.
  String? volumeOf(String path) {
    for (final r in roots) {
      if (path.startsWith('$r/')) return r;
    }
    return null;
  }

  /// Está num cartão SD (e não no armazenamento interno).
  bool isRemovable(String path) => volumeOf(path) != root && volumeOf(path) != null;

  List<MediaFile> filesIn(String volume) =>
      _files.where((f) => f.path.startsWith('$volume/')).toList();

  /// O que não é mídia no volume (documentos, áudio, pastas escondidas...).
  int otherBytesIn(String volume) => _snapshots.entries
      .where((e) => e.key == volume || e.key.startsWith('$volume/'))
      .fold(0, (sum, e) => sum + e.value.otherBytes);

  /// Mostra o resultado da última varredura sem tocar no armazenamento.
  /// False se não tem cache (primeira abertura).
  Future<bool> loadCached() async {
    final data = await _scanCache.read();
    if (data is! Map<String, dynamic>) return false;
    try {
      _snapshots = {
        for (final MapEntry(:key, :value) in (data['dirs'] as Map<String, dynamic>).entries)
          // Pasta de cartão que não tá montado agora fica de fora.
          if (volumeOf(key) != null || roots.contains(key))
            key: DirSnapshot.fromJson(key, value as Map<String, dynamic>),
      };
    } on Object {
      return false; // formato antigo ou corrompido: faz a varredura completa
    }
    _set(_sorted(_snapshots.values.expand((s) => s.media)));
    return true;
  }

  /// Lê o armazenamento. Por padrão só relista as pastas que mudaram desde a
  /// última vez; [full] ignora o cache.
  /// Devolve quantas pastas foram listadas de verdade.
  Future<int> scan({bool full = false}) async {
    _scanning = true;
    _forgottenDuringScan.clear();
    final result = await _scanInIsolate(roots, trash.directories, full ? const {} : _snapshots);
    _scanning = false;

    _snapshots = result.snapshots;
    final gone = Set.of(_forgottenDuringScan);
    _set(_sorted(result.media.where((f) => !gone.contains(f.path))));
    await _scanCache.write({
      'dirs': {for (final e in _snapshots.entries) e.key: e.value.toJson()},
    });
    return result.listedDirs;
  }

  /// Varre todos os volumes num isolate só.
  /// Estático pra closure do isolate não capturar o `this`.
  static Future<StorageScan> _scanInIsolate(
    List<String> roots,
    Set<String> skip,
    Map<String, DirSnapshot> previous,
  ) =>
      Isolate.run(() {
        final scans = [for (final r in roots) scanStorage(r, skip: skip, previous: previous)];
        return StorageScan(
          media: [for (final s in scans) ...s.media],
          otherBytes: scans.fold(0, (sum, s) => sum + s.otherBytes),
          snapshots: {for (final s in scans) ...s.snapshots},
          listedDirs: scans.fold(0, (sum, s) => sum + s.listedDirs),
        );
      });

  static List<MediaFile> _sorted(Iterable<MediaFile> files) =>
      files.toList()..sort((a, b) => b.size.compareTo(a.size));

  final _plans = <String, Future<CompressionPlan?>>{};

  /// Se vale comprimir esse vídeo e como (null = já leve ou não é vídeo).
  /// Lê os metadados uma vez por arquivo.
  Future<CompressionPlan?> compressionPlan(MediaFile file) {
    if (!file.isVideo) return Future.value();
    return _plans.putIfAbsent(file.path, () async {
      final info = await native.videoInfo(file.path);
      return info == null ? null : planCompression(info, fileSize: file.size);
    });
  }

  /// Troca um arquivo pela versão nova (depois de comprimir).
  void replace(String oldPath, MediaFile newFile) {
    _plans.remove(oldPath);
    final gone = {oldPath, newFile.path};
    if (_scanning) _forgottenDuringScan.add(oldPath);
    _set(_sorted([..._files.where((f) => !gone.contains(f.path)), newFile]));
  }

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

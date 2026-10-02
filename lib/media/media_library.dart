import 'dart:isolate';

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
  MediaLibrary({NativeBridge? native, this.root = '/storage/emulated/0'})
      : native = native ?? NativeBridge();

  final String root;
  final NativeBridge native;

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

  Future<void> scan() async {
    final result = await _scanInIsolate(root, {trash.directory});
    otherBytes = result.otherBytes;
    _set(result.media..sort((a, b) => b.size.compareTo(a.size)));
  }

  /// Estático pra closure do isolate não capturar o `this`.
  static Future<StorageScan> _scanInIsolate(String root, Set<String> skip) =>
      Isolate.run(() => scanStorage(root, skip: skip));

  /// Tira da lista arquivos que saíram (pra lixeira, por exemplo).
  void forget(Iterable<String> paths) {
    final gone = paths.toSet();
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

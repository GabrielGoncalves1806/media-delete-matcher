import 'dart:io';
import 'dart:isolate';

import 'file_hash.dart';
import 'media_file.dart';
import 'media_library.dart';

class MoveResult {
  const MoveResult.ok(MediaFile this.newFile) : error = null;
  const MoveResult.failed(String this.error) : newFile = null;

  final MediaFile? newFile;
  final String? error;
  bool get ok => newFile != null;
}

/// Move um arquivo pra outro volume (do celular pro cartão SD).
///
/// Entre volumes não existe rename, então é cópia + apagar. Pra nunca perder
/// nada no meio do caminho:
///   1. confere se cabe no destino
///   2. copia pra um temporário escondido na pasta de destino
///   3. compara o SHA-1 do original com o da cópia
///   4. só então dá o nome final, mantém a data e apaga o original
class MediaMover {
  MediaMover(this.library);

  final MediaLibrary library;

  /// Folga pra não encher o cartão até o último byte.
  static const _margin = 10 * 1000 * 1000;

  Future<MoveResult> move(
    MediaFile file,
    String targetDir, {
    void Function(double progress)? onProgress,
  }) async {
    final volumes = await library.native.storageVolumes();
    final target = volumes.where((v) => targetDir == v.path || targetDir.startsWith('${v.path}/')).firstOrNull;
    if (target != null && target.free < file.size + _margin) {
      return const MoveResult.failed('Não cabe no cartão');
    }

    final temp = File('$targetDir/.${file.name}.moving');
    try {
      await _copy(File(file.path), temp, file.size, onProgress);
    } on FileSystemException catch (e) {
      await _deleteIfExists(temp);
      return MoveResult.failed('Não consegui copiar: ${e.osError?.message ?? e.message}');
    }

    final hashes = await _hashInIsolate([file.path, temp.path]);
    if (hashes[0] == null || hashes[0] != hashes[1]) {
      await _deleteIfExists(temp);
      return const MoveResult.failed('A cópia não bateu com o original; nada foi apagado');
    }

    final dest = _uniquePath(targetDir, file.name);
    await temp.rename(dest);
    await File(dest).setLastModified(file.modified);
    await File(file.path).delete();
    await library.native.scanFiles([file.path, dest]);

    final moved = MediaFile(path: dest, size: file.size, modified: file.modified, isVideo: file.isVideo);
    library.replace(file.path, moved);
    return MoveResult.ok(moved);
  }

  /// Com RandomAccessFile (e não openWrite): erro de abrir/escrever, como
  /// pasta que sumiu ou cartão removido, cai no try de quem chamou em vez de
  /// escapar assíncrono e derrubar o app.
  static Future<void> _copy(File from, File to, int size, void Function(double)? onProgress) async {
    final out = await to.open(mode: FileMode.write);
    var done = 0;
    try {
      await for (final chunk in from.openRead()) {
        await out.writeFrom(chunk);
        done += chunk.length;
        onProgress?.call(size == 0 ? 1 : done / size);
      }
      await out.flush();
    } finally {
      await out.close();
    }
  }

  /// "IMG.jpg" -> "IMG (2).jpg" se já existir um com o mesmo nome.
  static String _uniquePath(String dir, String name) {
    final dot = name.lastIndexOf('.');
    final base = dot > 0 ? name.substring(0, dot) : name;
    final ext = dot > 0 ? name.substring(dot) : '';
    var candidate = '$dir/$name';
    for (var i = 2; File(candidate).existsSync(); i++) {
      candidate = '$dir/$base ($i)$ext';
    }
    return candidate;
  }

  static Future<List<String?>> _hashInIsolate(List<String> paths) =>
      Isolate.run(() => fullHashes(paths));

  static Future<void> _deleteIfExists(File file) async {
    if (await file.exists()) await file.delete();
  }
}

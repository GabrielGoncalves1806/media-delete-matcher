import 'dart:io';

import 'package:flutter/services.dart';

import 'compression.dart';
import 'media_file.dart';
import 'media_library.dart';

enum CompressOutcome {
  /// Ficou menor: original na lixeira, versão leve no lugar.
  compressed,

  /// O resultado não ficou nem 15% menor: original intacto.
  alreadyLight,
  failed,
  cancelled,
}

class CompressResult {
  const CompressResult(this.outcome, {this.newFile, this.savedBytes = 0, this.error});

  final CompressOutcome outcome;
  final MediaFile? newFile;
  final int savedBytes;
  final String? error;
}

/// Comprime um vídeo sem nunca perder o original:
///   1. recodifica pra um arquivo temporário escondido do lado do original
///   2. se não ficou bem menor, descarta o temporário e pronto
///   3. se ficou, o original vai pra lixeira do app (restaurável por 30 dias)
///      e a versão leve assume o lugar, com a mesma data de modificação
class VideoCompressor {
  VideoCompressor(this.library);

  final MediaLibrary library;

  /// Abaixo disso de economia não vale trocar o arquivo.
  static const _minSaving = 0.15;

  Future<CompressResult> compress(
    MediaFile file,
    CompressionPlan plan, {
    void Function(double progress)? onProgress,
  }) async {
    final temp = File('${file.folder}/.${file.name}.compressing.mp4');
    try {
      await library.native.compressVideo(
        input: file.path,
        output: temp.path,
        plan: plan,
        onProgress: onProgress,
      );
    } on PlatformException catch (e) {
      await _deleteIfExists(temp);
      return e.code == 'cancelled'
          ? const CompressResult(CompressOutcome.cancelled)
          : CompressResult(CompressOutcome.failed, error: e.message);
    }

    final newSize = await temp.length();
    if (newSize > file.size * (1 - _minSaving)) {
      await temp.delete();
      return const CompressResult(CompressOutcome.alreadyLight);
    }

    final moved = await library.trash.moveIn([file]);
    if (moved.isEmpty) {
      await temp.delete();
      return const CompressResult(CompressOutcome.failed, error: 'Não consegui tirar o original do lugar');
    }

    final target = _targetPath(file);
    await temp.rename(target);
    await File(target).setLastModified(file.modified);
    await library.native.scanFiles([target]);

    final newFile = MediaFile(path: target, size: newSize, modified: file.modified, isVideo: true);
    library.replace(file.path, newFile);
    return CompressResult(CompressOutcome.compressed, newFile: newFile, savedBytes: file.size - newSize);
  }

  Future<void> cancel() => library.native.cancelCompression();

  /// O resultado é sempre MP4: um .mkv/.3gp vira .mp4 (sem pisar em outro arquivo).
  static String _targetPath(MediaFile file) {
    if (file.path.toLowerCase().endsWith('.mp4')) return file.path;
    final base = file.path.substring(0, file.path.lastIndexOf('.'));
    var candidate = '$base.mp4';
    for (var i = 2; File(candidate).existsSync(); i++) {
      candidate = '$base ($i).mp4';
    }
    return candidate;
  }

  static Future<void> _deleteIfExists(File file) async {
    if (await file.exists()) await file.delete();
  }
}

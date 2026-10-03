import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_swipe/media/compression.dart';
import 'package:media_swipe/media/media_file.dart';
import 'package:media_swipe/media/media_library.dart';
import 'package:media_swipe/media/native_bridge.dart';
import 'package:media_swipe/media/video_compressor.dart';

/// "Comprime" escrevendo [outputSize] bytes, ou falha com [errorCode].
class FakeNative extends NativeBridge {
  FakeNative({this.outputSize = 10, this.errorCode});

  final int outputSize;
  final String? errorCode;
  final scanned = <String>[];

  @override
  Future<void> compressVideo({
    required String input,
    required String output,
    required CompressionPlan plan,
    void Function(double progress)? onProgress,
  }) async {
    onProgress?.call(0.5);
    if (errorCode != null) {
      File(output).writeAsBytesSync([1, 2, 3]); // lixo pela metade
      throw PlatformException(code: errorCode!, message: 'falhou');
    }
    File(output).writeAsBytesSync(List.filled(outputSize, 9));
  }

  @override
  Future<void> scanFiles(List<String> paths) async => scanned.addAll(paths);
}

const _plan = CompressionPlan(shortSide: 720, bitrate: 2500000, estimatedBytes: 10);

void main() {
  group('planCompression', () {
    test('vídeo 1080p de câmera compensa e vai pra 720p', () {
      // 60 s a ~17 Mbps ≈ 128 MB
      const info = VideoInfo(width: 1080, height: 1920, bitrate: 17000000, durationMs: 60000);
      final plan = planCompression(info, fileSize: 128000000)!;

      expect(plan.shortSide, 720);
      expect(plan.bitrate, maxVideoBitrate);
      expect(plan.estimatedBytes, closeTo((2500000 + 128000) * 60 / 8, 1));
    });

    test('vídeo já leve (tipo os que o WhatsApp recomprime) não compensa', () {
      const info = VideoInfo(width: 480, height: 848, bitrate: 1200000, durationMs: 60000);
      expect(planCompression(info, fileSize: 9000000), isNull);
    });

    test('não reduz resolução de vídeo menor que 720p, só o bitrate', () {
      const info = VideoInfo(width: 640, height: 480, bitrate: 8000000, durationMs: 10000);
      expect(planCompression(info, fileSize: 10000000)!.shortSide, 480);
    });

    test('sem bitrate nos metadados, estima pelo tamanho e duração', () {
      const info = VideoInfo(width: 1920, height: 1080, bitrate: 0, durationMs: 10000);
      expect(planCompression(info, fileSize: 20000000), isNotNull); // ~16 Mbps
    });

    test('sem duração não dá pra planejar', () {
      const info = VideoInfo(width: 1920, height: 1080, bitrate: 9000000, durationMs: 0);
      expect(planCompression(info, fileSize: 20000000), isNull);
    });
  });

  group('VideoCompressor', () {
    late Directory root;

    setUp(() => root = Directory.systemTemp.createTempSync('media_swipe_compress'));
    tearDown(() => root.deleteSync(recursive: true));

    Future<(MediaLibrary, MediaFile)> setup(FakeNative native, {String name = 'v.mp4'}) async {
      final file = File('${root.path}/DCIM/Camera/$name')
        ..createSync(recursive: true)
        ..writeAsBytesSync(List.filled(100, 7))
        ..setLastModifiedSync(DateTime(2024, 5, 12));
      final library = MediaLibrary(root: root.path, dataDir: '${root.path}/.app', native: native);
      await library.scan();
      return (library, library.byPath(file.path)!);
    }

    test('ficou menor: original na lixeira, leve no lugar com a mesma data', () async {
      final native = FakeNative(outputSize: 30);
      final (library, file) = await setup(native);
      final progress = <double>[];

      final result = await VideoCompressor(library).compress(file, _plan, onProgress: progress.add);

      expect(result.outcome, CompressOutcome.compressed);
      expect(result.savedBytes, 70);
      expect(progress, [0.5]);
      expect(File(file.path).lengthSync(), 30);
      expect(File(file.path).lastModifiedSync(), DateTime(2024, 5, 12));
      expect(library.trash.entries.single.originalPath, file.path);
      expect(library.byPath(file.path)!.size, 30);
      expect(native.scanned, contains(file.path));
      // nenhum temporário sobrando
      expect(Directory(file.folder).listSync().map((e) => e.path.split('/').last), ['v.mp4']);
    });

    test('não ficou 15% menor: original intacto e nada na lixeira', () async {
      final (library, file) = await setup(FakeNative(outputSize: 90));

      final result = await VideoCompressor(library).compress(file, _plan);

      expect(result.outcome, CompressOutcome.alreadyLight);
      expect(File(file.path).lengthSync(), 100);
      expect(library.trash.entries, isEmpty);
      expect(Directory(file.folder).listSync(), hasLength(1));
    });

    test('erro ou cancelamento: apaga o temporário e não mexe no original', () async {
      for (final (code, outcome) in [
        ('compress', CompressOutcome.failed),
        ('cancelled', CompressOutcome.cancelled),
      ]) {
        final (library, file) = await setup(FakeNative(errorCode: code), name: '$code.mp4');

        final result = await VideoCompressor(library).compress(file, _plan);

        expect(result.outcome, outcome);
        expect(File(file.path).lengthSync(), 100);
        expect(File('${file.folder}/.${file.name}.compressing.mp4').existsSync(), isFalse);
      }
    });

    test('.mkv vira .mp4 sem pisar em arquivo com o mesmo nome', () async {
      final (library, file) = await setup(FakeNative(outputSize: 20), name: 'clip.mkv');
      File('${file.folder}/clip.mp4').writeAsBytesSync([1]); // já existe um clip.mp4

      final result = await VideoCompressor(library).compress(file, _plan);

      expect(result.newFile!.path, '${file.folder}/clip (2).mp4');
      expect(File('${file.folder}/clip.mp4').lengthSync(), 1); // intocado
      expect(library.contains(file.path), isFalse);
    });
  });
}

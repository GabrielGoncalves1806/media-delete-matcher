import 'package:flutter/services.dart';

import 'compression.dart';

typedef StorageStats = ({int total, int free, int system});

/// Ponte pro MainActivity.kt.
class NativeBridge {
  static const _channel = MethodChannel('media_swipe/native');
  void Function(double progress)? _onCompressProgress;

  Future<bool> hasAllFilesAccess() async =>
      await _channel.invokeMethod<bool>('hasAllFilesAccess') ?? false;

  /// Abre a tela do sistema. O resultado chega quando o app volta pro primeiro plano.
  Future<void> requestAllFilesAccess() => _channel.invokeMethod('requestAllFilesAccess');

  /// [total] é a capacidade de fábrica; [system] o que o Android reserva pra si.
  Future<StorageStats> storageStats() async {
    final stats = await _channel.invokeMapMethod<String, int>('storageStats');
    return (total: stats!['total']!, free: stats['free']!, system: stats['system']!);
  }

  /// JPEG pequeno, gerado pelo Android. Null se o arquivo não abrir.
  Future<Uint8List?> thumbnail(String path, {required bool video, int size = 400}) =>
      _channel.invokeMethod<Uint8List>('thumbnail', {
        'path': path,
        'video': video,
        'size': size,
      });

  /// Null se o arquivo não abrir como vídeo.
  Future<VideoInfo?> videoInfo(String path) async {
    final map = await _channel.invokeMapMethod<String, int>('videoInfo', {'path': path});
    return map == null ? null : VideoInfo.fromMap(map);
  }

  /// Recodifica [input] em [output] (MP4, H.264). Uma por vez.
  /// Lança PlatformException com code 'cancelled' se [cancelCompression] for chamado.
  Future<void> compressVideo({
    required String input,
    required String output,
    required CompressionPlan plan,
    void Function(double progress)? onProgress,
  }) async {
    _onCompressProgress = onProgress;
    // Registrado aqui (e não no construtor) pra não exigir o binding do
    // Flutter só de criar a ponte, o que quebraria os testes.
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'compressProgress') _onCompressProgress?.call((call.arguments as int) / 100);
    });
    try {
      await _channel.invokeMethod('compressVideo', {
        'input': input,
        'output': output,
        'shortSide': plan.shortSide,
        'bitrate': plan.bitrate,
      });
    } finally {
      _onCompressProgress = null;
    }
  }

  Future<void> cancelCompression() => _channel.invokeMethod('cancelCompress');

  /// Avisa o MediaStore que esses caminhos mudaram (sumiram ou voltaram),
  /// pra galeria não ficar mostrando fantasma.
  Future<void> scanFiles(List<String> paths) =>
      _channel.invokeMethod('scanFiles', {'paths': paths});
}

/// Cache em memória das miniaturas, com limite (descarta as mais antigas).
class Thumbnails {
  Thumbnails(this._native);

  final NativeBridge _native;
  final _cache = <String, Future<Uint8List?>>{};
  static const _max = 300;

  Future<Uint8List?> of(String path, {required bool video}) {
    final hit = _cache.remove(path);
    if (hit != null) return _cache[path] = hit; // volta pro fim da fila
    final future = _native.thumbnail(path, video: video);
    _cache[path] = future;
    if (_cache.length > _max) _cache.remove(_cache.keys.first);
    return future;
  }
}

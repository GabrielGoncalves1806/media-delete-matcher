import 'package:flutter/services.dart';

/// Ponte pro MainActivity.kt.
class NativeBridge {
  static const _channel = MethodChannel('media_swipe/native');

  Future<bool> hasAllFilesAccess() async =>
      await _channel.invokeMethod<bool>('hasAllFilesAccess') ?? false;

  /// Abre a tela do sistema. O resultado chega quando o app volta pro primeiro plano.
  Future<void> requestAllFilesAccess() => _channel.invokeMethod('requestAllFilesAccess');

  Future<({int total, int free})> storageStats() async {
    final stats = await _channel.invokeMapMethod<String, int>('storageStats');
    return (total: stats!['total']!, free: stats['free']!);
  }

  /// JPEG pequeno, gerado pelo Android. Null se o arquivo não abrir.
  Future<Uint8List?> thumbnail(String path, {required bool video, int size = 400}) =>
      _channel.invokeMethod<Uint8List>('thumbnail', {
        'path': path,
        'video': video,
        'size': size,
      });

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

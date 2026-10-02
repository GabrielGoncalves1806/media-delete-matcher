import 'dart:io';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';

/// Funções puras de hash, pensadas pra rodar dentro de `Isolate.run`.
/// Devolvem null se o arquivo não puder ser lido.

const _edge = 64 * 1024;
const _chunk = 1024 * 1024;

/// SHA-1 dos primeiros e dos últimos 64 KB. Barato e já separa quase
/// tudo que só coincidiu no tamanho.
String? partialHash(String path) {
  RandomAccessFile? file;
  try {
    file = File(path).openSync();
    final length = file.lengthSync();
    final head = file.readSync(math.min(_edge, length));
    file.setPositionSync(math.max(0, length - _edge));
    final tail = file.readSync(math.min(_edge, length));
    return sha1.convert([...head, ...tail]).toString();
  } on FileSystemException {
    return null;
  } finally {
    file?.closeSync();
  }
}

/// SHA-1 do arquivo inteiro, lido em pedaços de 1 MB.
String? fullHash(String path) {
  RandomAccessFile? file;
  try {
    file = File(path).openSync();
    final sink = _DigestSink();
    final input = sha1.startChunkedConversion(sink);
    while (true) {
      final bytes = file.readSync(_chunk);
      if (bytes.isEmpty) break;
      input.add(bytes);
    }
    input.close();
    return sink.value.toString();
  } on FileSystemException {
    return null;
  } finally {
    file?.closeSync();
  }
}

List<String?> partialHashes(List<String> paths) => paths.map(partialHash).toList();
List<String?> fullHashes(List<String> paths) => paths.map(fullHash).toList();

class _DigestSink implements Sink<Digest> {
  late Digest value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}

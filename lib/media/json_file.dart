import 'dart:convert';
import 'dart:io';

/// Arquivo JSON com gravação atômica: escreve num `.tmp` e renomeia por cima,
/// então um crash no meio nunca deixa o arquivo pela metade.
class JsonFile {
  JsonFile(this.file);

  final File file;

  /// Null se não existe ou está corrompido.
  Future<Object?> read() async {
    if (!await file.exists()) return null;
    try {
      return jsonDecode(await file.readAsString());
    } on FormatException {
      return null;
    }
  }

  Future<void> write(Object? data) async {
    await file.parent.create(recursive: true);
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(jsonEncode(data), flush: true);
    await tmp.rename(file.path);
  }
}

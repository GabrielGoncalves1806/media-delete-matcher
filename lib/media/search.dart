import 'media_file.dart';
import 'media_filter.dart';

enum SearchSort { largest, newest, oldest }

const _accents = {
  'á': 'a', 'à': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a',
  'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
  'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i',
  'ó': 'o', 'ò': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o',
  'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u',
  'ç': 'c', 'ñ': 'n',
};

/// Minúsculo e sem acento: "Câmera" e "camera" batem.
String normalize(String text) {
  final lower = text.toLowerCase();
  if (!lower.codeUnits.any((c) => c > 127)) return lower; // sem acento: caminho rápido
  final out = StringBuffer();
  for (final rune in lower.runes) {
    final char = String.fromCharCode(rune);
    out.write(_accents[char] ?? char);
  }
  return out.toString();
}

/// Índice de busca: o texto normalizado de cada arquivo é calculado uma vez,
/// não a cada tecla. Normalizar ~11 mil caminhos por busca deixava a
/// digitação lenta.
class SearchIndex {
  SearchIndex(this.files, {List<String> roots = const []})
      : _texts = [for (final f in files) normalize(_relative(f.path, roots))];

  final List<MediaFile> files;
  final List<String> _texts;

  /// Caminho sem a raiz do volume ("storage", "emulated" e o id do cartão
  /// estão em tudo e não devem bater na busca).
  static String _relative(String path, List<String> roots) {
    for (final root in roots) {
      if (path.startsWith('$root/')) return path.substring(root.length + 1);
    }
    return path;
  }

  /// Cada palavra de [query] tem que aparecer em algum lugar do caminho.
  List<MediaFile> search({
    String query = '',
    MediaFilter filter = MediaFilter.none,
    String? volume,
    SearchSort sort = SearchSort.largest,
  }) {
    final words = normalize(query).split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    final result = <MediaFile>[];
    for (var i = 0; i < files.length; i++) {
      final f = files[i];
      if (volume != null && !f.path.startsWith('$volume/')) continue;
      if (!filter.matches(f)) continue;
      if (words.isNotEmpty && !words.every(_texts[i].contains)) continue;
      result.add(f);
    }
    switch (sort) {
      case SearchSort.largest:
        result.sort((a, b) => b.size.compareTo(a.size));
      case SearchSort.newest:
        result.sort((a, b) => b.modified.compareTo(a.modified));
      case SearchSort.oldest:
        result.sort((a, b) => a.modified.compareTo(b.modified));
    }
    return result;
  }
}

/// Atalho pra uma busca só (monta o índice e busca).
List<MediaFile> searchFiles(
  List<MediaFile> files, {
  String query = '',
  MediaFilter filter = MediaFilter.none,
  String? volume,
  SearchSort sort = SearchSort.largest,
  List<String> roots = const [],
}) =>
    SearchIndex(files, roots: roots).search(query: query, filter: filter, volume: volume, sort: sort);

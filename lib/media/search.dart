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
  final out = StringBuffer();
  for (final rune in lower.runes) {
    final char = String.fromCharCode(rune);
    out.write(_accents[char] ?? char);
  }
  return out.toString();
}

/// Busca por nome ou pasta. Cada palavra de [query] tem que aparecer em algum
/// lugar do caminho (depois de [root], pra raiz do volume não entrar na conta).
List<MediaFile> searchFiles(
  List<MediaFile> files, {
  String query = '',
  MediaFilter filter = MediaFilter.none,
  String? volume,
  SearchSort sort = SearchSort.largest,
  List<String> roots = const [],
}) {
  final words = normalize(query).split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();

  String searchable(MediaFile f) {
    var path = f.path;
    for (final root in roots) {
      if (path.startsWith('$root/')) {
        path = path.substring(root.length + 1);
        break;
      }
    }
    return normalize(path);
  }

  final result = files.where((f) {
    if (volume != null && !f.path.startsWith('$volume/')) return false;
    if (!filter.matches(f)) return false;
    if (words.isEmpty) return true;
    final text = searchable(f);
    return words.every(text.contains);
  }).toList();

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

import 'dart:io';

const _imageExtensions = {'jpg', 'jpeg', 'png', 'heic', 'heif', 'webp', 'gif', 'bmp'};
const _videoExtensions = {'mp4', 'mkv', 'mov', '3gp', 'webm', 'avi', 'm4v'};

/// Uma foto ou vídeo no armazenamento. Identificado pelo caminho.
class MediaFile {
  const MediaFile({
    required this.path,
    required this.size,
    required this.modified,
    required this.isVideo,
  });

  final String path;
  final int size;
  final DateTime modified;
  final bool isVideo;

  String get name => path.substring(path.lastIndexOf('/') + 1);
  String get folder => path.substring(0, path.lastIndexOf('/'));
  String get folderName => folder.substring(folder.lastIndexOf('/') + 1);

  @override
  bool operator ==(Object other) => other is MediaFile && other.path == path;

  @override
  int get hashCode => path.hashCode;
}

/// true = vídeo, false = foto, null = não é mídia.
bool? isVideoFile(String name) {
  final dot = name.lastIndexOf('.');
  if (dot < 0) return null;
  final ext = name.substring(dot + 1).toLowerCase();
  if (_videoExtensions.contains(ext)) return true;
  if (_imageExtensions.contains(ext)) return false;
  return null;
}

/// Varre [root] atrás de fotos e vídeos, ignorando `.nomedia` de propósito.
///
/// Pula tudo que começa com ponto (`.thumbnails`, `.trashed-*` da lixeira do
/// Android, `.Statuses`...), `Android/data` e `Android/obb` (o sistema bloqueia)
/// e as pastas em [skip]. Síncrono: é pra rodar dentro de `Isolate.run`.
List<MediaFile> scanStorage(String root, {Set<String> skip = const {}}) {
  final blocked = {'$root/Android/data', '$root/Android/obb', ...skip};
  final result = <MediaFile>[];
  final pending = [Directory(root)];

  while (pending.isNotEmpty) {
    final dir = pending.removeLast();
    final List<FileSystemEntity> entries;
    try {
      entries = dir.listSync(followLinks: false);
    } on FileSystemException {
      continue; // pasta sem permissão de leitura
    }
    for (final entry in entries) {
      final name = entry.path.substring(entry.path.lastIndexOf('/') + 1);
      if (name.startsWith('.')) continue;
      if (entry is Directory) {
        if (!blocked.contains(entry.path)) pending.add(entry);
        continue;
      }
      if (entry is! File) continue;
      final video = isVideoFile(name);
      if (video == null) continue;
      try {
        final stat = entry.statSync();
        if (stat.size == 0) continue; // download quebrado
        result.add(MediaFile(
          path: entry.path,
          size: stat.size,
          modified: stat.modified,
          isVideo: video,
        ));
      } on FileSystemException {
        continue;
      }
    }
  }
  return result;
}

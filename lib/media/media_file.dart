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

/// Resultado da varredura: a mídia e quanto o resto dos arquivos ocupa.
class StorageScan {
  const StorageScan(this.media, this.otherBytes);

  final List<MediaFile> media;

  /// Tudo que não é mídia visível: documentos, áudio, bancos do WhatsApp,
  /// pastas escondidas (`.thumbnails`, `.Statuses`...). Pro painel de espaço.
  final int otherBytes;
}

/// Varre [root] atrás de fotos e vídeos, ignorando `.nomedia` de propósito.
///
/// Mídia dentro de algo que começa com ponto (`.thumbnails`, `.trashed-*` da
/// lixeira do Android, `.Statuses`...) não entra na lista, mas o tamanho conta
/// em [StorageScan.otherBytes]. `Android/data` e `Android/obb` o sistema
/// bloqueia; as pastas em [skip] são puladas inteiras.
/// Síncrono: é pra rodar dentro de `Isolate.run`.
StorageScan scanStorage(String root, {Set<String> skip = const {}}) {
  final blocked = {'$root/Android/data', '$root/Android/obb', ...skip};
  final media = <MediaFile>[];
  var otherBytes = 0;
  final pending = [(dir: Directory(root), hidden: false)];

  while (pending.isNotEmpty) {
    final (:dir, :hidden) = pending.removeLast();
    final List<FileSystemEntity> entries;
    try {
      entries = dir.listSync(followLinks: false);
    } on FileSystemException {
      continue; // pasta sem permissão de leitura
    }
    for (final entry in entries) {
      final name = entry.path.substring(entry.path.lastIndexOf('/') + 1);
      final isHidden = hidden || name.startsWith('.');
      if (entry is Directory) {
        if (!blocked.contains(entry.path)) pending.add((dir: entry, hidden: isHidden));
        continue;
      }
      if (entry is! File) continue;
      final FileStat stat;
      try {
        stat = entry.statSync();
      } on FileSystemException {
        continue;
      }
      final video = isHidden ? null : isVideoFile(name);
      if (video == null || stat.size == 0) {
        otherBytes += stat.size;
        continue;
      }
      media.add(MediaFile(
        path: entry.path,
        size: stat.size,
        modified: stat.modified,
        isVideo: video,
      ));
    }
  }
  return StorageScan(media, otherBytes);
}

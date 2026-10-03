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

/// O que a varredura lembra de uma pasta. Se a data de modificação da pasta
/// não mudou (nada foi criado, apagado ou renomeado dentro dela), a próxima
/// varredura reaproveita isso sem listar a pasta nem consultar cada arquivo.
class DirSnapshot {
  const DirSnapshot({
    required this.modified,
    required this.media,
    required this.otherBytes,
    required this.subdirs,
  });

  factory DirSnapshot.fromJson(String dir, Map<String, dynamic> json) => DirSnapshot(
        modified: json['m'] as int,
        otherBytes: json['o'] as int,
        subdirs: [for (final name in json['d'] as List) '$dir/$name'],
        media: [
          for (final f in json['f'] as List)
            MediaFile(
              path: '$dir/${f[0]}',
              size: f[1] as int,
              modified: DateTime.fromMillisecondsSinceEpoch(f[2] as int),
              isVideo: f[3] as bool,
            ),
        ],
      );

  /// Data de modificação da pasta, em ms.
  final int modified;

  /// Mídia que está direto nesta pasta (não nas subpastas).
  final List<MediaFile> media;
  final int otherBytes;
  final List<String> subdirs;

  /// Compacto: só nomes, já que o caminho da pasta é a chave.
  Map<String, dynamic> toJson() => {
        'm': modified,
        'o': otherBytes,
        'd': [for (final d in subdirs) d.substring(d.lastIndexOf('/') + 1)],
        'f': [
          for (final f in media) [f.name, f.size, f.modified.millisecondsSinceEpoch, f.isVideo],
        ],
      };
}

/// Resultado da varredura: a mídia e quanto o resto dos arquivos ocupa.
class StorageScan {
  const StorageScan({
    required this.media,
    required this.otherBytes,
    required this.snapshots,
    required this.listedDirs,
  });

  final List<MediaFile> media;

  /// Tudo que não é mídia visível: documentos, áudio, bancos do WhatsApp,
  /// pastas escondidas (`.thumbnails`, `.Statuses`...). Pro painel de espaço.
  final int otherBytes;

  /// Pra passar como `previous` na próxima varredura.
  final Map<String, DirSnapshot> snapshots;

  /// Quantas pastas precisaram ser listadas de verdade (o resto veio do cache).
  final int listedDirs;
}

/// Varre [root] atrás de fotos e vídeos, ignorando `.nomedia` de propósito.
///
/// Mídia dentro de algo que começa com ponto (`.thumbnails`, `.trashed-*` da
/// lixeira do Android, `.Statuses`...) não entra na lista, mas o tamanho conta
/// em [StorageScan.otherBytes]. `Android/data` e `Android/obb` o sistema
/// bloqueia; as pastas em [skip] são puladas inteiras.
///
/// Com [previous], só relista as pastas que mudaram desde aquela varredura.
/// Síncrono: é pra rodar dentro de `Isolate.run`.
StorageScan scanStorage(
  String root, {
  Set<String> skip = const {},
  Map<String, DirSnapshot> previous = const {},
}) {
  final now = DateTime.now().millisecondsSinceEpoch;
  final blocked = {'$root/Android/data', '$root/Android/obb', ...skip};
  final snapshots = <String, DirSnapshot>{};
  final media = <MediaFile>[];
  var otherBytes = 0;
  var listedDirs = 0;
  final pending = [(path: root, hidden: false)];

  while (pending.isNotEmpty) {
    final (:path, :hidden) = pending.removeLast();
    final FileStat dirStat;
    try {
      dirStat = Directory(path).statSync();
    } on FileSystemException {
      continue;
    }
    if (dirStat.type != FileSystemEntityType.directory) continue;
    final modified = dirStat.modified.millisecondsSinceEpoch;

    var snapshot = previous[path];
    if (snapshot == null || snapshot.modified != modified) {
      // A data da pasta tem precisão de ms: algo criado no mesmo instante em
      // que a pasta é lida não mudaria a data. Pasta mexida há menos de
      // [_settle] não é confiável e fica marcada pra relistar na próxima.
      final trusted = now - modified > _settle.inMilliseconds;
      final listed = _listDir(path, trusted ? modified : -1, hidden: hidden);
      if (listed == null) continue; // sem permissão de leitura
      snapshot = listed;
      listedDirs++;
    }

    snapshots[path] = snapshot;
    media.addAll(snapshot.media);
    otherBytes += snapshot.otherBytes;
    for (final sub in snapshot.subdirs) {
      if (blocked.contains(sub)) continue;
      final name = sub.substring(sub.lastIndexOf('/') + 1);
      pending.add((path: sub, hidden: hidden || name.startsWith('.')));
    }
  }

  return StorageScan(
    media: media,
    otherBytes: otherBytes,
    snapshots: snapshots,
    listedDirs: listedDirs,
  );
}

const _settle = Duration(seconds: 2);

DirSnapshot? _listDir(String path, int modified, {required bool hidden}) {
  final List<FileSystemEntity> entries;
  try {
    entries = Directory(path).listSync(followLinks: false);
  } on FileSystemException {
    return null;
  }
  final media = <MediaFile>[];
  final subdirs = <String>[];
  var otherBytes = 0;
  for (final entry in entries) {
    if (entry is Directory) {
      subdirs.add(entry.path);
      continue;
    }
    if (entry is! File) continue;
    final FileStat stat;
    try {
      stat = entry.statSync();
    } on FileSystemException {
      continue;
    }
    final name = entry.path.substring(entry.path.lastIndexOf('/') + 1);
    final video = hidden || name.startsWith('.') ? null : isVideoFile(name);
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
  return DirSnapshot(modified: modified, media: media, otherBytes: otherBytes, subdirs: subdirs);
}

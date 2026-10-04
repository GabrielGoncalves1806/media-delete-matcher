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

enum ScanPhase {
  /// Andando pelas pastas e listando o que existe (rápido).
  listing,

  /// Consultando tamanho e data de cada arquivo (a parte demorada; aqui já se
  /// sabe o total, então dá pra mostrar progresso de verdade).
  measuring,
}

class ScanProgress {
  const ScanProgress(this.phase, {required this.dirs, required this.files, this.measured = 0});

  final ScanPhase phase;
  final int dirs;

  /// Arquivos que precisam ser medidos (pastas iguais ao cache não entram).
  final int files;
  final int measured;

  /// Null enquanto ainda tá listando (não se sabe o total).
  double? get fraction => phase == ScanPhase.measuring && files > 0 ? measured / files : null;
}

/// Uma pasta que mudou: listada na fase 1, medida na fase 2.
class _DirWork {
  _DirWork(this.path, this.modified, this.hidden, this.files, this.subdirs);

  final String path;
  final int modified;
  final bool hidden;
  final List<File> files;
  final List<String> subdirs;
}

/// Varre [root] atrás de fotos e vídeos. Atalho pra [scanVolumes] com um volume.
StorageScan scanStorage(
  String root, {
  Set<String> skip = const {},
  Map<String, DirSnapshot> previous = const {},
  void Function(ScanProgress progress)? onProgress,
}) =>
    scanVolumes([root], skip: skip, previous: previous, onProgress: onProgress);

/// Varre os volumes atrás de fotos e vídeos, ignorando `.nomedia` de propósito.
///
/// Mídia dentro de algo que começa com ponto (`.thumbnails`, `.trashed-*` da
/// lixeira do Android, `.Statuses`...) não entra na lista, mas o tamanho conta
/// em [StorageScan.otherBytes]. `Android/data` e `Android/obb` o sistema
/// bloqueia; as pastas em [skip] são puladas inteiras.
///
/// Com [previous], só relista as pastas que mudaram desde aquela varredura.
/// Em duas fases, pra [onProgress] poder mostrar quanto falta: primeiro lista
/// as pastas (rápido), depois mede os arquivos (aí o total já é conhecido).
/// Síncrono: é pra rodar dentro de um isolate.
StorageScan scanVolumes(
  List<String> roots, {
  Set<String> skip = const {},
  Map<String, DirSnapshot> previous = const {},
  void Function(ScanProgress progress)? onProgress,
}) {
  final now = DateTime.now().millisecondsSinceEpoch;
  final blocked = {
    for (final root in roots) ...['$root/Android/data', '$root/Android/obb'],
    ...skip,
  };
  final snapshots = <String, DirSnapshot>{};
  final work = <_DirWork>[];
  var dirs = 0;
  var files = 0;

  // Fase 1: andar pelas pastas. Pasta igual ao cache é reaproveitada; as
  // outras são listadas e os arquivos ficam pra medir depois.
  final pending = [for (final root in roots.reversed) (path: root, hidden: false)];
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

    final List<String> subdirs;
    final cached = previous[path];
    if (cached != null && cached.modified == modified) {
      snapshots[path] = cached;
      subdirs = cached.subdirs;
    } else {
      final List<FileSystemEntity> entries;
      try {
        entries = Directory(path).listSync(followLinks: false);
      } on FileSystemException {
        continue; // sem permissão de leitura
      }
      subdirs = [for (final e in entries) if (e is Directory) e.path];
      final dirFiles = entries.whereType<File>().toList();
      // A data da pasta tem precisão de ms: algo criado no mesmo instante em
      // que a pasta é lida não mudaria a data. Pasta mexida há menos de
      // [_settle] não é confiável e fica marcada pra relistar na próxima.
      final trusted = now - modified > _settle.inMilliseconds;
      work.add(_DirWork(path, trusted ? modified : -1, hidden, dirFiles, subdirs));
      files += dirFiles.length;
    }

    dirs++;
    if (dirs % 50 == 0) onProgress?.call(ScanProgress(ScanPhase.listing, dirs: dirs, files: files));
    for (final sub in subdirs.reversed) {
      if (blocked.contains(sub)) continue;
      final name = sub.substring(sub.lastIndexOf('/') + 1);
      pending.add((path: sub, hidden: hidden || name.startsWith('.')));
    }
  }

  // Fase 2: medir os arquivos das pastas que mudaram.
  var measured = 0;
  void report() => onProgress?.call(ScanProgress(ScanPhase.measuring, dirs: dirs, files: files, measured: measured));
  report();
  for (final dir in work) {
    snapshots[dir.path] = _measure(dir, onFile: () {
      measured++;
      if (measured % 200 == 0) report();
    });
  }
  report();

  return StorageScan(
    media: [for (final s in snapshots.values) ...s.media],
    otherBytes: snapshots.values.fold(0, (sum, s) => sum + s.otherBytes),
    snapshots: snapshots,
    listedDirs: work.length,
  );
}

const _settle = Duration(seconds: 2);

DirSnapshot _measure(_DirWork dir, {required void Function() onFile}) {
  final media = <MediaFile>[];
  var otherBytes = 0;
  for (final file in dir.files) {
    onFile();
    final FileStat stat;
    try {
      stat = file.statSync();
    } on FileSystemException {
      continue;
    }
    final name = file.path.substring(file.path.lastIndexOf('/') + 1);
    final video = dir.hidden || name.startsWith('.') ? null : isVideoFile(name);
    if (video == null || stat.size == 0) {
      otherBytes += stat.size;
      continue;
    }
    media.add(MediaFile(
      path: file.path,
      size: stat.size,
      modified: stat.modified,
      isVideo: video,
    ));
  }
  return DirSnapshot(modified: dir.modified, media: media, otherBytes: otherBytes, subdirs: dir.subdirs);
}

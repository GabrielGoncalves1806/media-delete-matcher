import 'dart:convert';
import 'dart:io';

import 'media_file.dart';

class TrashEntry {
  TrashEntry({
    required this.fileName,
    required this.originalPath,
    required this.trashedAt,
    required this.size,
    required this.isVideo,
  });

  factory TrashEntry.fromJson(Map<String, dynamic> json) => TrashEntry(
        fileName: json['file'] as String,
        originalPath: json['original'] as String,
        trashedAt: DateTime.fromMillisecondsSinceEpoch(json['at'] as int),
        size: json['size'] as int,
        isVideo: json['video'] as bool,
      );

  /// Nome do arquivo dentro da pasta da lixeira.
  final String fileName;
  final String originalPath;
  final DateTime trashedAt;
  final int size;
  final bool isVideo;

  String get originalName => originalPath.substring(originalPath.lastIndexOf('/') + 1);

  Map<String, dynamic> toJson() => {
        'file': fileName,
        'original': originalPath,
        'at': trashedAt.millisecondsSinceEpoch,
        'size': size,
        'video': isVideo,
      };
}

/// Lixeira do próprio app: uma pasta escondida (com `.nomedia`) no mesmo
/// volume. Mover pra cá é um rename, instantâneo, sem copiar nada.
/// O espaço só volta quando a lixeira é esvaziada.
class TrashBin {
  TrashBin(this.directory, {required this.onFilesChanged});

  static const keepFor = Duration(days: 30);

  final String directory;

  /// Chamado com os caminhos originais que sumiram ou voltaram.
  final Future<void> Function(List<String> paths) onFilesChanged;

  final _entries = <TrashEntry>[];
  int _counter = 0;

  List<TrashEntry> get entries => List.unmodifiable(_entries);
  int get bytes => _entries.fold(0, (sum, e) => sum + e.size);

  File get _index => File('$directory/index.json');
  String pathOf(TrashEntry entry) => '$directory/${entry.fileName}';

  Future<void> load() async {
    _entries.clear();
    if (!await _index.exists()) return;
    final list = jsonDecode(await _index.readAsString()) as List;
    _entries.addAll(list.map((e) => TrashEntry.fromJson(e as Map<String, dynamic>)));
  }

  /// Move pra lixeira. Devolve os caminhos que realmente saíram.
  Future<List<String>> moveIn(List<MediaFile> files, {DateTime? now}) async {
    await Directory(directory).create(recursive: true);
    final nomedia = File('$directory/.nomedia');
    if (!await nomedia.exists()) await nomedia.create();

    final at = now ?? DateTime.now();
    final moved = <String>[];
    for (final file in files) {
      final fileName = '${at.microsecondsSinceEpoch}_${_counter++}_${file.name}';
      try {
        await File(file.path).rename('$directory/$fileName');
      } on FileSystemException {
        // Sumiu por fora do app ou sem permissão. Cartão SD não chega aqui:
        // a varredura só olha o armazenamento interno, mesmo volume da lixeira.
        continue;
      }
      _entries.add(TrashEntry(
        fileName: fileName,
        originalPath: file.path,
        trashedAt: at,
        size: file.size,
        isVideo: file.isVideo,
      ));
      moved.add(file.path);
    }
    await _save();
    await onFilesChanged(moved);
    return moved;
  }

  /// Devolve pro lugar original. False se já existe outro arquivo lá.
  Future<bool> restore(TrashEntry entry) async {
    final target = File(entry.originalPath);
    if (await target.exists()) return false;
    await target.parent.create(recursive: true);
    await File(pathOf(entry)).rename(entry.originalPath);
    _entries.remove(entry);
    await _save();
    await onFilesChanged([entry.originalPath]);
    return true;
  }

  /// Apaga de vez. Devolve quantos bytes liberou.
  Future<int> delete(Iterable<TrashEntry> toDelete) async {
    final list = toDelete.toList();
    var freed = 0;
    for (final entry in list) {
      final file = File(pathOf(entry));
      if (await file.exists()) await file.delete();
      freed += entry.size;
      _entries.remove(entry);
    }
    await _save();
    return freed;
  }

  Future<int> empty() => delete(_entries.toList());

  /// Apaga o que passou do prazo. Chamado ao abrir o app.
  Future<int> purgeExpired({DateTime? now}) {
    final limit = (now ?? DateTime.now()).subtract(keepFor);
    return delete(_entries.where((e) => e.trashedAt.isBefore(limit)));
  }

  Future<void> _save() async {
    if (!await Directory(directory).exists()) return;
    await _index.writeAsString(jsonEncode([for (final e in _entries) e.toJson()]));
  }
}

/// Uma [TrashBin] por volume (interno, cartão SD), com cara de lixeira única.
///
/// Cada arquivo vai pra lixeira do próprio volume: mover é um rename, e
/// rename não atravessa volumes. Mandar algo do cartão pra lixeira do
/// interno seria copiar o arquivo inteiro (e ocupar o interno).
class MultiTrash {
  MultiTrash({required this.onFilesChanged});

  static const folderName = '.media_swipe_trash';

  final Future<void> Function(List<String> paths) onFilesChanged;

  /// Raiz do volume -> lixeira dele. Só volumes montados agora.
  var _bins = <String, TrashBin>{};

  /// Pastas de lixeira, pra varredura pular.
  Set<String> get directories => {for (final bin in _bins.values) bin.directory};

  /// Define os volumes montados. A lixeira de volume que saiu (cartão
  /// removido) some da lista e volta quando ele for montado de novo.
  void useVolumes(Iterable<String> roots) {
    _bins = {
      for (final root in roots)
        root: _bins[root] ?? TrashBin('$root/$folderName', onFilesChanged: onFilesChanged),
    };
  }

  Future<void> load() async {
    for (final bin in _bins.values) {
      await bin.load();
    }
  }

  List<TrashEntry> get entries => [for (final bin in _bins.values) ...bin.entries];
  int get bytes => _bins.values.fold(0, (sum, bin) => sum + bin.bytes);

  /// Quanto a lixeira ocupa num volume específico.
  int bytesIn(String root) => _bins[root]?.bytes ?? 0;

  /// Lixeira do volume onde o caminho está (null = fora de qualquer volume).
  TrashBin? _binFor(String path) {
    for (final MapEntry(key: root, value: bin) in _bins.entries) {
      if (path.startsWith('$root/')) return bin;
    }
    return null;
  }

  String pathOf(TrashEntry entry) => _binFor(entry.originalPath)!.pathOf(entry);

  /// Separa por volume e manda cada grupo pra lixeira certa.
  Future<List<String>> moveIn(List<MediaFile> files, {DateTime? now}) async {
    final byBin = <TrashBin, List<MediaFile>>{};
    for (final file in files) {
      final bin = _binFor(file.path);
      if (bin != null) byBin.putIfAbsent(bin, () => []).add(file);
    }
    return [
      for (final MapEntry(key: bin, value: group) in byBin.entries) ...await bin.moveIn(group, now: now),
    ];
  }

  Future<bool> restore(TrashEntry entry) => _binFor(entry.originalPath)!.restore(entry);

  Future<int> delete(Iterable<TrashEntry> toDelete) async {
    var freed = 0;
    for (final entry in toDelete.toList()) {
      freed += await _binFor(entry.originalPath)!.delete([entry]);
    }
    return freed;
  }

  Future<int> empty() async {
    var freed = 0;
    for (final bin in _bins.values) {
      freed += await bin.empty();
    }
    return freed;
  }

  Future<int> purgeExpired({DateTime? now}) async {
    var freed = 0;
    for (final bin in _bins.values) {
      freed += await bin.purgeExpired(now: now);
    }
    return freed;
  }
}

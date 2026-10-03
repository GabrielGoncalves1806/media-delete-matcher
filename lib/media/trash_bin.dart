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

import 'package:flutter/material.dart';

import '../format.dart';
import '../media/decision_store.dart';
import '../media/media_file.dart';
import '../media/media_library.dart';
import '../media/media_mover.dart';
import '../media/native_bridge.dart';
import '../theme.dart';
import 'folder_picker_screen.dart';

/// Cartão SD montado agora, se tiver.
bool hasCard(MediaLibrary library) => _card(library) != null;

/// Escolhe uma pasta no cartão e move [files] pra lá, com progresso.
/// O que vai pro cartão conta como mantido. Devolve os caminhos ANTIGOS do
/// que foi movido (pra quem chamou tirar da lista).
Future<List<String>> moveToCard(
  BuildContext context,
  MediaLibrary library,
  DecisionStore store,
  List<MediaFile> files,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final card = _card(library);
  if (card == null) {
    messenger.showSnackBar(const SnackBar(content: Text('Nenhum cartão SD montado')));
    return [];
  }
  final toMove = files.where((f) => !library.isRemovable(f.path)).toList();
  if (toMove.isEmpty) {
    messenger.showSnackBar(const SnackBar(content: Text('Já tá no cartão')));
    return [];
  }

  final bytes = toMove.fold(0, (sum, f) => sum + f.size);
  final dir = await Navigator.of(context).push<String>(
    MaterialPageRoute(
      builder: (_) => FolderPickerScreen(
        root: card.path,
        rootLabel: 'Cartão SD',
        actionLabel: toMove.length == 1
            ? 'Mover pra cá · ${formatBytes(bytes)}'
            : 'Mover ${plural(toMove.length, 'item', 'itens')} pra cá · ${formatBytes(bytes)}',
      ),
    ),
  );
  if (dir == null || !context.mounted) return [];

  final progress = ValueNotifier((index: 0, value: 0.0));
  final navigator = Navigator.of(context, rootNavigator: true);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PopScope(
      canPop: false,
      child: AlertDialog(
        title: const Text('Movendo pro cartão'),
        content: ValueListenableBuilder(
          valueListenable: progress,
          builder: (context, p, _) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${p.index + 1} de ${toMove.length} · ${toMove[p.index].name}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.muted, fontSize: 13),
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(
                  value: p.value,
                  minHeight: 6,
                  color: AppColors.warn,
                  backgroundColor: AppColors.surface2,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Copia, confere a cópia e só então apaga do celular.',
                style: TextStyle(color: AppColors.muted, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  final mover = MediaMover(library);
  final moved = <String>[];
  var movedBytes = 0;
  String? error;
  for (final (i, file) in toMove.indexed) {
    progress.value = (index: i, value: 0.0);
    final result = await mover.move(file, dir, onProgress: (v) => progress.value = (index: i, value: v));
    if (!result.ok) {
      error = result.error;
      break; // o resto fica onde estava
    }
    store.forget(file.path);
    store.keep(result.newFile!.path);
    moved.add(file.path);
    movedBytes += file.size;
  }
  navigator.pop();
  progress.dispose();

  final folder = dir == card.path ? 'Cartão SD' : dir.substring(dir.lastIndexOf('/') + 1);
  final done = moved.isEmpty
      ? ''
      : '${plural(moved.length, 'item movido', 'itens movidos')} (${formatBytes(movedBytes)}) pra "$folder"';
  messenger.showSnackBar(SnackBar(
    content: Text([if (done.isNotEmpty) done, ?error].join('. ')),
  ));
  return moved;
}

StorageVolume? _card(MediaLibrary library) =>
    library.volumes.where((v) => v.removable && library.roots.contains(v.path)).firstOrNull;

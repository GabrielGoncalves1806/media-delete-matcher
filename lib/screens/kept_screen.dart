import 'package:flutter/material.dart';

import '../format.dart';
import '../media/decision_store.dart';
import '../media/media_file.dart';
import '../media/media_library.dart';
import '../theme.dart';
import '../widgets/media_thumb.dart';

/// Tudo que foi mantido. Dá pra voltar com algo pro swipe ou marcar pra apagar
/// direto, pra quando "manteve sem querer".
class KeptScreen extends StatefulWidget {
  const KeptScreen({super.key, required this.library, required this.store});

  final MediaLibrary library;
  final DecisionStore store;

  @override
  State<KeptScreen> createState() => _KeptScreenState();
}

class _KeptScreenState extends State<KeptScreen> {
  final _selected = <String>{};

  /// Só o que ainda existe, do maior pro menor (a ordem da biblioteca).
  List<MediaFile> get _files =>
      widget.library.files.where((f) => widget.store.kept.contains(f.path)).toList();

  int _bytesOf(Iterable<MediaFile> files) => files.fold(0, (sum, f) => sum + f.size);

  void _toggle(String path) => setState(() {
        if (!_selected.remove(path)) _selected.add(path);
      });

  void _sendBack() {
    final n = _selected.length;
    widget.store.forgetAll(_selected);
    _done('${plural(n, 'item voltou', 'itens voltaram')} pro swipe');
  }

  void _markForDeletion() {
    final n = _selected.length;
    for (final path in _selected) {
      final file = widget.library.byPath(path);
      if (file != null) widget.store.markForDeletion(path, file.size);
    }
    _done('${plural(n, 'item marcado', 'itens marcados')} pra apagar · confirma na revisão');
  }

  void _done(String message) {
    setState(_selected.clear);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final files = _files;
    final allSelected = files.isNotEmpty && _selected.length == files.length;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mantidos'),
        actions: [
          if (files.isNotEmpty)
            TextButton(
              onPressed: () => setState(() {
                allSelected ? _selected.clear() : _selected.addAll(files.map((f) => f.path));
              }),
              child: Text(allSelected ? 'Limpar seleção' : 'Selecionar tudo'),
            ),
        ],
      ),
      body: files.isEmpty
          ? const Center(
              child: Text('Nada mantido ainda', style: TextStyle(color: AppColors.muted, fontSize: 16)),
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '${plural(files.length, 'item', 'itens')} · ${formatBytes(_bytesOf(files))}. '
                      'Toca pra selecionar.',
                      style: const TextStyle(color: AppColors.muted),
                    ),
                  ),
                ),
                Expanded(
                  child: GridView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      mainAxisSpacing: 4,
                      crossAxisSpacing: 4,
                    ),
                    itemCount: files.length,
                    itemBuilder: (context, i) {
                      final file = files[i];
                      final selected = _selected.contains(file.path);
                      return GestureDetector(
                        key: ValueKey(file.path),
                        onTap: () => _toggle(file.path),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              MediaThumb(
                                path: file.path,
                                isVideo: file.isVideo,
                                thumbnails: widget.library.thumbnails,
                              ),
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 120),
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: selected ? AppColors.accent : Colors.transparent,
                                    width: 3,
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                  color: selected ? AppColors.accent.withValues(alpha: 0.2) : null,
                                ),
                              ),
                              if (selected)
                                const Positioned(
                                  top: 6,
                                  right: 6,
                                  child: Icon(Icons.check_circle_rounded, color: AppColors.accent, size: 22),
                                ),
                              Positioned(
                                left: 6,
                                bottom: 4,
                                child: Text(
                                  formatBytes(file.size),
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    shadows: [Shadow(color: Colors.black87, blurRadius: 4)],
                                  ),
                                ),
                              ),
                              if (file.isVideo)
                                const Positioned(
                                  right: 6,
                                  bottom: 4,
                                  child: Icon(
                                    Icons.play_arrow_rounded,
                                    size: 16,
                                    shadows: [Shadow(color: Colors.black87, blurRadius: 4)],
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 180),
                  child: _selected.isEmpty
                      ? const SizedBox(width: double.infinity)
                      : SafeArea(
                          top: false,
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton(
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(vertical: 15),
                                      side: const BorderSide(color: AppColors.line),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                    ),
                                    onPressed: _sendBack,
                                    child: Text('Voltar ${_selected.length} pro swipe'),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: FilledButton(
                                    style: FilledButton.styleFrom(
                                      backgroundColor: AppColors.delete,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(vertical: 15),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                    ),
                                    onPressed: _markForDeletion,
                                    child: Text('Apagar ${_selected.length}'),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                ),
              ],
            ),
    );
  }
}

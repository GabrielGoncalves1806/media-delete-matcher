import 'package:flutter/material.dart';

import '../format.dart';
import '../media/decision_store.dart';
import '../media/media_file.dart';
import '../media/media_library.dart';
import '../theme.dart';
import '../widgets/media_thumb.dart';
import 'done_screen.dart';

/// Grid do que foi marcado. Tocar alterna marcado/mantido.
/// Devolve `true` pro Navigator quando algo foi pra lixeira.
class ReviewScreen extends StatefulWidget {
  const ReviewScreen({super.key, required this.library, required this.store});

  final MediaLibrary library;
  final DecisionStore store;

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  /// Ordem congelada ao abrir, pra miniatura não pular de lugar ao desmarcar.
  late final List<String> _paths = widget.store.marked.keys.toList().reversed.toList();
  bool _busy = false;

  @override
  void dispose() {
    widget.store.closeReview();
    super.dispose();
  }

  Future<bool> _confirm(int count, int bytes) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Mover ${plural(count, 'item', 'itens')} pra lixeira?'),
        content: Text(
          '${formatBytes(bytes)} saem da galeria e do WhatsApp. Ficam 30 dias '
          'na lixeira do app, dá pra restaurar. O espaço volta quando ela for esvaziada.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.delete),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Mover'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  Future<void> _trash() async {
    final store = widget.store;
    final library = widget.library;
    if (!await _confirm(store.markedCount, store.markedBytes)) return;
    setState(() => _busy = true);

    final files = <MediaFile>[];
    for (final path in store.marked.keys.toList()) {
      final file = library.byPath(path);
      file == null ? store.forget(path) : files.add(file); // sumiu por fora do app
    }
    final moved = await library.trash.moveIn(files);
    if (!mounted) return;
    setState(() => _busy = false);

    if (moved.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não consegui mover nada.')),
      );
      return;
    }

    final bytes = moved.fold<int>(0, (sum, p) => sum + (store.marked[p] ?? 0));
    store.confirmTrashed(moved);
    library.forget(moved);
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DoneScreen(movedBytes: bytes, count: moved.length, library: library),
      ),
    );
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Revisar'),
      ),
      body: ListenableBuilder(
        listenable: widget.store,
        builder: (context, _) {
          final store = widget.store;
          final n = store.markedCount;
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: '${plural(n, 'item', 'itens')} · ${formatBytes(store.markedBytes)}',
                          style: const TextStyle(color: AppColors.delete, fontWeight: FontWeight.w700),
                        ),
                        const TextSpan(text: ' pra liberar'),
                      ],
                    ),
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
                  itemCount: _paths.length,
                  itemBuilder: (context, i) {
                    final path = _paths[i];
                    return _Thumb(
                      key: ValueKey(path),
                      file: widget.library.byPath(path),
                      bytes: store.marked[path] ?? store.unmarkedInReview[path] ?? 0,
                      selected: store.marked.containsKey(path),
                      library: widget.library,
                      onTap: () => store.toggleInReview(path),
                    );
                  },
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  child: Column(
                    children: [
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.delete,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                          onPressed: n == 0 || _busy ? null : _trash,
                          child: _busy
                              ? const SizedBox.square(
                                  dimension: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : Text(
                                  n == 0
                                      ? 'Nada marcado'
                                      : 'Mover ${plural(n, 'item', 'itens')} pra lixeira',
                                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                                ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Toca numa miniatura pra desmarcar · fica 30 dias na lixeira',
                        style: TextStyle(color: AppColors.muted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({
    super.key,
    required this.file,
    required this.bytes,
    required this.selected,
    required this.library,
    required this.onTap,
  });

  /// Null se o arquivo sumiu por fora do app.
  final MediaFile? file;
  final int bytes;
  final bool selected;
  final MediaLibrary library;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const shadow = [Shadow(color: Colors.black87, blurRadius: 4)];
    final file = this.file;
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (file == null)
              const ColoredBox(
                color: AppColors.surface,
                child: Center(child: Icon(Icons.hide_image_outlined, color: AppColors.muted)),
              )
            else
              Opacity(
                opacity: selected ? 1 : 0.35,
                child: MediaThumb(
                  path: file.path,
                  isVideo: file.isVideo,
                  thumbnails: library.thumbnails,
                ),
              ),
            Positioned(
              top: 5,
              right: 5,
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: selected ? AppColors.delete : Colors.black38,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: selected
                    ? const Icon(Icons.check_rounded, size: 14, color: Colors.white)
                    : null,
              ),
            ),
            Positioned(
              left: 6,
              bottom: 4,
              child: Text(
                formatBytes(bytes),
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, shadows: shadow),
              ),
            ),
            if (file?.isVideo ?? false)
              const Positioned(
                right: 6,
                bottom: 4,
                child: Icon(Icons.play_arrow_rounded, size: 16, shadows: shadow),
              ),
          ],
        ),
      ),
    );
  }
}

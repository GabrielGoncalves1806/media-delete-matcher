import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

import '../format.dart';
import '../media/decision_store.dart';
import '../media/media_library.dart';
import '../theme.dart';
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
  late final List<String> _ids = widget.store.marked.keys.toList().reversed.toList();
  bool _busy = false;

  @override
  void dispose() {
    widget.store.closeReview();
    super.dispose();
  }

  Future<void> _trash() async {
    final store = widget.store;
    final ids = store.marked.keys.toList();
    final sizes = Map.of(store.marked);
    setState(() => _busy = true);

    final result = await widget.library.trash(ids);
    if (!mounted) return;
    setState(() => _busy = false);

    result.missing.forEach(store.forget);
    if (result.trashed.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nada foi apagado.')),
      );
      return;
    }

    final freed = result.trashed.fold<int>(0, (sum, id) => sum + (sizes[id] ?? 0));
    store.confirmTrashed(result.trashed);
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DoneScreen(
          freedBytes: freed,
          count: result.trashed.length,
          totalFreedBytes: store.freedBytes,
        ),
      ),
    );
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Revisar', style: TextStyle(fontWeight: FontWeight.w700)),
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
                  itemCount: _ids.length,
                  itemBuilder: (context, i) {
                    final id = _ids[i];
                    final selected = store.marked.containsKey(id);
                    final bytes = store.marked[id] ?? store.unmarkedInReview[id] ?? 0;
                    return _Thumb(
                      key: ValueKey(id),
                      id: id,
                      bytes: bytes,
                      selected: selected,
                      onTap: () => store.toggleInReview(id),
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

class _Thumb extends StatefulWidget {
  const _Thumb({
    super.key,
    required this.id,
    required this.bytes,
    required this.selected,
    required this.onTap,
  });

  final String id;
  final int bytes;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_Thumb> createState() => _ThumbState();
}

class _ThumbState extends State<_Thumb> {
  Uint8List? _data;
  bool _isVideo = false;
  bool _gone = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final asset = await AssetEntity.fromId(widget.id);
    if (asset == null) {
      if (mounted) setState(() => _gone = true);
      return;
    }
    final data = await asset.thumbnailDataWithSize(const ThumbnailSize.square(300));
    if (mounted) {
      setState(() {
        _data = data;
        _isVideo = asset.type == AssetType.video;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    const shadow = [Shadow(color: Colors.black87, blurRadius: 4)];
    return GestureDetector(
      onTap: widget.onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: AppColors.surface),
            if (_data != null)
              Opacity(
                opacity: widget.selected ? 1 : 0.35,
                child: Image.memory(_data!, fit: BoxFit.cover, gaplessPlayback: true),
              ),
            if (_gone)
              const Center(
                child: Icon(Icons.hide_image_outlined, color: AppColors.muted),
              ),
            Positioned(
              top: 5,
              right: 5,
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: widget.selected ? AppColors.delete : Colors.black38,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: widget.selected
                    ? const Icon(Icons.check_rounded, size: 14, color: Colors.white)
                    : null,
              ),
            ),
            Positioned(
              left: 6,
              bottom: 4,
              child: Text(
                formatBytes(widget.bytes),
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, shadows: shadow),
              ),
            ),
            if (_isVideo)
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

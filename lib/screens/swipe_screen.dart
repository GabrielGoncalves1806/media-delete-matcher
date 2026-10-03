import 'package:flutter/material.dart';

import '../format.dart';
import '../media/decision_store.dart';
import '../media/media_file.dart';
import '../media/media_library.dart';
import '../theme.dart';
import '../widgets/media_preview.dart';
import '../widgets/swipe_card.dart';
import 'review_screen.dart';
import 'viewer_screen.dart';

class SwipeScreen extends StatefulWidget {
  const SwipeScreen({
    super.key,
    required this.files,
    required this.title,
    required this.library,
    required this.store,
  });

  /// Na ordem em que vão aparecer (do maior pro menor).
  final List<MediaFile> files;
  final String title;
  final MediaLibrary library;
  final DecisionStore store;

  @override
  State<SwipeScreen> createState() => _SwipeScreenState();
}

class _SwipeScreenState extends State<SwipeScreen> {
  late final List<MediaFile> _queue =
      widget.files.where((f) => !widget.store.isDecided(f.path)).toList();
  final _history = <MediaFile>[];
  var _cardKey = GlobalKey<SwipeCardState>();

  /// Uma GlobalKey por carta visível. Quando a carta de baixo sobe, o Flutter
  /// move o widget (com o vídeo já carregado) em vez de criar outro do zero.
  final _faceKeys = <String, GlobalKey>{};

  GlobalKey _faceKey(String path) => _faceKeys.putIfAbsent(path, GlobalKey.new);

  Future<void> _openViewer(MediaFile file) async {
    final decision = await Navigator.of(context).push<SwipeDirection>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => ViewerScreen(file: file, thumbnails: widget.library.thumbnails),
      ),
    );
    if (decision != null) await _cardKey.currentState?.swipe(decision);
  }

  MediaFile? get _current => _queue.isEmpty ? null : _queue.first;

  void _onSwiped(SwipeDirection direction) {
    final file = _current;
    if (file == null) return;
    if (direction == SwipeDirection.delete) {
      widget.store.markForDeletion(file.path, file.size);
    } else {
      widget.store.keep(file.path);
    }
    setState(() {
      _history.add(file);
      _queue.removeAt(0);
      _cardKey = GlobalKey();
    });
    _leaveIfDone();
  }

  /// Algum arquivo desta lista marcado e ainda não confirmado na revisão.
  bool get _hasPendingMarks => widget.files.any((f) => widget.store.marked.containsKey(f.path));

  /// Sem nada pra revisar e sem marcado esperando confirmação: volta pra home.
  /// Se ainda tem marcado, fica na tela vazia que leva pra revisão.
  void _leaveIfDone() {
    if (_queue.isNotEmpty || _hasPendingMarks || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${widget.title}: tudo revisado ✓')),
    );
    Navigator.of(context).pop();
  }

  void _undo() {
    if (_history.isEmpty) return;
    final last = _history.removeLast();
    widget.store.forget(last.path);
    setState(() {
      _queue.insert(0, last);
      _cardKey = GlobalKey();
    });
  }

  Future<void> _openReview() async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ReviewScreen(library: widget.library, store: widget.store),
      ),
    );
    if (!mounted) return;
    // Sai da fila o que foi pra lixeira e o que virou "mantido" na revisão.
    setState(() {
      _queue.removeWhere(
        (f) => widget.store.isDecided(f.path) || !widget.library.contains(f.path),
      );
      _history.removeWhere((f) => !widget.library.contains(f.path));
      _cardKey = GlobalKey();
    });
    _leaveIfDone();
  }

  @override
  Widget build(BuildContext context) {
    final current = _current;
    final next = _queue.length > 1 ? _queue[1] : null;
    _faceKeys.removeWhere((path, _) => path != current?.path && path != next?.path);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _TopBar(
              title: widget.title,
              remaining: _queue.length,
              store: widget.store,
              onReview: _openReview,
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: current == null
                    ? _EmptyDeck(onReview: _openReview)
                    : Stack(
                        fit: StackFit.expand,
                        children: [
                          if (next != null)
                            Transform.translate(
                              offset: const Offset(0, 14),
                              child: Transform.scale(
                                scale: 0.95,
                                child: _CardFace(
                                  key: _faceKey(next.path),
                                  file: next,
                                  library: widget.library,
                                  active: false,
                                ),
                              ),
                            ),
                          SwipeCard(
                            key: _cardKey,
                            onSwiped: _onSwiped,
                            child: _CardFace(
                              key: _faceKey(current.path),
                              file: current,
                              library: widget.library,
                              active: true,
                              onLongPress: () => _openViewer(current),
                            ),
                          ),
                        ],
                      ),
              ),
            ),
            _Actions(
              onDelete: current == null
                  ? null
                  : () => _cardKey.currentState?.swipe(SwipeDirection.delete),
              onKeep: current == null
                  ? null
                  : () => _cardKey.currentState?.swipe(SwipeDirection.keep),
              onUndo: _history.isEmpty ? null : _undo,
            ),
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text.rich(
                TextSpan(
                  style: TextStyle(color: AppColors.muted, fontSize: 12),
                  children: [
                    TextSpan(text: '← apagar', style: TextStyle(color: AppColors.delete)),
                    TextSpan(text: '  ·  segura = tela cheia  ·  '),
                    TextSpan(text: 'manter →', style: TextStyle(color: AppColors.keep)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.title,
    required this.remaining,
    required this.store,
    required this.onReview,
  });

  final String title;
  final int remaining;
  final DecisionStore store;
  final VoidCallback onReview;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 16, 10),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.chevron_left_rounded, size: 28),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: display(17), overflow: TextOverflow.ellipsis),
                Text(
                  plural(remaining, 'restante', 'restantes'),
                  style: const TextStyle(color: AppColors.muted, fontSize: 12),
                ),
              ],
            ),
          ),
          ListenableBuilder(
            listenable: store,
            builder: (context, _) => GestureDetector(
              onTap: store.markedCount == 0 ? null : onReview,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: AppColors.delete.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  '🗑 ${formatCount(store.markedCount)} · ${formatBytes(store.markedBytes)}',
                  style: const TextStyle(
                    color: AppColors.delete,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// O conteúdo visual da carta: mídia + informações por cima.
class _CardFace extends StatefulWidget {
  const _CardFace({
    super.key,
    required this.file,
    required this.library,
    required this.active,
    this.onLongPress,
  });

  final MediaFile file;
  final MediaLibrary library;

  /// false = carta de baixo: carrega o vídeo/foto, mas não toca.
  final bool active;
  final Future<void> Function()? onLongPress;

  @override
  State<_CardFace> createState() => _CardFaceState();
}

class _CardFaceState extends State<_CardFace> {
  Duration? _duration;

  @override
  Widget build(BuildContext context) {
    final file = widget.file;
    final kind = !file.isVideo
        ? 'FOTO'
        : _duration == null
            ? '▶ VÍDEO'
            : '▶ VÍDEO · ${formatDuration(_duration!)}';

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(color: Colors.black87, blurRadius: 30, offset: Offset(0, 14)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          fit: StackFit.expand,
          children: [
            MediaPreview(
              file: file,
              thumbnails: widget.library.thumbnails,
              active: widget.active,
              preload: true,
              onLongPress: widget.onLongPress,
              onDuration: (d) => setState(() => _duration = d),
            ),
            const IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.black38, Colors.transparent, Colors.transparent, Colors.black87],
                    stops: [0, 0.3, 0.55, 1],
                  ),
                ),
              ),
            ),
            Positioned(top: 14, left: 14, child: _Badge(kind)),
            Positioned(
              top: 10,
              right: 14,
              child: Text(
                formatBytes(file.size),
                style: display(24).copyWith(
                  shadows: const [Shadow(color: Colors.black54, blurRadius: 8)],
                ),
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 18,
              child: IgnorePointer(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      file.name,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${file.folderName} · ${formatDate(file.modified)}',
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
    );
  }
}

class _Actions extends StatelessWidget {
  const _Actions({required this.onDelete, required this.onKeep, required this.onUndo});

  final VoidCallback? onDelete;
  final VoidCallback? onKeep;
  final VoidCallback? onUndo;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 18, 0, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _RoundButton(icon: Icons.close_rounded, color: AppColors.delete, size: 64, onTap: onDelete),
          const SizedBox(width: 20),
          _RoundButton(icon: Icons.undo_rounded, color: AppColors.muted, size: 46, onTap: onUndo),
          const SizedBox(width: 20),
          _RoundButton(icon: Icons.check_rounded, color: AppColors.keep, size: 64, onTap: onKeep),
        ],
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.icon,
    required this.color,
    required this.size,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final double size;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Material(
      color: AppColors.surface,
      shape: CircleBorder(
        side: BorderSide(color: color.withValues(alpha: enabled ? 0.3 : 0.1), width: 2),
      ),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox.square(
          dimension: size,
          child: Icon(icon, color: enabled ? color : color.withValues(alpha: 0.3), size: size * 0.45),
        ),
      ),
    );
  }
}

class _EmptyDeck extends StatelessWidget {
  const _EmptyDeck({required this.onReview});

  final VoidCallback onReview;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.line, width: 2),
        borderRadius: BorderRadius.circular(24),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('Acabou por aqui 🎉', style: display(22)),
          const SizedBox(height: 6),
          const Text(
            'Vai pra revisão confirmar o que marcou.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.muted),
          ),
          const SizedBox(height: 18),
          FilledButton(onPressed: onReview, child: const Text('Revisar')),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

import '../format.dart';
import '../media/decision_store.dart';
import '../media/media_library.dart';
import '../theme.dart';
import '../widgets/media_preview.dart';
import '../widgets/swipe_card.dart';
import 'review_screen.dart';

class SwipeScreen extends StatefulWidget {
  const SwipeScreen({
    super.key,
    required this.album,
    required this.title,
    required this.library,
    required this.store,
  });

  final AssetPathEntity album;
  final String title;
  final MediaLibrary library;
  final DecisionStore store;

  @override
  State<SwipeScreen> createState() => _SwipeScreenState();
}

class _SwipeScreenState extends State<SwipeScreen> {
  final _queue = <AssetEntity>[];
  final _history = <AssetEntity>[];
  var _cardKey = GlobalKey<SwipeCardState>();
  int _page = 0;
  bool _exhausted = false;
  bool _loading = false;
  int _generation = 0;

  AssetEntity? get _current => _queue.isEmpty ? null : _queue.first;

  @override
  void initState() {
    super.initState();
    _fill();
  }

  /// Mantém pelo menos alguns itens sem decisão na fila, buscando por página.
  Future<void> _fill() async {
    if (_loading || _exhausted) return;
    _loading = true;
    final generation = _generation;
    while (_queue.length < 8 && !_exhausted) {
      final assets = await widget.library.page(widget.album, _page++);
      if (generation != _generation) return; // um _reload começou no meio
      if (assets.isEmpty) _exhausted = true;
      final seen = _queue.map((a) => a.id).toSet();
      _queue.addAll(
        assets.where((a) => !widget.store.isDecided(a.id) && !seen.contains(a.id)),
      );
    }
    _loading = false;
    if (mounted) setState(() {});
  }

  /// Depois de mandar coisas pra lixeira as páginas mudam; recomeça do zero.
  Future<void> _reload() async {
    _generation++;
    _loading = false;
    _queue.clear();
    _history.clear();
    _page = 0;
    _exhausted = false;
    _cardKey = GlobalKey();
    setState(() {});
    await _fill();
  }

  Future<void> _onSwiped(SwipeDirection direction) async {
    final asset = _current;
    if (asset == null) return;
    final bytes = await widget.library.sizeOf(asset);
    if (direction == SwipeDirection.delete) {
      widget.store.markForDeletion(asset.id, bytes);
    } else {
      widget.store.keep(asset.id);
    }
    setState(() {
      _history.add(asset);
      _queue.removeAt(0);
      _cardKey = GlobalKey();
    });
    _fill();
  }

  void _undo() {
    if (_history.isEmpty) return;
    final last = _history.removeLast();
    widget.store.forget(last.id);
    setState(() {
      _queue.insert(0, last);
      _cardKey = GlobalKey();
    });
  }

  Future<void> _openReview() async {
    final trashedSomething = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ReviewScreen(library: widget.library, store: widget.store),
      ),
    );
    if (trashedSomething ?? false) {
      await _reload();
    } else {
      // Desmarcados na revisão viram "mantidos": tira da fila se estiverem nela.
      setState(() => _queue.removeWhere((a) => widget.store.isDecided(a.id)));
      _fill();
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = _current;
    final next = _queue.length > 1 ? _queue[1] : null;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _TopBar(
              title: widget.title,
              store: widget.store,
              onReview: _openReview,
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: current == null
                    ? _EmptyDeck(loading: _loading || !_exhausted, onReview: _openReview)
                    : Stack(
                        fit: StackFit.expand,
                        children: [
                          if (next != null)
                            Transform.translate(
                              offset: const Offset(0, 14),
                              child: Transform.scale(
                                scale: 0.95,
                                child: _CardFace(
                                  key: ValueKey('next-${next.id}'),
                                  asset: next,
                                  library: widget.library,
                                  albumTitle: widget.title,
                                  active: false,
                                ),
                              ),
                            ),
                          SwipeCard(
                            key: _cardKey,
                            onSwiped: _onSwiped,
                            child: _CardFace(
                              key: ValueKey('top-${current.id}'),
                              asset: current,
                              library: widget.library,
                              albumTitle: widget.title,
                              active: true,
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
                    TextSpan(text: '  ·  toque = som  ·  '),
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
  const _TopBar({required this.title, required this.store, required this.onReview});

  final String title;
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
            child: Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              overflow: TextOverflow.ellipsis,
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
class _CardFace extends StatelessWidget {
  const _CardFace({
    super.key,
    required this.asset,
    required this.library,
    required this.albumTitle,
    required this.active,
  });

  final AssetEntity asset;
  final MediaLibrary library;
  final String albumTitle;
  final bool active;

  bool get _isVideo => asset.type == AssetType.video;

  @override
  Widget build(BuildContext context) {
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
            MediaPreview(asset: asset, active: active),
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
            Positioned(
              top: 14,
              left: 14,
              child: _Badge(
                _isVideo ? '▶ VÍDEO · ${formatDuration(asset.videoDuration)}' : 'FOTO',
              ),
            ),
            Positioned(
              top: 10,
              right: 14,
              child: FutureBuilder<int>(
                future: library.sizeOf(asset),
                builder: (context, snap) => Text(
                  snap.hasData ? formatBytes(snap.data!) : '',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    shadows: [Shadow(color: Colors.black54, blurRadius: 8)],
                  ),
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
                      asset.title ?? '',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${_folderName(asset) ?? albumTitle} · ${formatDate(asset.createDateTime)}',
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

  /// "Android/media/com.whatsapp/WhatsApp/Media/WhatsApp Video/" -> "WhatsApp Video"
  static String? _folderName(AssetEntity asset) {
    final parts = (asset.relativePath ?? '').split('/').where((p) => p.isNotEmpty);
    return parts.isEmpty ? null : parts.last;
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
  const _EmptyDeck({required this.loading, required this.onReview});

  final bool loading;
  final VoidCallback onReview;

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.line, width: 2),
        borderRadius: BorderRadius.circular(24),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text(
            'Acabou o álbum 🎉',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
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

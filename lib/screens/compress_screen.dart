import 'package:flutter/material.dart';

import '../format.dart';
import '../media/compression.dart';
import '../media/decision_store.dart';
import '../media/media_file.dart';
import '../media/media_library.dart';
import '../media/video_compressor.dart';
import '../theme.dart';
import '../widgets/media_thumb.dart';

enum _ItemState { waiting, running, done, light, failed }

class _Item {
  _Item(this.file);

  final MediaFile file;
  CompressionPlan? plan;
  _ItemState state = _ItemState.waiting;
  double progress = 0;
  int saved = 0;
  String? error;
}

/// Fila dos vídeos marcados pra comprimir (swipe pra cima). Roda um por vez,
/// com o app aberto; o original de cada um vai pra lixeira do app.
class CompressScreen extends StatefulWidget {
  const CompressScreen({super.key, required this.library, required this.store});

  final MediaLibrary library;
  final DecisionStore store;

  @override
  State<CompressScreen> createState() => _CompressScreenState();
}

class _CompressScreenState extends State<CompressScreen> {
  late final _compressor = VideoCompressor(widget.library);
  late final List<_Item> _items = [
    for (final path in widget.store.toCompress.keys)
      if (widget.library.byPath(path) case final file?) _Item(file),
  ];
  bool _running = false;
  bool _finished = false;
  bool _cancelRequested = false;

  int get _totalBytes => _items.fold(0, (sum, i) => sum + i.file.size);
  int get _estimatedBytes => _items.fold(0, (sum, i) => sum + (i.plan?.estimatedBytes ?? i.file.size));
  int get _savedBytes => _items.fold(0, (sum, i) => sum + i.saved);

  @override
  void initState() {
    super.initState();
    _loadPlans();
  }

  Future<void> _loadPlans() async {
    for (final item in _items) {
      item.plan = await widget.library.compressionPlan(item.file);
      if (mounted) setState(() {});
    }
  }

  void _remove(_Item item) {
    widget.store.forget(item.file.path);
    setState(() => _items.remove(item));
  }

  Future<void> _run() async {
    setState(() {
      _running = true;
      _cancelRequested = false;
    });
    for (final item in _items.where((i) => i.state == _ItemState.waiting).toList()) {
      if (_cancelRequested || !mounted) break;
      final plan = item.plan ?? await widget.library.compressionPlan(item.file);
      if (plan == null) {
        widget.store.keep(item.file.path);
        setState(() => item.state = _ItemState.light);
        continue;
      }
      setState(() => item.state = _ItemState.running);
      final result = await _compressor.compress(
        item.file,
        plan,
        onProgress: (p) {
          if (mounted) setState(() => item.progress = p);
        },
      );
      if (!mounted) return;
      setState(() {
        switch (result.outcome) {
          case CompressOutcome.compressed:
            item.state = _ItemState.done;
            item.saved = result.savedBytes;
            widget.store.confirmCompressed(item.file.path, result.newFile!.path);
          case CompressOutcome.alreadyLight:
            item.state = _ItemState.light;
            widget.store.keep(item.file.path);
          case CompressOutcome.failed:
            item.state = _ItemState.failed;
            item.error = result.error;
          case CompressOutcome.cancelled:
            item.state = _ItemState.waiting;
            item.progress = 0;
        }
      });
    }
    if (mounted) {
      setState(() {
        _running = false;
        _finished = !_cancelRequested;
      });
    }
  }

  Future<void> _cancel() async {
    setState(() => _cancelRequested = true);
    await _compressor.cancel();
  }

  Future<bool> _confirmLeave() async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Parar a compressão?'),
        content: const Text('O vídeo que tá sendo comprimido agora fica como estava. Os outros continuam na fila.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Continuar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Parar')),
        ],
      ),
    );
    if (leave ?? false) await _cancel();
    return leave ?? false;
  }

  Future<void> _emptyTrash() async {
    final freed = await widget.library.trash.empty();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${formatBytes(freed)} liberados')));
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_running,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmLeave() && context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Comprimir vídeos')),
        body: _items.isEmpty
            ? const Center(
                child: Text('Nada na fila', style: TextStyle(color: AppColors.muted, fontSize: 16)),
              )
            : Column(
                children: [
                  _Summary(
                    count: _items.length,
                    totalBytes: _totalBytes,
                    estimatedBytes: _estimatedBytes,
                    savedBytes: _savedBytes,
                    finished: _finished,
                  ),
                  Expanded(
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                      itemCount: _items.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, i) => _ItemRow(
                        item: _items[i],
                        library: widget.library,
                        onRemove: _running ? null : () => _remove(_items[i]),
                      ),
                    ),
                  ),
                  SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: _finished
                          ? _FinishedActions(
                              trashBytes: widget.library.trash.bytes,
                              onEmptyTrash: _emptyTrash,
                              onDone: () => Navigator.of(context).pop(),
                            )
                          : SizedBox(
                              width: double.infinity,
                              child: FilledButton(
                                style: FilledButton.styleFrom(
                                  backgroundColor: _running ? AppColors.surface2 : AppColors.accent,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                ),
                                onPressed: _running ? (_cancelRequested ? null : _cancel) : _run,
                                child: Text(
                                  _running
                                      ? (_cancelRequested ? 'Parando…' : 'Parar')
                                      : 'Comprimir ${plural(_items.where((i) => i.state == _ItemState.waiting).length, 'vídeo', 'vídeos')}',
                                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                                ),
                              ),
                            ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({
    required this.count,
    required this.totalBytes,
    required this.estimatedBytes,
    required this.savedBytes,
    required this.finished,
  });

  final int count;
  final int totalBytes;
  final int estimatedBytes;
  final int savedBytes;
  final bool finished;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  finished ? '−${formatBytes(savedBytes)}' : '${formatBytes(totalBytes)} → ~${formatBytes(estimatedBytes)}',
                  style: display(24),
                ),
                const SizedBox(height: 4),
                Text(
                  finished
                      ? 'Originais na lixeira do app por 30 dias'
                      : '${plural(count, 'vídeo', 'vídeos')} em 720p. Deixa o app aberto enquanto roda.',
                  style: const TextStyle(color: AppColors.muted, fontSize: 13),
                ),
              ],
            ),
          ),
          const Icon(Icons.compress_rounded, color: AppColors.accent, size: 28),
        ],
      ),
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({required this.item, required this.library, required this.onRemove});

  final _Item item;
  final MediaLibrary library;
  final VoidCallback? onRemove;

  String get _status => switch (item.state) {
        _ItemState.waiting => item.plan == null
            ? formatBytes(item.file.size)
            : '${formatBytes(item.file.size)} → ~${formatBytes(item.plan!.estimatedBytes)}',
        _ItemState.running => 'Comprimindo… ${(item.progress * 100).round()}%',
        _ItemState.done => '−${formatBytes(item.saved)} ✓',
        _ItemState.light => 'Já estava leve, ficou como era',
        _ItemState.failed => 'Erro: ${item.error ?? 'não deu'}',
      };

  Color get _statusColor => switch (item.state) {
        _ItemState.done => AppColors.keep,
        _ItemState.failed => AppColors.delete,
        _ItemState.running => AppColors.accent,
        _ => AppColors.muted,
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox.square(
              dimension: 56,
              child: MediaThumb(path: item.file.path, isVideo: true, thumbnails: library.thumbnails),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.file.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(_status, style: TextStyle(color: _statusColor, fontSize: 12)),
                if (item.state == _ItemState.running) ...[
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: LinearProgressIndicator(
                      value: item.progress,
                      minHeight: 4,
                      color: AppColors.accent,
                      backgroundColor: AppColors.surface2,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (onRemove != null && item.state == _ItemState.waiting)
            IconButton(
              onPressed: onRemove,
              icon: const Icon(Icons.close_rounded, color: AppColors.muted, size: 20),
              tooltip: 'Tirar da fila',
            ),
        ],
      ),
    );
  }
}

class _FinishedActions extends StatelessWidget {
  const _FinishedActions({required this.trashBytes, required this.onEmptyTrash, required this.onDone});

  final int trashBytes;
  final VoidCallback onEmptyTrash;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (trashBytes > 0) ...[
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.delete,
                side: const BorderSide(color: AppColors.delete),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              onPressed: onEmptyTrash,
              child: Text('Esvaziar lixeira agora (${formatBytes(trashBytes)})'),
            ),
          ),
          const SizedBox(height: 10),
        ],
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.keep,
              foregroundColor: const Color(0xFF04210F),
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            onPressed: onDone,
            child: const Text('Pronto', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          ),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';

import '../format.dart';
import '../media/decision_store.dart';
import '../media/duplicate_finder.dart';
import '../media/media_file.dart';
import '../media/media_library.dart';
import '../theme.dart';
import '../widgets/media_thumb.dart';
import 'review_screen.dart';
import 'viewer_screen.dart';

/// Varre a galeria atrás de cópias idênticas e deixa marcar todas
/// (menos uma de cada grupo) de uma vez.
class DuplicatesScreen extends StatefulWidget {
  const DuplicatesScreen({super.key, required this.library, required this.store});

  final MediaLibrary library;
  final DecisionStore store;

  @override
  State<DuplicatesScreen> createState() => _DuplicatesScreenState();
}

class _DuplicatesScreenState extends State<DuplicatesScreen> {
  late final _finder = DuplicateFinder(widget.library.hashCache);
  List<DuplicateGroup>? _groups;
  ScanStage _stage = ScanStage.partial;
  int _done = 0;
  int _total = 0;
  bool _cancelled = false;

  @override
  void initState() {
    super.initState();
    _scan();
  }

  @override
  void dispose() {
    _cancelled = true;
    super.dispose();
  }

  Future<void> _scan() async {
    setState(() => _groups = null);
    final groups = await _finder.scan(
      widget.library.files,
      isCancelled: () => _cancelled,
      onProgress: (stage, done, total) {
        if (!mounted) return;
        setState(() {
          _stage = stage;
          _done = done;
          _total = total;
        });
      },
    );
    if (mounted) setState(() => _groups = groups);
  }

  int get _toFree => _groups!.fold(0, (sum, g) => sum + g.bytesToFree);
  int get _copyCount => _groups!.fold(0, (sum, g) => sum + g.copies.length);

  Future<void> _markAllAndReview() async {
    for (final group in _groups!) {
      for (final copy in group.copies) {
        widget.store.markForDeletion(copy.path, copy.size);
      }
      final keeper = group.keeperPath;
      if (keeper != null) widget.store.keep(keeper);
    }
    final trashed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ReviewScreen(library: widget.library, store: widget.store),
      ),
    );
    if (trashed ?? false) _scan();
  }

  /// Tela cheia pra ver direito o que é (a miniatura não basta).
  void _open(MediaFile file) => Navigator.of(context).push(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => ViewerScreen(
            file: file,
            thumbnails: widget.library.thumbnails,
            onShare: () => widget.library.native.share([file.path]),
            showDecisions: false,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final groups = _groups;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Duplicados'),
      ),
      body: groups == null
          ? _Progress(stage: _stage, done: _done, total: _total)
          : groups.isEmpty
              ? const Center(
                  child: Text('Nenhuma cópia idêntica 🎉', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                )
              : Column(
                  children: [
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        itemCount: groups.length + 1,
                        itemBuilder: (context, i) {
                          if (i == 0) {
                            return _ReviewProgress(
                              reviewed: groups.where((g) => g.reviewed).length,
                              total: groups.length,
                              files: _copyCount,
                              bytes: _toFree,
                            );
                          }
                          final group = groups[i - 1];
                          return _GroupCard(
                            group: group,
                            library: widget.library,
                            onPickKeeper: (path) => setState(() {
                              group.keeperPath = path;
                              group.reviewed = true;
                            }),
                            onToggleDeleteAll: () => setState(() {
                              group.keeperPath = group.deleteAll ? chooseKeeper(group.items).path : null;
                              group.reviewed = true;
                            }),
                            onAccept: () => setState(() => group.reviewed = true),
                            onOpen: _open,
                          );
                        },
                      ),
                    ),
                    SafeArea(
                      top: false,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.delete,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            ),
                            onPressed: _markAllAndReview,
                            child: Text(
                              'Revisar ${plural(_copyCount, 'arquivo', 'arquivos')} · ${formatBytes(_toFree)}',
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
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

class _Progress extends StatelessWidget {
  const _Progress({required this.stage, required this.done, required this.total});

  final ScanStage stage;
  final int done;
  final int total;

  String get _label => switch (stage) {
        ScanStage.partial => 'Comparando começo e fim dos arquivos',
        ScanStage.full => 'Confirmando cópias (hash completo)',
      };

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'Passo ${stage.index + 1} de 2',
            style: const TextStyle(color: AppColors.muted, fontSize: 12, letterSpacing: 1),
          ),
          const SizedBox(height: 6),
          Text(
            _label,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 18),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: total == 0 ? null : done / total,
              minHeight: 6,
              color: AppColors.accent,
              backgroundColor: AppColors.surface2,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            total == 0 ? '' : '${formatCount(done)} de ${formatCount(total)}',
            style: const TextStyle(color: AppColors.muted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

/// "5 de 17 grupos revisados", com barra, e o total que vai sair.
class _ReviewProgress extends StatelessWidget {
  const _ReviewProgress({
    required this.reviewed,
    required this.total,
    required this.files,
    required this.bytes,
  });

  final int reviewed;
  final int total;
  final int files;
  final int bytes;

  @override
  Widget build(BuildContext context) {
    final done = reviewed == total;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(18)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  done ? 'Tudo revisado ✓' : '$reviewed de ${plural(total, 'grupo', 'grupos')} revisados',
                  style: display(17, color: done ? AppColors.keep : AppColors.text),
                ),
              ),
              Text(
                '${plural(files, 'arquivo', 'arquivos')} · ${formatBytes(bytes)}',
                style: const TextStyle(color: AppColors.delete, fontWeight: FontWeight.w700, fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: total == 0 ? 0 : reviewed / total,
              minHeight: 6,
              color: AppColors.keep,
              backgroundColor: AppColors.surface2,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'A verde fica. Toca em outra pra trocar, em "Apagar todas" pra não ficar nenhuma, '
            'ou em "Tá certo" pra aceitar. Segura uma cópia pra ver em tela cheia.',
            style: TextStyle(color: AppColors.muted, fontSize: 12, height: 1.4),
          ),
        ],
      ),
    );
  }
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({
    required this.group,
    required this.library,
    required this.onPickKeeper,
    required this.onToggleDeleteAll,
    required this.onAccept,
    required this.onOpen,
  });

  final DuplicateGroup group;
  final MediaLibrary library;

  /// Tocar numa cópia faz ela ser a que fica (e sai do "apagar todas").
  final ValueChanged<String> onPickKeeper;
  final VoidCallback onToggleDeleteAll;

  /// Aceita a sugestão como está (conta como revisado).
  final VoidCallback onAccept;
  final ValueChanged<MediaFile> onOpen;

  @override
  Widget build(BuildContext context) {
    // Revisado fica mais discreto, pra destacar os que faltam.
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: group.reviewed ? 0.6 : 1,
      child: _card(),
    );
  }

  Widget _card() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: group.deleteAll ? AppColors.delete.withValues(alpha: 0.08) : AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: group.deleteAll ? AppColors.delete.withValues(alpha: 0.5) : Colors.transparent),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  group.deleteAll
                      ? '${group.items.length}× ${formatBytes(group.bytesEach)}  ·  todas saem'
                      : '${group.items.length}× ${formatBytes(group.bytesEach)}'
                          '  ·  ${formatBytes(group.wastedBytes)} sobrando',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: group.deleteAll ? AppColors.delete : AppColors.text,
                  ),
                ),
              ),
              if (group.reviewed)
                const Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: Icon(Icons.check_circle_rounded, color: AppColors.keep, size: 20),
                ),
            ],
          ),
          Row(
            children: [
              TextButton.icon(
                onPressed: onToggleDeleteAll,
                style: TextButton.styleFrom(
                  foregroundColor: group.deleteAll ? AppColors.text : AppColors.delete,
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                icon: Icon(group.deleteAll ? Icons.undo_rounded : Icons.delete_sweep_rounded, size: 18),
                label: Text(group.deleteAll ? 'Manter uma' : 'Apagar todas'),
              ),
              const Spacer(),
              if (!group.reviewed)
                TextButton.icon(
                  onPressed: onAccept,
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.keep,
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  icon: const Icon(Icons.check_rounded, size: 18),
                  label: const Text('Tá certo'),
                ),
            ],
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 132,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: group.items.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final file = group.items[i];
                return _CopyTile(
                  key: ValueKey(file.path),
                  file: file,
                  library: library,
                  isKeeper: file.path == group.keeperPath,
                  onTap: () => onPickKeeper(file.path),
                  onOpen: () => onOpen(file),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _CopyTile extends StatelessWidget {
  const _CopyTile({
    super.key,
    required this.file,
    required this.library,
    required this.isKeeper,
    required this.onTap,
    required this.onOpen,
  });

  final MediaFile file;
  final MediaLibrary library;
  final bool isKeeper;

  /// Tocar escolhe qual fica; segurar (ou o ícone no canto) abre em tela cheia.
  final VoidCallback onTap;
  final VoidCallback onOpen;

  /// ".../WhatsApp Video/Sent/x.mp4" -> "WhatsApp Video/Sent"
  String get _folder {
    final parts = file.folder.split('/').where((p) => p.isNotEmpty).toList();
    return parts.length <= 2 ? parts.join('/') : parts.sublist(parts.length - 2).join('/');
  }

  @override
  Widget build(BuildContext context) {
    final color = isKeeper ? AppColors.keep : AppColors.delete;
    return GestureDetector(
      onTap: onTap,
      onLongPress: onOpen,
      child: SizedBox(
        width: 96,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: color, width: 3),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(7),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Opacity(
                      opacity: isKeeper ? 1 : 0.5,
                      child: MediaThumb(
                        path: file.path,
                        isVideo: file.isVideo,
                        thumbnails: library.thumbnails,
                      ),
                    ),
                    Positioned(
                      left: 4,
                      top: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(5)),
                        child: Text(
                          isKeeper ? 'FICA' : 'SAI',
                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.white),
                        ),
                      ),
                    ),
                    // abre em tela cheia (com área de toque maior que o ícone)
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: GestureDetector(
                        onTap: onOpen,
                        behavior: HitTestBehavior.opaque,
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                            child: Icon(
                              file.isVideo ? Icons.play_arrow_rounded : Icons.open_in_full_rounded,
                              size: 14,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _folder,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.muted, fontSize: 10, height: 1.2),
            ),
          ],
        ),
      ),
    );
  }
}

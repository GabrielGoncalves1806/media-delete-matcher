import 'package:flutter/material.dart';

import '../format.dart';
import '../media/decision_store.dart';
import '../media/duplicate_finder.dart';
import '../media/media_file.dart';
import '../media/media_library.dart';
import '../media/similar_finder.dart';
import '../theme.dart';
import '../widgets/media_thumb.dart';
import 'review_screen.dart';
import 'viewer_screen.dart';

/// Cópias pra limpar, em duas abas: idênticas (byte a byte) e parecidas
/// (o mesmo vídeo recomprimido, a mesma foto em outra resolução, rajada...).
class DuplicatesScreen extends StatelessWidget {
  const DuplicatesScreen({
    super.key,
    required this.library,
    required this.store,
  });

  final MediaLibrary library;
  final DecisionStore store;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Duplicados'),
          bottom: const TabBar(
            indicatorColor: AppColors.accent,
            labelColor: AppColors.text,
            unselectedLabelColor: AppColors.muted,
            tabs: [
              Tab(text: 'Idênticos'),
              Tab(text: 'Parecidos'),
            ],
          ),
        ),
        // A aba de parecidos só começa a calcular quando é aberta (TabBarView
        // só monta a aba visível), e cada aba guarda o resultado ao trocar.
        body: TabBarView(
          children: [
            _GroupsTab(library: library, store: store, similar: false),
            _GroupsTab(library: library, store: store, similar: true),
          ],
        ),
      ),
    );
  }
}

class _GroupsTab extends StatefulWidget {
  const _GroupsTab({
    required this.library,
    required this.store,
    required this.similar,
  });

  final MediaLibrary library;
  final DecisionStore store;
  final bool similar;

  @override
  State<_GroupsTab> createState() => _GroupsTabState();
}

class _GroupsTabState extends State<_GroupsTab>
    with AutomaticKeepAliveClientMixin {
  List<DuplicateGroup>? _groups;
  String _step = '';
  String _label = 'Preparando…';
  int _done = 0;
  int _total = 0;
  bool _cancelled = false;

  @override
  bool get wantKeepAlive => true;

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

  void _progress(String step, String label, int done, int total) {
    if (!mounted) return;
    setState(() {
      _step = step;
      _label = label;
      _done = done;
      _total = total;
    });
  }

  Future<void> _scan() async {
    setState(() => _groups = null);
    final library = widget.library;
    final List<DuplicateGroup> groups;
    if (widget.similar) {
      groups = await SimilarFinder(library.native, library.fingerprintCache)
          .scan(
            library.files,
            isCancelled: () => _cancelled,
            onProgress: (stage, done, total) => switch (stage) {
              SimilarStage.reading => _progress(
                'Passo 1 de 2',
                'Lendo a "impressão digital" de cada foto e vídeo',
                done,
                total,
              ),
              SimilarStage.comparing => _progress(
                'Passo 2 de 2',
                'Comparando o que parece com o quê',
                0,
                0,
              ),
            },
          );
    } else {
      groups = await DuplicateFinder(library.hashCache).scan(
        library.files,
        isCancelled: () => _cancelled,
        onProgress: (stage, done, total) => switch (stage) {
          ScanStage.partial => _progress(
            'Passo 1 de 2',
            'Comparando começo e fim dos arquivos',
            done,
            total,
          ),
          ScanStage.full => _progress(
            'Passo 2 de 2',
            'Confirmando cópias (hash completo)',
            done,
            total,
          ),
        },
      );
    }
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
        builder: (_) =>
            ReviewScreen(library: widget.library, store: widget.store),
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
    super.build(context);
    final groups = _groups;
    return groups == null
        ? _Progress(step: _step, label: _label, done: _done, total: _total)
        : groups.isEmpty
        ? Center(
            child: Text(
              widget.similar ? 'Nada parecido 🎉' : 'Nenhuma cópia idêntica 🎉',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
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
                        group.keeperPath = group.deleteAll
                            ? chooseKeeper(group.items).path
                            : null;
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
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      onPressed: _markAllAndReview,
                      child: Text(
                        'Revisar ${plural(_copyCount, 'arquivo', 'arquivos')} · ${formatBytes(_toFree)}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
  }
}

class _Progress extends StatelessWidget {
  const _Progress({
    required this.step,
    required this.label,
    required this.done,
    required this.total,
  });

  final String step;
  final String label;
  final int done;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            step,
            style: const TextStyle(
              color: AppColors.muted,
              fontSize: 12,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
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
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  done
                      ? 'Tudo revisado ✓'
                      : '$reviewed de ${plural(total, 'grupo', 'grupos')} revisados',
                  style: display(
                    17,
                    color: done ? AppColors.keep : AppColors.text,
                  ),
                ),
              ),
              Text(
                '${plural(files, 'arquivo', 'arquivos')} · ${formatBytes(bytes)}',
                style: const TextStyle(
                  color: AppColors.delete,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
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
        color: group.deleteAll
            ? AppColors.delete.withValues(alpha: 0.08)
            : AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: group.deleteAll
              ? AppColors.delete.withValues(alpha: 0.5)
              : Colors.transparent,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  switch ((group.similar, group.deleteAll)) {
                    (true, true) =>
                      '${group.items.length} parecidos  ·  todos saem',
                    (true, false) =>
                      '${group.items.length} parecidos  ·  ${formatBytes(group.wastedBytes)} sobrando',
                    (false, true) =>
                      '${group.items.length}× ${formatBytes(group.bytesEach)}  ·  todas saem',
                    (false, false) =>
                      '${group.items.length}× ${formatBytes(group.bytesEach)}'
                          '  ·  ${formatBytes(group.wastedBytes)} sobrando',
                  },
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: group.deleteAll ? AppColors.delete : AppColors.text,
                  ),
                ),
              ),
              if (group.reviewed)
                const Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: Icon(
                    Icons.check_circle_rounded,
                    color: AppColors.keep,
                    size: 20,
                  ),
                ),
            ],
          ),
          Row(
            children: [
              TextButton.icon(
                onPressed: onToggleDeleteAll,
                style: TextButton.styleFrom(
                  foregroundColor: group.deleteAll
                      ? AppColors.text
                      : AppColors.delete,
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                icon: Icon(
                  group.deleteAll
                      ? Icons.undo_rounded
                      : Icons.delete_sweep_rounded,
                  size: 18,
                ),
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
            height: group.similar ? 150 : 132, // parecidos têm a linha do tamanho
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
                  showSize:
                      group.similar, // nos parecidos o tamanho de cada um varia
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
    this.showSize = false,
  });

  final MediaFile file;
  final MediaLibrary library;
  final bool isKeeper;
  final bool showSize;

  /// Tocar escolhe qual fica; segurar (ou o ícone no canto) abre em tela cheia.
  final VoidCallback onTap;
  final VoidCallback onOpen;

  /// ".../WhatsApp Video/Sent/x.mp4" -> "WhatsApp Video/Sent"
  String get _folder {
    final parts = file.folder.split('/').where((p) => p.isNotEmpty).toList();
    return parts.length <= 2
        ? parts.join('/')
        : parts.sublist(parts.length - 2).join('/');
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
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          isKeeper ? 'FICA' : 'SAI',
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
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
                            decoration: const BoxDecoration(
                              color: Colors.black54,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              file.isVideo
                                  ? Icons.play_arrow_rounded
                                  : Icons.open_in_full_rounded,
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
            if (showSize)
              Text(
                formatBytes(file.size),
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            Text(
              _folder,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.muted,
                fontSize: 10,
                height: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

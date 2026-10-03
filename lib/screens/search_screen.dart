import 'package:flutter/material.dart';

import '../format.dart';
import '../media/decision_store.dart';
import '../media/media_file.dart';
import '../media/media_filter.dart';
import '../media/media_library.dart';
import '../media/search.dart';
import '../theme.dart';
import '../widgets/album_widgets.dart';
import '../widgets/media_thumb.dart';
import '../widgets/swipe_card.dart';
import 'move_flow.dart';
import 'swipe_screen.dart';
import 'viewer_screen.dart';

/// Busca por nome ou pasta, com os mesmos filtros da home, e ação em lote:
/// segurar seleciona; dá pra marcar pra apagar, mover pro cartão ou comprimir.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key, required this.library, required this.store});

  final MediaLibrary library;
  final DecisionStore store;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _query = TextEditingController();
  MediaFilter _filter = MediaFilter.none;
  SearchSort _sort = SearchSort.largest;

  /// null = celular e cartão.
  String? _volume;
  final _selected = <String>{};

  MediaLibrary get _library => widget.library;
  bool get _selecting => _selected.isNotEmpty;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  List<MediaFile> get _results => searchFiles(
        _library.files,
        query: _query.text,
        filter: _filter,
        volume: _volume,
        sort: _sort,
        roots: _library.roots,
      );

  void _toggle(String path) => setState(() {
        if (!_selected.remove(path)) _selected.add(path);
      });

  Future<void> _open(MediaFile file) async {
    final decision = await Navigator.of(context).push<SwipeDirection>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => ViewerScreen(
          file: file,
          thumbnails: _library.thumbnails,
          onShare: () => _library.native.share([file.path]),
        ),
      ),
    );
    if (decision == SwipeDirection.delete) widget.store.markForDeletion(file.path, file.size);
    if (decision == SwipeDirection.keep) widget.store.keep(file.path);
  }

  Future<void> _swipeResults(List<MediaFile> results) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SwipeScreen(
          files: results,
          title: _query.text.trim().isEmpty ? 'Busca' : '"${_query.text.trim()}"',
          library: _library,
          store: widget.store,
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  List<MediaFile> get _selectedFiles => [for (final path in _selected) ?_library.byPath(path)];

  void _markSelected() {
    final files = _selectedFiles;
    for (final f in files) {
      widget.store.markForDeletion(f.path, f.size);
    }
    _finish('${plural(files.length, 'item marcado', 'itens marcados')} pra apagar · confirma na revisão');
  }

  void _compressSelected() {
    final videos = _selectedFiles.where((f) => f.isVideo).toList();
    for (final f in videos) {
      widget.store.markForCompression(f.path, f.size);
    }
    _finish(videos.isEmpty
        ? 'Nenhum vídeo na seleção'
        : '${plural(videos.length, 'vídeo', 'vídeos')} na fila de compressão');
  }

  Future<void> _moveSelected() async {
    final moved = await moveToCard(context, _library, widget.store, _selectedFiles);
    if (!mounted) return;
    setState(() => _selected.removeAll(moved));
  }

  /// Compartilha e mantém a seleção (dá pra mandar pra mais de uma pessoa).
  void _shareSelected() => _library.native.share([for (final f in _selectedFiles) f.path]);

  void _finish(String message) {
    setState(_selected.clear);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _pickYear() async {
    final filter = await pickYear(context, _filter, _library.oldestYear);
    if (filter != null) setState(() => _filter = filter);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(_selected.clear); // voltar primeiro limpa a seleção
      },
      child: Scaffold(
        appBar: _selecting
            ? AppBar(
                leading: IconButton(
                  onPressed: () => setState(_selected.clear),
                  icon: const Icon(Icons.close_rounded),
                ),
                title: Text('${_selected.length} selecionados'),
                actions: [
                  TextButton(
                    onPressed: () => setState(() => _selected.addAll(_results.map((f) => f.path))),
                    child: const Text('Todos'),
                  ),
                ],
              )
            : AppBar(
                titleSpacing: 0,
                title: TextField(
                  controller: _query,
                  autofocus: true,
                  textInputAction: TextInputAction.search,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Nome ou pasta (ex.: VID-2024, Camera)',
                    border: InputBorder.none,
                    suffixIcon: _query.text.isEmpty
                        ? null
                        : IconButton(
                            onPressed: () => setState(_query.clear),
                            icon: const Icon(Icons.close_rounded, color: AppColors.muted),
                          ),
                  ),
                ),
              ),
        body: ListenableBuilder(
          listenable: widget.store,
          builder: (context, _) {
            final results = _results;
            final bytes = results.fold(0, (sum, f) => sum + f.size);
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                  child: FilterBar(
                    filter: _filter,
                    onChanged: (f) => setState(() => _filter = f),
                    onPickYear: _pickYear,
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 34,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: [
                      for (final (sort, label) in [
                        (SearchSort.largest, 'Maiores'),
                        (SearchSort.newest, 'Mais recentes'),
                        (SearchSort.oldest, 'Mais antigos'),
                      ])
                        _SmallChip(label: label, selected: _sort == sort, onTap: () => setState(() => _sort = sort)),
                      if (hasCard(_library)) ...[
                        const SizedBox(width: 10),
                        _SmallChip(label: 'Celular', selected: _volume == _library.root, onTap: () {
                          setState(() => _volume = _volume == _library.root ? null : _library.root);
                        }),
                        _SmallChip(
                          label: 'Cartão',
                          selected: _volume != null && _volume != _library.root,
                          onTap: () {
                            final card = _library.roots.skip(1).first;
                            setState(() => _volume = _volume == card ? null : card);
                          },
                        ),
                      ],
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 8, 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${plural(results.length, 'arquivo', 'arquivos')} · ${formatBytes(bytes)}',
                          style: const TextStyle(color: AppColors.muted),
                        ),
                      ),
                      if (results.isNotEmpty && !_selecting)
                        TextButton.icon(
                          onPressed: () => _swipeResults(results),
                          icon: const Icon(Icons.swipe_rounded, size: 18),
                          label: const Text('Swipe nesses'),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: results.isEmpty
                      ? const Center(
                          child: Text('Nada encontrado', style: TextStyle(color: AppColors.muted, fontSize: 16)),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
                          itemCount: results.length,
                          itemBuilder: (context, i) {
                            final file = results[i];
                            return _ResultRow(
                              key: ValueKey(file.path),
                              file: file,
                              library: _library,
                              status: _statusOf(file),
                              selected: _selected.contains(file.path),
                              onTap: () => _selecting ? _toggle(file.path) : _open(file),
                              onLongPress: () => _toggle(file.path),
                            );
                          },
                        ),
                ),
                if (_selecting)
                  SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                      child: Row(
                        children: [
                          _BulkAction(
                            icon: Icons.share_rounded,
                            label: 'Enviar',
                            color: AppColors.sky,
                            onTap: _shareSelected,
                          ),
                          _BulkAction(
                            icon: Icons.delete_outline_rounded,
                            label: 'Apagar',
                            color: AppColors.delete,
                            onTap: _markSelected,
                          ),
                          if (hasCard(_library))
                            _BulkAction(
                              icon: Icons.sd_card_rounded,
                              label: 'Pro cartão',
                              color: AppColors.warn,
                              onTap: _moveSelected,
                            ),
                          _BulkAction(
                            icon: Icons.compress_rounded,
                            label: 'Comprimir',
                            color: AppColors.accent,
                            onTap: _compressSelected,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Etiqueta do que já foi decidido sobre o arquivo.
  ({String label, Color color})? _statusOf(MediaFile file) {
    final store = widget.store;
    if (store.marked.containsKey(file.path)) return (label: 'marcado', color: AppColors.delete);
    if (store.toCompress.containsKey(file.path)) return (label: 'comprimir', color: AppColors.accent);
    if (store.kept.contains(file.path)) return (label: 'mantido', color: AppColors.keep);
    return null;
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({
    super.key,
    required this.file,
    required this.library,
    required this.status,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
  });

  final MediaFile file;
  final MediaLibrary library;
  final ({String label, Color color})? status;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final status = this.status;
    return Material(
      color: selected ? AppColors.accent.withValues(alpha: 0.16) : Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox.square(
                  dimension: 56,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      MediaThumb(path: file.path, isVideo: file.isVideo, thumbnails: library.thumbnails),
                      if (file.isVideo)
                        const Positioned(
                          right: 3,
                          bottom: 2,
                          child: Icon(
                            Icons.play_arrow_rounded,
                            size: 16,
                            shadows: [Shadow(color: Colors.black87, blurRadius: 4)],
                          ),
                        ),
                      if (selected)
                        const ColoredBox(
                          color: Colors.black45,
                          child: Center(child: Icon(Icons.check_circle_rounded, color: AppColors.accent)),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(file.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(
                      '${library.isRemovable(file.path) ? 'SD · ' : ''}${file.folderName} · ${formatDate(file.modified)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppColors.muted, fontSize: 12),
                    ),
                    if (status != null) ...[
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: status.color.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          status.label,
                          style: TextStyle(color: status.color, fontSize: 10, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(formatBytes(file.size), style: display(15)),
            ],
          ),
        ),
      ),
    );
  }
}

class _SmallChip extends StatelessWidget {
  const _SmallChip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? AppColors.accent.withValues(alpha: 0.2) : Colors.transparent,
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: selected ? AppColors.accent : AppColors.line),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? AppColors.text : AppColors.muted,
            ),
          ),
        ),
      ),
    );
  }
}

class _BulkAction extends StatelessWidget {
  const _BulkAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Material(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(
                children: [
                  Icon(icon, color: color, size: 22),
                  const SizedBox(height: 4),
                  Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

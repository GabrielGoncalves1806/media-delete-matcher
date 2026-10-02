import 'package:flutter/material.dart';

import '../format.dart';
import '../media/media_library.dart';
import '../media/trash_bin.dart';
import '../theme.dart';
import '../widgets/media_thumb.dart';

/// Lixeira do app: restaurar um item, apagar de vez ou esvaziar tudo.
/// Devolve `true` pro Navigator se algo foi restaurado (precisa reler o armazenamento).
class TrashScreen extends StatefulWidget {
  const TrashScreen({super.key, required this.library});

  final MediaLibrary library;

  @override
  State<TrashScreen> createState() => _TrashScreenState();
}

class _TrashScreenState extends State<TrashScreen> {
  bool _restored = false;
  bool _busy = false;

  List<TrashEntry> get _entries =>
      widget.library.trash.entries.toList()..sort((a, b) => b.trashedAt.compareTo(a.trashedAt));

  Future<void> _emptyAll() async {
    final trash = widget.library.trash;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Esvaziar a lixeira?'),
        content: Text(
          '${plural(trash.entries.length, 'item', 'itens')} · ${formatBytes(trash.bytes)} '
          'apagados de vez. Não dá pra desfazer.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.delete),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Esvaziar'),
          ),
        ],
      ),
    );
    if (!(ok ?? false)) return;
    setState(() => _busy = true);
    final freed = await trash.empty();
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${formatBytes(freed)} liberados')),
    );
  }

  Future<void> _openEntry(TrashEntry entry) async {
    final trash = widget.library.trash;
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surface,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(entry.originalName, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                '${formatBytes(entry.size)} · ${_daysLeft(entry)}\n${entry.originalPath}',
                style: const TextStyle(color: AppColors.muted, fontSize: 12),
              ),
              isThreeLine: true,
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.restore_rounded, color: AppColors.keep),
              title: const Text('Restaurar pro lugar original'),
              onTap: () => Navigator.pop(context, 'restore'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_forever_rounded, color: AppColors.delete),
              title: const Text('Apagar de vez'),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;

    if (action == 'restore') {
      final ok = await trash.restore(entry);
      if (!mounted) return;
      if (ok) _restored = true;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ok ? 'Restaurado' : 'Já existe um arquivo com esse nome lá'),
        ),
      );
    } else {
      await trash.delete([entry]);
    }
    if (mounted) setState(() {});
  }

  static String _daysLeft(TrashEntry entry) {
    final left = TrashBin.keepFor - DateTime.now().difference(entry.trashedAt);
    final days = left.inDays;
    return days <= 0 ? 'some hoje' : 'some em ${plural(days, 'dia', 'dias')}';
  }

  @override
  Widget build(BuildContext context) {
    final trash = widget.library.trash;
    final entries = _entries;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_restored);
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Lixeira', style: TextStyle(fontWeight: FontWeight.w700)),
        ),
        body: entries.isEmpty
            ? const Center(
                child: Text('Lixeira vazia', style: TextStyle(color: AppColors.muted, fontSize: 16)),
              )
            : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Text(
                      '${plural(entries.length, 'item', 'itens')} · ${formatBytes(trash.bytes)} '
                      'ocupando espaço. Toca num item pra restaurar.',
                      style: const TextStyle(color: AppColors.muted),
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
                      itemCount: entries.length,
                      itemBuilder: (context, i) {
                        final entry = entries[i];
                        return GestureDetector(
                          key: ValueKey(entry.fileName),
                          onTap: () => _openEntry(entry),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                MediaThumb(
                                  path: trash.pathOf(entry),
                                  isVideo: entry.isVideo,
                                  thumbnails: widget.library.thumbnails,
                                ),
                                Positioned(
                                  left: 6,
                                  bottom: 4,
                                  child: Text(
                                    formatBytes(entry.size),
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      shadows: [Shadow(color: Colors.black87, blurRadius: 4)],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
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
                          onPressed: _busy ? null : _emptyAll,
                          child: Text(
                            _busy ? 'Esvaziando…' : 'Esvaziar tudo · liberar ${formatBytes(trash.bytes)}',
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

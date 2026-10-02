import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

import '../format.dart';
import '../media/decision_store.dart';
import '../media/duplicate_finder.dart';
import '../media/media_library.dart';
import '../theme.dart';
import 'review_screen.dart';

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
  late final _finder = DuplicateFinder(widget.library);
  List<DuplicateGroup>? _groups;
  ScanStage _stage = ScanStage.sizes;
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

  int get _wasted => _groups!.fold(0, (sum, g) => sum + g.wastedBytes);
  int get _copyCount => _groups!.fold(0, (sum, g) => sum + g.items.length - 1);

  Future<void> _markAllAndReview() async {
    for (final group in _groups!) {
      for (final copy in group.copies) {
        widget.store.markForDeletion(copy.id, group.bytesEach);
      }
      widget.store.keep(group.keeperId);
    }
    final trashed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ReviewScreen(library: widget.library, store: widget.store),
      ),
    );
    if (trashed ?? false) _scan();
  }

  @override
  Widget build(BuildContext context) {
    final groups = _groups;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Duplicados', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: groups == null
          ? _Progress(stage: _stage, done: _done, total: _total)
          : groups.isEmpty
              ? const Center(
                  child: Text(
                    'Nenhuma cópia idêntica 🎉',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
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
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 14),
                              child: Text.rich(
                                TextSpan(
                                  children: [
                                    TextSpan(
                                      text: '${plural(_copyCount, 'cópia', 'cópias')} · ${formatBytes(_wasted)}',
                                      style: const TextStyle(
                                        color: AppColors.delete,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    TextSpan(
                                      text: ' em ${plural(groups.length, 'grupo', 'grupos')}. '
                                          'A verde fica; toca em outra pra trocar.',
                                    ),
                                  ],
                                ),
                                style: const TextStyle(color: AppColors.muted),
                              ),
                            );
                          }
                          final group = groups[i - 1];
                          return _GroupCard(
                            group: group,
                            onPickKeeper: (id) => setState(() => group.keeperId = id),
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
                              'Manter 1 de cada · revisar ${plural(_copyCount, 'cópia', 'cópias')}',
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
        ScanStage.sizes => 'Lendo tamanhos',
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
            'Passo ${stage.index + 1} de 3',
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

class _GroupCard extends StatelessWidget {
  const _GroupCard({required this.group, required this.onPickKeeper});

  final DuplicateGroup group;
  final ValueChanged<String> onPickKeeper;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${group.items.length}× ${formatBytes(group.bytesEach)}'
            '  ·  ${formatBytes(group.wastedBytes)} sobrando',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 132,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: group.items.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final asset = group.items[i];
                return _CopyTile(
                  key: ValueKey(asset.id),
                  asset: asset,
                  isKeeper: asset.id == group.keeperId,
                  onTap: () => onPickKeeper(asset.id),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _CopyTile extends StatefulWidget {
  const _CopyTile({
    super.key,
    required this.asset,
    required this.isKeeper,
    required this.onTap,
  });

  final AssetEntity asset;
  final bool isKeeper;
  final VoidCallback onTap;

  @override
  State<_CopyTile> createState() => _CopyTileState();
}

class _CopyTileState extends State<_CopyTile> {
  Uint8List? _thumb;

  @override
  void initState() {
    super.initState();
    widget.asset.thumbnailDataWithSize(const ThumbnailSize.square(240)).then((data) {
      if (mounted) setState(() => _thumb = data);
    });
  }

  /// "Android/media/com.whatsapp/WhatsApp/Media/WhatsApp Video/Sent/" -> "WhatsApp Video/Sent"
  String get _folder {
    final parts = (widget.asset.relativePath ?? '').split('/').where((p) => p.isNotEmpty).toList();
    return parts.length <= 2 ? parts.join('/') : parts.sublist(parts.length - 2).join('/');
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.isKeeper ? AppColors.keep : AppColors.delete;
    return GestureDetector(
      onTap: widget.onTap,
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
                    const ColoredBox(color: AppColors.surface2),
                    if (_thumb != null)
                      Opacity(
                        opacity: widget.isKeeper ? 1 : 0.5,
                        child: Image.memory(_thumb!, fit: BoxFit.cover, gaplessPlayback: true),
                      ),
                    Positioned(
                      left: 4,
                      top: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(5)),
                        child: Text(
                          widget.isKeeper ? 'FICA' : 'SAI',
                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.white),
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

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

import '../format.dart';
import '../media/decision_store.dart';
import '../media/media_filter.dart';
import '../media/media_library.dart';
import '../theme.dart';
import 'duplicates_screen.dart';
import 'review_screen.dart';
import 'swipe_screen.dart';

enum _Status { loading, noAccess, ready }

/// Mapa da galeria: quanto cada álbum pesa e por onde começar.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.library, required this.store});

  final MediaLibrary library;
  final DecisionStore store;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  _Status _status = _Status.loading;
  AssetPathEntity? _all;
  List<AssetPathEntity> _albums = [];
  final _counts = <String, int>{};
  final _sizes = <String, int>{};
  int _generation = 0;
  MediaFilter _filter = MediaFilter.none;
  int _oldestYear = DateTime.now().year;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _generation++; // cancela a soma de tamanhos em andamento
    super.dispose();
  }

  Future<void> _init() async {
    final ok = await widget.library.requestAccess();
    if (!mounted) return;
    if (!ok) {
      setState(() => _status = _Status.noAccess);
      return;
    }
    widget.library.oldestYear().then((year) {
      if (mounted) setState(() => _oldestYear = year);
    });
    await _load();
  }

  void _setFilter(MediaFilter filter) {
    if (filter == _filter) return;
    setState(() => _filter = filter);
    _load();
  }

  Future<void> _pickYear() async {
    final years = [for (var y = DateTime.now().year; y >= _oldestYear; y--) y];
    final picked = await showModalBottomSheet<int?>(
      context: context,
      backgroundColor: AppColors.surface,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              title: const Text('Todos os anos'),
              trailing: _filter.year == null ? const Icon(Icons.check_rounded) : null,
              onTap: () => Navigator.pop(context, -1),
            ),
            for (final y in years)
              ListTile(
                title: Text('$y'),
                trailing: _filter.year == y ? const Icon(Icons.check_rounded) : null,
                onTap: () => Navigator.pop(context, y),
              ),
          ],
        ),
      ),
    );
    if (picked == null) return; // fechou sem escolher
    _setFilter(_filter.copyWith(year: () => picked == -1 ? null : picked));
  }

  Future<void> _load() async {
    final generation = ++_generation;
    final paths = await widget.library.albums(filter: _filter);
    final counts = await Future.wait(paths.map((p) => p.assetCountAsync));
    if (!mounted || generation != _generation) return;

    setState(() {
      _status = _Status.ready;
      _all = paths.where((p) => p.isAll).firstOrNull;
      _albums = paths.where((p) => !p.isAll).toList();
      _counts
        ..clear()
        ..addEntries([for (var i = 0; i < paths.length; i++) MapEntry(paths[i].id, counts[i])]);
      _sizes.clear();
    });

    // Soma os tamanhos em segundo plano, um álbum por vez (maiores em itens primeiro).
    final byCount = [..._albums]..sort((a, b) => _counts[b.id]!.compareTo(_counts[a.id]!));
    for (final album in byCount) {
      final size = await widget.library.totalSize(
        album,
        isCancelled: () => !mounted || generation != _generation,
      );
      if (!mounted || generation != _generation) return;
      setState(() => _sizes[album.id] = size);
    }
  }

  bool get _allSized => _albums.every((a) => _sizes.containsKey(a.id));
  int get _totalBytes => _sizes.values.fold(0, (a, b) => a + b);

  List<AssetPathEntity> get _sortedAlbums {
    int key(AssetPathEntity a) => _sizes[a.id] ?? -1;
    return [..._albums]..sort((a, b) {
        final bySize = key(b).compareTo(key(a));
        return bySize != 0 ? bySize : _counts[b.id]!.compareTo(_counts[a.id]!);
      });
  }

  Future<void> _openSwipe(AssetPathEntity album, String title) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SwipeScreen(
          album: album,
          title: title,
          library: widget.library,
          store: widget.store,
        ),
      ),
    );
    _load(); // algo pode ter ido pra lixeira
  }

  Future<void> _openDuplicates() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DuplicatesScreen(library: widget.library, store: widget.store),
      ),
    );
    _load();
  }

  Future<void> _openReview() async {
    final trashed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ReviewScreen(library: widget.library, store: widget.store),
      ),
    );
    if (trashed ?? false) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: switch (_status) {
          _Status.loading => const Center(child: CircularProgressIndicator()),
          _Status.noAccess => _NoAccess(
              onSettings: widget.library.openSettings,
              onRetry: _init,
            ),
          _Status.ready => _buildReady(),
        },
      ),
    );
  }

  Widget _buildReady() {
    final all = _all;
    final totalCount = all == null ? 0 : _counts[all.id] ?? 0;
    final maxSize = _sizes.values.fold(1, (a, b) => a > b ? a : b);

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          const Text(
            'Mídias',
            style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -0.5),
          ),
          const SizedBox(height: 14),
          _SummaryCard(
            totalLabel: _allSized ? formatBytes(_totalBytes) : '${formatBytes(_totalBytes)}…',
            countLabel: _filter.isEmpty
                ? 'em ${plural(totalCount, 'foto ou vídeo', 'fotos e vídeos')}'
                : 'em ${plural(totalCount, 'item', 'itens')} · ${_filter.label}',
            freedBytes: widget.store.freedBytes,
          ),
          ListenableBuilder(
            listenable: widget.store,
            builder: (context, _) => widget.store.markedCount == 0
                ? const SizedBox.shrink()
                : _PendingCard(store: widget.store, onTap: _openReview),
          ),
          const SizedBox(height: 14),
          if (Platform.isAndroid) ...[
            _FilterBar(filter: _filter, onChanged: _setFilter, onPickYear: _pickYear),
            const SizedBox(height: 12),
          ],
          if (all != null)
            _AllButton(
              subtitle: '${plural(totalCount, 'item', 'itens')}'
                  '${_allSized ? ' · ${formatBytes(_totalBytes)}' : ''}',
              onTap: () => _openSwipe(all, _filter.isEmpty ? 'Tudo' : 'Tudo · ${_filter.label}'),
            )
          else
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text('Nada com esse filtro', style: TextStyle(color: AppColors.muted)),
              ),
            ),
          const SizedBox(height: 10),
          _DuplicatesButton(onTap: _openDuplicates),
          const SizedBox(height: 20),
          const Text(
            'ÁLBUNS',
            style: TextStyle(color: AppColors.muted, fontSize: 12, letterSpacing: 1),
          ),
          const SizedBox(height: 6),
          for (final album in _sortedAlbums)
            _AlbumRow(
              name: album.name,
              count: _counts[album.id] ?? 0,
              bytes: _sizes[album.id],
              fraction: (_sizes[album.id] ?? 0) / maxSize,
              onTap: () => _openSwipe(
                album,
                _filter.isEmpty ? album.name : '${album.name} · ${_filter.label}',
              ),
            ),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.totalLabel,
    required this.countLabel,
    required this.freedBytes,
  });

  final String totalLabel;
  final String countLabel;
  final int freedBytes;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(totalLabel, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
          Text(countLabel, style: const TextStyle(color: AppColors.muted, fontSize: 13)),
          if (freedBytes > 0) ...[
            const SizedBox(height: 8),
            Text(
              '♻ ${formatBytes(freedBytes)} já liberados',
              style: const TextStyle(color: AppColors.keep, fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ],
        ],
      ),
    );
  }
}

class _PendingCard extends StatelessWidget {
  const _PendingCard({required this.store, required this.onTap});

  final DecisionStore store;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Material(
        color: AppColors.delete.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                const Text('🗑', style: TextStyle(fontSize: 20)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '${plural(store.markedCount, 'marcado', 'marcados')} · ${formatBytes(store.markedBytes)}',
                    style: const TextStyle(color: AppColors.delete, fontWeight: FontWeight.w700),
                  ),
                ),
                const Text(
                  'Revisar ›',
                  style: TextStyle(color: AppColors.delete, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AllButton extends StatelessWidget {
  const _AllButton({required this.subtitle, required this.onTap});

  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: const LinearGradient(colors: [AppColors.delete, Color(0xFFFF7A45)]),
        ),
        child: Row(
          children: [
            const Text('🔥', style: TextStyle(fontSize: 26)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    Theme.of(context).platform == TargetPlatform.android
                        ? 'Tudo, maiores primeiro'
                        : 'Tudo',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: Colors.white),
                  ),
                  Text(subtitle, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: Colors.white),
          ],
        ),
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({required this.filter, required this.onChanged, required this.onPickYear});

  final MediaFilter filter;
  final ValueChanged<MediaFilter> onChanged;
  final VoidCallback onPickYear;

  @override
  Widget build(BuildContext context) {
    Widget kind(String label, MediaKind kind) => _Chip(
          label: label,
          selected: filter.kind == kind,
          onTap: () => onChanged(filter.copyWith(kind: kind)),
        );

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          kind('Todos', MediaKind.all),
          kind('Vídeos', MediaKind.videos),
          kind('Fotos', MediaKind.photos),
          _Chip(
            label: '> 50 MB',
            selected: filter.bigOnly,
            onTap: () => onChanged(filter.copyWith(bigOnly: !filter.bigOnly)),
          ),
          _Chip(
            label: filter.year == null ? 'Ano ▾' : '${filter.year} ▾',
            selected: filter.year != null,
            onTap: onPickYear,
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? AppColors.text : AppColors.surface,
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: selected ? AppColors.text : AppColors.line),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? AppColors.bg : AppColors.muted,
            ),
          ),
        ),
      ),
    );
  }
}

class _DuplicatesButton extends StatelessWidget {
  const _DuplicatesButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Text('🔁', style: TextStyle(fontSize: 24)),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Duplicados', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                    Text(
                      'Cópias idênticas, byte a byte',
                      style: TextStyle(color: AppColors.muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: AppColors.muted),
            ],
          ),
        ),
      ),
    );
  }
}

class _AlbumRow extends StatelessWidget {
  const _AlbumRow({
    required this.name,
    required this.count,
    required this.bytes,
    required this.fraction,
    required this.onTap,
  });

  final String name;
  final int count;
  final int? bytes;
  final double fraction;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                  Text(
                    plural(count, 'item', 'itens'),
                    style: const TextStyle(color: AppColors.muted, fontSize: 12),
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: LinearProgressIndicator(
                      value: bytes == null ? null : fraction.clamp(0.02, 1.0),
                      minHeight: 3,
                      color: AppColors.delete,
                      backgroundColor: AppColors.surface2,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Text(
              bytes == null ? '…' : formatBytes(bytes!),
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoAccess extends StatelessWidget {
  const _NoAccess({required this.onSettings, required this.onRetry});

  final VoidCallback onSettings;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('📷', style: TextStyle(fontSize: 48)),
          const SizedBox(height: 16),
          const Text(
            'Preciso de acesso às fotos e vídeos',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          const Text(
            'Sem isso não dá pra mostrar o que tá ocupando espaço.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.muted),
          ),
          const SizedBox(height: 24),
          FilledButton(onPressed: onSettings, child: const Text('Abrir configurações')),
          TextButton(onPressed: onRetry, child: const Text('Tentar de novo')),
        ],
      ),
    );
  }
}

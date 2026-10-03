import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../format.dart';
import '../media/decision_store.dart';
import '../media/media_filter.dart';
import '../media/media_library.dart';
import '../media/native_bridge.dart';
import '../theme.dart';
import 'compress_screen.dart';
import 'duplicates_screen.dart';
import 'kept_screen.dart';
import 'review_screen.dart';
import 'swipe_screen.dart';
import 'trash_screen.dart';
import 'welcome_screen.dart';

enum _Status { checking, welcome, scanning, ready }

/// Mapa da galeria: quanto o celular tem, o que falta revisar e por onde começar.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.library, required this.store});

  final MediaLibrary library;
  final DecisionStore store;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  _Status _status = _Status.checking;
  bool _askedForAccess = false;
  MediaFilter _filter = MediaFilter.none;
  StorageStats? _storage;

  /// Atualizando em segundo plano por cima do que veio do cache.
  bool _updating = false;

  MediaLibrary get _library => widget.library;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Quem volta da tela de permissão do sistema cai aqui.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _status == _Status.welcome) _init();
  }

  Future<void> _init() async {
    final ok = await _library.native.hasAllFilesAccess();
    if (!mounted) return;
    if (!ok) {
      setState(() => _status = _Status.welcome);
      return;
    }
    await _library.setVolumes(await _library.native.storageVolumes());
    await _library.trash.purgeExpired();
    if (await _library.loadCached()) {
      // Abre na hora com a última varredura e atualiza só o que mudou.
      if (!mounted) return;
      setState(() {
        _status = _Status.ready;
        _updating = true;
      });
      _refreshStorage();
      await _library.scan();
      if (mounted) setState(() => _updating = false);
      _refreshStorage();
    } else {
      await _rescan();
    }
  }

  void _requestAccess() {
    setState(() => _askedForAccess = true);
    _library.native.requestAllFilesAccess();
  }

  /// Varredura completa, ignorando o cache (refresh manual e primeira vez).
  Future<void> _rescan() async {
    setState(() => _status = _Status.scanning);
    // Relê os volumes: o cartão pode ter sido colocado ou tirado.
    await _library.setVolumes(await _library.native.storageVolumes());
    await _library.scan(full: true);
    await _refreshStorage();
    if (mounted) {
      setState(() {
        _status = _Status.ready;
        _updating = false;
      });
    }
  }

  Future<void> _refreshStorage() async {
    final storage = await _library.native.storageStats();
    final volumes = await _library.native.storageVolumes();
    if (!mounted) return;
    setState(() {
      _storage = storage;
      // Só atualiza o espaço; trocar de volumes fica pro refresh completo.
      _library.volumes = volumes;
    });
  }

  /// Depois de voltar de outra tela: a lista em memória já foi atualizada,
  /// só falta redesenhar e reler o espaço livre.
  void _afterReturn() {
    if (!mounted) return;
    setState(() {});
    _refreshStorage();
  }

  Future<void> _push(Widget screen) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    _afterReturn();
  }

  void _openSwipe(Album album) => _push(SwipeScreen(
        files: album.files,
        title: _filter.isEmpty ? album.name : '${album.name} · ${_filter.label}',
        library: _library,
        store: widget.store,
      ));

  Future<void> _openTrash() async {
    final restored = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => TrashScreen(library: _library)),
    );
    if (restored ?? false) {
      await _rescan(); // arquivo voltou pro lugar: precisa reler
    } else {
      _afterReturn();
    }
  }

  Future<void> _pickYear() async {
    final years = [for (var y = DateTime.now().year; y >= _library.oldestYear; y--) y];
    final picked = await showModalBottomSheet<int>(
      context: context,
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
    setState(() => _filter = _filter.copyWith(year: () => picked == -1 ? null : picked));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: switch (_status) {
        _Status.checking => const SizedBox.shrink(),
        _Status.welcome => WelcomeScreen(onGrant: _requestAccess, askedBefore: _askedForAccess),
        _Status.scanning => const SafeArea(child: _HomeSkeleton()),
        _Status.ready => SafeArea(
            child: ListenableBuilder(
              listenable: widget.store,
              builder: (context, _) => _buildReady(),
            ),
          ),
      },
    );
  }

  int get _keptCount {
    final kept = widget.store.kept;
    return kept.isEmpty ? 0 : _library.files.where((f) => kept.contains(f.path)).length;
  }

  Widget _buildReady() {
    final isDecided = widget.store.isDecided;
    final all = _library.all(_filter, isDecided: isDecided);
    final albums = _library.albums(_filter, isDecided: isDecided);
    final maxAlbum = albums.isEmpty ? 1 : albums.first.bytes;

    return RefreshIndicator(
      onRefresh: _rescan,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _Header(onRefresh: _rescan, updating: _updating),
          const SizedBox(height: 16),
          if (_storage != null) _StorageCard(storage: _storage!, library: _library),
          for (final volume in _library.volumes.where((v) => v.removable))
            if (_library.roots.contains(volume.path)) _SdCard(volume: volume, library: _library),
          if (widget.store.markedCount > 0)
            _ActionCard(
              icon: Icons.delete_outline_rounded,
              text: '${plural(widget.store.markedCount, 'marcado', 'marcados')} · '
                  '${formatBytes(widget.store.markedBytes)}',
              action: 'Revisar',
              color: AppColors.delete,
              onTap: () => _push(ReviewScreen(library: _library, store: widget.store)),
            ),
          if (widget.store.compressCount > 0)
            _ActionCard(
              icon: Icons.compress_rounded,
              text: 'Comprimir · ${plural(widget.store.compressCount, 'vídeo', 'vídeos')} · '
                  '${formatBytes(widget.store.compressBytes)}',
              action: 'Abrir',
              color: AppColors.accent,
              onTap: () => _push(CompressScreen(library: _library, store: widget.store)),
            ),
          if (_keptCount > 0)
            _ActionCard(
              icon: Icons.bookmark_border_rounded,
              text: 'Mantidos · ${plural(_keptCount, 'item', 'itens')}',
              action: 'Rever',
              color: AppColors.keep,
              onTap: () => _push(KeptScreen(library: _library, store: widget.store)),
            ),
          if (_library.trash.bytes > 0)
            _ActionCard(
              icon: Icons.recycling_rounded,
              text: 'Lixeira · ${plural(_library.trash.entries.length, 'item', 'itens')} · '
                  '${formatBytes(_library.trash.bytes)}',
              action: 'Abrir',
              color: AppColors.muted,
              onTap: _openTrash,
            ),
          const SizedBox(height: 22),
          _FilterBar(
            filter: _filter,
            onChanged: (f) => setState(() => _filter = f),
            onPickYear: _pickYear,
          ),
          const SizedBox(height: 12),
          if (all.files.isEmpty)
            _AllDone(filtered: !_filter.isEmpty)
          else
            _AllButton(
              subtitle: '${plural(all.files.length, 'item', 'itens')} pra revisar · ${formatBytes(all.bytes)}',
              onTap: () => _openSwipe(all),
            ),
          const SizedBox(height: 10),
          _DuplicatesButton(
            onTap: () => _push(DuplicatesScreen(library: _library, store: widget.store)),
          ),
          if (albums.isNotEmpty) ...[
            const SizedBox(height: 26),
            const _SectionTitle('Pastas pra revisar'),
            const SizedBox(height: 4),
            for (final album in albums)
              _AlbumRow(
                album: album,
                onSdCard: _library.isRemovable(album.folder ?? ''),
                fraction: album.bytes / maxAlbum,
                onTap: () => _openSwipe(album),
              ),
          ],
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onRefresh, required this.updating});

  final VoidCallback onRefresh;
  final bool updating;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Mídias', style: display(32)),
              const SizedBox(height: 2),
              Text(
                updating ? 'Atualizando…' : 'O que tá ocupando teu celular',
                style: const TextStyle(color: AppColors.muted, fontSize: 13),
              ),
            ],
          ),
        ),
        if (updating)
          const Padding(
            padding: EdgeInsets.all(12),
            child: SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.muted),
            ),
          )
        else
          IconButton.filledTonal(
            style: IconButton.styleFrom(backgroundColor: AppColors.surface),
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh_rounded, color: AppColors.muted),
            tooltip: 'Ler tudo de novo',
          ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        color: AppColors.muted,
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.2,
      ),
    );
  }
}

/// O "dashboardzinho": capacidade, barra de uso e pra onde foi cada GB,
/// no estilo da tela de armazenamento do Android.
class _StorageCard extends StatelessWidget {
  const _StorageCard({required this.storage, required this.library});

  final StorageStats storage;
  final MediaLibrary library;

  static const _lowSpace = 2 * 1000 * 1000 * 1000;

  @override
  Widget build(BuildContext context) {
    // Só o armazenamento interno: o cartão SD tem o card dele.
    var whatsapp = 0, camera = 0, otherMedia = 0;
    for (final f in library.filesIn(library.root)) {
      if (f.path.contains('/com.whatsapp/')) {
        whatsapp += f.size;
      } else if (f.path.contains('/DCIM/')) {
        camera += f.size;
      } else {
        otherMedia += f.size;
      }
    }
    final trash = library.trash.bytesIn(library.root);
    final otherFiles = library.otherBytesIn(library.root);
    final used = storage.total - storage.free;
    final known = storage.system + whatsapp + camera + otherMedia + otherFiles + trash;
    // O que sobra é o que fica em /data: apps, dados e caches (inclusive
    // downloads do Spotify, que ficam em Android/data).
    final apps = (used - known).clamp(0, used);

    final segments = [
      (label: 'WhatsApp', bytes: whatsapp, color: AppColors.keep),
      (label: 'Câmera', bytes: camera, color: AppColors.warn),
      (label: 'Outras mídias', bytes: otherMedia, color: AppColors.accent),
      (label: 'Outros arquivos', bytes: otherFiles, color: AppColors.sky),
      if (trash > 0) (label: 'Lixeira do app', bytes: trash, color: AppColors.delete),
      (label: 'Apps e dados', bytes: apps, color: AppColors.apps),
      (label: 'Sistema', bytes: storage.system, color: AppColors.system),
    ];
    final percent = (used / storage.total * 100).round();
    final low = storage.free < _lowSpace;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1A1A24), AppColors.surface],
        ),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(formatBytes(used), style: display(30)),
                    const SizedBox(height: 2),
                    Text(
                      'usados de ${formatBytes(storage.total)}',
                      style: const TextStyle(color: AppColors.muted, fontSize: 13),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: (low ? AppColors.delete : AppColors.keep).withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  '$percent%',
                  style: display(14, color: low ? AppColors.delete : AppColors.keep),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _UsageBar(
            total: storage.total,
            segments: [for (final s in segments) (bytes: s.bytes, color: s.color)],
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final columnWidth = (constraints.maxWidth - 16) / 2;
              return Wrap(
                spacing: 16,
                runSpacing: 10,
                children: [
                  for (final s in segments)
                    SizedBox(
                      width: columnWidth,
                      child: _LegendItem(label: s.label, bytes: s.bytes, color: s.color),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 14),
          const Divider(height: 1, color: AppColors.line),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(
                low ? Icons.warning_amber_rounded : Icons.check_circle_outline_rounded,
                size: 16,
                color: low ? AppColors.delete : AppColors.keep,
              ),
              const SizedBox(width: 6),
              Text(
                low ? 'Só ${formatBytes(storage.free)} livres' : '${formatBytes(storage.free)} livres',
                style: TextStyle(
                  color: low ? AppColors.delete : AppColors.keep,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Card compacto de um cartão SD: mídia, outros arquivos, lixeira e livre.
class _SdCard extends StatelessWidget {
  const _SdCard({required this.volume, required this.library});

  final StorageVolume volume;
  final MediaLibrary library;

  @override
  Widget build(BuildContext context) {
    final media = library.filesIn(volume.path).fold(0, (sum, f) => sum + f.size);
    final other = library.otherBytesIn(volume.path);
    final trash = library.trash.bytesIn(volume.path);
    final used = volume.total - volume.free;
    final rest = (used - media - other - trash).clamp(0, used);
    final segments = [
      (label: 'Mídias', bytes: media, color: AppColors.accent),
      (label: 'Outros arquivos', bytes: other, color: AppColors.sky),
      if (trash > 0) (label: 'Lixeira do app', bytes: trash, color: AppColors.delete),
      if (rest > 0) (label: 'Sistema de arquivos', bytes: rest, color: AppColors.system),
    ];

    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.sd_card_rounded, color: AppColors.warn, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  volume.label,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(formatBytes(used), style: display(16)),
              Text(
                ' / ${formatBytes(volume.total)}',
                style: const TextStyle(color: AppColors.muted, fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _UsageBar(
            total: volume.total,
            segments: [for (final s in segments) (bytes: s.bytes, color: s.color)],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 14,
            runSpacing: 6,
            children: [
              for (final s in segments)
                SizedBox(
                  width: 140,
                  child: _LegendItem(label: s.label, bytes: s.bytes, color: s.color),
                ),
              Text(
                '${formatBytes(volume.free)} livres',
                style: const TextStyle(color: AppColors.keep, fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Barra segmentada de uso: cada categoria uma cor, o resto é espaço livre.
class _UsageBar extends StatelessWidget {
  const _UsageBar({required this.total, required this.segments});

  final int total;
  final List<({int bytes, Color color})> segments;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(99),
      child: Container(
        height: 14,
        color: AppColors.surface2,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            return Row(
              children: [
                for (final s in segments)
                  if (s.bytes > 0)
                    Container(
                      // mínimo de 2px pra categoria pequena não sumir
                      width: (s.bytes / total * width).clamp(2.0, width),
                      color: s.color,
                      margin: const EdgeInsets.only(right: 1.5),
                    ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.label, required this.bytes, required this.color});

  final String label;
  final int bytes;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(color: AppColors.muted, fontSize: 12),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Text(formatBytes(bytes), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
      ],
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.text,
    required this.action,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String text;
  final String action;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Material(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w700)),
                ),
                Text(action, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
                Icon(Icons.chevron_right_rounded, color: color, size: 20),
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
    return Material(
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: Ink(
        decoration: const BoxDecoration(
          gradient: LinearGradient(colors: [AppColors.delete, AppColors.orange]),
        ),
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.local_fire_department_rounded, color: Colors.white),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Tudo, maiores primeiro', style: display(17, color: Colors.white)),
                      const SizedBox(height: 2),
                      Text(subtitle, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward_rounded, color: Colors.white),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AllDone extends StatelessWidget {
  const _AllDone({required this.filtered});

  final bool filtered;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.keep.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle_rounded, color: AppColors.keep),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              filtered ? 'Nada pra revisar com esse filtro' : 'Tudo revisado 🎉',
              style: const TextStyle(color: AppColors.keep, fontWeight: FontWeight.w700),
            ),
          ),
        ],
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
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.content_copy_rounded, color: AppColors.accent, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Duplicados', style: display(17)),
                    const SizedBox(height: 2),
                    const Text(
                      'Cópias idênticas, byte a byte',
                      style: TextStyle(color: AppColors.muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
            ],
          ),
        ),
      ),
    );
  }
}

/// Ícone e cor pela "cara" da pasta, como os tiles coloridos do design.
({IconData icon, Color color}) _folderStyle(String? folder) {
  final p = (folder ?? '').toLowerCase();
  if (p.contains('whatsapp')) return (icon: Icons.chat_rounded, color: AppColors.keep);
  if (p.contains('/dcim/camera')) return (icon: Icons.photo_camera_rounded, color: AppColors.warn);
  if (p.contains('screenshot')) return (icon: Icons.screenshot_rounded, color: AppColors.accent);
  if (p.contains('screenrecord')) return (icon: Icons.videocam_rounded, color: AppColors.orange);
  if (p.contains('telegram')) return (icon: Icons.send_rounded, color: AppColors.sky);
  if (p.contains('instagram') || p.contains('threads')) {
    return (icon: Icons.camera_alt_outlined, color: AppColors.pink);
  }
  if (p.contains('download')) return (icon: Icons.download_rounded, color: AppColors.sky);
  if (p.contains('movies')) return (icon: Icons.movie_rounded, color: AppColors.pink);
  return (icon: Icons.folder_rounded, color: AppColors.muted);
}

class _AlbumRow extends StatelessWidget {
  const _AlbumRow({
    required this.album,
    required this.onSdCard,
    required this.fraction,
    required this.onTap,
  });

  final Album album;
  final bool onSdCard;
  final double fraction;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final style = _folderStyle(album.folder);
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: style.color.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(style.icon, color: style.color, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (onSdCard) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: AppColors.warn.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: const Text(
                            'SD',
                            style: TextStyle(color: AppColors.warn, fontSize: 10, fontWeight: FontWeight.w800),
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      Expanded(
                        child: Text(
                          album.name,
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(formatBytes(album.bytes), style: display(15)),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    plural(album.files.length, 'item', 'itens'),
                    style: const TextStyle(color: AppColors.muted, fontSize: 12),
                  ),
                  const SizedBox(height: 7),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: LinearProgressIndicator(
                      value: fraction.clamp(0.02, 1.0),
                      minHeight: 3,
                      color: style.color,
                      backgroundColor: AppColors.surface2,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Esqueleto da home enquanto lê o armazenamento.
class _HomeSkeleton extends StatelessWidget {
  const _HomeSkeleton();

  @override
  Widget build(BuildContext context) {
    Widget box(double height, {double? width, double radius = 18}) => Container(
          height: height,
          width: width,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(radius),
          ),
        );

    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        Text('Mídias', style: display(32)),
        const SizedBox(height: 2),
        const Text(
          'Lendo o armazenamento…',
          style: TextStyle(color: AppColors.muted, fontSize: 13),
        ),
        const SizedBox(height: 16),
        Shimmer.fromColors(
          baseColor: AppColors.surface,
          highlightColor: AppColors.surface2,
          period: const Duration(milliseconds: 1200),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              box(210, radius: 22),
              const SizedBox(height: 22),
              Row(
                children: [
                  for (final w in [64.0, 70.0, 62.0, 72.0, 60.0]) ...[
                    box(34, width: w, radius: 99),
                    const SizedBox(width: 6),
                  ],
                ],
              ),
              const SizedBox(height: 12),
              box(76, radius: 20),
              const SizedBox(height: 10),
              box(72, radius: 20),
              const SizedBox(height: 26),
              box(12, width: 120, radius: 4),
              const SizedBox(height: 10),
              for (var i = 0; i < 5; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(
                    children: [
                      box(42, width: 42, radius: 13),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            box(13, width: 150 - i * 12.0, radius: 4),
                            const SizedBox(height: 8),
                            box(10, width: 60, radius: 4),
                            const SizedBox(height: 9),
                            box(3, radius: 99),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

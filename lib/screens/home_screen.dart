import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shimmer/shimmer.dart';

import '../format.dart';
import '../media/decision_store.dart';
import '../media/media_filter.dart';
import '../media/media_library.dart';
import '../media/native_bridge.dart';
import '../theme.dart';
import '../widgets/album_widgets.dart';
import 'compress_screen.dart';
import 'duplicates_screen.dart';
import 'kept_screen.dart';
import 'review_screen.dart';
import 'search_screen.dart';
import 'swipe_screen.dart';
import 'trash_screen.dart';
import 'volume_screen.dart';
import 'onboarding_screen.dart';

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

  /// Já passou pelo onboarding uma vez. Se a permissão for tirada depois,
  /// aparece só o passo da permissão.
  bool _onboarded = false;
  static const _onboardedKey = 'onboarded';
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
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        _onboarded = prefs.getBool(_onboardedKey) ?? false;
        _status = _Status.welcome;
      });
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
    setState(() {
      _askedForAccess = true;
      _onboarded = true;
    });
    SharedPreferences.getInstance().then((prefs) => prefs.setBool(_onboardedKey, true));
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
    final filter = await pickYear(context, _filter, _library.oldestYear);
    if (filter != null) setState(() => _filter = filter);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: switch (_status) {
        _Status.checking => const SizedBox.shrink(),
        _Status.welcome => OnboardingScreen(
            native: _library.native,
            onGrant: _requestAccess,
            askedBefore: _askedForAccess,
            permissionOnly: _onboarded,
          ),
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
    // A home é o armazenamento interno; o cartão SD tem a tela dele.
    final all = _library.all(_filter, isDecided: isDecided, volume: _library.root);
    final albums = _library.albums(_filter, isDecided: isDecided, volume: _library.root);
    final maxAlbum = albums.isEmpty ? 1 : albums.first.bytes;

    return RefreshIndicator(
      onRefresh: _rescan,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _Header(
            onRefresh: _rescan,
            updating: _updating,
            onSearch: () => _push(SearchScreen(library: _library, store: widget.store)),
          ),
          const SizedBox(height: 16),
          if (_storage != null) _StorageCard(storage: _storage!, library: _library),
          for (final volume in _library.volumes.where((v) => v.removable))
            if (_library.roots.contains(volume.path))
              VolumeCard(
                volume: volume,
                library: _library,
                pending: _library.all(MediaFilter.none, isDecided: isDecided, volume: volume.path).files.length,
                onTap: () => _push(VolumeScreen(volume: volume, library: _library, store: widget.store)),
              ),
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
          FilterBar(
            filter: _filter,
            onChanged: (f) => setState(() => _filter = f),
            onPickYear: _pickYear,
          ),
          const SizedBox(height: 12),
          if (all.files.isEmpty)
            AllDone(filtered: !_filter.isEmpty)
          else
            AllButton(
              subtitle: '${plural(all.files.length, 'item', 'itens')} pra revisar · ${formatBytes(all.bytes)}',
              onTap: () => _openSwipe(all),
            ),
          const SizedBox(height: 10),
          _DuplicatesButton(
            onTap: () => _push(DuplicatesScreen(library: _library, store: widget.store)),
          ),
          if (albums.isNotEmpty) ...[
            const SizedBox(height: 26),
            const SectionTitle('Pastas do celular'),
            const SizedBox(height: 4),
            for (final album in albums)
              AlbumRow(
                album: album,
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
  const _Header({required this.onRefresh, required this.updating, required this.onSearch});

  final VoidCallback onRefresh;
  final bool updating;
  final VoidCallback onSearch;

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
        IconButton.filledTonal(
          style: IconButton.styleFrom(backgroundColor: AppColors.surface),
          onPressed: onSearch,
          icon: const Icon(Icons.search_rounded, color: AppColors.text),
          tooltip: 'Buscar',
        ),
        const SizedBox(width: 6),
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
          UsageBar(
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
                      child: LegendItem(label: s.label, bytes: s.bytes, color: s.color),
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

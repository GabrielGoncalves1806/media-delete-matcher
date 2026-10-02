import 'package:flutter/material.dart';

import '../format.dart';
import '../media/decision_store.dart';
import '../media/media_filter.dart';
import '../media/media_library.dart';
import '../theme.dart';
import 'duplicates_screen.dart';
import 'review_screen.dart';
import 'swipe_screen.dart';
import 'trash_screen.dart';

enum _Status { checking, noAccess, scanning, ready }

/// Mapa da galeria: quanto o celular tem, quanto cada pasta pesa e por onde começar.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.library, required this.store});

  final MediaLibrary library;
  final DecisionStore store;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  _Status _status = _Status.checking;
  MediaFilter _filter = MediaFilter.none;
  ({int total, int free})? _storage;

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
    if (state == AppLifecycleState.resumed && _status == _Status.noAccess) _init();
  }

  Future<void> _init() async {
    final ok = await _library.native.hasAllFilesAccess();
    if (!mounted) return;
    if (!ok) {
      setState(() => _status = _Status.noAccess);
      return;
    }
    await _rescan();
  }

  Future<void> _rescan() async {
    setState(() => _status = _Status.scanning);
    await _library.trash.load();
    await _library.trash.purgeExpired();
    await _library.scan();
    await _refreshStorage();
    if (mounted) setState(() => _status = _Status.ready);
  }

  Future<void> _refreshStorage() async {
    final storage = await _library.native.storageStats();
    if (mounted) setState(() => _storage = storage);
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
    setState(() => _filter = _filter.copyWith(year: () => picked == -1 ? null : picked));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: switch (_status) {
          _Status.checking => const Center(child: CircularProgressIndicator()),
          _Status.noAccess => _NoAccess(onGrant: _library.native.requestAllFilesAccess),
          _Status.scanning => const _Scanning(),
          _Status.ready => _buildReady(),
        },
      ),
    );
  }

  Widget _buildReady() {
    final all = _library.all(_filter);
    final albums = _library.albums(_filter);
    final maxAlbum = albums.isEmpty ? 1 : albums.first.bytes;

    return RefreshIndicator(
      onRefresh: _rescan,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          const Text(
            'Mídias',
            style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -0.5),
          ),
          const SizedBox(height: 14),
          if (_storage != null) _StorageCard(storage: _storage!, library: _library),
          ListenableBuilder(
            listenable: widget.store,
            builder: (context, _) => widget.store.markedCount == 0
                ? const SizedBox.shrink()
                : _PendingCard(
                    store: widget.store,
                    onTap: () => _push(ReviewScreen(library: _library, store: widget.store)),
                  ),
          ),
          if (_library.trash.bytes > 0)
            _TrashCard(
              bytes: _library.trash.bytes,
              count: _library.trash.entries.length,
              onTap: _openTrash,
            ),
          const SizedBox(height: 14),
          _FilterBar(
            filter: _filter,
            onChanged: (f) => setState(() => _filter = f),
            onPickYear: _pickYear,
          ),
          const SizedBox(height: 12),
          if (all.files.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text('Nada com esse filtro', style: TextStyle(color: AppColors.muted)),
              ),
            )
          else
            _AllButton(
              subtitle: '${plural(all.files.length, 'item', 'itens')} · ${formatBytes(all.bytes)}',
              onTap: () => _openSwipe(all),
            ),
          const SizedBox(height: 10),
          _DuplicatesButton(
            onTap: () => _push(DuplicatesScreen(library: _library, store: widget.store)),
          ),
          const SizedBox(height: 20),
          const Text(
            'PASTAS',
            style: TextStyle(color: AppColors.muted, fontSize: 12, letterSpacing: 1),
          ),
          const SizedBox(height: 6),
          for (final album in albums)
            _AlbumRow(
              name: album.name,
              count: album.files.length,
              bytes: album.bytes,
              fraction: album.bytes / maxAlbum,
              onTap: () => _openSwipe(album),
            ),
        ],
      ),
    );
  }
}

/// O "dashboardzinho": quanto o celular tem e pra onde foi o espaço.
class _StorageCard extends StatelessWidget {
  const _StorageCard({required this.storage, required this.library});

  final ({int total, int free}) storage;
  final MediaLibrary library;

  static const _lowSpace = 2 * 1024 * 1024 * 1024;

  @override
  Widget build(BuildContext context) {
    var whatsapp = 0, camera = 0, otherMedia = 0;
    for (final f in library.files) {
      if (f.path.contains('/com.whatsapp/')) {
        whatsapp += f.size;
      } else if (f.path.contains('/DCIM/')) {
        camera += f.size;
      } else {
        otherMedia += f.size;
      }
    }
    final trash = library.trash.bytes;
    final used = storage.total - storage.free;
    final rest = (used - whatsapp - camera - otherMedia - trash).clamp(0, used);

    final segments = [
      (label: 'WhatsApp', bytes: whatsapp, color: AppColors.delete),
      (label: 'Câmera', bytes: camera, color: AppColors.warn),
      (label: 'Outras mídias', bytes: otherMedia, color: AppColors.accent),
      if (trash > 0) (label: 'Lixeira', bytes: trash, color: AppColors.muted),
      (label: 'Apps e sistema', bytes: rest, color: const Color(0xFF3A3A48)),
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(formatBytes(used), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
              const SizedBox(width: 6),
              Text(
                'de ${formatBytes(storage.total)} usados',
                style: const TextStyle(color: AppColors.muted, fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: SizedBox(
              height: 10,
              child: Row(
                children: [
                  for (final s in segments)
                    if (s.bytes > 0)
                      Expanded(
                        flex: (s.bytes / storage.total * 1000).round().clamp(1, 1000),
                        child: ColoredBox(color: s.color),
                      ),
                  if (storage.free > 0)
                    Expanded(
                      flex: (storage.free / storage.total * 1000).round().clamp(1, 1000),
                      child: const ColoredBox(color: AppColors.surface2),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              for (final s in segments)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(color: s.color, borderRadius: BorderRadius.circular(2)),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${s.label} ${formatBytes(s.bytes)}',
                      style: const TextStyle(color: AppColors.muted, fontSize: 11),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            storage.free < _lowSpace
                ? '⚠ só ${formatBytes(storage.free)} livres'
                : '${formatBytes(storage.free)} livres',
            style: TextStyle(
              color: storage.free < _lowSpace ? AppColors.delete : AppColors.keep,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
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
    return _ActionCard(
      emoji: '🗑',
      text: '${plural(store.markedCount, 'marcado', 'marcados')} · ${formatBytes(store.markedBytes)}',
      action: 'Revisar ›',
      color: AppColors.delete,
      onTap: onTap,
    );
  }
}

class _TrashCard extends StatelessWidget {
  const _TrashCard({required this.bytes, required this.count, required this.onTap});

  final int bytes;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _ActionCard(
      emoji: '♻',
      text: 'Lixeira: ${plural(count, 'item', 'itens')} · ${formatBytes(bytes)}',
      action: 'Abrir ›',
      color: AppColors.muted,
      onTap: onTap,
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.emoji,
    required this.text,
    required this.action,
    required this.color,
    required this.onTap,
  });

  final String emoji;
  final String text;
  final String action;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Material(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Text(emoji, style: const TextStyle(fontSize: 20)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w700)),
                ),
                Text(action, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
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
                  const Text(
                    'Tudo, maiores primeiro',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: Colors.white),
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
  final int bytes;
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
                      value: fraction.clamp(0.02, 1.0),
                      minHeight: 3,
                      color: AppColors.delete,
                      backgroundColor: AppColors.surface2,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Text(formatBytes(bytes), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          ],
        ),
      ),
    );
  }
}

class _Scanning extends StatelessWidget {
  const _Scanning();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Lendo o armazenamento…', style: TextStyle(color: AppColors.muted)),
        ],
      ),
    );
  }
}

class _NoAccess extends StatelessWidget {
  const _NoAccess({required this.onGrant});

  final VoidCallback onGrant;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('📂', style: TextStyle(fontSize: 48)),
          const SizedBox(height: 16),
          const Text(
            'Preciso de acesso a todos os arquivos',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          const Text(
            'A galeria do Android esconde a mídia do WhatsApp (e de outros apps). '
            'Lendo os arquivos direto dá pra ver tudo que ocupa espaço.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.muted),
          ),
          const SizedBox(height: 24),
          FilledButton(onPressed: onGrant, child: const Text('Dar acesso')),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../format.dart';
import '../media/decision_store.dart';
import '../media/media_filter.dart';
import '../media/media_library.dart';
import '../media/native_bridge.dart';
import '../theme.dart';
import '../widgets/album_widgets.dart';
import 'swipe_screen.dart';

/// A mesma home, só que com o conteúdo do cartão SD em vez do celular.
class VolumeScreen extends StatefulWidget {
  const VolumeScreen({
    super.key,
    required this.volume,
    required this.library,
    required this.store,
  });

  final StorageVolume volume;
  final MediaLibrary library;
  final DecisionStore store;

  @override
  State<VolumeScreen> createState() => _VolumeScreenState();
}

class _VolumeScreenState extends State<VolumeScreen> {
  MediaFilter _filter = MediaFilter.none;

  MediaLibrary get _library => widget.library;

  /// O volume com o espaço mais recente (a home atualiza a lista).
  StorageVolume get _volume =>
      _library.volumes.where((v) => v.path == widget.volume.path).firstOrNull ??
      widget.volume;

  Future<void> _openSwipe(Album album, String name) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SwipeScreen(
          files: album.files,
          title: _filter.isEmpty ? name : '$name · ${_filter.label}',
          library: _library,
          store: widget.store,
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _pickYear() async {
    final filter = await pickYear(context, _filter, _library.oldestYear);
    if (filter != null) setState(() => _filter = filter);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListenableBuilder(
          listenable: widget.store,
          builder: (context, _) {
            final isDecided = widget.store.isDecided;
            final path = widget.volume.path;
            final all = _library.all(
              _filter,
              isDecided: isDecided,
              volume: path,
            );
            final albums = _library.albums(
              _filter,
              isDecided: isDecided,
              volume: path,
            );
            final maxAlbum = albums.isEmpty ? 1 : albums.first.bytes;

            return ListView(
              padding: const EdgeInsets.fromLTRB(8, 8, 16, 32),
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.chevron_left_rounded, size: 30),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Cartão SD', style: display(32)),
                          const SizedBox(height: 2),
                          const Text(
                            'O que tá ocupando o cartão',
                            style: TextStyle(
                              color: AppColors.muted,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      VolumeCard(volume: _volume, library: _library),
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
                          subtitle:
                              '${plural(all.files.length, 'item', 'itens')} pra revisar · ${formatBytes(all.bytes)}',
                          onTap: () => _openSwipe(all, 'Cartão SD'),
                        ),
                      if (albums.isNotEmpty) ...[
                        const SizedBox(height: 26),
                        const SectionTitle('Pastas do cartão'),
                        const SizedBox(height: 4),
                        for (final album in albums)
                          AlbumRow(
                            album: album,
                            fraction: album.bytes / maxAlbum,
                            onTap: () => _openSwipe(album, album.name),
                          ),
                      ],
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

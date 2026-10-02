import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:video_player/video_player.dart';

import '../theme.dart';

/// Mostra a foto ou o vídeo de um item.
///
/// Sempre começa pela miniatura (rápida). Quando [active] é true, carrega o
/// arquivo original: foto em resolução de tela, vídeo tocando mudo em loop.
/// Tocar liga/desliga o som do vídeo.
class MediaPreview extends StatefulWidget {
  const MediaPreview({super.key, required this.asset, required this.active});

  final AssetEntity asset;
  final bool active;

  @override
  State<MediaPreview> createState() => _MediaPreviewState();
}

class _MediaPreviewState extends State<MediaPreview> {
  Uint8List? _thumb;
  File? _photo;
  VideoPlayerController? _video;
  bool _muted = true;
  bool _loadingFull = false;

  bool get _isVideo => widget.asset.type == AssetType.video;

  @override
  void initState() {
    super.initState();
    _loadThumb();
    if (widget.active) _loadFull();
  }

  @override
  void didUpdateWidget(MediaPreview old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) _loadFull();
  }

  @override
  void dispose() {
    _video?.dispose();
    super.dispose();
  }

  Future<void> _loadThumb() async {
    final data = await widget.asset.thumbnailDataWithSize(const ThumbnailSize(540, 960));
    if (mounted) setState(() => _thumb = data);
  }

  Future<void> _loadFull() async {
    if (_loadingFull) return;
    _loadingFull = true;
    // No Android 11+ isso devolve o caminho original, sem copiar o arquivo.
    final file = await widget.asset.file;
    if (!mounted || file == null) return;

    if (!_isVideo) {
      setState(() => _photo = file);
      return;
    }

    final controller = VideoPlayerController.file(file);
    try {
      await controller.initialize();
    } catch (_) {
      await controller.dispose();
      return; // fica só a miniatura
    }
    if (!mounted) {
      await controller.dispose();
      return;
    }
    await controller.setLooping(true);
    await controller.setVolume(0);
    await controller.play();
    setState(() => _video = controller);
  }

  void _toggleSound() {
    final video = _video;
    if (video == null) return;
    setState(() => _muted = !_muted);
    video.setVolume(_muted ? 0 : 1);
  }

  @override
  Widget build(BuildContext context) {
    final video = _video;
    return GestureDetector(
      onTap: _toggleSound,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: AppColors.surface),
          if (_thumb != null)
            Image.memory(_thumb!, fit: BoxFit.cover, gaplessPlayback: true),
          if (_photo != null)
            Image.file(
              _photo!,
              fit: BoxFit.cover,
              cacheWidth: 1440,
              gaplessPlayback: true,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
          if (video != null && video.value.isInitialized)
            FittedBox(
              fit: BoxFit.cover,
              clipBehavior: Clip.hardEdge,
              child: SizedBox(
                width: video.value.size.width,
                height: video.value.size.height,
                child: VideoPlayer(video),
              ),
            ),
          if (_isVideo)
            Positioned(
              right: 14,
              top: 52,
              child: _SoundBadge(muted: _muted),
            ),
          if (video != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: VideoProgressIndicator(
                video,
                allowScrubbing: false,
                padding: EdgeInsets.zero,
                colors: const VideoProgressColors(
                  playedColor: Colors.white,
                  bufferedColor: Colors.white24,
                  backgroundColor: Colors.white10,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SoundBadge extends StatelessWidget {
  const _SoundBadge({required this.muted});

  final bool muted;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: const BoxDecoration(color: Colors.black45, shape: BoxShape.circle),
      child: Icon(muted ? Icons.volume_off_rounded : Icons.volume_up_rounded, size: 18),
    );
  }
}

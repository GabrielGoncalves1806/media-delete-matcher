import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../media/media_file.dart';
import '../media/native_bridge.dart';
import 'media_thumb.dart';

/// Mostra a foto ou o vídeo de um arquivo.
///
/// Sempre começa pela miniatura (rápida). Quando [active] é true, carrega o
/// original: foto em resolução de tela, vídeo tocando mudo em loop.
/// Tocar liga/desliga o som do vídeo.
class MediaPreview extends StatefulWidget {
  const MediaPreview({
    super.key,
    required this.file,
    required this.thumbnails,
    required this.active,
    this.onDuration,
  });

  final MediaFile file;
  final Thumbnails thumbnails;
  final bool active;

  /// Avisa a duração quando o vídeo termina de carregar.
  final ValueChanged<Duration>? onDuration;

  @override
  State<MediaPreview> createState() => _MediaPreviewState();
}

class _MediaPreviewState extends State<MediaPreview> {
  VideoPlayerController? _video;
  bool _muted = true;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    if (widget.active) _loadVideo();
  }

  @override
  void didUpdateWidget(MediaPreview old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) _loadVideo();
  }

  @override
  void dispose() {
    _video?.dispose();
    super.dispose();
  }

  Future<void> _loadVideo() async {
    if (!widget.file.isVideo || _loading) return;
    _loading = true;
    final controller = VideoPlayerController.file(File(widget.file.path));
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
    widget.onDuration?.call(controller.value.duration);
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
    final file = widget.file;
    final video = _video;
    return GestureDetector(
      onTap: _toggleSound,
      child: Stack(
        fit: StackFit.expand,
        children: [
          MediaThumb(path: file.path, isVideo: file.isVideo, thumbnails: widget.thumbnails),
          if (widget.active && !file.isVideo)
            Image.file(
              File(file.path),
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
          if (file.isVideo)
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

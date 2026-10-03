import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../format.dart';
import '../media/media_file.dart';
import '../media/native_bridge.dart';
import '../theme.dart';
import '../widgets/media_thumb.dart';
import '../widgets/swipe_card.dart';

/// Tela cheia pra conferir antes de decidir: foto com zoom (pinça e duplo
/// toque), vídeo com som, pausa e barra de progresso arrastável.
/// Devolve a decisão (ou null se só fechou).
class ViewerScreen extends StatefulWidget {
  const ViewerScreen({super.key, required this.file, required this.thumbnails});

  final MediaFile file;
  final Thumbnails thumbnails;

  @override
  State<ViewerScreen> createState() => _ViewerScreenState();
}

class _ViewerScreenState extends State<ViewerScreen> {
  final _zoom = TransformationController();
  VideoPlayerController? _video;

  @override
  void initState() {
    super.initState();
    if (widget.file.isVideo) _loadVideo();
  }

  @override
  void dispose() {
    _zoom.dispose();
    _video?.dispose();
    super.dispose();
  }

  Future<void> _loadVideo() async {
    final controller = VideoPlayerController.file(File(widget.file.path));
    try {
      await controller.initialize();
    } catch (_) {
      await controller.dispose();
      return;
    }
    if (!mounted) {
      await controller.dispose();
      return;
    }
    await controller.setLooping(true);
    await controller.play();
    controller.addListener(() => setState(() {}));
    setState(() => _video = controller);
  }

  void _togglePlay() {
    final video = _video;
    if (video == null) return;
    video.value.isPlaying ? video.pause() : video.play();
  }

  /// Duplo toque alterna entre 1x e 2,5x centrado no toque.
  void _doubleTapZoom(TapDownDetails details) {
    if (_zoom.value.getMaxScaleOnAxis() > 1) {
      _zoom.value = Matrix4.identity();
      return;
    }
    const scale = 2.5;
    final p = details.localPosition;
    _zoom.value = Matrix4.identity()
      ..translateByDouble(-p.dx * (scale - 1), -p.dy * (scale - 1), 0, 1)
      ..scaleByDouble(scale, scale, 1, 1);
  }

  void _decide(SwipeDirection direction) {
    HapticFeedback.lightImpact();
    Navigator.of(context).pop(direction);
  }

  @override
  Widget build(BuildContext context) {
    final file = widget.file;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (file.isVideo) _buildVideo() else _buildPhoto(),
          // topo: fechar + info
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: DecoratedBox(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black87, Colors.transparent],
                ),
              ),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(4, 4, 16, 24),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close_rounded),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(file.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.w700)),
                            Text(
                              '${file.folderName} · ${formatDate(file.modified)}',
                              style: const TextStyle(color: Colors.white70, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      Text(formatBytes(file.size), style: display(18)),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // base: progresso do vídeo + decisão
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: DecoratedBox(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Colors.black87, Colors.transparent],
                ),
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 32, 16, 12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_video != null) ...[
                        _VideoBar(video: _video!, onTogglePlay: _togglePlay),
                        const SizedBox(height: 16),
                      ],
                      Row(
                        children: [
                          Expanded(
                            child: _DecisionButton(
                              label: 'Apagar',
                              icon: Icons.close_rounded,
                              color: AppColors.delete,
                              onTap: () => _decide(SwipeDirection.delete),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _DecisionButton(
                              label: 'Manter',
                              icon: Icons.check_rounded,
                              color: AppColors.keep,
                              onTap: () => _decide(SwipeDirection.keep),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhoto() {
    return GestureDetector(
      onDoubleTapDown: _doubleTapZoom,
      onDoubleTap: () {},
      child: InteractiveViewer(
        transformationController: _zoom,
        maxScale: 6,
        child: Center(
          child: Image.file(
            File(widget.file.path),
            fit: BoxFit.contain,
            cacheWidth: 3000, // nitidez no zoom sem estourar memória
            errorBuilder: (_, _, _) => MediaThumb(
              path: widget.file.path,
              isVideo: false,
              thumbnails: widget.thumbnails,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVideo() {
    final video = _video;
    if (video == null) {
      return Center(
        child: SizedBox.square(
          dimension: 220,
          child: MediaThumb(path: widget.file.path, isVideo: true, thumbnails: widget.thumbnails),
        ),
      );
    }
    return GestureDetector(
      onTap: _togglePlay,
      child: Center(
        child: AspectRatio(
          aspectRatio: video.value.aspectRatio,
          child: Stack(
            alignment: Alignment.center,
            children: [
              VideoPlayer(video),
              if (!video.value.isPlaying)
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: const BoxDecoration(color: Colors.black45, shape: BoxShape.circle),
                  child: const Icon(Icons.play_arrow_rounded, size: 40),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VideoBar extends StatelessWidget {
  const _VideoBar({required this.video, required this.onTogglePlay});

  final VideoPlayerController video;
  final VoidCallback onTogglePlay;

  @override
  Widget build(BuildContext context) {
    final value = video.value;
    return Row(
      children: [
        IconButton(
          onPressed: onTogglePlay,
          icon: Icon(value.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded),
        ),
        Text(formatDuration(value.position), style: const TextStyle(fontSize: 12)),
        const SizedBox(width: 10),
        Expanded(
          child: VideoProgressIndicator(
            video,
            allowScrubbing: true,
            padding: const EdgeInsets.symmetric(vertical: 10),
            colors: const VideoProgressColors(
              playedColor: Colors.white,
              bufferedColor: Colors.white24,
              backgroundColor: Colors.white12,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(formatDuration(value.duration), style: const TextStyle(fontSize: 12)),
      ],
    );
  }
}

class _DecisionButton extends StatelessWidget {
  const _DecisionButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: 0.16),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 15),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 15)),
            ],
          ),
        ),
      ),
    );
  }
}

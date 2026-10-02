import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../media/native_bridge.dart';
import '../theme.dart';

/// Miniatura gerada pelo Android, com cache.
class MediaThumb extends StatelessWidget {
  const MediaThumb({
    super.key,
    required this.path,
    required this.isVideo,
    required this.thumbnails,
  });

  final String path;
  final bool isVideo;
  final Thumbnails thumbnails;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      // O cache devolve o mesmo Future, então rebuild não refaz o trabalho.
      future: thumbnails.of(path, video: isVideo),
      builder: (context, snap) {
        final data = snap.data;
        if (data == null) {
          return ColoredBox(
            color: AppColors.surface2,
            child: snap.connectionState == ConnectionState.done
                ? const Center(child: Icon(Icons.broken_image_outlined, color: AppColors.muted))
                : null,
          );
        }
        return Image.memory(data, fit: BoxFit.cover, gaplessPlayback: true);
      },
    );
  }
}

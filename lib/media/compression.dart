import 'dart:math' as math;

/// Dimensões (já com a rotação aplicada), bitrate e duração de um vídeo.
class VideoInfo {
  const VideoInfo({
    required this.width,
    required this.height,
    required this.bitrate,
    required this.durationMs,
  });

  factory VideoInfo.fromMap(Map<String, int> map) => VideoInfo(
        width: map['width'] ?? 0,
        height: map['height'] ?? 0,
        bitrate: map['bitrate'] ?? 0,
        durationMs: map['durationMs'] ?? 0,
      );

  final int width;
  final int height;

  /// bits/s (vídeo + áudio). 0 quando o arquivo não informa.
  final int bitrate;
  final int durationMs;
}

/// Como comprimir um vídeo e quanto ele deve ficar.
class CompressionPlan {
  const CompressionPlan({
    required this.shortSide,
    required this.bitrate,
    required this.estimatedBytes,
  });

  /// Lado menor do resultado (720 pra vídeo maior que isso).
  final int shortSide;

  /// Bitrate de vídeo pedido ao encoder, em bits/s.
  final int bitrate;
  final int estimatedBytes;
}

/// 720p em H.264 a até 2,5 Mbps: bom pra rever no celular, bem menor que
/// vídeo de câmera (~17 Mbps em 1080p) ou "HD" do WhatsApp.
const targetShortSide = 720;
const maxVideoBitrate = 2500000;
const _audioBitrate = 128000;

/// Só compensa se o resultado estimado ficar com no máximo 70% do original.
const _worthIt = 0.7;

/// Null se não compensa: vídeo já leve (a maioria do que o WhatsApp
/// recomprime ao enviar) ou sem informação suficiente.
CompressionPlan? planCompression(VideoInfo info, {required int fileSize}) {
  if (info.durationMs <= 0 || info.width <= 0 || info.height <= 0) return null;
  final sourceBitrate =
      info.bitrate > 0 ? info.bitrate : (fileSize * 8 * 1000 / info.durationMs).round();
  final videoBitrate = math.min(maxVideoBitrate, (sourceBitrate * 0.6).round());
  final estimated = ((videoBitrate + _audioBitrate) * info.durationMs / 8000).round();
  if (estimated > fileSize * _worthIt) return null;
  return CompressionPlan(
    shortSide: math.min(targetShortSide, math.min(info.width, info.height)),
    bitrate: videoBitrate,
    estimatedBytes: estimated,
  );
}

import 'media_file.dart';

enum MediaKind { all, videos, photos }

class MediaFilter {
  const MediaFilter({this.kind = MediaKind.all, this.bigOnly = false, this.year});

  static const none = MediaFilter();
  static const bigThreshold = 50 * 1000 * 1000; // decimal, igual o formatBytes

  final MediaKind kind;
  final bool bigOnly;

  /// Ano da última modificação do arquivo (pra mídia do WhatsApp, o dia em
  /// que chegou no celular).
  final int? year;

  bool get isEmpty => kind == MediaKind.all && !bigOnly && year == null;

  bool matches(MediaFile file) =>
      switch (kind) {
        MediaKind.all => true,
        MediaKind.videos => file.isVideo,
        MediaKind.photos => !file.isVideo,
      } &&
      (!bigOnly || file.size > bigThreshold) &&
      (year == null || file.modified.year == year);

  MediaFilter copyWith({MediaKind? kind, bool? bigOnly, int? Function()? year}) => MediaFilter(
        kind: kind ?? this.kind,
        bigOnly: bigOnly ?? this.bigOnly,
        year: year == null ? this.year : year(),
      );

  /// "vídeos · > 50 MB · 2024", ou vazio sem filtro.
  String get label => [
        if (kind == MediaKind.videos) 'vídeos',
        if (kind == MediaKind.photos) 'fotos',
        if (bigOnly) '> 50 MB',
        if (year != null) '$year',
      ].join(' · ');

  @override
  bool operator ==(Object other) =>
      other is MediaFilter && other.kind == kind && other.bigOnly == bigOnly && other.year == year;

  @override
  int get hashCode => Object.hash(kind, bigOnly, year);
}

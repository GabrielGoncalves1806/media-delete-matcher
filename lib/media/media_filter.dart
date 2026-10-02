import 'package:photo_manager/photo_manager.dart';

enum MediaKind { all, videos, photos }

/// Filtro aplicado na query do MediaStore (Android).
///
/// Vira um `WHERE` em SQL. O photo_manager descarta o filtro de tipo quando
/// recebe um where próprio, então o `media_type` vai sempre explícito aqui.
class MediaFilter {
  const MediaFilter({this.kind = MediaKind.all, this.bigOnly = false, this.year});

  static const none = MediaFilter();
  static const bigThreshold = 50 * 1024 * 1024;

  final MediaKind kind;
  final bool bigOnly;
  final int? year;

  bool get isEmpty => kind == MediaKind.all && !bigOnly && year == null;

  MediaFilter copyWith({MediaKind? kind, bool? bigOnly, int? Function()? year}) => MediaFilter(
        kind: kind ?? this.kind,
        bigOnly: bigOnly ?? this.bigOnly,
        year: year == null ? this.year : year(),
      );

  RequestType get requestType => switch (kind) {
        MediaKind.all => RequestType.common,
        MediaKind.videos => RequestType.video,
        MediaKind.photos => RequestType.image,
      };

  /// Colunas de MediaStore.Files. Escritas na mão (e não via
  /// `CustomColumns.android`) porque aquele getter recusa rodar fora do
  /// Android, o que impede testar o filtro no computador.
  static const _mediaType = 'media_type';
  static const _size = '_size';
  static const _dateAdded = 'date_added';

  String toSqlWhere() {
    // MediaStore.Files.FileColumns: MEDIA_TYPE_IMAGE = 1, MEDIA_TYPE_VIDEO = 3
    final types = switch (kind) {
      MediaKind.all => '1, 3',
      MediaKind.videos => '3',
      MediaKind.photos => '1',
    };
    final parts = ['$_mediaType IN ($types)'];
    if (bigOnly) parts.add('$_size > $bigThreshold');
    if (year != null) {
      // date_added é em segundos (UTC); horário local é bom o bastante aqui.
      final from = DateTime(year!).millisecondsSinceEpoch ~/ 1000;
      final to = DateTime(year! + 1).millisecondsSinceEpoch ~/ 1000;
      parts.add('$_dateAdded >= $from AND $_dateAdded < $to');
    }
    return parts.join(' AND ');
  }

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

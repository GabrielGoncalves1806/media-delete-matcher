import 'package:flutter_test/flutter_test.dart';
import 'package:media_swipe/media/media_filter.dart';

void main() {
  test('sem filtro: só fotos e vídeos', () {
    expect(MediaFilter.none.toSqlWhere(), 'media_type IN (1, 3)');
    expect(MediaFilter.none.isEmpty, isTrue);
    expect(MediaFilter.none.label, '');
  });

  test('vídeos grandes de um ano', () {
    const filter = MediaFilter(kind: MediaKind.videos, bigOnly: true, year: 2024);
    final from = DateTime(2024).millisecondsSinceEpoch ~/ 1000;
    final to = DateTime(2025).millisecondsSinceEpoch ~/ 1000;

    expect(
      filter.toSqlWhere(),
      'media_type IN (3) AND _size > ${50 * 1024 * 1024} '
      'AND date_added >= $from AND date_added < $to',
    );
    expect(filter.label, 'vídeos · > 50 MB · 2024');
  });

  test('copyWith limpa o ano com null explícito e mantém o resto', () {
    const filter = MediaFilter(kind: MediaKind.photos, year: 2023);

    expect(filter.copyWith(bigOnly: true).year, 2023);
    expect(filter.copyWith(year: () => null).year, isNull);
    expect(filter.copyWith(year: () => null).kind, MediaKind.photos);
    expect(filter.copyWith(kind: MediaKind.all), const MediaFilter(year: 2023));
  });
}

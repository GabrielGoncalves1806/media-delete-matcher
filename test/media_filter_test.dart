import 'package:flutter_test/flutter_test.dart';
import 'package:media_swipe/media/media_file.dart';
import 'package:media_swipe/media/media_filter.dart';

MediaFile file({bool video = false, int mb = 1, int year = 2024}) => MediaFile(
      path: '/x/${video ? 'v.mp4' : 'f.jpg'}',
      size: mb * 1024 * 1024,
      modified: DateTime(year, 6),
      isVideo: video,
    );

void main() {
  test('sem filtro aceita tudo', () {
    expect(MediaFilter.none.isEmpty, isTrue);
    expect(MediaFilter.none.label, '');
    expect(MediaFilter.none.matches(file()), isTrue);
    expect(MediaFilter.none.matches(file(video: true)), isTrue);
  });

  test('vídeos grandes de um ano', () {
    const filter = MediaFilter(kind: MediaKind.videos, bigOnly: true, year: 2024);

    expect(filter.matches(file(video: true, mb: 80, year: 2024)), isTrue);
    expect(filter.matches(file(video: true, mb: 10, year: 2024)), isFalse); // pequeno
    expect(filter.matches(file(video: true, mb: 80, year: 2023)), isFalse); // outro ano
    expect(filter.matches(file(mb: 80, year: 2024)), isFalse); // foto
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

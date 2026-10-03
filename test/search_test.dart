import 'package:flutter_test/flutter_test.dart';
import 'package:media_swipe/media/media_file.dart';
import 'package:media_swipe/media/media_filter.dart';
import 'package:media_swipe/media/search.dart';

const _phone = '/storage/emulated/0';
const _card = '/storage/48CA-D0FC';

MediaFile f(String path, {int size = 10, int year = 2024, bool video = false}) => MediaFile(
      path: path,
      size: size,
      modified: DateTime(year),
      isVideo: video,
    );

final _files = [
  f('$_phone/DCIM/Camera/IMG_2024.jpg', size: 30, year: 2024),
  f('$_phone/Android/media/com.whatsapp/WhatsApp/Media/WhatsApp Video/VID-20230101.mp4',
      size: 500, year: 2023, video: true),
  f('$_phone/Pictures/Câmera Antiga/foto.jpg', size: 5, year: 2019),
  f('$_card/DCIM/Viagem/praia.mp4', size: 200, year: 2022, video: true),
];

List<String> names(List<MediaFile> files) => files.map((e) => e.name).toList();

void main() {
  test('sem texto lista tudo, do maior pro menor', () {
    expect(names(searchFiles(_files)), ['VID-20230101.mp4', 'praia.mp4', 'IMG_2024.jpg', 'foto.jpg']);
  });

  test('acha por pasta, sem ligar pra acento e maiúscula', () {
    expect(names(searchFiles(_files, query: 'camera', roots: [_phone, _card])), ['IMG_2024.jpg', 'foto.jpg']);
    expect(names(searchFiles(_files, query: 'WHATSAPP')), ['VID-20230101.mp4']);
  });

  test('várias palavras: todas têm que aparecer', () {
    expect(names(searchFiles(_files, query: 'dcim viagem', roots: [_phone, _card])), ['praia.mp4']);
    expect(searchFiles(_files, query: 'dcim whatsapp', roots: [_phone, _card]), isEmpty);
  });

  test('a raiz do volume não entra na busca', () {
    // "emulated" e "storage" estão no caminho de tudo, mas são da raiz
    expect(searchFiles(_files, query: 'emulated', roots: [_phone, _card]), isEmpty);
    expect(searchFiles(_files, query: '48ca', roots: [_phone, _card]), isEmpty);
  });

  test('filtro, volume e ordem por data', () {
    expect(
      names(searchFiles(_files, filter: const MediaFilter(kind: MediaKind.videos), volume: _card)),
      ['praia.mp4'],
    );
    expect(names(searchFiles(_files, sort: SearchSort.oldest)).first, 'foto.jpg');
    expect(names(searchFiles(_files, sort: SearchSort.newest)).first, 'IMG_2024.jpg');
  });

  test('normalize', () {
    expect(normalize('Câmera Ação ÇÃO'), 'camera acao cao');
  });
}

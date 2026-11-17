import 'package:flutter_test/flutter_test.dart';

import 'package:ultimate_mobile/services/local_music.dart';

void main() {
  group('SongInfo.fromMap', () {
    test('alandan okur ve süreyi mm:ss biçimine çevirir', () {
      final song = SongInfo.fromMap({
        'id': 7,
        'title': 'Parça',
        'artist': 'Sanatçı',
        'album': 'Albüm',
        'duration': 125000,
        'uri': 'content://media/external/audio/media/7',
      });

      expect(song.id, 7);
      expect(song.title, 'Parça');
      expect(song.artist, 'Sanatçı');
      expect(song.album, 'Albüm');
      expect(song.durationLabel, '2:05');
      expect(song.uri, endsWith('/7'));
    });

    test('eksik alanlarda varsayılanları kullanır', () {
      final song = SongInfo.fromMap({'id': 1});

      expect(song.title, 'Bilinmeyen Parça');
      expect(song.artist, 'Bilinmeyen Sanatçı');
      expect(song.album, isNull);
      expect(song.durationMs, 0);
      expect(song.durationLabel, '0:00');
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:ultimate_mobile/services/import_parser.dart';
import 'package:ultimate_mobile/services/local_music.dart';

SongInfo _song(int id, String title) => SongInfo(
      id: id,
      title: title,
      artist: 'Sanatçı',
      album: null,
      durationMs: 0,
      uri: 'content://media/external/audio/media/$id',
      mimeType: 'audio/mpeg',
    );

void main() {
  group('ImportParser.extractNames', () {
    test('m3u8 dosyasından EXTINF başlıklarını ve dosya adlarını çıkarır', () {
      const content = '''
#EXTM3U
#EXTINF:-1,Artist - Song A
content://media/external/audio/media/1
#EXTINF:-1,Song B
/storage/emulated/0/Music/Song_B.mp3
''';
      final names = ImportParser.extractNames(content);
      expect(names, containsAll(<String>['Artist - Song A', 'Song B', 'Song_B.mp3']));
      // content:// uri satırı sayısal kimlik olarak eklenmemeli
      expect(names, isNot(contains('1')));
    });

    test('düz metinde her satır bir şarkıdır, boşlar atlanır', () {
      const content = 'A Cruel Angel\'s Thesis\n\n  Zoltraak  \n';
      final names = ImportParser.extractNames(content);
      expect(names, <String>['A Cruel Angel\'s Thesis', 'Zoltraak']);
    });

    test('yorum satırları (#) atlanır', () {
      const content = '# Ultimate Asistan - Arşiv\nŞarkı 1\n#EXTM3U\nŞarkı 2';
      final names = ImportParser.extractNames(content);
      expect(names, <String>['Şarkı 1', 'Şarkı 2']);
    });

    test('"# - " önekli gerçek dosya adları başlık sayılır', () {
      const content = '#EXTM3U\n# - One Piece Opening 24\n# yorum satırı\n'
          '# PLAYER\nNormal Şarkı';
      final names = ImportParser.extractNames(content);
      expect(names, contains('# - One Piece Opening 24'));
      expect(names, contains('Normal Şarkı'));
      expect(names, isNot(contains('# yorum satırı')));
      expect(names, isNot(contains('# PLAYER')));
    });
  });

  group('ImportParser.normalize', () {
    test('uzantı, parantez, köşeli parantez ve noktalamayı temizler', () {
      final n = ImportParser.normalize(
        'Zoltraak (EPIC VERSION) _ Frieren_ Beyond Journeys End [xPJFC5ZKl-Q].mp3',
      );
      expect(n, contains('zoltraak'));
      expect(n, contains('frieren'));
      expect(n, isNot(contains('(')));
      expect(n, isNot(contains('[')));
      expect(n, isNot(contains('_')));
      expect(n, isNot(contains('.')));
    });

    test('ASCII dışı alfabeler korunur (CJK başlıklar boşa düşmez)', () {
      expect(ImportParser.normalize('残酷な天使のテーゼ'), isNotEmpty);
      expect(ImportParser.normalize('おっぱいドラゴンの歌'), 'おっぱいドラゴンの歌');
    });
  });

  group('SongMatcher', () {
    late SongMatcher matcher;

    setUp(() {
      matcher = SongMatcher([
        _song(1, 'A Cruel Angel\'s Thesis'),
        _song(2, 'Zoltraak (EPIC VERSION) _ Frieren Beyond Journeys End'),
        _song(3, '# - 静寂のアポストル'),
        _song(4, 'Silhouette'),
      ]);
    });

    test('birebir başlığı eşler', () {
      expect(matcher.matchName('A Cruel Angel\'s Thesis')?.id, 1);
    });

    test('kısmi adı içeren şarkıyı eşler', () {
      expect(matcher.matchName('Zoltraak')?.id, 2);
      expect(matcher.matchName('Silhouette')?.id, 4);
    });

    test('dosya adı/uzantılı adı eşler', () {
      expect(matcher.matchName('Silhouette.mp3')?.id, 4);
    });

    test('alakasız adı eşleştirmez', () {
      expect(matcher.matchName('Tamamen Alakasız Bir Şarkı Adı'), isNull);
    });

    test('matchAll her satır için bir sonuç üretir', () {
      final entries = matcher.matchAll(['Silhouette', 'Yok Böyle Bir Şey']);
      expect(entries.length, 2);
      expect(entries[0].matched, isTrue);
      expect(entries[1].matched, isFalse);
    });

    test('CJK ve "# - " önekli başlıkları eşler', () {
      expect(matcher.matchName('静寂のアポストル')?.id, 3);
      expect(matcher.matchName('# - 静寂のアポストル')?.id, 3);
    });
  });

  group('SongInfo.isMidi', () {
    test('midi uzantısını ve mime tipini tanır', () {
      final mid = SongInfo(
        id: 1,
        title: 'X',
        artist: 'Y',
        album: null,
        durationMs: 0,
        uri: 'content://media/external/audio/media/9',
        mimeType: 'audio/midi',
      );
      expect(mid.isMidi, isTrue);

      final midByExt = SongInfo(
        id: 2,
        title: 'X',
        artist: 'Y',
        album: null,
        durationMs: 0,
        uri: '/sdcard/8 bit music/demo.mid',
        mimeType: null,
      );
      expect(midByExt.isMidi, isTrue);

      expect(_song(3, 'Normal').isMidi, isFalse);
    });
  });
}

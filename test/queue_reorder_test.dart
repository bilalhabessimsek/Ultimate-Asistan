import 'package:flutter_test/flutter_test.dart';
import 'package:ultimate_mobile/services/local_music.dart';
import 'package:ultimate_mobile/services/player_controller.dart';

SongInfo _song(int id) => SongInfo(
      id: id,
      title: 'Song $id',
      artist: 'Artist',
      album: 'Album',
      durationMs: 1000 * id,
      uri: 'content://media/external/audio/media/$id',
    );

List<int> _ids(PlayerController c) =>
    List<int>.generate(c.queueLength, (i) => c.songAt(i).id);

void main() {
  // AudioPlayer (just_audio) bir platform kanalı kullandığı için gerekli.
  TestWidgetsFlutterBinding.ensureInitialized();

  test('kuyruk tekilleştirme, sürükle-bırak sıralaması ve sıralama ölçütü',
      () async {
    final c = PlayerController.instance;

    // Çalmadan yükle; aynı id iki kez verilir (tekilleşmeli).
    await c.setQueue([_song(1), _song(2), _song(2), _song(3)], autoPlay: false);
    expect(_ids(c), [1, 2, 3]);

    // Var olan şarkıyı eklemek false döner (kopya oluşmaz).
    expect(c.enqueue(_song(2)), isFalse);
    expect(_ids(c), [1, 2, 3]);

    // 0. şarkıyı 2. sıraya taşı -> [2, 3, 1]
    c.reorder(0, 3);
    expect(_ids(c), [2, 3, 1]);

    // Sondan başa taşı -> [1, 2, 3]
    c.reorder(2, 0);
    expect(_ids(c), [1, 2, 3]);

    // Ada göre azalan sıralama ve karışığın kapanması.
    c.sortQueue(QueueSort.name, ascending: false);
    expect(_ids(c), [3, 2, 1]);
    expect(c.shuffle, isFalse);

    // Süreye göre artan (id = saniye) -> [1, 2, 3]
    c.sortQueue(QueueSort.duration, ascending: true);
    expect(_ids(c), [1, 2, 3]);
  });
}

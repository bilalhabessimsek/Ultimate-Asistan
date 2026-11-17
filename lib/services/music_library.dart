import 'package:flutter/foundation.dart';

import 'local_music.dart';

/// Telefondaki müzik arşivini (MediaStore) tek noktadan yükleyip ekranlar
/// arasında paylaşan basit önbellek.
///
/// Böylece "Müzik Çalar", "Listelerim", "Liste Detayı" ve "İçe Aktar"
/// ekranları aynı listeyi yeniden yeniden taramak zorunda kalmaz.
class MusicLibrary extends ChangeNotifier {
  MusicLibrary._();

  static final MusicLibrary instance = MusicLibrary._();

  final LocalMusicService _music = LocalMusicService();

  List<SongInfo> songs = const [];
  List<PlaylistInfo> devicePlaylists = const [];
  Map<int, SongInfo> index = const {};

  /// Masaüstüyle ortak `trackId` -> şarkı eşlemesi (senkron için).
  Map<String, SongInfo> byTrackId = const {};
  bool hasPermission = false;
  bool loading = true;

  /// Kütüphane hazır mı? (trackId eşlemesi yapılabilir mi?)
  bool get isReady => !loading;

  /// Şarkının masaüstüyle ortak kimliği (yoksa `null`).
  String? trackIdOf(int songId) {
    final id = index[songId]?.trackId;
    return (id == null || id.isEmpty) ? null : id;
  }

  /// Ortak kimlikten telefondaki şarkıya (telefonda yoksa `null`).
  SongInfo? songForTrackId(String trackId) => byTrackId[trackId];

  /// Ortak kimlik listesini telefondaki şarkı id'lerine çevirir.
  List<int> idsForTrackIds(Iterable<String> trackIds) => trackIds
      .map((t) => byTrackId[t]?.id)
      .whereType<int>()
      .toList(growable: false);

  bool _started = false;

  Future<void> ensureLoaded() async {
    if (_started) return;
    _started = true;
    await reload();
  }

  Future<void> reload() async {
    loading = true;
    notifyListeners();

    var granted = await _music.hasPermission();
    if (!granted) granted = await _music.requestPermission();

    var loadedSongs = const <SongInfo>[];
    var loadedPlaylists = const <PlaylistInfo>[];
    if (granted) {
      final results = await Future.wait([
        _music.querySongs(),
        _music.queryPlaylists(),
      ]);
      loadedSongs = results[0] as List<SongInfo>;
      loadedPlaylists = results[1] as List<PlaylistInfo>;
    }

    // Şarkı içeren listeler en üste gelsin (boş sistem artıkları sonda).
    final sorted = [...loadedPlaylists]..sort((a, b) {
        if (a.count != b.count) return b.count.compareTo(a.count);
        return a.name.compareTo(b.name);
      });

    songs = loadedSongs;
    index = {for (final s in loadedSongs) s.id: s};
    final byId = <String, SongInfo>{};
    for (final s in loadedSongs) {
      if (s.trackId.isNotEmpty) byId[s.trackId] = s;
    }
    byTrackId = byId;
    devicePlaylists = sorted;
    hasPermission = granted;
    loading = false;
    notifyListeners();
  }

  List<SongInfo> songsForIds(Iterable<int> ids) =>
      ids.map((id) => index[id]).whereType<SongInfo>().toList();
}

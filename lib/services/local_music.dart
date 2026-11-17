import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Telefondaki yerel bir şarkıyı temsil eder.
class SongInfo {
  final int id;
  final String title;
  final String artist;
  final String? album;
  final int durationMs;
  final String uri;
  final String? mimeType;

  /// MediaStore `DATE_ADDED` (saniye). Sıralama için kullanılır.
  final int dateAdded;

  /// Masaüstü ("ULTİMATE") uygulamasıyla **ortak** kararlı kimlik:
  /// depolama köküne göre göreli yolun küçük harfli hâli (`music/rock/x.mp3`).
  /// Çalma listelerini Supabase üzerinden senkronlamak için kullanılır.
  final String trackId;

  SongInfo({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.durationMs,
    required this.uri,
    this.mimeType,
    this.dateAdded = 0,
    this.trackId = '',
  });

  factory SongInfo.fromMap(Map<dynamic, dynamic> map) {
    return SongInfo(
      id: (map['id'] as num?)?.toInt() ?? 0,
      title: (map['title'] ?? 'Bilinmeyen Parça').toString(),
      artist: (map['artist'] ?? 'Bilinmeyen Sanatçı').toString(),
      album: map['album']?.toString(),
      durationMs: (map['duration'] as num?)?.toInt() ?? 0,
      uri: (map['uri'] ?? '').toString(),
      mimeType: map['mime']?.toString(),
      dateAdded: (map['dateAdded'] as num?)?.toInt() ?? 0,
      trackId: (map['trackId'] ?? '').toString(),
    );
  }

  /// MIDI / XMF / RTTTL gibi sentezlenen dosyalar mı? (ExoPlayer bunları
  /// çalamaz; yerleşik MediaPlayer ile çalınır.)
  bool get isMidi {
    final m = (mimeType ?? '').toLowerCase();
    if (m.contains('midi') ||
        m.contains('xmf') ||
        m.contains('sp-midi') ||
        m.contains('rtttl') ||
        m.contains('mobile-xmf')) {
      return true;
    }
    final u = uri.toLowerCase();
    for (final ext in const [
      '.mid',
      '.midi',
      '.xmf',
      '.mxmf',
      '.rtttl',
      '.rtx',
      '.ota',
      '.imy',
    ]) {
      if (u.endsWith(ext)) return true;
    }
    return false;
  }

  /// 'mm:ss' biçiminde süre.
  String get durationLabel {
    final totalSeconds = (durationMs / 1000).round();
    final minutes = totalSeconds ~/ 60;
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

/// Başka bir uygulamanın (MediaStore üzerinden) oluşturduğu çalma listesi.
class PlaylistInfo {
  final int id;
  final String name;
  final int count;

  PlaylistInfo({required this.id, required this.name, required this.count});

  factory PlaylistInfo.fromMap(Map<dynamic, dynamic> map) {
    return PlaylistInfo(
      id: (map['id'] as num?)?.toInt() ?? 0,
      name: (map['name'] ?? 'Liste').toString(),
      count: (map['count'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Telefondaki müzikleri MediaStore üzerinden tarayan köprü
/// (`android/.../MainActivity.kt` içindeki kanal ile konuşur).
class LocalMusicService {
  static const MethodChannel _channel = MethodChannel('ultimate_mobile/media');

  Future<bool> hasPermission() async {
    try {
      final result = await _channel.invokeMethod<bool>('hasPermission');
      return result ?? false;
    } on PlatformException catch (err) {
      debugPrint('İzin sorgulanamadı: ${err.message}');
      return false;
    } on MissingPluginException {
      // Masaüstü/test ortamında kanal yok; sessizce başarısız ol.
      return false;
    }
  }

  Future<bool> requestPermission() async {
    try {
      final result = await _channel.invokeMethod<bool>('requestPermission');
      return result ?? false;
    } on PlatformException catch (err) {
      debugPrint('İzin istenemedi: ${err.message}');
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<List<SongInfo>> querySongs() async {
    try {
      final result = await _channel.invokeMethod<List<dynamic>>('querySongs');
      if (result == null) return const [];
      return result
          .whereType<Map<dynamic, dynamic>>()
          .map(SongInfo.fromMap)
          .toList();
    } on PlatformException catch (err) {
      debugPrint('Şarkılar taranamadı: ${err.message}');
      return const [];
    } on MissingPluginException {
      return const [];
    }
  }

  /// Cihazdaki diğer uygulamaların MediaStore'a yazdığı çalma listeleri.
  Future<List<PlaylistInfo>> queryPlaylists() async {
    try {
      final result =
          await _channel.invokeMethod<List<dynamic>>('queryPlaylists');
      if (result == null) return const [];
      return result
          .whereType<Map<dynamic, dynamic>>()
          .map(PlaylistInfo.fromMap)
          .toList();
    } on PlatformException catch (err) {
      debugPrint('Listeler taranamadı: ${err.message}');
      return const [];
    } on MissingPluginException {
      return const [];
    }
  }

  /// Bir çalma listesinin şarkıları.
  Future<List<SongInfo>> queryPlaylistSongs(int playlistId) async {
    try {
      final result = await _channel.invokeMethod<List<dynamic>>(
        'queryPlaylistSongs',
        {'playlistId': playlistId},
      );
      if (result == null) return const [];
      return result
          .whereType<Map<dynamic, dynamic>>()
          .map(SongInfo.fromMap)
          .toList();
    } on PlatformException catch (err) {
      debugPrint('Liste şarkıları alınamadı: ${err.message}');
      return const [];
    } on MissingPluginException {
      return const [];
    }
  }
}

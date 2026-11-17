import '../services/local_music.dart';

/// Müzik arayüzlerinde kullanılan küçük biçimlendirme yardımcıları.
class MusicFormat {
  MusicFormat._();

  /// `m:ss` (gerekiyorsa `h:mm:ss`).
  static String duration(Duration d) {
    final total = d.inSeconds;
    if (total <= 0) return '0:00';
    final hours = total ~/ 3600;
    final minutes = (total % 3600) ~/ 60;
    final seconds = (total % 60).toString().padLeft(2, '0');
    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:$seconds';
    }
    return '$minutes:$seconds';
  }

  /// Ses kalitesi/format etiketi (MP3, M4A, MIDI...).
  static String formatLabel(SongInfo? song) {
    if (song == null) return 'AUDIO';
    final uri = song.uri.toLowerCase();
    final dot = uri.lastIndexOf('.');
    if (dot >= 0 && dot < uri.length - 1) {
      final ext = uri.substring(dot + 1).split('?').first;
      if (ext.isNotEmpty && ext.length <= 5) return ext.toUpperCase();
    }
    final mime = (song.mimeType ?? '').toLowerCase();
    if (mime.contains('mpeg')) return 'MP3';
    if (mime.contains('mp4') || mime.contains('m4a') || mime.contains('aac')) {
      return 'M4A';
    }
    if (mime.contains('flac')) return 'FLAC';
    if (mime.contains('wav')) return 'WAV';
    if (mime.contains('ogg')) return 'OGG';
    return song.isMidi ? 'MIDI' : 'AUDIO';
  }

  /// Plak ortasındaki harf.
  static String discLetter(String? title) {
    final t = (title ?? '').trim();
    for (final rune in t.runes) {
      final ch = String.fromCharCode(rune);
      if (RegExp(r'[A-Za-z0-9]').hasMatch(ch)) return ch.toUpperCase();
    }
    return '♪';
  }

  /// Dosya sistemi için güvenli ad.
  static String safeFileName(String name) {
    final cleaned = name.replaceAll(RegExp(r'[\\/:*?"<>|]+'), '_').trim();
    return cleaned.isEmpty ? 'liste' : cleaned;
  }
}

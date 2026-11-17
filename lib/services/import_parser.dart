import 'dart:math' as math;

import 'local_music.dart';

/// İçe aktarma önizlemesindeki tek bir satır: ham metin + eşleşen şarkı.
class ImportEntry {
  final String raw;
  final SongInfo? song;

  ImportEntry(this.raw, this.song);

  bool get matched => song != null;
}

/// TXT / CSV / M3U içeriğini şarkı adlarına ayırır ve arşivdeki şarkılarla
/// eşleştirir. Dosya adı, başlık ve sanatçı bilgisi esnek biçimde eşlenir.
class ImportParser {
  /// Metinden şarkı adaylarını çıkarır.
  static List<String> extractNames(String content) {
    final names = <String>[];
    for (final line in content.split(RegExp(r'\r\n|\r|\n'))) {
      final l = line.trim();
      if (l.isEmpty) continue;

      if (l.startsWith('#')) {
        final upper = l.toUpperCase();
        // #EXTINF:-1,Sanatçı - Şarkı  -> başlığı al
        if (upper.startsWith('#EXTINF')) {
          final i = l.indexOf(',');
          if (i >= 0) {
            final t = l.substring(i + 1).trim();
            if (t.isNotEmpty) names.add(t);
          }
        }
        // m3u/m3u8 yönergeleri (#EXTM3U, #PLAYLIST, ...) ve yorum satırları
        // atlanır. Ancak bazı arşivler (ör. XMusic) bulunamayan parçaları
        // "# - Şarkı Adı" biçiminde adlandırır; bu satırlar başlık sayılır.
        final brokenName = RegExp(r'^#\s*[-–—]\s*').hasMatch(l);
        if (upper.startsWith('#EXT') ||
            upper.startsWith('#PLAYLIST') ||
            !brokenName) {
          continue;
        }
      }

      // MediaStore uri satırları sayısal kimlik içerir; başlık yukarıdaki
      // #EXTINF satırından zaten alındı, bu yüzden atlanır.
      if (l.startsWith('content://')) continue;

      // Satır bir yol/uri olabilir; dosya adına indirge.
      final base = _basename(l);
      if (base.isNotEmpty) names.add(base);
    }
    return names;
  }

  static String _basename(String rawPath) {
    var p = rawPath.replaceAll('\\', '/').trim();
    final q = p.indexOf('?');
    if (q >= 0) p = p.substring(0, q);
    final slash = p.lastIndexOf('/');
    if (slash >= 0) p = p.substring(slash + 1);
    try {
      p = Uri.decodeComponent(p);
    } catch (_) {}
    return p.trim();
  }

  /// Karşılaştırma için sadeleştirme: uzantı, [youtube id], parantez,
  /// alt çizgi/tire ve noktalama temizlenir; küçük harfe indirilir.
  static String normalize(String input) {
    var t = input.toLowerCase();
    t = t.replaceAll(RegExp(r'\.[a-z0-9]{2,5}$'), ' ');
    t = t.replaceAll(RegExp(r'\[[^\]]*\]'), ' ');
    t = t.replaceAll(RegExp(r'\([^)]*\)'), ' ');
    t = t.replaceAll(RegExp(r'[_\-.]+'), ' ');
    // Tüm alfabelerin harfleri/rakamları korunur (CJK, Kiril, Arapça...).
    // Aksi halde yalnızca başka bir alfabeyle yazılmış başlıklar tamamen
    // boşa düşüyor ve hiçbir şarkıyla eşleşemiyordu.
    t = t.replaceAll(RegExp(r'[^\p{L}\p{N} ]+', unicode: true), ' ');
    t = t.replaceAll(RegExp(r'\s+'), ' ').trim();
    return t;
  }
}

/// Arşivdeki şarkıları normalize edilmiş başlıklarına göre indeksler ve gelen
/// adları en uygun şarkıyla eşler.
class SongMatcher {
  SongMatcher(this.songs) {
    for (final s in songs) {
      final n = ImportParser.normalize(s.title);
      if (n.isEmpty) continue;
      _byNorm.putIfAbsent(n, () => s);
    }
    _entries = _byNorm.entries.toList(growable: false);
  }

  final List<SongInfo> songs;
  final Map<String, SongInfo> _byNorm = {};
  late final List<MapEntry<String, SongInfo>> _entries;

  List<ImportEntry> matchAll(Iterable<String> names) =>
      names.map((n) => ImportEntry(n, matchName(n))).toList();

  SongInfo? matchName(String raw) {
    final q = ImportParser.normalize(raw);
    if (q.isEmpty) return null;

    final exact = _byNorm[q];
    if (exact != null) return exact;

    SongInfo? best;
    var bestScore = 0.0;
    for (final e in _entries) {
      final score = _score(q, e.key);
      if (score > bestScore) {
        bestScore = score;
        best = e.value;
      }
    }
    return bestScore >= 0.62 ? best : null;
  }

  double _score(String q, String t) {
    if (q == t) return 1;

    if (t.contains(q) || q.contains(t)) {
      final ratio = math.min(q.length, t.length) / math.max(q.length, t.length);
      return 0.70 + 0.25 * ratio;
    }

    final qs = q.split(' ').where((e) => e.isNotEmpty).toSet();
    final ts = t.split(' ').where((e) => e.isNotEmpty).toSet();
    if (qs.isEmpty || ts.isEmpty) return 0;
    final inter = qs.intersection(ts).length;
    if (inter == 0) return 0;
    return (inter / math.max(qs.length, ts.length)) * 0.85;
  }
}

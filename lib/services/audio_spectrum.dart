import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'local_music.dart';

/// Bir şarkı için çıkarılmış 8 bantlık seviye zarfı.
///
/// Veriler şarkının **kendi** sesinden (dosya çözülerek) üretilir; her bayt
/// 0..255 arası normalize edilmiş seviyedir (bas -> tiz).
class SpectrumEnvelope {
  SpectrumEnvelope({
    required this.fps,
    required this.bands,
    required this.data,
  });

  /// Saniyedeki kare sayısı (ör. 21.5).
  final double fps;

  /// Bant sayısı (8).
  final int bands;

  /// `frameCount * bands` uzunluğunda seviyeler.
  final Uint8List data;

  int get frameCount => bands <= 0 ? 0 : data.length ~/ bands;

  /// Verilen konuma karşılık gelen kare indeksi.
  int frameIndexAt(Duration position) {
    if (fps <= 0 || frameCount <= 0) return 0;
    final ms = position.inMilliseconds;
    if (ms <= 0) return 0;
    final index = (ms * fps / 1000.0).floor();
    return index.clamp(0, frameCount - 1);
  }
}

/// Şarkı dosyasını yerel tarafta çözdürüp 8 bantlık bas/tiz zarfı alır.
///
/// Mikrofon izni GEREKMEZ, hiçbir ses kaydedilmez; dosya yalnızca okunur.
/// Şarkı başına ~40 KB bellek kullanır ve sonuçlar önbelleğe alınır.
class AudioSpectrum {
  AudioSpectrum._();

  static final AudioSpectrum instance = AudioSpectrum._();

  static const MethodChannel _channel =
      MethodChannel('ultimate_mobile/spectrum');

  /// Yerel tarafla aynı olmalı.
  static const int bandCount = 8;

  /// Önbellekte tutulacak en fazla şarkı zarfı.
  static const int _maxCache = 4;

  final Map<int, SpectrumEnvelope?> _cache = <int, SpectrumEnvelope?>{};

  /// Zarf hazır olduğunda artar; arayüz buna göre yeniden çizer.
  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  /// Zarf hazırsa döndürür; yoksa/başarısızsa `null`.
  SpectrumEnvelope? envelopeOf(int songId) => _cache[songId];

  /// Analizin denenip başarısız olduğu şarkılar (tekrar denenmez).
  bool isUnsupported(int songId) =>
      _cache.containsKey(songId) && _cache[songId] == null;

  /// Analizi (gerekirse) başlatır. Hazır olunca `revision` artar.
  Future<void> prepare(SongInfo song) async {
    if (song.id <= 0 || _cache.containsKey(song.id)) return;
    if (song.uri.isEmpty || song.isMidi) {
      _cache[song.id] = null;
      return;
    }
    // Aynı şarkı için ikinci bir analiz başlatma.
    _cache[song.id] = null;
    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'analyze',
        <String, dynamic>{'uri': song.uri},
      );
      final data = result?['data'];
      final fps = (result?['fps'] as num?)?.toDouble() ?? 0;
      final bands = (result?['bands'] as num?)?.toInt() ?? bandCount;
      if (data is Uint8List && fps > 0 && data.isNotEmpty) {
        _cache[song.id] = SpectrumEnvelope(fps: fps, bands: bands, data: data);
        _evict();
        revision.value++;
      }
    } catch (err) {
      debugPrint('Spektrum analizi başarısız: $err');
    }
  }

  void _evict() {
    while (_cache.length > _maxCache) {
      final first = _cache.keys.first;
      _cache.remove(first);
    }
  }
}

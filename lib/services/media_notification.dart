import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Bildirim panelindeki / kilit ekranındaki müzik kontrolüyle konuşan köprü.
///
/// Yerel tarafta bir ön plan servisi (`MediaPlaybackService`) ve yerleşik
/// `MediaSession` + `Notification.MediaStyle` kullanılır. Böylece uygulama
/// arka plandayken de müzik çalar; bildirimdeki düğmeler ve Bluetooth kulaklık
/// tuşları çalışır.
///
/// Bildirimdeki bir düğmeye basıldığında `onAction` geri çağrısı tetiklenir.
class MediaNotification {
  MediaNotification._();

  static final MediaNotification instance = MediaNotification._();

  static const MethodChannel _channel =
      MethodChannel('ultimate_mobile/media_notification');

  /// Bildirimden gelen komut: 'play', 'pause', 'toggle', 'next',
  /// 'previous', 'stop' ya da 'seek:<milis>'.
  void Function(String action)? onAction;

  bool _available = true;
  bool _bound = false;

  String _lastTitle = '';
  String _lastArtist = '';
  bool _lastPlaying = false;
  bool _lastHasNext = false;
  bool _lastHasPrev = false;
  bool _lastVisible = false;
  DateTime _lastSentAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// Yerel köprüyü dinlemeye başlar (bir kez).
  void bind() {
    if (_bound) return;
    _bound = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'action') {
        onAction?.call(call.arguments?.toString() ?? '');
      }
      return null;
    });
  }

  /// Android 13+ için bildirim izni ister (verilmezse bildirim görünmez).
  Future<void> requestPermission() async {
    if (!_available) return;
    try {
      await _channel.invokeMethod<bool>('requestPermission');
    } on MissingPluginException {
      _available = false;
    } catch (err) {
      debugPrint('Bildirim izni istenemedi: $err');
    }
  }

  /// Bildirimi günceller. Aynı bilgiler kısa süre içinde tekrar gönderilmez.
  void update({
    required String title,
    required String artist,
    required bool playing,
    required int positionMs,
    required int durationMs,
    required bool hasNext,
    required bool hasPrev,
  }) {
    if (!_available) return;
    final now = DateTime.now();
    final sameMeta = _lastVisible &&
        title == _lastTitle &&
        artist == _lastArtist &&
        playing == _lastPlaying &&
        hasNext == _lastHasNext &&
        hasPrev == _lastHasPrev;
    // Yalnızca konum değiştiyse en fazla saniyede bir gönder.
    if (sameMeta && now.difference(_lastSentAt) < const Duration(seconds: 1)) {
      return;
    }

    _lastTitle = title;
    _lastArtist = artist;
    _lastPlaying = playing;
    _lastHasNext = hasNext;
    _lastHasPrev = hasPrev;
    _lastVisible = true;
    _lastSentAt = now;

    _invoke('update', <String, dynamic>{
      'title': title,
      'artist': artist,
      'playing': playing,
      'positionMs': positionMs,
      'durationMs': durationMs,
      'hasNext': hasNext,
      'hasPrev': hasPrev,
    });
  }

  /// Bildirimi gizler (servisi durdurur).
  void stop() {
    if (!_available || !_lastVisible) return;
    _lastVisible = false;
    _invoke('stop', null);
  }

  void _invoke(String method, Object? args) {
    _channel.invokeMethod<void>(method, args).catchError((Object err) {
      if (err is MissingPluginException) _available = false;
      return null;
    });
  }
}

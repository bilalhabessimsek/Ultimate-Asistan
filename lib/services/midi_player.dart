import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// MIDI dosyalarını Android'in yerleşik `MediaPlayer`'ı (Sonivox synth) ile
/// çalan köprü. `just_audio`/ExoPlayer MIDI desteklemediği için ayrı bir yol
/// kullanıyoruz (`MainActivity.kt` -> "ultimate_mobile/midi" kanalı).
class MidiPlayer {
  static const MethodChannel _channel = MethodChannel('ultimate_mobile/midi');
  static const EventChannel _events =
      EventChannel('ultimate_mobile/midi_events');

  /// Parça bitince "completed" olayı yayınlar.
  Stream<dynamic> get events => _events.receiveBroadcastStream();

  /// Belirtilen uri'yi çalar. Hazır olunca `true` döner.
  Future<bool> play(String uri) async {
    try {
      final ok = await _channel.invokeMethod<bool>('play', {'uri': uri});
      return ok ?? false;
    } on PlatformException catch (e) {
      debugPrint('MIDI çalınamadı: ${e.message}');
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<void> pause() async {
    try {
      await _channel.invokeMethod('pause');
    } catch (_) {}
  }

  Future<void> resume() async {
    try {
      await _channel.invokeMethod('resume');
    } catch (_) {}
  }

  Future<void> stop() async {
    try {
      await _channel.invokeMethod('stop');
    } catch (_) {}
  }

  Future<bool> isPlaying() async {
    try {
      return await _channel.invokeMethod<bool>('isPlaying') ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> setVolume(double volume) async {
    try {
      await _channel.invokeMethod('setVolume', {'volume': volume});
    } catch (_) {}
  }

  /// Geçerli konum (ms) veya bilinmiyorsa `null`.
  Future<int?> position() async {
    try {
      return await _channel.invokeMethod<int>('position');
    } catch (_) {
      return null;
    }
  }

  /// Parça süresi (ms) veya bilinmiyorsa `null`.
  Future<int?> duration() async {
    try {
      return await _channel.invokeMethod<int>('duration');
    } catch (_) {
      return null;
    }
  }

  Future<void> seek(int ms) async {
    try {
      await _channel.invokeMethod('seek', {'ms': ms});
    } catch (_) {}
  }

  /// Çalan MIDI parçasının ses oturumu kimliği (görselleştirici için).
  /// Bilinmiyorsa `0` döner.
  Future<int> audioSessionId() async {
    try {
      return await _channel.invokeMethod<int>('sessionId') ?? 0;
    } catch (_) {
      return 0;
    }
  }
}

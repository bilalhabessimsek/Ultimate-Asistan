import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Basit anahtar/değer ayar deposu.
///
/// Öncelik sırası:
///   1. Supabase `music_state` tablosu (cihazlar arası senkron).
///   2. Yerel `shared_preferences` (çevrimdışı / tablo erişilemezse yedek).
///
/// Böylece Supabase'e erişim olmasa bile ayarlar kaybolmaz ve ekrana
/// hata basılmaz.
class SettingsStore {
  static const String _localPrefix = 'setting_';

  Future<String> get(String key) async {
    try {
      final client = Supabase.instance.client;
      if (client.auth.currentUser != null) {
        final row = await client
            .from('music_state')
            .select('value')
            .eq('key', key)
            .maybeSingle();
        if (row != null) {
          final value = row['value'];
          if (value is String && value.isNotEmpty) {
            await _saveLocal(key, value);
            return value;
          }
          if (value != null) {
            final text = value.toString();
            await _saveLocal(key, text);
            return text;
          }
        }
      }
    } catch (err) {
      debugPrint('Ayar uzaktan okunamadı ($key): $err');
    }
    return _loadLocal(key);
  }

  /// Yalnızca yerel değeri okur. CV senkronunda bulut ve yerel değerleri
  /// karşılaştırmak için kullanılır.
  Future<String> getLocal(String key) => _loadLocal(key);

  /// Değerleri yalnızca cihaza yazar; ağ isteği yapmaz.
  Future<void> setAllLocal(Map<String, String> values) async {
    for (final entry in values.entries) {
      await _saveLocal(entry.key, entry.value);
    }
  }

  /// Tüm anahtarları kaydeder. Uzak senkron başarılıysa `true` döner.
  Future<bool> setAll(Map<String, String> values) async {
    for (final entry in values.entries) {
      await _saveLocal(entry.key, entry.value);
    }

    try {
      final client = Supabase.instance.client;
      final user = client.auth.currentUser;
      if (user == null) return false;

      final now = DateTime.now().toUtc().toIso8601String();
      final rows = values.entries
          .map((e) => {
                'user_id': user.id,
                'key': e.key,
                'value': e.value,
                'updated_at': now,
              })
          .toList();

      await client.from('music_state').upsert(rows, onConflict: 'user_id,key');
      return true;
    } catch (err) {
      debugPrint('Ayar uzaktan kaydedilemedi: $err');
      return false;
    }
  }

  Future<String> _loadLocal(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('$_localPrefix$key') ?? '';
    } catch (err) {
      debugPrint('Ayar yerelden okunamadı ($key): $err');
      return '';
    }
  }

  Future<void> _saveLocal(String key, String value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('$_localPrefix$key', value);
    } catch (err) {
      debugPrint('Ayar yerele kaydedilemedi ($key): $err');
    }
  }
}

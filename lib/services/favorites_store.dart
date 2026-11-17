import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Favori şarkıları (MediaStore şarkı id'leri) yönetir ve `SharedPreferences`
/// içinde saklar.
///
/// Tüm ekranlar aynı örneği (`FavoritesStore.instance`) dinler; bir ekranda
/// yapılan değişiklik anında diğerlerine yansır.
class FavoritesStore extends ChangeNotifier {
  FavoritesStore._();

  static final FavoritesStore instance = FavoritesStore._();

  static const String _prefsKey = 'favorite_songs';

  final Set<int> _ids = <int>{};
  bool _loaded = false;

  bool get isLoaded => _loaded;
  int get count => _ids.length;

  /// Favori şarkı id'leri (en son eklenen başta değil; sıra önemsiz).
  List<int> get ids => _ids.toList(growable: false);

  bool contains(int songId) => _ids.contains(songId);

  Future<void> load() async {
    if (_loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = prefs.getStringList(_prefsKey);
      if (data != null) {
        _ids
          ..clear()
          ..addAll(data.map(int.tryParse).whereType<int>());
      }
    } catch (_) {
      // Bozuk kayıt varsa sessizce yoksay.
    }
    _loaded = true;
    notifyListeners();
  }

  /// Favori durumunu değiştirir. Eklendiyse `true` döner.
  Future<bool> toggle(int songId) async {
    final added = !_ids.remove(songId);
    if (added) _ids.add(songId);
    notifyListeners();
    await _persist();
    return added;
  }

  Future<void> clear() async {
    if (_ids.isEmpty) return;
    _ids.clear();
    notifyListeners();
    await _persist();
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        _prefsKey,
        _ids.map((e) => e.toString()).toList(growable: false),
      );
    } catch (_) {
      // Yazma başarısız olsa da uygulama akışı bozulmasın.
    }
  }
}

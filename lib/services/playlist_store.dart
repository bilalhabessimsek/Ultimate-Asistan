import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'music_library.dart';

/// Kullanıcının kendi çalma listelerini (liste adı -> şarkı id'leri) yönetir.
///
/// Yerel kayıt `SharedPreferences` içindedir. Ayrıca **masaüstü ("ULTİMATE")
/// uygulamasıyla aynı** Supabase `playlists` tablosuna (liste adı ->
/// `track_ids`) senkronlanır. Böylece telefonda oluşturulan liste PC'de,
/// PC'de oluşturulan liste telefonda görünür.
///
/// Ortak anahtar `trackId`'dir: telefon deposuna göre göreli yolun küçük
/// harfli hâli (ör. `music/rock/parca.mp3`). Masaüstü kökü
/// `C:\Users\bilal\Music` ile telefonun `/storage/emulated/0/` kökü eşlenir.
class PlaylistStore extends ChangeNotifier {
  PlaylistStore._();

  static final PlaylistStore instance = PlaylistStore._();

  /// Eski sürümle uyumluluk için anahtar adı korundu.
  static const String _prefsKey = 'local_playlists';

  /// Bulutta olup telefonda bulunmayan şarkı yolları (liste bazında).
  static const String _cloudExtrasKey = 'playlist_cloud_extras';

  /// Telefonda silinen liste adları (buluttan da silinene kadar).
  static const String _deletedKey = 'playlist_deleted';

  /// Liste başına son yerel değişiklik zamanı (ms).
  static const String _updatedKey = 'playlist_updated';

  /// İlk tam eşitleme yapıldı mı?
  static const String _syncedOnceKey = 'playlist_synced_once';

  /// İçe aktarma hedefi olarak kullanılan ayrılmış adlar.
  static const String reservedQueue = '\u0000queue';
  static const String reservedNew = '\u0000new';

  final Map<String, List<int>> _lists = {};

  /// Bulutta olup telefonda **bulunmayan** şarkı yolları. Böylece PC'ye özel
  /// parçalar, telefonda listeye dokunulduğunda silinmez.
  final Map<String, List<String>> _cloudExtras = {};

  /// Telefonda silinen liste adları; buluttan da silinene kadar tutulur.
  final Set<String> _deleted = {};

  /// Liste başına son yerel değişiklik zamanı (ms).
  final Map<String, int> _updatedAt = {};

  bool _loaded = false;
  bool _syncing = false;
  String? _lastSyncError;

  bool get isLoaded => _loaded;
  bool get isEmpty => _lists.isEmpty;
  bool get isSyncing => _syncing;
  String? get lastSyncError => _lastSyncError;
  List<String> get names => _lists.keys.toList(growable: false);

  List<int> idsOf(String name) =>
      List<int>.unmodifiable(_lists[name] ?? const <int>[]);

  int countOf(String name) => _lists[name]?.length ?? 0;

  /// Listede telefonda bulunmayan (yalnızca PC'de olan) şarkı sayısı.
  int cloudOnlyCountOf(String name) => _cloudExtras[name]?.length ?? 0;

  bool has(String name) => _lists.containsKey(name);

  bool contains(String name, int songId) =>
      _lists[name]?.contains(songId) ?? false;

  /// Ad kullanılabilir mi? (boş / ayrılmış / var olan adlar reddedilir)
  bool canCreate(String name) {
    final n = name.trim();
    if (n.isEmpty) return false;
    if (n == reservedQueue || n == reservedNew) return false;
    return !_lists.containsKey(n);
  }

  // ------------------------------------------------------------------ yükleme

  Future<void> load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();

    final data = prefs.getString(_prefsKey);
    if (data != null) {
      try {
        final decoded = jsonDecode(data) as Map<String, dynamic>;
        _lists
          ..clear()
          ..addAll(
            decoded.map(
              (k, v) => MapEntry(k, List<int>.from(v as List<dynamic>)),
            ),
          );
      } catch (_) {
        // Bozuk kayıt varsa sessizce yoksay.
      }
    }

    final extras = prefs.getString(_cloudExtrasKey);
    if (extras != null) {
      try {
        final decoded = jsonDecode(extras) as Map<String, dynamic>;
        _cloudExtras
          ..clear()
          ..addAll(
            decoded.map(
              (k, v) => MapEntry(k, List<String>.from(v as List<dynamic>)),
            ),
          );
      } catch (_) {}
    }

    _deleted
      ..clear()
      ..addAll(prefs.getStringList(_deletedKey) ?? const <String>[]);

    final updated = prefs.getString(_updatedKey);
    if (updated != null) {
      try {
        final decoded = jsonDecode(updated) as Map<String, dynamic>;
        _updatedAt
          ..clear()
          ..addAll(decoded.map((k, v) => MapEntry(k, (v as num).toInt())));
      } catch (_) {}
    }

    _loaded = true;
    notifyListeners();

    // trackId eşlemesi için kütüphane hazır olunca bulutla eşitle.
    if (MusicLibrary.instance.isReady) {
      unawaited(syncCloud());
    } else {
      MusicLibrary.instance.addListener(_onLibraryReady);
    }
  }

  void _onLibraryReady() {
    if (!MusicLibrary.instance.isReady) return;
    MusicLibrary.instance.removeListener(_onLibraryReady);
    unawaited(syncCloud());
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(_lists));
    await prefs.setString(_cloudExtrasKey, jsonEncode(_cloudExtras));
    await prefs.setStringList(_deletedKey, _deleted.toList());
    await prefs.setString(_updatedKey, jsonEncode(_updatedAt));
  }

  void _touch(String name) {
    _updatedAt[name] = DateTime.now().millisecondsSinceEpoch;
  }

  // ------------------------------------------------------------ düzenleme

  /// Yeni liste oluşturur. Oluşturulduysa `true` döner.
  Future<bool> create(String name) async {
    if (!canCreate(name)) return false;
    final n = name.trim();
    _lists[n] = [];
    _touch(n);
    notifyListeners();
    await _persist();
    unawaited(_pushOne(n));
    return true;
  }

  Future<void> delete(String name) async {
    if (_lists.remove(name) == null) return;
    _cloudExtras.remove(name);
    _updatedAt.remove(name);
    _deleted.add(name);
    notifyListeners();
    await _persist();
    unawaited(_deleteRemote(name));
  }

  Future<bool> add(String name, int songId) async {
    final list = _lists[name];
    if (list == null) return false;
    if (list.contains(songId)) return false;
    list.add(songId);
    _touch(name);
    notifyListeners();
    await _persist();
    unawaited(_pushOne(name));
    return true;
  }

  /// Şarkıları listeye ekler; eklenen (yeni) şarkı sayısını döner.
  Future<int> addAll(String name, Iterable<int> songIds) async {
    final list = _lists[name];
    if (list == null) return 0;
    var added = 0;
    for (final id in songIds) {
      if (!list.contains(id)) {
        list.add(id);
        added++;
      }
    }
    if (added > 0) {
      _touch(name);
      notifyListeners();
      await _persist();
      unawaited(_pushOne(name));
    }
    return added;
  }

  Future<void> remove(String name, int songId) async {
    final list = _lists[name];
    if (list == null) return;
    if (list.remove(songId)) {
      _touch(name);
      notifyListeners();
      await _persist();
      unawaited(_pushOne(name));
    }
  }

  /// Şarkıyı listeye ekler/çıkarır. Eklendiyse `true` döner.
  Future<bool> toggle(String name, int songId) async {
    final list = _lists[name];
    if (list == null) return false;
    final added = !list.remove(songId);
    if (added) list.add(songId);
    _touch(name);
    notifyListeners();
    await _persist();
    unawaited(_pushOne(name));
    return added;
  }

  Future<void> clear(String name) async {
    final list = _lists[name];
    if (list == null || list.isEmpty) return;
    list.clear();
    _cloudExtras.remove(name);
    _touch(name);
    notifyListeners();
    await _persist();
    unawaited(_pushOne(name));
  }

  // ------------------------------------------------------------- senkron

  /// Bir listenin masaüstüyle paylaşılacak şarkı yolları: telefondaki
  /// çözülebilen şarkılar + yalnızca PC'de bulunan (telefonda olmayan) yollar.
  List<String> _trackIdsForPush(String name) {
    final lib = MusicLibrary.instance;
    final seen = <String>{};
    final out = <String>[];
    for (final id in _lists[name] ?? const <int>[]) {
      final t = lib.trackIdOf(id);
      if (t != null && seen.add(t)) out.add(t);
    }
    for (final t in _cloudExtras[name] ?? const <String>[]) {
      if (seen.add(t)) out.add(t);
    }
    return out;
  }

  /// Tek bir listeyi buluta yazar (yerel değişiklikten hemen sonra).
  Future<void> _pushOne(String name) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    if (!MusicLibrary.instance.isReady) return;
    try {
      await Supabase.instance.client.from('playlists').upsert(
        {
          'user_id': user.id,
          'name': name,
          'track_ids': _trackIdsForPush(name),
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        onConflict: 'user_id,name',
      );
      _updatedAt[name] = DateTime.now().millisecondsSinceEpoch;
      await _persist();
      _lastSyncError = null;
    } catch (err) {
      _lastSyncError = err.toString();
      debugPrint('Çalma listesi buluta yazılamadı ($name): $err');
    }
  }

  Future<void> _deleteRemote(String name) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    try {
      await Supabase.instance.client
          .from('playlists')
          .delete()
          .eq('user_id', user.id)
          .eq('name', name);
      _deleted.remove(name);
      await _persist();
    } catch (err) {
      debugPrint('Çalma listesi buluttan silinemedi ($name): $err');
    }
  }

  /// Telefondaki listeleri Supabase'e yazar, buluttakileri indirir.
  ///
  /// İlk eşitlemede veri kaybını önlemek için listeler **birleştirilir**.
  /// Sonraki eşitlemelerde en son değişen taraf kazanır.
  Future<void> syncCloud() async {
    if (_syncing || !_loaded) return;
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    if (user == null) return;
    final lib = MusicLibrary.instance;
    if (!lib.isReady) return;

    _syncing = true;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      final firstSync = !(prefs.getBool(_syncedOnceKey) ?? false);

      final rows =
          await client.from('playlists').select('name, track_ids, updated_at');
      final remote = <String, List<String>>{};
      final remoteTs = <String, int>{};
      for (final raw in rows as List<dynamic>) {
        final map = raw as Map<String, dynamic>;
        final name = (map['name'] ?? '').toString();
        if (name.isEmpty) continue;
        final ids = (map['track_ids'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            <String>[];
        remote[name] = ids;
        remoteTs[name] = DateTime.tryParse((map['updated_at'] ?? '').toString())
                ?.millisecondsSinceEpoch ??
            0;
      }

      final toPush = <String, List<String>>{};

      // 1) Telefonda silinenleri buluttan da kaldır.
      for (final name in _deleted.toList()) {
        if (!remote.containsKey(name)) {
          _deleted.remove(name);
          continue;
        }
        try {
          await client
              .from('playlists')
              .delete()
              .eq('user_id', user.id)
              .eq('name', name);
          remote.remove(name);
          _deleted.remove(name);
        } catch (err) {
          debugPrint('Çalma listesi buluttan silinemedi ($name): $err');
        }
      }

      // 2) Buluttakileri yerelle birleştir.
      for (final entry in remote.entries) {
        final name = entry.key;
        final cloudIds = entry.value;
        final resolved = lib.idsForTrackIds(cloudIds);
        final extras = cloudIds
            .where((t) => lib.songForTrackId(t) == null)
            .toList(growable: false);
        final cloudTs = remoteTs[name] ?? 0;

        if (!_lists.containsKey(name)) {
          _lists[name] = resolved;
          _cloudExtras[name] = extras;
          _updatedAt[name] = cloudTs;
          continue;
        }

        final localTs = _updatedAt[name] ?? 0;
        if (firstSync) {
          // İlk eşitlemede hiçbir şey kaybolmasın: birleştir ve yukarı gönder.
          _lists[name] = _unionIds(_lists[name]!, resolved);
          _cloudExtras[name] = extras;
          toPush[name] = _trackIdsForPush(name);
        } else if (cloudTs > localTs) {
          _lists[name] = resolved;
          _cloudExtras[name] = extras;
          _updatedAt[name] = cloudTs;
        } else if (localTs > cloudTs) {
          toPush[name] = _trackIdsForPush(name);
        }
      }

      // 3) Yerelde olup bulutta olmayan listeleri yukarı gönder.
      for (final name in _lists.keys) {
        if (!remote.containsKey(name) && !toPush.containsKey(name)) {
          toPush[name] = _trackIdsForPush(name);
        }
      }

      for (final entry in toPush.entries) {
        await client.from('playlists').upsert(
          {
            'user_id': user.id,
            'name': entry.key,
            'track_ids': entry.value,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          },
          onConflict: 'user_id,name',
        );
        _updatedAt[entry.key] = DateTime.now().millisecondsSinceEpoch;
      }

      await prefs.setBool(_syncedOnceKey, true);
      _lastSyncError = null;
      debugPrint('PLAYLIST_SYNC_OK toplam=${_lists.length} '
          'yazilan=${toPush.length} buluttan=${remote.length}');
      await _persist();
      notifyListeners();
    } catch (err) {
      _lastSyncError = err.toString();
      debugPrint('Çalma listesi senkronu başarısız: $err');
    } finally {
      _syncing = false;
      notifyListeners();
    }
  }

  static List<int> _unionIds(List<int> a, List<int> b) {
    final out = <int>[...a];
    final seen = a.toSet();
    for (final x in b) {
      if (seen.add(x)) out.add(x);
    }
    return out;
  }
}

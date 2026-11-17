import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/cv_templates.dart';
import '../utils/settings_store.dart';

/// CV'nin cihazlar arası senkron deposu.
///
/// Supabase'te ayrı bir tablo açmaya gerek kalmaması için mevcut
/// `music_state` anahtar/değer tablosu kullanılır. Her CV sürümü ayrı bir
/// `career_cv_history_<id>` satırıdır; böylece iki cihaz aynı anda farklı
/// sürümler kaydettiğinde birbirinin üzerine yazmaz.
///
/// İnternet yoksa tüm işlemler yerel `shared_preferences` üzerinde çalışmaya
/// devam eder; bağlantı gelince sürümler buluta gönderilir.
class CvSyncStore {
  static const String profileKey = 'career_cv_profile';
  static const String templateKey = 'career_cv_template';
  static const String themeKey = 'career_cv_theme';
  static const String updatedAtKey = 'career_cv_updated_at';
  static const String reposKey = 'career_github_repos';
  static const String githubApiUrlKey = 'career_github_api_url';
  static const String legacyGithubKey = 'career_github';
  static const String legacyLinkedinKey = 'career_linkedin';

  static const String _historyPrefix = 'career_cv_history_';
  static const String _historyTombstonePrefix = 'career_cv_history_deleted_';
  static const String _localHistoryKey = 'career_cv_history_local';
  static const String _localTombstoneKey = 'career_cv_history_deleted_local';
  static const int _maxLocalHistory = 80;

  final SettingsStore _settings = SettingsStore();

  static const List<String> _currentKeys = [
    profileKey,
    templateKey,
    themeKey,
    updatedAtKey,
    reposKey,
    githubApiUrlKey,
    legacyGithubKey,
    legacyLinkedinKey,
  ];

  /// Bulut ve yerel kopyayı karşılaştırarak en güncel CV anlık görüntüsünü
  /// döndürür. Hiç kayıt yoksa `null` döner.
  Future<CvSnapshot?> loadCurrent() async {
    final localValues = await Future.wait(
      _currentKeys.map(_settings.getLocal),
    );
    final local = <String, String>{
      for (var i = 0; i < _currentKeys.length; i++)
        _currentKeys[i]: localValues[i],
    };

    final remote = <String, String>{};
    final remoteUpdated = <String, DateTime>{};
    final rows = await Future.wait(
      _currentKeys.map((key) => _remoteRow(key)),
    );
    for (var i = 0; i < _currentKeys.length; i++) {
      final row = rows[i];
      if (row == null) continue;
      final key = _currentKeys[i];
      remote[key] = _stringValue(row['value']);
      final parsed = DateTime.tryParse('${row['updated_at'] ?? ''}');
      if (parsed != null) remoteUpdated[key] = parsed;
    }

    var localProfile = _decodeProfile(local[profileKey]);
    var cloudProfile = _decodeProfile(remote[profileKey]);
    final localTemplateId = local[templateKey] ?? '';
    final cloudTemplateId = remote[templateKey] ?? '';

    // Eski mobil sürümler yalnızca career_github / career_linkedin
    // anahtarlarını tutuyordu. Profil yoksa varsayılan CV'yi bu bilgilerle
    // oluşturup veri kaybını önle.
    if (localProfile == null) {
      final legacyGithub = local[legacyGithubKey] ?? '';
      final legacyLinkedin = local[legacyLinkedinKey] ?? '';
      if (legacyGithub.trim().isNotEmpty || legacyLinkedin.trim().isNotEmpty) {
        localProfile = CvProfile.defaults(
          templateById(
              localTemplateId.isNotEmpty ? localTemplateId : cloudTemplateId),
        ).copyWith(
          github: normalizeGithub(legacyGithub),
          linkedin: normalizeLinkedin(legacyLinkedin),
        );
      }
    }
    if (cloudProfile == null) {
      final legacyGithub = remote[legacyGithubKey] ?? '';
      final legacyLinkedin = remote[legacyLinkedinKey] ?? '';
      if (legacyGithub.trim().isNotEmpty || legacyLinkedin.trim().isNotEmpty) {
        cloudProfile = CvProfile.defaults(
          templateById(
              cloudTemplateId.isNotEmpty ? cloudTemplateId : localTemplateId),
        ).copyWith(
          github: normalizeGithub(legacyGithub),
          linkedin: normalizeLinkedin(legacyLinkedin),
        );
      }
    }

    if (localProfile == null && cloudProfile == null) return null;

    final localSaved = DateTime.tryParse(local[updatedAtKey] ?? '');
    DateTime? cloudSaved = DateTime.tryParse(remote[updatedAtKey] ?? '');
    if (cloudSaved == null) {
      for (final value in remoteUpdated.values) {
        if (cloudSaved == null || value.isAfter(cloudSaved)) cloudSaved = value;
      }
    }

    final preferLocal = cloudProfile == null ||
        (localProfile != null &&
            localSaved != null &&
            (cloudSaved == null || localSaved.isAfter(cloudSaved)));

    CvProfile chosen;
    if (localProfile != null && cloudProfile != null) {
      chosen = preferLocal
          ? _mergeProfiles(localProfile, cloudProfile)
          : _mergeProfiles(cloudProfile, localProfile);
    } else {
      chosen = (localProfile ?? cloudProfile)!;
    }

    String chooseText(String localValue, String cloudValue) {
      if (preferLocal) {
        return localValue.trim().isNotEmpty ? localValue : cloudValue;
      }
      return cloudValue.trim().isNotEmpty ? cloudValue : localValue;
    }

    final templateId = chooseText(localTemplateId, cloudTemplateId);
    final themeId = chooseText(
      local[themeKey] ?? '',
      remote[themeKey] ?? '',
    );
    final apiUrl = chooseText(
      local[githubApiUrlKey] ?? '',
      remote[githubApiUrlKey] ?? '',
    );
    final localRepos = _decodeRepos(local[reposKey]);
    final cloudRepos = _decodeRepos(remote[reposKey]);
    final hasLocalRepos = (local[reposKey] ?? '').trim().isNotEmpty;
    final hasCloudRepos = remote.containsKey(reposKey);
    // Boş liste de anlamlı bir değerdir; bir cihazda projeler temizlendiğinde
    // diğer cihaz eski listeyi geri getirmemeli.
    final repos = preferLocal
        ? (hasLocalRepos ? localRepos : cloudRepos)
        : (hasCloudRepos ? cloudRepos : localRepos);
    final savedAt = preferLocal
        ? (localSaved ?? cloudSaved ?? DateTime.now())
        : (cloudSaved ?? localSaved ?? DateTime.now());

    final snapshot = CvSnapshot(
      profile: chosen,
      templateId: templateId.isEmpty ? 'software' : templateId,
      themeId: themeId.isEmpty ? 'grafit' : themeId,
      repos: repos,
      savedAt: savedAt,
      apiUrl: apiUrl,
    );
    await _cacheSnapshot(snapshot);
    return snapshot;
  }

  /// Geçerli CV'yi hem cihaza hem Supabase'e yazar.
  Future<bool> saveCurrent(CvSnapshot snapshot) async {
    final values = <String, String>{
      profileKey: jsonEncode(snapshot.profile.toJson()),
      templateKey: snapshot.templateId,
      themeKey: snapshot.themeId,
      updatedAtKey: snapshot.savedAt.toUtc().toIso8601String(),
      reposKey:
          jsonEncode(snapshot.repos.map((repo) => repo.toJson()).toList()),
      githubApiUrlKey: snapshot.apiUrl.trim(),
      legacyGithubKey: snapshot.profile.github,
      legacyLinkedinKey: snapshot.profile.linkedin,
    };
    await _settings.setAllLocal(values);
    return _settings.setAll(values);
  }

  /// Bulut ve yereldeki tüm CV sürümlerini birleştirir.
  Future<List<CvHistoryEntry>> loadHistory() async {
    final local = await _readLocalHistory();
    final localTombstones = await _readLocalTombstones();

    try {
      final client = Supabase.instance.client;
      if (client.auth.currentUser == null) {
        final entries = _withoutTombstones(local, localTombstones);
        await _writeLocalHistory(entries);
        return entries;
      }

      final rows = await client
          .from('music_state')
          .select('key,value,updated_at')
          .like('key', '$_historyPrefix%');

      final remote = <String, CvHistoryEntry>{};
      final cloudTombstones = <String>{};
      for (final raw in rows as List) {
        final row = Map<String, dynamic>.from(raw as Map);
        final key = '${row['key'] ?? ''}';
        if (key.startsWith(_historyTombstonePrefix)) {
          final id = key.substring(_historyTombstonePrefix.length);
          if (id.isNotEmpty) cloudTombstones.add(id);
          continue;
        }
        final entry = _decodeHistory(row['value']);
        if (entry == null) continue;
        final id = entry.id.isNotEmpty
            ? entry.id
            : key.replaceFirst(_historyPrefix, '');
        remote[id] = CvHistoryEntry(
          id: id,
          title: entry.title,
          profile: entry.profile,
          templateId: entry.templateId,
          themeId: entry.themeId,
          repos: entry.repos,
          savedAt: entry.savedAt,
        );
      }

      final tombstones = {...localTombstones, ...cloudTombstones};
      await _writeLocalTombstones(tombstones);

      final merged = <String, CvHistoryEntry>{
        for (final entry in local) entry.id: entry,
        for (final entry in remote.values) entry.id: entry,
      };
      final entries = _withoutTombstones(merged.values.toList(), tombstones);
      await _writeLocalHistory(entries);

      // Çevrimdışı kaydedilmiş sürümleri bir sonraki açılışta buluta taşı.
      final remoteIds = remote.keys.toSet();
      for (final entry in local) {
        if (!remoteIds.contains(entry.id) && !tombstones.contains(entry.id)) {
          await _writeRemoteHistory(entry);
        }
      }

      // Başka bir cihazda silinen kayıtları diğer cihazlara da yay.
      for (final id in tombstones) {
        if (!cloudTombstones.contains(id)) {
          await _writeRemoteTombstone(id);
        }
      }
      return entries;
    } catch (err) {
      debugPrint('CV arşivi buluttan okunamadı: $err');
      final entries = _withoutTombstones(local, localTombstones);
      await _writeLocalHistory(entries);
      return entries;
    }
  }

  /// Yeni bir CV sürümünü yerel arşive ve buluta ekler.
  Future<bool> saveHistory(CvHistoryEntry entry) async {
    final local = await _readLocalHistory();
    local.removeWhere((item) => item.id == entry.id);
    local.add(entry);
    local.sort(_historySort);
    final trimmed = local.take(_maxLocalHistory).toList();
    await _writeLocalHistory(trimmed);

    // Aynı kimlikle yeniden kaydedilirse eski silme işaretini kaldır.
    final tombstones = await _readLocalTombstones();
    if (tombstones.remove(entry.id)) {
      await _writeLocalTombstones(tombstones);
    }
    return _writeRemoteHistory(entry);
  }

  /// Bir CV sürümünü iki taraftan da siler.
  ///
  /// Satırı yalnızca silmek yetmez: diğer cihaz yerel kopyasını buluta geri
  /// gönderebilir. Bu yüzden `career_cv_history_deleted_<id>` biçiminde bir
  /// silme işareti de yazılır ve arşiv yüklenirken bu kimlikler atlanır.
  Future<bool> deleteHistory(String id) async {
    final local = await _readLocalHistory();
    local.removeWhere((item) => item.id == id);
    await _writeLocalHistory(local);

    final tombstones = await _readLocalTombstones();
    tombstones.add(id);
    await _writeLocalTombstones(tombstones);

    return _writeRemoteTombstone(id);
  }

  List<CvHistoryEntry> _withoutTombstones(
    List<CvHistoryEntry> entries,
    Set<String> tombstones,
  ) {
    return entries.where((entry) => !tombstones.contains(entry.id)).toList()
      ..sort(_historySort);
  }

  Future<Set<String>> _readLocalTombstones() async {
    final raw = await _settings.getLocal(_localTombstoneKey);
    if (raw.trim().isEmpty) return <String>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <String>{};
      return decoded
          .map((value) => value.toString())
          .where((id) => id.isNotEmpty)
          .toSet();
    } catch (err) {
      debugPrint('CV silme işaretleri okunamadı: $err');
      return <String>{};
    }
  }

  Future<void> _writeLocalTombstones(Set<String> tombstones) async {
    await _settings.setAllLocal({
      _localTombstoneKey: jsonEncode(tombstones.toList()..sort()),
    });
  }

  Future<bool> _writeRemoteTombstone(String id) async {
    try {
      final client = Supabase.instance.client;
      final user = client.auth.currentUser;
      if (user == null) return false;
      final now = DateTime.now().toUtc().toIso8601String();
      await client.from('music_state').upsert(
        {
          'user_id': user.id,
          'key': '$_historyTombstonePrefix$id',
          'value': now,
          'updated_at': now,
        },
        onConflict: 'user_id,key',
      );
      await client.from('music_state').delete().eq('key', '$_historyPrefix$id');
      return true;
    } catch (err) {
      debugPrint('CV sürümü buluttan silinemedi: $err');
      return false;
    }
  }

  Future<void> _cacheSnapshot(CvSnapshot snapshot) async {
    await _settings.setAllLocal({
      profileKey: jsonEncode(snapshot.profile.toJson()),
      templateKey: snapshot.templateId,
      themeKey: snapshot.themeId,
      updatedAtKey: snapshot.savedAt.toUtc().toIso8601String(),
      reposKey:
          jsonEncode(snapshot.repos.map((repo) => repo.toJson()).toList()),
      githubApiUrlKey: snapshot.apiUrl.trim(),
      legacyGithubKey: snapshot.profile.github,
      legacyLinkedinKey: snapshot.profile.linkedin,
    });
  }

  Future<Map<String, dynamic>?> _remoteRow(String key) async {
    try {
      final client = Supabase.instance.client;
      if (client.auth.currentUser == null) return null;
      final row = await client
          .from('music_state')
          .select('value,updated_at')
          .eq('key', key)
          .maybeSingle();
      return row == null ? null : Map<String, dynamic>.from(row);
    } catch (err) {
      debugPrint('CV bulut değeri okunamadı ($key): $err');
      return null;
    }
  }

  Future<List<CvHistoryEntry>> _readLocalHistory() async {
    final raw = await _settings.getLocal(_localHistoryKey);
    if (raw.trim().isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map>()
          .map((item) => CvHistoryEntry.fromJson(
                Map<String, dynamic>.from(item),
              ))
          .where((entry) => entry.id.isNotEmpty)
          .toList();
    } catch (err) {
      debugPrint('Yerel CV arşivi okunamadı: $err');
      return [];
    }
  }

  Future<void> _writeLocalHistory(List<CvHistoryEntry> entries) async {
    await _settings.setAllLocal({
      _localHistoryKey: jsonEncode(
        entries.map((entry) => entry.toJson()).toList(),
      ),
    });
  }

  Future<bool> _writeRemoteHistory(CvHistoryEntry entry) async {
    try {
      final client = Supabase.instance.client;
      final user = client.auth.currentUser;
      if (user == null) return false;
      await client.from('music_state').upsert(
        {
          'user_id': user.id,
          'key': '$_historyPrefix${entry.id}',
          'value': jsonEncode(entry.toJson()),
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        onConflict: 'user_id,key',
      );
      return true;
    } catch (err) {
      debugPrint('CV sürümü buluta kaydedilemedi: $err');
      return false;
    }
  }

  CvProfile? _decodeProfile(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return CvProfile.fromJson(Map<String, dynamic>.from(decoded));
      }
    } catch (err) {
      debugPrint('CV profili çözümlenemedi: $err');
    }
    return null;
  }

  List<GithubRepo> _decodeRepos(String? raw) {
    if (raw == null || raw.trim().isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map>()
          .map((item) => GithubRepo.fromJson(
                Map<String, dynamic>.from(item),
              ))
          .where((repo) => repo.name.trim().isNotEmpty)
          .toList();
    } catch (err) {
      debugPrint('GitHub depoları çözümlenemedi: $err');
      return [];
    }
  }

  CvHistoryEntry? _decodeHistory(dynamic value) {
    try {
      dynamic decoded = value;
      if (value is String) {
        if (value.trim().isEmpty) return null;
        decoded = jsonDecode(value);
      }
      if (decoded is Map) {
        return CvHistoryEntry.fromJson(
          Map<String, dynamic>.from(decoded),
        );
      }
    } catch (err) {
      debugPrint('CV sürümü çözümlenemedi: $err');
    }
    return null;
  }

  String _stringValue(dynamic value) {
    if (value == null) return '';
    if (value is String) return value;
    if (value is Map || value is List) return jsonEncode(value);
    return value.toString();
  }

  CvProfile _mergeProfiles(CvProfile primary, CvProfile fallback) {
    String pick(String first, String second) =>
        first.trim().isNotEmpty ? first : second;
    return CvProfile(
      fullName: pick(primary.fullName, fallback.fullName),
      headline: pick(primary.headline, fallback.headline),
      github: pick(primary.github, fallback.github),
      linkedin: pick(primary.linkedin, fallback.linkedin),
      website: pick(primary.website, fallback.website),
      summary: pick(primary.summary, fallback.summary),
      education: pick(primary.education, fallback.education),
      skills: pick(primary.skills, fallback.skills),
      experience: pick(primary.experience, fallback.experience),
      projects: pick(primary.projects, fallback.projects),
      languages: pick(primary.languages, fallback.languages),
      certificates: pick(primary.certificates, fallback.certificates),
    );
  }

  int _historySort(CvHistoryEntry a, CvHistoryEntry b) =>
      b.savedAt.compareTo(a.savedAt);
}

/// Kullanıcının girdiği GitHub API/proxy adresini kullanılabilir bir istek
/// adresine dönüştüren yardımcılar.
///
/// Desteklenen girişler:
/// - Boş bırakılırsa: `https://api.github.com/users/<kullanıcı>/repos`
/// - Yalnızca taban adres: `https://proxy.example.com`
///   → `https://proxy.example.com/users/<kullanıcı>/repos`
/// - `{username}` / `:username` içeren tam uç nokta:
///   `https://proxy.example.com/repos?username={username}`
///   → adres olduğu gibi çağrılır, yalnızca yer tutucu doldurulur.
/// - Kullanıcı adı içermeyen hazır uç nokta:
///   `https://proxy.example.com/api/projeler` → olduğu gibi çağrılır;
///   bu durumda GitHub kullanıcı adı boş bırakılabilir.
///
/// Özel API'ye GitHub'a özgü `per_page` / `sort` / `type` parametreleri
/// eklenmez; böylece sistem gerçekten kullanıcının girdiği adrese göre çalışır.
library;

final RegExp _userPlaceholder = RegExp(
  r'\{(username|user)\}|:(username|user)\b',
  caseSensitive: false,
);

final RegExp _trailingSlashes = RegExp(r'/+$');

/// GitHub repo listesini çekmek için istek adresini oluşturur.
///
/// [apiUrl] boşsa varsayılan GitHub API'si kullanılır ve [username] zorunludur.
/// [apiUrl] doluysa adres olduğu gibi korunur; yalnızca `{username}` benzeri
/// yer tutucular doldurulur. Taban adres verilirse GitHub uyumlu
/// `/users/<kullanıcı>/repos` yolu eklenir.
Uri buildGithubReposUri({
  required String apiUrl,
  required String username,
}) {
  final user = username.trim();
  final input = apiUrl.trim();
  final usesDefaultApi = input.isEmpty;

  if (usesDefaultApi && user.isEmpty) {
    throw const FormatException('GitHub kullanıcı adı boş olamaz.');
  }

  var raw = usesDefaultApi ? 'https://api.github.com' : input;
  if (!raw.toLowerCase().startsWith('http://') &&
      !raw.toLowerCase().startsWith('https://')) {
    raw = 'https://$raw';
  }

  final hasPlaceholder = _userPlaceholder.hasMatch(raw);
  if (hasPlaceholder && user.isEmpty) {
    throw const FormatException(
      'API adresinde {username} yer tutucusu var; GitHub kullanıcı adını da yaz.',
    );
  }

  final encodedUser = Uri.encodeComponent(user);
  raw = raw.replaceAllMapped(_userPlaceholder, (_) => encodedUser);

  final parsed = Uri.tryParse(raw);
  if (parsed == null || parsed.host.isEmpty) {
    throw const FormatException(
      'Geçerli bir API adresi gir (örn. https://proxy.example.com).',
    );
  }

  final query = <String, String>{...parsed.queryParameters};
  final normalizedQueryKeys = query.keys.map((key) => key.toLowerCase());
  final hasUserQuery = normalizedQueryKeys.any(
    (key) => key == 'username' || key == 'user' || key == 'login',
  );

  var path = parsed.path;
  final lowerPath = path.toLowerCase();
  final isGithubHost = parsed.host.toLowerCase() == 'api.github.com';
  final looksLikeGithubReposEndpoint =
      lowerPath.endsWith('/repos') || lowerPath.contains('/repos/');
  final hasUserInPath = lowerPath.contains('/users/') ||
      (encodedUser.isNotEmpty && path.contains(encodedUser)) ||
      (user.isNotEmpty && path.contains(user));

  final trimmedPath = path.replaceFirst(_trailingSlashes, '');
  final isBaseUrl = trimmedPath.isEmpty || trimmedPath == '/';

  if (usesDefaultApi) {
    path = '/users/$encodedUser/repos';
    query.putIfAbsent('per_page', () => '100');
  } else if (isBaseUrl) {
    // Yalnızca taban adres verildi: GitHub uyumlu yolu biz kuruyoruz.
    if (user.isEmpty) {
      throw const FormatException(
        'API taban adresi kullanılıyor; GitHub kullanıcı adını da yaz.',
      );
    }
    path = '/users/$encodedUser/repos';
    query.putIfAbsent('per_page', () => '100');
  } else {
    // Tam uç nokta: kullanıcının yazdığı adresi bozmadan kullan.
    path = trimmedPath;
    if (looksLikeGithubReposEndpoint &&
        !hasUserInPath &&
        !hasUserQuery &&
        user.isNotEmpty) {
      // GitHub biçimli `/repos` uç noktaları kullanıcı adını sorgudan
      // bekleyebilir. Başka bir parametre eklenmez.
      query['username'] = user;
    }
  }

  if (isGithubHost) {
    query.putIfAbsent('per_page', () => '100');
    query.putIfAbsent('sort', () => 'updated');
    query.putIfAbsent('type', () => 'owner');
  }

  if (query.isEmpty) {
    return Uri(
      scheme: parsed.scheme,
      userInfo: parsed.userInfo.isEmpty ? null : parsed.userInfo,
      host: parsed.host,
      port: parsed.hasPort ? parsed.port : null,
      path: path,
      fragment: parsed.hasFragment ? parsed.fragment : null,
    );
  }
  return parsed.replace(path: path, queryParameters: query);
}

/// GitHub veya bir proxy'nin döndürdüğü JSON içinden repo listesini çıkarır.
///
/// Doğrudan dizi, `{repos: [...]}`, `{data: [...]}`, `{items: [...]}`,
/// `{result: {projects: [...]}}` gibi yaygın sarmalayıcıları destekler.
List<Map<String, dynamic>> extractGithubRepoItems(dynamic payload) {
  dynamic current = payload;

  for (var depth = 0; depth < 5; depth++) {
    if (current is List) {
      return current
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    }
    if (current is! Map) return [];

    final map = Map<String, dynamic>.from(current);
    const preferredKeys = [
      'repos',
      'repositories',
      'projects',
      'items',
      'results',
      'result',
      'data',
      'payload',
    ];

    var moved = false;
    for (final key in preferredKeys) {
      final value = map[key];
      if (value is List) {
        return value
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList();
      }
      if (value is Map) {
        current = value;
        moved = true;
        break;
      }
    }
    if (moved) continue;

    // Bilinmeyen bir sarmalayıcıysa ilk nesne listesini dene.
    for (final value in map.values) {
      if (value is List) {
        return value
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList();
      }
    }
    return [];
  }

  return [];
}

/// Proxy'nin hata gövdesinden okunabilir bir mesaj çıkarır.
String githubApiErrorMessage(dynamic payload) {
  if (payload is Map) {
    for (final key in ['error', 'message', 'detail', 'error_description']) {
      final value = payload[key];
      if (value is String && value.trim().isNotEmpty) return value.trim();
      if (value is Map) {
        final nested = githubApiErrorMessage(value);
        if (nested.isNotEmpty) return nested;
      }
    }
  }
  return '';
}

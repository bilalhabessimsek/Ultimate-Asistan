import 'package:flutter_test/flutter_test.dart';
import 'package:ultimate_mobile/utils/github_api.dart';

void main() {
  group('GitHub repo istek adresi', () {
    test('API boşken varsayılan GitHub adresi kurulur', () {
      final uri = buildGithubReposUri(apiUrl: '', username: 'bilal');

      expect(uri.host, 'api.github.com');
      expect(uri.path, '/users/bilal/repos');
      expect(uri.queryParameters['per_page'], '100');
      expect(uri.queryParameters['sort'], 'updated');
      expect(uri.queryParameters['type'], 'owner');
    });

    test('yalnızca taban adres verilirse GitHub yolu eklenir', () {
      final uri = buildGithubReposUri(
        apiUrl: 'https://proxy.example.com/',
        username: 'bilal',
      );

      expect(uri.host, 'proxy.example.com');
      expect(uri.path, '/users/bilal/repos');
      expect(uri.queryParameters['per_page'], '100');
      expect(uri.queryParameters.containsKey('sort'), isFalse);
      expect(uri.queryParameters.containsKey('type'), isFalse);
    });

    test('tam uç nokta olduğu gibi kullanılır ve yer tutucu doldurulur', () {
      final uri = buildGithubReposUri(
        apiUrl: 'https://proxy.example.com/api/repos?username={username}',
        username: 'bilal',
      );

      expect(uri.path, '/api/repos');
      expect(uri.queryParameters['username'], 'bilal');
      expect(uri.queryParameters.containsKey('per_page'), isFalse);
    });

    test('iki nokta yer tutucusu ve büyük harf desteklenir', () {
      final uri = buildGithubReposUri(
        apiUrl: 'https://proxy.example.com/users/:username/repos',
        username: 'bilal',
      );
      expect(uri.path, '/users/bilal/repos');

      final upper = buildGithubReposUri(
        apiUrl: 'https://proxy.example.com/repos?login={USERNAME}',
        username: 'bilal',
      );
      expect(upper.queryParameters['login'], 'bilal');
    });

    test('kullanıcı adı içermeyen hazır uç nokta boş kullanıcıyla çalışır',
        () {
      final uri = buildGithubReposUri(
        apiUrl: 'https://myapi.dev/api/projeler',
        username: '',
      );

      expect(uri.toString(), 'https://myapi.dev/api/projeler');
    });

    test('mevcut sorgu parametreleri korunur', () {
      final uri = buildGithubReposUri(
        apiUrl: 'https://proxy.example.com/items?token=abc&page=2',
        username: '',
      );

      expect(uri.queryParameters['token'], 'abc');
      expect(uri.queryParameters['page'], '2');
    });

    test('GitHub biçimli /repos uç noktasına kullanıcı adı eklenir', () {
      final uri = buildGithubReposUri(
        apiUrl: 'https://proxy.example.com/api/repos',
        username: 'bilal',
      );

      expect(uri.path, '/api/repos');
      expect(uri.queryParameters['username'], 'bilal');
      expect(uri.queryParameters.containsKey('per_page'), isFalse);
    });

    test('yer tutucu varken boş kullanıcı adı hata verir', () {
      expect(
        () => buildGithubReposUri(
          apiUrl: 'https://proxy.example.com/repos?username={username}',
          username: ' ',
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('taban adres ve boş kullanıcı adı hata verir', () {
      expect(
        () => buildGithubReposUri(
          apiUrl: 'https://proxy.example.com',
          username: '',
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('geçersiz adres hata verir', () {
      expect(
        () => buildGithubReposUri(apiUrl: 'https://', username: 'bilal'),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('API yanıtı çözümleme', () {
    test('doğrudan dizi okunur', () {
      final items = extractGithubRepoItems([
        {'name': 'bir'},
        {'name': 'iki'},
      ]);
      expect(items, hasLength(2));
    });

    test('iç içe sarmalayıcılar bulunur', () {
      final items = extractGithubRepoItems({
        'result': {
          'projects': [
            {'name': 'bir'},
          ],
        },
      });
      expect(items.single['name'], 'bir');
    });

    test('bilinmeyen sarmalayıcıdaki ilk liste bulunur', () {
      final items = extractGithubRepoItems({
        'meta': {'count': 1},
        'kayitlar': [
          {'name': 'bir'},
        ],
      });
      expect(items.single['name'], 'bir');
    });

    test('hata mesajı iç içe gövdeden okunur', () {
      final message = githubApiErrorMessage({
        'error': {'message': 'Token geçersiz'},
      });
      expect(message, 'Token geçersiz');
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:ultimate_mobile/utils/cv_templates.dart';

void main() {
  group('CV kalıpları ve ATS incelemesi', () {
    test('dolu varsayılan CV tam puan alır', () {
      final template = templateById('software');
      final profile = CvProfile.defaults(template);
      final report = analyzeCv(profile, template);

      expect(report.score, 100);
      expect(report.criteria, hasLength(11));
      expect(report.verdict, 'ATS dostu');
    });

    test('eksik alanlar puanı düşürür ve öneri üretir', () {
      final template = templateById('software');
      final profile = CvProfile.defaults(template).copyWith(
        summary: '',
        skills: '',
        experience: '',
        projects: '',
        github: '',
        linkedin: '',
      );
      final report = analyzeCv(profile, template);

      expect(report.score, lessThan(60));
      expect(report.failedCriteria, isNotEmpty);
      expect(report.suggestions, isNotEmpty);
    });

    test('düz metin çıktısı dolu bölümleri içerir', () {
      final template = templateById('data');
      final profile = CvProfile.defaults(template);
      final text = buildCvPlainText(profile);

      expect(text, contains('PROFİL ÖZETİ'));
      expect(text, contains('YETENEKLER'));
      expect(text, contains('DENEYİM'));
      expect(text, contains('BİLAL HABEŞ ŞİMŞEK'));
    });

    test('GitHub bağlantısı ve projeleri CV çıktısına eklenir', () {
      final template = templateById('software');
      final profile = CvProfile.defaults(template).copyWith(
        website: 'bilal.dev',
      );
      final repos = [
        const GithubRepo(
          name: 'ultimate_mobile',
          description: 'Flutter tabanlı kişisel asistan.',
          language: 'Dart',
          stars: 12,
          archived: false,
        ),
      ];

      expect(githubUsername('https://github.com/bilalhabessimsek'),
          'bilalhabessimsek');
      expect(
          normalizeGithub('bilalhabessimsek'), 'github.com/bilalhabessimsek');
      expect(
        mergeReposIntoProjects(profile, repos).projects,
        contains('Ultimate Mobile'),
      );

      final text = buildCvPlainText(profile, repos: repos);
      expect(text, contains('GITHUB PROJELERİ'));
      expect(text, contains('Dart'));
      expect(text, contains('bilal.dev'));
    });

    test('CV sürümü JSON olarak geri okunur ve başlık imzayı değiştirmez', () {
      final template = templateById('software');
      final now = DateTime.utc(2026, 10, 26, 12, 30);
      final first = CvHistoryEntry(
        id: 'version-1',
        title: 'İlk kayıt',
        profile: CvProfile.defaults(template).copyWith(website: 'bilal.dev'),
        templateId: template.id,
        themeId: 'grafit',
        repos: const [
          GithubRepo(
            name: 'ultimate_mobile',
            description: 'Mobil asistan',
            language: 'Dart',
            stars: 3,
            archived: false,
          ),
        ],
        savedAt: now,
      );
      final second = CvHistoryEntry(
        id: 'version-2',
        title: 'Farklı başlık',
        profile: first.profile,
        templateId: first.templateId,
        themeId: first.themeId,
        repos: first.repos,
        savedAt: now.add(const Duration(minutes: 1)),
      );

      final decoded = CvHistoryEntry.fromJson(first.toJson());
      expect(decoded.id, 'version-1');
      expect(decoded.profile.website, 'bilal.dev');
      expect(decoded.repos.single.name, 'ultimate_mobile');
      expect(decoded.title, 'İlk kayıt');
      expect(first.signature, second.signature);
    });
  });
}

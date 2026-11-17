import 'package:flutter/material.dart';

/// ATS uyumlu CV içerik kalıbı.
///
/// Her kalıp; hedef unvan, özet, yetenekler ve örnek deneyim/proje metinleri
/// içerir. Kullanıcı kalıbı seçip metinleri kendi deneyimine göre düzenler.
class CvTemplate {
  final String id;
  final String name;
  final String subtitle;
  final IconData icon;
  final Color accent;
  final String headline;
  final String summary;
  final String skills;
  final String experience;
  final String projects;
  final String certificates;
  final List<String> keywords;

  const CvTemplate({
    required this.id,
    required this.name,
    required this.subtitle,
    required this.icon,
    required this.accent,
    required this.headline,
    required this.summary,
    required this.skills,
    required this.experience,
    required this.projects,
    required this.certificates,
    required this.keywords,
  });
}

/// CV'nin görsel şablonu. Seçilen renk önizleme ve vurgularda kullanılır.
class CvThemeOption {
  final String id;
  final String name;
  final Color accent;

  const CvThemeOption({
    required this.id,
    required this.name,
    required this.accent,
  });
}

const List<CvTemplate> cvTemplates = [
  CvTemplate(
    id: 'software',
    name: 'Yazılım Mühendisi',
    subtitle: 'Full-stack geliştirme',
    icon: Icons.code_rounded,
    accent: Color(0xFF38BDF8),
    headline: 'Bilgisayar Mühendisi · Full-Stack Yazılım Geliştirici',
    summary:
        'Gazi Üniversitesi Bilgisayar Mühendisliği mezunu; C, Kotlin, TypeScript ve C# ile ölçeklenebilir uygulamalar geliştiren yazılım mühendisi. React, Node.js ve Supabase tabanlı projelerde uçtan uca geliştirme, REST API entegrasyonu ve performans iyileştirme deneyimi. Temiz kod, test ve sürdürülebilir mimari odaklı çalışır.',
    skills:
        'C, Kotlin, TypeScript, C#, React, Node.js, Flutter, Supabase, REST API, Git, SQL, Docker',
    experience:
        'Full-Stack Geliştirici — Serbest / Kişisel Projeler (2024–Günümüz)\n'
        '• React ve Node.js ile 3 web uygulaması geliştirdim; API yanıt süresini %30 iyileştirdim.\n'
        '• Supabase üzerinde kimlik doğrulama ve gerçek zamanlı veri senkronizasyonu kurdum.',
    projects: 'Ultimate Asistan — Flutter, Kotlin, Supabase\n'
        'Notlar, takvim, müzik çalar ve kariyer modüllerini tek uygulamada birleştiren kişisel asistan; çevrimdışı önbellek ve cihazlar arası senkronizasyon içerir.',
    certificates:
        'AWS Cloud Practitioner (2025), Meta Front-End Developer (2024)',
    keywords: [
      'kotlin',
      'typescript',
      'react',
      'node.js',
      'flutter',
      'supabase',
      'rest',
      'api',
      'git',
      'sql',
      'docker',
      'c#',
    ],
  ),
  CvTemplate(
    id: 'data',
    name: 'Veri Analisti',
    subtitle: 'SQL · Python · BI',
    icon: Icons.bar_chart_rounded,
    accent: Color(0xFF34D399),
    headline: 'Veri Analisti · SQL & Python',
    summary:
        'Veriyi anlamlı içgörülere dönüştüren, SQL ve Python ile büyük veri kümelerini analiz eden veri analisti. Dashboard ve raporlama süreçlerinde deneyimli; veri temizleme, KPI takibi ve karar destek modelleri geliştirme odaklı çalışır.',
    skills:
        'SQL, Python, Pandas, NumPy, Power BI, Excel, Veri Görselleştirme, İstatistik, ETL, Git',
    experience: 'Veri Analisti — Proje Bazlı (2024–Günümüz)\n'
        '• SQL ile 100.000+ satırlık veri setlerini temizleyip analiz ettim.\n'
        '• Power BI dashboardları ile raporlama süresini %40 kısalttım.',
    projects: 'Satış Performans Panosu — Python, SQL, Power BI\n'
        'Aylık satış verilerini otomatik işleyen ve KPI sapmalarını görselleştiren raporlama panosu.',
    certificates: 'Google Data Analytics (2024), Microsoft Power BI (2025)',
    keywords: [
      'sql',
      'python',
      'pandas',
      'numpy',
      'power bi',
      'excel',
      'veri',
      'istatistik',
      'etl',
      'dashboard',
      'git',
    ],
  ),
  CvTemplate(
    id: 'product',
    name: 'Ürün Yöneticisi',
    subtitle: 'Ürün · Proje yönetimi',
    icon: Icons.layers_outlined,
    accent: Color(0xFFFBBF24),
    headline: 'Ürün Yöneticisi · Dijital Ürünler',
    summary:
        'Kullanıcı ihtiyaçlarını veriye dayalı kararlarla ürüne dönüştüren ürün yöneticisi. Yol haritası planlama, çevik ekip koordinasyonu ve paydaş yönetimi deneyimi; teknik ekiplerle yakın çalışarak teslim sürelerini kısaltma odaklı.',
    skills:
        'Ürün Yönetimi, Agile/Scrum, Jira, Yol Haritası, Kullanıcı Araştırması, A/B Testi, Analitik, Paydaş Yönetimi, SQL',
    experience: 'Ürün Yöneticisi — Dijital Projeler (2024–Günümüz)\n'
        '• 2 ürünün yol haritasını oluşturup sürüm teslimlerini %25 hızlandırdım.\n'
        '• Kullanıcı araştırmaları ve A/B testleri ile dönüşüm oranını %15 artırdım.',
    projects: 'Ultimate Asistan — Ürün Keşfi ve Yol Haritası\n'
        'Kullanıcı ihtiyaç analizi, özellik önceliklendirme ve sürüm planlaması ile çok modüllü mobil ürünün uçtan uca koordinasyonu.',
    certificates: 'Google Project Management (2024), Scrum Master (2025)',
    keywords: [
      'ürün',
      'agile',
      'scrum',
      'jira',
      'yol haritası',
      'kullanıcı',
      'a/b',
      'analitik',
      'paydaş',
      'sql',
    ],
  ),
  CvTemplate(
    id: 'graduate',
    name: 'Yeni Mezun',
    subtitle: 'İlk kariyer adımı',
    icon: Icons.school_outlined,
    accent: Color(0xFFA78BFA),
    headline: 'Yeni Mezun · Bilgisayar Mühendisliği',
    summary:
        'Gazi Üniversitesi Bilgisayar Mühendisliği yeni mezunu. C, Kotlin ve TypeScript ile akademik ve kişisel projeler geliştirdi; takım çalışmasına yatkın, hızlı öğrenen ve üretmeyi seven bir mühendis adayı. İlk profesyonel rolünde yazılım geliştirme alanında katkı sağlamayı hedefliyor.',
    skills:
        'C, Kotlin, TypeScript, C#, React, Node.js, Git, SQL, Veri Yapıları, Algoritmalar',
    experience: 'Stajyer Yazılım Geliştirici — Üniversite / Proje (2023–2024)\n'
        '• React ve Node.js ile 2 akademik proje geliştirdim; 1 projeyi tek başıma teslim ettim.\n'
        '• Git tabanlı ekip çalışmasında kod inceleme ve test süreçlerine katıldım.',
    projects: 'Bitirme Projesi — Mobil Uygulama\n'
        'Flutter ve Supabase kullanarak not, takvim ve müzik modülleri olan bir asistan uygulaması geliştirdim.',
    certificates: 'BTK Akademi Yazılım Geliştirme (2024)',
    keywords: [
      'kotlin',
      'typescript',
      'react',
      'node.js',
      'flutter',
      'git',
      'sql',
      'algoritma',
      'veri yapıları',
      'c#',
    ],
  ),
];

const List<CvThemeOption> cvThemeOptions = [
  CvThemeOption(id: 'grafit', name: 'Grafit', accent: Color(0xFFE5E7EB)),
  CvThemeOption(id: 'okyanus', name: 'Okyanus', accent: Color(0xFF38BDF8)),
  CvThemeOption(id: 'zumrut', name: 'Zümrüt', accent: Color(0xFF34D399)),
  CvThemeOption(id: 'amber', name: 'Amber', accent: Color(0xFFFBBF24)),
  CvThemeOption(id: 'mor', name: 'Mor', accent: Color(0xFFA78BFA)),
];

CvTemplate templateById(String? id) {
  for (final template in cvTemplates) {
    if (template.id == id) return template;
  }
  return cvTemplates.first;
}

CvThemeOption themeById(String? id) {
  for (final theme in cvThemeOptions) {
    if (theme.id == id) return theme;
  }
  return cvThemeOptions.first;
}

/// GitHub alanına yazılan kullanıcı adı veya bağlantıyı `github.com/kullanici`
/// biçimine getirir. Boş değer boş kalır.
String normalizeGithub(String value) {
  var cleaned = value
      .trim()
      .replaceFirst(RegExp(r'^https?://', caseSensitive: false), '')
      .replaceFirst(RegExp(r'^www\.', caseSensitive: false), '')
      .replaceFirst(RegExp(r'/+$'), '');
  if (cleaned.isEmpty) return '';
  if (!cleaned.toLowerCase().contains('github.com')) {
    cleaned = 'github.com/$cleaned';
  }
  return cleaned;
}

/// LinkedIn alanına yazılan kullanıcı adı veya bağlantıyı
/// `linkedin.com/in/kullanici` biçimine getirir.
String normalizeLinkedin(String value) {
  var cleaned = value
      .trim()
      .replaceFirst(RegExp(r'^https?://', caseSensitive: false), '')
      .replaceFirst(RegExp(r'^www\.', caseSensitive: false), '')
      .replaceFirst(RegExp(r'/+$'), '');
  if (cleaned.isEmpty) return '';
  if (!cleaned.toLowerCase().contains('linkedin.com')) {
    cleaned = 'linkedin.com/in/$cleaned';
  }
  return cleaned;
}

/// GitHub bağlantısından yalnızca kullanıcı adını döndürür.
String githubUsername(String value) {
  return normalizeGithub(value)
      .replaceFirst(RegExp(r'^github\.com/', caseSensitive: false), '')
      .split('/')
      .first
      .trim();
}

/// LinkedIn bağlantısından yalnızca kullanıcı adını döndürür.
String linkedinUsername(String value) {
  return normalizeLinkedin(value)
      .replaceFirst(RegExp(r'^linkedin\.com/in/', caseSensitive: false), '')
      .split('/')
      .first
      .trim();
}

/// GitHub API'den çekilen bir depo.
class GithubRepo {
  final String name;
  final String description;
  final String language;
  final int stars;
  final bool archived;

  const GithubRepo({
    required this.name,
    required this.description,
    required this.language,
    required this.stars,
    required this.archived,
  });

  factory GithubRepo.fromJson(Map<String, dynamic> json) {
    final rawStars = json['stars'] ??
        json['stargazers_count'] ??
        json['star_count'] ??
        json['stars_count'] ??
        json['total_stars'] ??
        json['watchers_count'] ??
        json['star'];
    final language = json['lang'] ??
        json['language'] ??
        json['primary_language'] ??
        json['technologies'] ??
        json['tech_stack'] ??
        '';
    return GithubRepo(
      name: (json['name'] ??
              json['repo'] ??
              json['repository'] ??
              json['full_name'] ??
              json['project_name'] ??
              json['repo_name'] ??
              '')
          .toString(),
      description: (json['desc'] ??
              json['description'] ??
              json['summary'] ??
              json['about'] ??
              json['details'] ??
              '')
          .toString(),
      language: language is List
          ? (language.isEmpty ? 'Çeşitli' : language.join(', '))
          : (language.toString().trim().isEmpty
              ? 'Çeşitli'
              : language.toString()),
      stars: rawStars is num
          ? rawStars.toInt()
          : int.tryParse('${rawStars ?? 0}') ?? 0,
      archived: json['archived'] == true ||
          json['is_archived'] == true ||
          json['isArchived'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'desc': description,
        'lang': language,
        'stars': stars,
        'archived': archived,
      };
}

String formatRepoName(String name) {
  return name
      .replaceAll(RegExp(r'[-_]'), ' ')
      .split(' ')
      .where((word) => word.isNotEmpty)
      .map((word) => word[0].toUpperCase() + word.substring(1).toLowerCase())
      .join(' ');
}

/// GitHub depolarını CV projeleri metnine ekler. ATS ve panoya kopyalama
/// çıktısında depo adı, teknoloji ve açıklaması birlikte yer alır.
CvProfile mergeReposIntoProjects(
  CvProfile profile,
  List<GithubRepo> repos,
) {
  if (repos.isEmpty) return profile;
  final repoText = repos
      .map((repo) => '${formatRepoName(repo.name)} — ${repo.language}\n'
          '${repo.description.trim()}')
      .join('\n\n');
  return profile.copyWith(
    projects: [profile.projects.trim(), repoText]
        .where((part) => part.isNotEmpty)
        .join('\n\n'),
  );
}

/// Cihazlar arasında senkronize edilen CV anlık görüntüsü.
class CvSnapshot {
  final CvProfile profile;
  final String templateId;
  final String themeId;
  final List<GithubRepo> repos;
  final DateTime savedAt;

  /// Kullanıcının GitHub projelerini çekmek için girdiği API/proxy adresi.
  /// Boşsa doğrudan `api.github.com` kullanılır.
  final String apiUrl;

  const CvSnapshot({
    required this.profile,
    required this.templateId,
    required this.themeId,
    required this.repos,
    required this.savedAt,
    this.apiUrl = '',
  });

  factory CvSnapshot.fromJson(Map<String, dynamic> json) {
    final rawProfile = json['profile'];
    final profile = rawProfile is Map
        ? CvProfile.fromJson(Map<String, dynamic>.from(rawProfile))
        : CvProfile.defaults(templateById(json['templateId']?.toString()));
    final rawRepos = json['repos'];
    final repos = rawRepos is List
        ? rawRepos
            .whereType<Map>()
            .map((item) => GithubRepo.fromJson(Map<String, dynamic>.from(item)))
            .toList()
        : <GithubRepo>[];
    return CvSnapshot(
      profile: profile,
      templateId: (json['templateId'] ?? 'software').toString(),
      themeId: (json['themeId'] ?? 'grafit').toString(),
      repos: repos,
      savedAt: DateTime.tryParse((json['savedAt'] ?? '').toString()) ??
          DateTime.now(),
      apiUrl: (json['apiUrl'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'profile': profile.toJson(),
        'templateId': templateId,
        'themeId': themeId,
        'repos': repos.map((repo) => repo.toJson()).toList(),
        'savedAt': savedAt.toUtc().toIso8601String(),
        'apiUrl': apiUrl,
      };
}

/// CV arşivinde saklanan tek bir sürüm.
class CvHistoryEntry extends CvSnapshot {
  final String id;
  final String title;

  const CvHistoryEntry({
    required this.id,
    required this.title,
    required super.profile,
    required super.templateId,
    required super.themeId,
    required super.repos,
    required super.savedAt,
  });

  factory CvHistoryEntry.fromJson(Map<String, dynamic> json) {
    final snapshot = CvSnapshot.fromJson(json);
    return CvHistoryEntry(
      id: (json['id'] ?? '').toString(),
      title: (json['title'] ?? 'CV sürümü').toString(),
      profile: snapshot.profile,
      templateId: snapshot.templateId,
      themeId: snapshot.themeId,
      repos: snapshot.repos,
      savedAt: snapshot.savedAt,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        ...super.toJson(),
        'id': id,
        'title': title,
      };

  /// Aynı içeriğin art arda kaydedilmesini engellemek için kullanılan imza.
  String get signature => [
        profile.fullName,
        profile.headline,
        profile.github,
        profile.linkedin,
        profile.website,
        profile.summary,
        profile.education,
        profile.skills,
        profile.experience,
        profile.projects,
        profile.languages,
        profile.certificates,
        templateId,
        themeId,
        repos
            .map((repo) => '${repo.name}|${repo.language}|${repo.description}')
            .join(';'),
      ].join('\u0001');
}

/// CV ekranındaki tüm alanların taşındığı model.
class CvProfile {
  final String fullName;
  final String headline;
  final String github;
  final String linkedin;
  final String website;
  final String summary;
  final String education;
  final String skills;
  final String experience;
  final String projects;
  final String languages;
  final String certificates;

  const CvProfile({
    required this.fullName,
    required this.headline,
    required this.github,
    required this.linkedin,
    required this.website,
    required this.summary,
    required this.education,
    required this.skills,
    required this.experience,
    required this.projects,
    required this.languages,
    required this.certificates,
  });

  /// İlk açılışta alanları anlamlı biçimde dolduran başlangıç profili.
  factory CvProfile.defaults(CvTemplate template) {
    return CvProfile(
      fullName: 'Bilal Habeş Şimşek',
      headline: template.headline,
      github: 'github.com/bilalhabessimsek',
      linkedin: 'linkedin.com/in/bilalhabessimsek',
      website: '',
      summary: template.summary,
      education: 'Gazi Üniversitesi — Bilgisayar Mühendisliği',
      skills: template.skills,
      experience: template.experience,
      projects: template.projects,
      languages: 'Türkçe (Ana Dil), İngilizce (B2)',
      certificates: '',
    );
  }

  factory CvProfile.fromJson(Map<String, dynamic> json) {
    return CvProfile(
      fullName: (json['fullName'] ?? '').toString(),
      headline: (json['headline'] ?? '').toString(),
      github: (json['github'] ?? '').toString(),
      linkedin: (json['linkedin'] ?? '').toString(),
      website: (json['website'] ?? '').toString(),
      summary: (json['summary'] ?? '').toString(),
      education: (json['education'] ?? '').toString(),
      skills: (json['skills'] ?? '').toString(),
      experience: (json['experience'] ?? '').toString(),
      projects: (json['projects'] ?? '').toString(),
      languages: (json['languages'] ?? '').toString(),
      certificates: (json['certificates'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'fullName': fullName,
        'headline': headline,
        'github': github,
        'linkedin': linkedin,
        'website': website,
        'summary': summary,
        'education': education,
        'skills': skills,
        'experience': experience,
        'projects': projects,
        'languages': languages,
        'certificates': certificates,
      };

  CvProfile copyWith({
    String? fullName,
    String? headline,
    String? github,
    String? linkedin,
    String? website,
    String? summary,
    String? education,
    String? skills,
    String? experience,
    String? projects,
    String? languages,
    String? certificates,
  }) {
    return CvProfile(
      fullName: fullName ?? this.fullName,
      headline: headline ?? this.headline,
      github: github ?? this.github,
      linkedin: linkedin ?? this.linkedin,
      website: website ?? this.website,
      summary: summary ?? this.summary,
      education: education ?? this.education,
      skills: skills ?? this.skills,
      experience: experience ?? this.experience,
      projects: projects ?? this.projects,
      languages: languages ?? this.languages,
      certificates: certificates ?? this.certificates,
    );
  }
}

/// Tek bir ATS kontrolü.
class AtsCriterion {
  final String label;
  final String hint;
  final int weight;
  final bool passed;

  const AtsCriterion({
    required this.label,
    required this.hint,
    required this.weight,
    required this.passed,
  });
}

/// ATS incelemesinin sonucu.
class AtsReport {
  final int score;
  final String verdict;
  final List<AtsCriterion> criteria;
  final List<String> matchedKeywords;
  final List<String> missingKeywords;
  final List<String> suggestions;

  const AtsReport({
    required this.score,
    required this.verdict,
    required this.criteria,
    required this.matchedKeywords,
    required this.missingKeywords,
    required this.suggestions,
  });

  List<AtsCriterion> get passedCriteria =>
      criteria.where((criterion) => criterion.passed).toList();

  List<AtsCriterion> get failedCriteria =>
      criteria.where((criterion) => !criterion.passed).toList();
}

List<String> _splitItems(String value) {
  return value
      .split(RegExp(r'[,;\n]'))
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList();
}

/// Türkçe İ/I/ı farklarını tek harfe indirerek anahtar kelime eşleşmesini
/// bozmadan büyük/küçük harf duyarsız arama yapar. Örn. "API", "İstatistik".
String _normalizeSearch(String value) {
  return value
      .replaceAll('İ', 'i')
      .replaceAll('I', 'i')
      .replaceAll('ı', 'i')
      .toLowerCase();
}

/// Türkçe kurallarına uygun büyük harf (i -> İ, ı -> I).
String _upperTr(String value) {
  return value.replaceAll('i', 'İ').replaceAll('ı', 'I').toUpperCase();
}

/// CV alanlarını ATS kurallarına göre puanlar (100 üzerinden).
AtsReport analyzeCv(CvProfile profile, CvTemplate template) {
  final summary = profile.summary.trim();
  final skills = _splitItems(profile.skills);
  final experience = profile.experience.trim();
  final projects = profile.projects.trim();

  final searchable = _normalizeSearch([
    profile.headline,
    profile.summary,
    profile.skills,
    profile.experience,
    profile.projects,
    profile.certificates,
  ].join(' '));

  final matchedKeywords = template.keywords
      .where((keyword) => searchable.contains(_normalizeSearch(keyword)))
      .toList();
  final missingKeywords = template.keywords
      .where((keyword) => !searchable.contains(_normalizeSearch(keyword)))
      .toList();

  final keywordThreshold =
      template.keywords.length < 4 ? template.keywords.length : 4;

  // Yıl yazımı (2024) tek başına yeterli olmasın; gerçek bir başarı ölçüsü ara.
  final measurable = RegExp(
    r'(\d+\s*%|%\s*\d+|\d+\+|\d+\s*(bin|kat|adet|kullanıcı|müşteri|proje|satır)|artı|iyileştir|kısalt|hızlandır)',
    caseSensitive: false,
  ).hasMatch('$experience $projects');

  final criteria = <AtsCriterion>[
    AtsCriterion(
      label: 'Ad soyad',
      hint: 'CV başlığına ad ve soyadını ekle.',
      weight: 6,
      passed: profile.fullName.trim().split(RegExp(r'\s+')).length >= 2,
    ),
    AtsCriterion(
      label: 'Hedef unvan',
      hint: 'Başvuracağın rolü belirten bir unvan yaz.',
      weight: 8,
      passed: profile.headline.trim().isNotEmpty,
    ),
    AtsCriterion(
      label: 'Profil özeti (120+ karakter)',
      hint:
          'Deneyimini 2-3 cümleyle, rolünle ilgili anahtar kelimelerle özetle.',
      weight: 12,
      passed: summary.length >= 120,
    ),
    AtsCriterion(
      label: 'Eğitim bilgisi',
      hint: 'Okul ve bölüm bilgisini ekle.',
      weight: 8,
      passed: profile.education.trim().isNotEmpty,
    ),
    AtsCriterion(
      label: 'En az 3 yetenek',
      hint: 'Virgülle ayırarak en az 3 teknik yetenek yaz.',
      weight: 10,
      passed: skills.length >= 3,
    ),
    AtsCriterion(
      label: 'Deneyim',
      hint: 'İş, staj veya gönüllü deneyimini ekle.',
      weight: 10,
      passed: experience.isNotEmpty,
    ),
    AtsCriterion(
      label: 'Proje',
      hint: 'En az bir proje ve kullandığın teknolojileri ekle.',
      weight: 8,
      passed: projects.isNotEmpty,
    ),
    AtsCriterion(
      label: 'Dil bilgisi',
      hint: 'Dillerini ve seviyelerini ekle.',
      weight: 6,
      passed: profile.languages.trim().isNotEmpty,
    ),
    AtsCriterion(
      label: 'GitHub + LinkedIn',
      hint: 'İki profesyonel bağlantıyı da ekle.',
      weight: 8,
      passed: profile.github.trim().isNotEmpty &&
          profile.linkedin.trim().isNotEmpty,
    ),
    AtsCriterion(
      label: 'Ölçülebilir başarı',
      hint: 'Deneyim veya projede sayı/yüzde içeren bir sonuç yaz.',
      weight: 8,
      passed: measurable,
    ),
    AtsCriterion(
      label: '${template.name} anahtar kelimeleri',
      hint:
          'Rolünle ilgili en az $keywordThreshold anahtar kelime kullan (ör. ${template.keywords.take(3).join(', ')}).',
      weight: 16,
      passed:
          keywordThreshold > 0 && matchedKeywords.length >= keywordThreshold,
    ),
  ];

  final score = criteria
      .where((criterion) => criterion.passed)
      .fold<int>(0, (total, criterion) => total + criterion.weight);

  final suggestions = <String>[
    for (final criterion in criteria)
      if (!criterion.passed) criterion.hint,
    if (profile.certificates.trim().isEmpty)
      'Sertifika veya tamamlanan eğitim eklemek güvenilirliği artırır.',
    if (missingKeywords.isNotEmpty)
      'Eksik anahtar kelimeler: ${missingKeywords.take(6).join(', ')}.',
    if (score >= 85)
      'CV ATS için güçlü görünüyor. Başvurduğun ilana özel anahtar kelimeleri kontrol etmeyi unutma.',
  ];

  final verdict = score >= 85
      ? 'ATS dostu'
      : score >= 65
          ? 'İyi — birkaç iyileştirme'
          : score >= 40
              ? 'Geliştirilmeli'
              : 'Zayıf';

  return AtsReport(
    score: score,
    verdict: verdict,
    criteria: criteria,
    matchedKeywords: matchedKeywords,
    missingKeywords: missingKeywords,
    suggestions: suggestions,
  );
}

/// CV'yi panoya kopyalanabilir düz metne çevirir (ATS metin çıktısı).
String buildCvPlainText(
  CvProfile profile, {
  List<GithubRepo> repos = const [],
}) {
  final contact = [profile.github, profile.linkedin, profile.website]
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .join(' | ');

  final header = [
    _upperTr(profile.fullName.trim()),
    profile.headline.trim(),
    contact,
  ].where((line) => line.isNotEmpty).join('\n');

  final sections = <String>[];
  void addSection(String title, String body) {
    final text = body.trim();
    if (text.isNotEmpty) sections.add('$title\n$text');
  }

  addSection('PROFİL ÖZETİ', profile.summary);
  addSection('EĞİTİM', profile.education);
  addSection('YETENEKLER', profile.skills);
  addSection('DENEYİM', profile.experience);
  addSection('PROJELER', profile.projects);
  if (repos.isNotEmpty) {
    addSection(
      'GITHUB PROJELERİ',
      repos
          .map((repo) => '${formatRepoName(repo.name)} — ${repo.language}'
              '${repo.stars > 0 ? ' · ${repo.stars} yıldız' : ''}\n'
              '${repo.description.trim()}')
          .join('\n\n'),
    );
  }
  addSection('DİLLER', profile.languages);
  addSection('SERTİFİKALAR', profile.certificates);

  return [header, ...sections]
      .where((part) => part.trim().isNotEmpty)
      .join('\n\n');
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/cv_sync_store.dart';
import '../utils/cv_templates.dart';
import '../utils/github_api.dart';

class CareerScreen extends StatefulWidget {
  const CareerScreen({super.key});

  /// Dashboard'daki "ATS Uygunluk İncelemesi" kısayolundan gelindiğinde,
  /// ekran yüklendikten sonra raporu otomatik açar.
  static bool _pendingAtsCheck = false;

  static void requestAtsCheck() {
    _pendingAtsCheck = true;
  }

  @override
  State<CareerScreen> createState() => _CareerScreenState();
}

class _CareerScreenState extends State<CareerScreen> {
  final _syncStore = CvSyncStore();

  final _fullNameController = TextEditingController();
  final _headlineController = TextEditingController();
  final _githubController = TextEditingController();
  final _githubApiController = TextEditingController();
  final _linkedinController = TextEditingController();
  final _websiteController = TextEditingController();
  final _summaryController = TextEditingController();
  final _educationController = TextEditingController();
  final _skillsController = TextEditingController();
  final _experienceController = TextEditingController();
  final _projectsController = TextEditingController();
  final _languagesController = TextEditingController();
  final _certificatesController = TextEditingController();

  bool _isLoading = true;
  bool _isSaving = false;
  bool _openAtsOnLoad = false;
  bool _suppressAutoSave = false;
  String _templateId = 'software';
  String _themeId = 'grafit';

  List<GithubRepo> _repos = [];
  bool _githubLoading = false;
  String _githubError = '';
  List<CvHistoryEntry> _history = [];
  bool _historyLoading = false;
  Timer? _autoSaveTimer;

  CvTemplate get _template => templateById(_templateId);
  CvThemeOption get _theme => themeById(_themeId);

  List<TextEditingController> get _controllers => [
        _fullNameController,
        _headlineController,
        _githubController,
        _githubApiController,
        _linkedinController,
        _websiteController,
        _summaryController,
        _educationController,
        _skillsController,
        _experienceController,
        _projectsController,
        _languagesController,
        _certificatesController,
      ];

  @override
  void initState() {
    super.initState();
    _openAtsOnLoad = CareerScreen._pendingAtsCheck;
    CareerScreen._pendingAtsCheck = false;
    for (final controller in _controllers) {
      controller.addListener(_scheduleAutoSave);
    }
    _load();
  }

  @override
  void dispose() {
    _autoSaveTimer?.cancel();
    for (final controller in _controllers) {
      controller.removeListener(_scheduleAutoSave);
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    _suppressAutoSave = true;
    final snapshot = await _syncStore.loadCurrent();
    final history = await _syncStore.loadHistory();

    if (!mounted) return;

    final template = templateById(snapshot?.templateId ?? _templateId);
    final theme = themeById(snapshot?.themeId ?? _themeId);
    final profile = snapshot?.profile ?? CvProfile.defaults(template);

    setState(() {
      _templateId = template.id;
      _themeId = theme.id;
      _fullNameController.text = profile.fullName;
      _headlineController.text = profile.headline;
      _githubController.text = githubUsername(profile.github);
      _githubApiController.text = snapshot?.apiUrl ?? '';
      _linkedinController.text = linkedinUsername(profile.linkedin);
      _websiteController.text = profile.website;
      _summaryController.text = profile.summary;
      _educationController.text = profile.education;
      _skillsController.text = profile.skills;
      _experienceController.text = profile.experience;
      _projectsController.text = profile.projects;
      _languagesController.text = profile.languages;
      _certificatesController.text = profile.certificates;
      _repos = snapshot?.repos ?? [];
      _history = history;
      _isLoading = false;
    });
    _suppressAutoSave = false;
    if (snapshot != null) _scheduleAutoSave();

    if (_openAtsOnLoad) {
      _openAtsOnLoad = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _showAtsSheet(analyzeCv(_effectiveProfile(), _template));
        }
      });
    }
  }

  CvProfile _currentProfile() {
    return CvProfile(
      fullName: _fullNameController.text.trim(),
      headline: _headlineController.text.trim(),
      github: normalizeGithub(_githubController.text.trim()),
      linkedin: normalizeLinkedin(_linkedinController.text.trim()),
      website: _websiteController.text.trim(),
      summary: _summaryController.text.trim(),
      education: _educationController.text.trim(),
      skills: _skillsController.text.trim(),
      experience: _experienceController.text.trim(),
      projects: _projectsController.text.trim(),
      languages: _languagesController.text.trim(),
      certificates: _certificatesController.text.trim(),
    );
  }

  CvProfile _effectiveProfile() {
    return mergeReposIntoProjects(_currentProfile(), _repos);
  }

  CvSnapshot _snapshot({DateTime? savedAt}) {
    return CvSnapshot(
      profile: _currentProfile(),
      templateId: _templateId,
      themeId: _themeId,
      repos: List<GithubRepo>.unmodifiable(_repos),
      savedAt: savedAt ?? DateTime.now(),
      apiUrl: _githubApiController.text.trim(),
    );
  }

  void _scheduleAutoSave() {
    if (_isLoading || _suppressAutoSave) return;
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted) return;
      if (_isSaving) {
        // Kaydetme sürerken yapılan değişiklikler kaybolmasın; kısa süre
        // sonra tekrar dene.
        _scheduleAutoSave();
        return;
      }
      _save(feedback: false, silent: true);
    });
  }

  Future<bool> _save({
    bool feedback = true,
    bool silent = false,
  }) async {
    if (_isSaving) return false;
    setState(() => _isSaving = true);

    final ok = await _syncStore.saveCurrent(_snapshot());

    if (!mounted) return false;
    setState(() => _isSaving = false);

    if (!silent) {
      _showSnack(
        ok
            ? 'CV kaydedildi ve senkronize edildi.'
            : 'CV kaydedildi (yalnızca bu cihazda).',
        isError: !ok,
      );
    }
    return ok;
  }

  Future<void> _saveAndAnalyze() async {
    final saved = await _save(feedback: false);
    if (!mounted) return;
    _showSnack(
      saved
          ? 'CV kaydedildi ve senkronize edildi.'
          : 'CV kaydedildi (yalnızca bu cihazda).',
      isError: !saved,
    );
    _showAtsSheet(analyzeCv(_effectiveProfile(), _template));
  }

  void _showSnack(
    String message, {
    bool isError = false,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            message,
            style: const TextStyle(color: Colors.white),
          ),
          backgroundColor:
              isError ? const Color(0xFF7F1D1D) : const Color(0xFF161B22),
          behavior: SnackBarBehavior.floating,
          action: actionLabel == null
              ? null
              : SnackBarAction(
                  label: actionLabel,
                  textColor: Colors.white,
                  onPressed: onAction ?? () {},
                ),
        ),
      );
  }

  void _applyTemplate(CvTemplate template) {
    setState(() {
      _templateId = template.id;
      _headlineController.text = template.headline;
      _summaryController.text = template.summary;
      _skillsController.text = template.skills;
      if (_experienceController.text.trim().isEmpty) {
        _experienceController.text = template.experience;
      }
      if (_projectsController.text.trim().isEmpty) {
        _projectsController.text = template.projects;
      }
    });
    _showSnack(
      '${template.name} kalıbı uygulandı. Deneyim ve projeleri kendine göre düzenle.',
    );
    _scheduleAutoSave();
  }

  Future<void> _confirmFillAll() async {
    final template = _template;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161B22),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Colors.white12),
        ),
        title: const Text(
          'Tüm alanları doldur',
          style: TextStyle(color: Colors.white, fontSize: 16),
        ),
        content: Text(
          '${template.name} kalıbı tüm CV alanlarına uygulanacak. Mevcut metinler değişecek. Devam edilsin mi?',
          style:
              const TextStyle(color: Colors.white70, fontSize: 13, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Doldur',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      _headlineController.text = template.headline;
      _summaryController.text = template.summary;
      _skillsController.text = template.skills;
      _experienceController.text = template.experience;
      _projectsController.text = template.projects;
      _educationController.text = 'Gazi Üniversitesi — Bilgisayar Mühendisliği';
      _languagesController.text = 'Türkçe (Ana Dil), İngilizce (B2)';
    });
    _showSnack('${template.name} kalıbı tüm CV alanlarına uygulandı.');
    _scheduleAutoSave();
  }

  void _applyExample(
    String label,
    TextEditingController controller,
    String example,
  ) {
    final previous = controller.text;
    controller.text = example;
    controller.selection = TextSelection.collapsed(offset: example.length);
    _showSnack(
      '$label için örnek metin yüklendi.',
      actionLabel: 'Geri al',
      onAction: () {
        if (!mounted) return;
        controller.text = previous;
        controller.selection = TextSelection.collapsed(offset: previous.length);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      body: SafeArea(
        child: _isLoading
            ? const Center(
                child: CircularProgressIndicator(color: Colors.white))
            : SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(),
                    const SizedBox(height: 20),
                    _buildTemplatesCard(),
                    const SizedBox(height: 20),
                    _buildProfileCard(),
                    const SizedBox(height: 20),
                    _buildGithubCard(),
                    const SizedBox(height: 20),
                    _buildContentCard(),
                    const SizedBox(height: 20),
                    _buildHistoryCard(),
                    const SizedBox(height: 22),
                    _buildActions(),
                    const SizedBox(height: 30),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildHeader() {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'PROFESYONEL PROFİL',
          style: TextStyle(
            fontSize: 11,
            letterSpacing: 1.5,
            color: Colors.grey,
            fontWeight: FontWeight.bold,
          ),
        ),
        SizedBox(height: 4),
        Text(
          'Kariyer & CV',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w900,
            color: Colors.white,
          ),
        ),
        SizedBox(height: 6),
        Text(
          'ATS uyumlu özgeçmişini kalıplarla doldur, GitHub projelerini ekle, puanla ve sürümlerini cihazlar arası sakla.',
          style: TextStyle(color: Colors.grey, fontSize: 13, height: 1.4),
        ),
      ],
    );
  }

  Widget _buildTemplatesCard() {
    final accent = _theme.accent;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'CV kalıpları',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Rolünü seç; başlık, özet ve yetenekler otomatik dolsun.',
                      style: TextStyle(color: Colors.grey, fontSize: 11.5),
                    ),
                  ],
                ),
              ),
              TextButton.icon(
                onPressed: _confirmFillAll,
                icon: Icon(Icons.auto_fix_high, size: 15, color: accent),
                label: Text(
                  'Tümünü doldur',
                  style: TextStyle(
                    color: accent,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 122,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: cvTemplates.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, index) {
                final template = cvTemplates[index];
                final selected = template.id == _templateId;
                return GestureDetector(
                  onTap: () => _applyTemplate(template),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: 152,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: selected
                          ? template.accent.withValues(alpha: 0.12)
                          : const Color(0xFF0D1117),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: selected ? template.accent : Colors.white12,
                        width: selected ? 1.5 : 1,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          template.icon,
                          color: selected ? template.accent : Colors.grey,
                          size: 20,
                        ),
                        const Spacer(),
                        Text(
                          template.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: selected ? Colors.white : Colors.white70,
                            fontSize: 12.5,
                            fontWeight: FontWeight.bold,
                            height: 1.2,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          template.subtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 10.5,
                            height: 1.25,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Text(
                  'GÖRÜNÜM · ${_theme.name.toUpperCase()}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.grey,
                    fontSize: 10,
                    letterSpacing: 1,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              ...cvThemeOptions.map(_themeDot),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Kalıplar örnektir; deneyim, proje ve rakamları kendine göre güncelle.',
            style: TextStyle(
              color: Color(0xFF6B7280),
              fontSize: 10.5,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  Widget _themeDot(CvThemeOption theme) {
    final selected = theme.id == _themeId;
    return GestureDetector(
      onTap: () {
        setState(() => _themeId = theme.id);
        _scheduleAutoSave();
      },
      child: Container(
        width: 24,
        height: 24,
        margin: const EdgeInsets.only(left: 6),
        decoration: BoxDecoration(
          color: theme.accent,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? Colors.white : Colors.white24,
            width: selected ? 2 : 1,
          ),
        ),
        child: selected
            ? const Icon(Icons.check, size: 15, color: Colors.black)
            : null,
      ),
    );
  }

  Widget _buildProfileCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Profil ve iletişim',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          _cvField(
            label: 'Ad soyad',
            controller: _fullNameController,
            icon: Icons.person_outline,
            hint: 'Ad Soyad',
          ),
          _cvField(
            label: 'Hedef unvan',
            controller: _headlineController,
            icon: Icons.badge_outlined,
            hint: 'Örn. Full-Stack Yazılım Geliştirici',
            example: _template.headline,
          ),
          _cvField(
            label: 'LinkedIn',
            controller: _linkedinController,
            icon: Icons.business_center_outlined,
            hint: 'linkedin.com/in/kullanici',
          ),
          _cvField(
            label: 'Kişisel site / portfolyo',
            controller: _websiteController,
            icon: Icons.language,
            hint: 'ornek.com',
          ),
        ],
      ),
    );
  }

  Widget _buildGithubCard() {
    final accent = _theme.accent;
    final visibleRepos = _repos.take(8).toList();
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.code, color: accent, size: 20),
              const SizedBox(width: 8),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'GitHub API',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Projelerini çek; CV projelerine ve ATS çıktısına otomatik eklensin.',
                      style: TextStyle(color: Colors.grey, fontSize: 11),
                    ),
                  ],
                ),
              ),
              if (_repos.isNotEmpty)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: accent.withValues(alpha: 0.35)),
                  ),
                  child: Text(
                    '${_repos.length} proje',
                    style: TextStyle(
                      color: accent,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          _cvField(
            label: 'GitHub kullanıcı adı',
            controller: _githubController,
            icon: Icons.alternate_email,
            hint: 'bilalhabessimsek · API kullanıcı adı içeriyorsa boş bırak',
          ),
          _cvField(
            label: 'GitHub API / proxy adresi (opsiyonel)',
            controller: _githubApiController,
            icon: Icons.dns_outlined,
            hint:
                'Boş = api.github.com · Örn: https://proxy.../repos?username={username}',
            maxLines: 2,
          ),
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Text(
              'Kendi API’ni kullanıyorsan adresi buraya yaz. Adres olduğu gibi çağrılır; {username} yazarsan yerine GitHub kullanıcı adı eklenir. GitHub’a özel parametreler özel adrese eklenmez; token katmanda kalmalı.',
              style: TextStyle(
                color: Color(0xFF6B7280),
                fontSize: 10,
                height: 1.35,
              ),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _githubLoading ? null : _fetchGithubRepos,
                  icon: _githubLoading
                      ? const SizedBox(
                          width: 15,
                          height: 15,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.black,
                          ),
                        )
                      : const Icon(Icons.cloud_download_outlined, size: 17),
                  label: Text(
                    _githubLoading ? 'Projeler çekiliyor...' : 'Projeleri Çek',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accent,
                    foregroundColor: Colors.black,
                    disabledBackgroundColor: accent.withValues(alpha: 0.4),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              if (_repos.isNotEmpty) ...[
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Projeleri temizle',
                  onPressed: () {
                    setState(() => _repos = []);
                    _scheduleAutoSave();
                  },
                  icon: const Icon(
                    Icons.delete_sweep_outlined,
                    color: Colors.grey,
                  ),
                ),
              ],
            ],
          ),
          if (_githubError.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: const Color(0xFF7F1D1D).withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFF87171)),
              ),
              child: Text(
                _githubError,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  height: 1.35,
                ),
              ),
            ),
          ],
          if (_repos.isNotEmpty) ...[
            const SizedBox(height: 14),
            for (final repo in visibleRepos) ...[
              _repoRow(repo),
              const SizedBox(height: 7),
            ],
            if (_repos.length > visibleRepos.length)
              Text(
                '+ ${_repos.length - visibleRepos.length} proje daha önizlemede gösterilir.',
                style: const TextStyle(color: Colors.grey, fontSize: 10),
              ),
          ],
        ],
      ),
    );
  }

  Widget _repoRow(GithubRepo repo) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1117),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  formatRepoName(repo.name),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  repo.description.trim().isEmpty
                      ? 'Açıklama yok'
                      : repo.description.trim(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.grey,
                    fontSize: 10.5,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                repo.language,
                style: TextStyle(
                  color: _theme.accent,
                  fontSize: 9.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (repo.stars > 0) ...[
                const SizedBox(height: 2),
                Text(
                  '★ ${repo.stars}',
                  style: const TextStyle(color: Colors.grey, fontSize: 9.5),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryCard() {
    final accent = _theme.accent;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.history, color: accent, size: 20),
              const SizedBox(width: 8),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'CV Arşivi',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Sürüm kaydet; eski CV\'lere dön. Kayıtlar hesabınla senkronize edilir.',
                      style: TextStyle(color: Colors.grey, fontSize: 11),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white10,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${_history.length}',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _isSaving ? null : _saveVersion,
                  icon: const Icon(Icons.bookmark_add_outlined, size: 17),
                  label: const Text('Sürüm Kaydet'),
                  style: _outlinedButtonStyle(),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _historyLoading ? null : _openHistorySheet,
                  icon: _historyLoading
                      ? const SizedBox(
                          width: 15,
                          height: 15,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.folder_open_outlined, size: 17),
                  label: Text('Önceki CV\'ler (${_history.length})'),
                  style: _outlinedButtonStyle(),
                ),
              ),
            ],
          ),
          if (_history.isNotEmpty) ...[
            const SizedBox(height: 12),
            GestureDetector(
              onTap: _openHistorySheet,
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF0D1117),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.check_circle_outline, color: accent, size: 15),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        'Son sürüm: ${_history.first.title}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 10.5,
                        ),
                      ),
                    ),
                    const Icon(Icons.chevron_right,
                        color: Colors.grey, size: 16),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _fetchGithubRepos() async {
    final username = githubUsername(_githubController.text);
    final apiInput = _githubApiController.text.trim();
    if (username.isEmpty && apiInput.isEmpty) {
      setState(() => _githubError =
          'GitHub kullanıcı adını ya da kendi API adresini yaz.');
      return;
    }

    final usesCustomApi = apiInput.isNotEmpty;

    setState(() {
      _githubLoading = true;
      _githubError = '';
    });

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final uri = buildGithubReposUri(apiUrl: apiInput, username: username);
      final request = await client.getUrl(uri);
      request.headers.set(HttpHeaders.userAgentHeader, 'Ultimate-Mobile');
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();

      dynamic decoded;
      if (body.trim().isNotEmpty) {
        try {
          decoded = jsonDecode(body.replaceFirst('\uFEFF', ''));
        } catch (_) {
          decoded = null;
        }
      }
      final apiDetail = githubApiErrorMessage(decoded);

      if (response.statusCode == 404) {
        throw FormatException(
          usesCustomApi
              ? 'API kullanıcıyı bulamadı (404). API adresini ve kullanıcı adını kontrol et.'
              : 'GitHub kullanıcısı bulunamadı.',
        );
      }
      if (response.statusCode == 401 ||
          response.statusCode == 403 ||
          response.statusCode == 429) {
        final base = usesCustomApi
            ? 'API isteği reddedildi (${response.statusCode}). Proxy token’ını ve istek sınırını kontrol et.'
            : 'GitHub API istek sınırı doldu. Birkaç dakika sonra tekrar dene.';
        throw FormatException(
          apiDetail.isEmpty ? base : '$base\n$apiDetail',
        );
      }
      if (response.statusCode != 200) {
        throw FormatException(
          'API hatası (${response.statusCode})'
          '${apiDetail.isEmpty ? '.' : ': $apiDetail'}',
        );
      }
      if (decoded == null) {
        throw const FormatException(
          'API yanıtı okunamadı. Adresin JSON döndürdüğünden emin ol.',
        );
      }

      final items = extractGithubRepoItems(decoded);
      final repos = items
          .where((item) {
            return item['fork'] != true &&
                item['is_fork'] != true &&
                item['isFork'] != true &&
                item['forked'] != true;
          })
          .map((item) {
            final rawName =
                '${item['name'] ?? item['repo'] ?? item['repository'] ?? item['full_name'] ?? item['project_name'] ?? item['repo_name'] ?? item['slug'] ?? item['title'] ?? ''}'
                    .trim();
            final name = rawName.contains('/')
                ? rawName.split('/').last.trim()
                : rawName;
            final rawStars = item['stargazers_count'] ??
                item['stars'] ??
                item['star_count'] ??
                item['stars_count'] ??
                item['total_stars'] ??
                item['watchers_count'] ??
                item['watchers'] ??
                item['star'];
            final stars = rawStars is num
                ? rawStars.toInt()
                : int.tryParse('$rawStars') ?? 0;
            final rawLanguageValue = item['language'] ??
                item['lang'] ??
                item['primary_language'] ??
                item['tech'] ??
                item['technologies'] ??
                item['tech_stack'] ??
                item['stack'];
            final rawLanguage = rawLanguageValue is List
                ? rawLanguageValue
                    .map((value) => '$value'.trim())
                    .where((value) => value.isNotEmpty)
                    .join(', ')
                : '${rawLanguageValue ?? ''}'.trim();
            final description =
                '${item['description'] ?? item['desc'] ?? item['summary'] ?? item['about'] ?? item['details'] ?? ''}'
                    .trim();
            return GithubRepo(
              name: name,
              description: description,
              language: rawLanguage.isEmpty ? 'Çeşitli' : rawLanguage,
              stars: stars,
              archived: item['archived'] == true ||
                  item['is_archived'] == true ||
                  item['isArchived'] == true,
            );
          })
          .where((repo) => repo.name.trim().isNotEmpty)
          .toList()
        ..sort((a, b) => b.stars.compareTo(a.stars));

      if (!mounted) return;
      setState(() {
        _githubLoading = false;
        _repos = repos;
        _githubError = repos.isEmpty
            ? 'Proje bulunamadı. Kullanıcı adını ve API yanıtını kontrol et.'
            : '';
      });
      if (repos.isNotEmpty) {
        _showSnack('${repos.length} GitHub projesi CV\'ye eklendi.');
        _scheduleAutoSave();
      }
    } on FormatException catch (err) {
      if (!mounted) return;
      setState(() {
        _githubLoading = false;
        _githubError = err.message;
      });
    } on SocketException {
      if (!mounted) return;
      setState(() {
        _githubLoading = false;
        _githubError =
            'İnternet bağlantısı kurulamadı. Bağlantını kontrol edip tekrar dene.';
      });
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _githubLoading = false;
        _githubError = 'GitHub projeleri çekilemedi: $err';
      });
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _saveVersion() async {
    final now = DateTime.now();
    final entry = CvHistoryEntry(
      id: '${now.microsecondsSinceEpoch}',
      title: '${_template.name} · ${_formatDate(now)}',
      profile: _currentProfile(),
      templateId: _templateId,
      themeId: _themeId,
      repos: List<GithubRepo>.unmodifiable(_repos),
      savedAt: now,
    );

    if (_history.isNotEmpty && _history.first.signature == entry.signature) {
      _showSnack('Bu CV zaten son sürümle aynı; yeni kayıt oluşturulmadı.');
      return;
    }

    await _save(feedback: false, silent: true);
    final ok = await _syncStore.saveHistory(entry);
    if (!mounted) return;

    setState(() {
      _history = [
        entry,
        ..._history.where((item) => item.id != entry.id),
      ]..sort((a, b) => b.savedAt.compareTo(a.savedAt));
    });
    _showSnack(
      ok
          ? 'CV sürümü kaydedildi ve buluta gönderildi.'
          : 'CV sürümü bu cihazda kaydedildi; bulut bağlantısı kurulamadı.',
      isError: !ok,
    );
  }

  Future<void> _refreshHistory({bool showFeedback = false}) async {
    setState(() => _historyLoading = true);
    final entries = await _syncStore.loadHistory();
    if (!mounted) return;
    setState(() {
      _history = entries;
      _historyLoading = false;
    });
    if (showFeedback) _showSnack('CV arşivi güncellendi.');
  }

  Future<void> _openHistorySheet() async {
    await _refreshHistory();
    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final entries = _history;
            return Container(
              height: MediaQuery.of(context).size.height * 0.82,
              decoration: const BoxDecoration(
                color: Color(0xFF0D1117),
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                children: [
                  _sheetGrabber(),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 12, 4),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Önceki CV\'ler',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Yenile',
                          onPressed: () async {
                            await _refreshHistory();
                            if (context.mounted) setSheetState(() {});
                          },
                          icon: const Icon(
                            Icons.refresh,
                            color: Colors.grey,
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(sheetContext),
                          icon: const Icon(Icons.close, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${entries.length} sürüm · hesabınla senkron',
                            style: const TextStyle(
                              color: Colors.grey,
                              fontSize: 11,
                            ),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () async {
                            await _saveVersion();
                            if (context.mounted) setSheetState(() {});
                          },
                          icon:
                              const Icon(Icons.bookmark_add_outlined, size: 16),
                          label: const Text('Sürüm Kaydet'),
                          style: TextButton.styleFrom(
                            foregroundColor: _theme.accent,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: entries.isEmpty
                        ? const Center(
                            child: Padding(
                              padding: EdgeInsets.all(30),
                              child: Text(
                                'Henüz kayıtlı CV sürümü yok. "Sürüm Kaydet" ile ilk kopyanı oluştur.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.grey,
                                  fontSize: 13,
                                  height: 1.5,
                                ),
                              ),
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                            itemCount: entries.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 9),
                            itemBuilder: (context, index) {
                              final entry = entries[index];
                              return _historyTile(
                                entry,
                                onLoad: () async {
                                  Navigator.pop(sheetContext);
                                  await _restoreHistory(entry);
                                },
                                onDelete: () async {
                                  await _deleteHistory(entry);
                                  if (context.mounted) setSheetState(() {});
                                },
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _historyTile(
    CvHistoryEntry entry, {
    required Future<void> Function() onLoad,
    required Future<void> Function() onDelete,
  }) {
    final template = templateById(entry.templateId);
    final theme = themeById(entry.themeId);
    final score = analyzeCv(
      mergeReposIntoProjects(entry.profile, entry.repos),
      template,
    ).score;
    final scoreColor = score >= 85
        ? const Color(0xFF34D399)
        : score >= 65
            ? const Color(0xFFFBBF24)
            : const Color(0xFFF87171);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.accent.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  entry.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: scoreColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(
                    color: scoreColor.withValues(alpha: 0.4),
                  ),
                ),
                child: Text(
                  'ATS $score',
                  style: TextStyle(
                    color: scoreColor,
                    fontSize: 9.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${template.name} · ${theme.name} · ${_formatDate(entry.savedAt)}'
            '${entry.repos.isNotEmpty ? ' · ${entry.repos.length} GitHub projesi' : ''}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.grey,
              fontSize: 10,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 9),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => onLoad(),
                  icon: const Icon(Icons.restore, size: 15),
                  label: const Text('Yükle'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side:
                        BorderSide(color: theme.accent.withValues(alpha: 0.5)),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(9),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Sürümü sil',
                onPressed: () => onDelete(),
                icon: const Icon(
                  Icons.delete_outline,
                  color: Colors.grey,
                  size: 19,
                ),
                style: IconButton.styleFrom(
                  side: const BorderSide(color: Colors.white12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(9),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _restoreHistory(CvHistoryEntry entry) async {
    final template = templateById(entry.templateId);
    final theme = themeById(entry.themeId);
    _suppressAutoSave = true;
    setState(() {
      _templateId = template.id;
      _themeId = theme.id;
      _fullNameController.text = entry.profile.fullName;
      _headlineController.text = entry.profile.headline;
      _githubController.text = githubUsername(entry.profile.github);
      _linkedinController.text = linkedinUsername(entry.profile.linkedin);
      _websiteController.text = entry.profile.website;
      _summaryController.text = entry.profile.summary;
      _educationController.text = entry.profile.education;
      _skillsController.text = entry.profile.skills;
      _experienceController.text = entry.profile.experience;
      _projectsController.text = entry.profile.projects;
      _languagesController.text = entry.profile.languages;
      _certificatesController.text = entry.profile.certificates;
      _repos = List<GithubRepo>.from(entry.repos);
    });
    _suppressAutoSave = false;
    _showSnack('${entry.title} CV\'ye yüklendi.');
    final saved = await _save(feedback: false, silent: true);
    if (!saved) _scheduleAutoSave();
  }

  Future<void> _deleteHistory(CvHistoryEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161B22),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: Colors.white12),
        ),
        title: const Text(
          'CV sürümünü sil',
          style: TextStyle(color: Colors.white, fontSize: 16),
        ),
        content: Text(
          '"${entry.title}" sürümü hesabından ve bu cihazdan silinecek. Emin misin?',
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 13,
            height: 1.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Sil',
              style: TextStyle(color: Color(0xFFF87171)),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final ok = await _syncStore.deleteHistory(entry.id);
    if (!mounted) return;
    setState(() => _history.removeWhere((item) => item.id == entry.id));
    _showSnack(
      ok
          ? 'CV sürümü silindi.'
          : 'Sürüm bu cihazdan silindi; bulut bağlantısı kurulamadı.',
      isError: !ok,
    );
  }

  String _formatDate(DateTime date) {
    final local = date.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(local.day)}.${two(local.month)}.${local.year} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  Widget _buildContentCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'CV içeriği',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Text(
                'Örnek ikonuna dokun',
                style: TextStyle(
                  color: _theme.accent.withValues(alpha: 0.8),
                  fontSize: 10,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _cvField(
            label: 'Profil özeti',
            controller: _summaryController,
            icon: Icons.notes_outlined,
            hint: 'Kendini 2-3 cümleyle özetle.',
            example: _template.summary,
            minLines: 4,
            maxLines: 8,
          ),
          _cvField(
            label: 'Eğitim',
            controller: _educationController,
            icon: Icons.school_outlined,
            hint: 'Okul — Bölüm',
            example: 'Gazi Üniversitesi — Bilgisayar Mühendisliği',
            minLines: 1,
            maxLines: 3,
          ),
          _cvField(
            label: 'Yetenekler',
            controller: _skillsController,
            icon: Icons.build_outlined,
            hint: 'Virgülle ayır: C, Kotlin, React...',
            example: _template.skills,
            minLines: 2,
            maxLines: 4,
          ),
          _cvField(
            label: 'Deneyim',
            controller: _experienceController,
            icon: Icons.work_outline,
            hint: 'Pozisyon — Şirket (yıl)\\n• Başarı',
            example: _template.experience,
            minLines: 4,
            maxLines: 8,
          ),
          _cvField(
            label: 'Projeler',
            controller: _projectsController,
            icon: Icons.folder_outlined,
            hint: 'Proje adı — Teknolojiler\\nKısa açıklama',
            example: _template.projects,
            minLines: 3,
            maxLines: 7,
          ),
          _cvField(
            label: 'Diller',
            controller: _languagesController,
            icon: Icons.language,
            hint: 'Türkçe (Ana Dil), İngilizce (B2)',
            example: 'Türkçe (Ana Dil), İngilizce (B2)',
          ),
          _cvField(
            label: 'Sertifikalar',
            controller: _certificatesController,
            icon: Icons.workspace_premium_outlined,
            hint: 'Sertifika adı — Kurum (yıl)',
            example: _template.certificates,
            minLines: 1,
            maxLines: 3,
          ),
        ],
      ),
    );
  }

  Widget _cvField({
    required String label,
    required TextEditingController controller,
    required IconData icon,
    String? hint,
    String? example,
    int minLines = 1,
    int maxLines = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: Colors.grey, size: 15),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (example != null && example.trim().isNotEmpty)
                InkWell(
                  onTap: () => _applyExample(label, controller, example),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.auto_fix_high,
                          size: 13,
                          color: _theme.accent,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Örnek',
                          style: TextStyle(
                            color: _theme.accent,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          TextField(
            controller: controller,
            minLines: minLines,
            maxLines: maxLines,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              height: 1.45,
            ),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(color: Colors.grey, fontSize: 12),
              filled: true,
              fillColor: const Color(0xFF0D1117),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 12,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: _theme.accent.withValues(alpha: 0.6),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActions() {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _isSaving ? null : _saveAndAnalyze,
            icon: const Icon(Icons.fact_check_outlined, color: Colors.black),
            label: Text(
              _isSaving ? 'Kaydediliyor...' : 'ATS Uygunluğunu İncele',
              style: const TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              disabledBackgroundColor: Colors.white70,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _isSaving ? null : _showPreviewSheet,
                icon: const Icon(Icons.visibility_outlined, size: 18),
                label: const Text('CV Önizle'),
                style: _outlinedButtonStyle(),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _isSaving ? null : () => _save(),
                icon: const Icon(Icons.save_outlined, size: 18),
                label: const Text('Kaydet'),
                style: _outlinedButtonStyle(),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          'CV alanları cihazında ve hesabında saklanır; istediğin zaman düzenleyebilirsin.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.grey.withValues(alpha: 0.65),
            fontSize: 10.5,
            height: 1.35,
          ),
        ),
      ],
    );
  }

  ButtonStyle _outlinedButtonStyle() {
    return OutlinedButton.styleFrom(
      foregroundColor: Colors.white,
      side: const BorderSide(color: Colors.white24),
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
    );
  }

  BoxDecoration _cardDecoration() {
    return BoxDecoration(
      color: const Color(0xFF161B22),
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: Colors.white12),
    );
  }

  // ---------------------------------------------------------------- önizleme

  Future<void> _showPreviewSheet() async {
    final profile = _currentProfile();
    final text = buildCvPlainText(profile, repos: _repos);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return Container(
          height: MediaQuery.of(sheetContext).size.height * 0.9,
          decoration: const BoxDecoration(
            color: Color(0xFF0D1117),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              _sheetGrabber(),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 12, 8),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'CV Önizleme',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(sheetContext),
                      icon: const Icon(Icons.close, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                  child: _buildPreviewCard(profile),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: text));
                      if (!sheetContext.mounted) return;
                      Navigator.pop(sheetContext);
                      _showSnack('CV metni panoya kopyalandı.');
                    },
                    icon: const Icon(Icons.copy_rounded, size: 18),
                    label: const Text(
                      'ATS metni olarak kopyala',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _theme.accent,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _sheetGrabber() {
    return Container(
      width: 42,
      height: 4,
      margin: const EdgeInsets.only(top: 10),
      decoration: BoxDecoration(
        color: Colors.white24,
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }

  Widget _buildPreviewCard(CvProfile profile) {
    final accent = _theme.accent;
    final contact = [profile.github, profile.linkedin, profile.website]
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .join('  ·  ');

    final sections = <Widget>[];
    void addSection(String title, String body) {
      if (body.trim().isNotEmpty) {
        sections.add(_previewSection(title, body));
      }
    }

    addSection('PROFİL ÖZETİ', profile.summary);
    addSection('EĞİTİM', profile.education);
    addSection('YETENEKLER', profile.skills);
    addSection('DENEYİM', profile.experience);
    addSection('PROJELER', profile.projects);
    if (_repos.isNotEmpty) {
      addSection(
        'GITHUB PROJELERİ',
        _repos
            .map((repo) => '${formatRepoName(repo.name)} — ${repo.language}'
                '${repo.stars > 0 ? ' · ★ ${repo.stars}' : ''}\n'
                '${repo.description.trim()}')
            .join('\n\n'),
      );
    }
    addSection('DİLLER', profile.languages);
    addSection('SERTİFİKALAR', profile.certificates);

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  accent.withValues(alpha: 0.22),
                  const Color(0xFF161B22),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  profile.fullName.isEmpty
                      ? 'AD SOYAD'
                      : profile.fullName.toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 21,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                    height: 1.15,
                  ),
                ),
                if (profile.headline.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    profile.headline,
                    style: TextStyle(
                      color: accent,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                    ),
                  ),
                ],
                if (contact.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    contact,
                    style: const TextStyle(
                      color: Colors.white60,
                      fontSize: 11,
                      height: 1.35,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: sections.isEmpty
                  ? const [
                      Text(
                        'CV alanları doldukça önizleme burada görünür.',
                        style: TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                    ]
                  : sections,
            ),
          ),
        ],
      ),
    );
  }

  Widget _previewSection(String title, String body) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: _theme.accent,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            body.trim(),
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12.5,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  // --------------------------------------------------------------- ATS raporu

  Future<void> _showAtsSheet(AtsReport report) async {
    final scoreColor = report.score >= 85
        ? const Color(0xFF34D399)
        : report.score >= 65
            ? const Color(0xFFFBBF24)
            : const Color(0xFFF87171);
    final profile = _currentProfile();
    final text = buildCvPlainText(profile, repos: _repos);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return Container(
          height: MediaQuery.of(sheetContext).size.height * 0.9,
          decoration: const BoxDecoration(
            color: Color(0xFF0D1117),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              _sheetGrabber(),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 12, 8),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'ATS Uygunluk Raporu',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(sheetContext),
                      icon: const Icon(Icons.close, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildScoreCard(report, scoreColor),
                      const SizedBox(height: 20),
                      _sectionLabel('KONTROLLER'),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: _cardDecoration(),
                        child: Column(
                          children: [
                            for (var i = 0;
                                i < report.criteria.length;
                                i++) ...[
                              _criterionRow(report.criteria[i]),
                              if (i != report.criteria.length - 1)
                                const Divider(
                                  color: Colors.white12,
                                  height: 18,
                                ),
                            ],
                          ],
                        ),
                      ),
                      if (report.missingKeywords.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        _sectionLabel('EKSİK ANAHTAR KELİMELER'),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: report.missingKeywords
                              .take(10)
                              .map(
                                (keyword) => Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF87171)
                                        .withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: const Color(0xFFF87171)
                                          .withValues(alpha: 0.3),
                                    ),
                                  ),
                                  child: Text(
                                    keyword,
                                    style: const TextStyle(
                                      color: Color(0xFFFCA5A5),
                                      fontSize: 10.5,
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      ],
                      const SizedBox(height: 20),
                      _sectionLabel('ÖNERİLER'),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: _cardDecoration(),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (final suggestion in report.suggestions)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 9),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(
                                      Icons.arrow_right_rounded,
                                      size: 17,
                                      color: report.failedCriteria.isEmpty
                                          ? const Color(0xFF34D399)
                                          : const Color(0xFFFBBF24),
                                    ),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Text(
                                        suggestion,
                                        style: const TextStyle(
                                          color: Colors.white70,
                                          fontSize: 12,
                                          height: 1.45,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(sheetContext),
                        style: _outlinedButtonStyle(),
                        child: const Text('Kapat'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          await Clipboard.setData(ClipboardData(text: text));
                          if (!sheetContext.mounted) return;
                          Navigator.pop(sheetContext);
                          _showSnack('CV metni panoya kopyalandı.');
                        },
                        icon: const Icon(Icons.copy_rounded, size: 17),
                        label: const Text(
                          'Kopyala',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: scoreColor,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildScoreCard(AtsReport report, Color scoreColor) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scoreColor.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 96,
            height: 96,
            child: Stack(
              fit: StackFit.expand,
              children: [
                CircularProgressIndicator(
                  value: report.score / 100,
                  strokeWidth: 8,
                  backgroundColor: Colors.white12,
                  color: scoreColor,
                  strokeCap: StrokeCap.round,
                ),
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${report.score}',
                        style: TextStyle(
                          color: scoreColor,
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                          height: 1,
                        ),
                      ),
                      const Text(
                        '/ 100',
                        style: TextStyle(color: Colors.grey, fontSize: 9),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  report.verdict,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${report.passedCriteria.length}/${report.criteria.length} kontrol geçti',
                  style: const TextStyle(color: Colors.grey, fontSize: 11.5),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Puan, ATS kontrollerinin ağırlıklı toplamıdır.',
                  style: TextStyle(
                    color: Color(0xFF6B7280),
                    fontSize: 10,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _criterionRow(AtsCriterion criterion) {
    final color =
        criterion.passed ? const Color(0xFF34D399) : const Color(0xFFF87171);
    return Row(
      children: [
        Icon(
          criterion.passed ? Icons.check_circle_outline : Icons.cancel_outlined,
          color: color,
          size: 18,
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            criterion.label,
            style: TextStyle(
              color: criterion.passed ? Colors.white70 : Colors.white,
              fontSize: 12,
              height: 1.35,
            ),
          ),
        ),
        Text(
          '${criterion.weight} p',
          style: TextStyle(
            color: criterion.passed ? Colors.grey : color,
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _sectionLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        color: Colors.grey,
        fontSize: 10,
        letterSpacing: 1.4,
        fontWeight: FontWeight.bold,
      ),
    );
  }
}

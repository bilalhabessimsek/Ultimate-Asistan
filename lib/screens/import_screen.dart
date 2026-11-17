import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/file_io.dart';
import '../services/import_parser.dart';
import '../services/local_music.dart';
import '../services/music_library.dart';
import '../services/player_controller.dart';
import '../services/playlist_store.dart';

/// İçe aktarma kaynağı.
enum _ImportSource { file, url, text }

/// Tasarım: "İçe Aktar (Import)" ekranı.
///
/// TXT/CSV/M3U dosyası, bağlantı (URL) veya düz metinden şarkı adlarını
/// okuyup arşivle eşleştirir; seçilen çalma listesine ya da doğrudan çalma
/// sırasına ekler.
class ImportScreen extends StatefulWidget {
  const ImportScreen({super.key});

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  // Tasarım renkleri (i_e_aktar_import_ekran).
  static const Color _bg = Color(0xFF0A0A0A);
  static const Color _surface = Color(0xFF121212);
  static const Color _card = Color(0xFF161616);
  static const Color _border = Color(0xFF262626);
  static const Color _subtle = Color(0xFF8E8E8E);

  final PlaylistStore _store = PlaylistStore.instance;
  final MusicLibrary _library = MusicLibrary.instance;
  final FileIo _fileIo = FileIo();

  final TextEditingController _urlController = TextEditingController();
  final TextEditingController _textController = TextEditingController();
  final TextEditingController _newListController = TextEditingController();

  _ImportSource _source = _ImportSource.file;
  String _content = '';
  String _fileName = '';
  bool _loadingUrl = false;

  String _target = PlaylistStore.reservedQueue;
  List<ImportEntry> _entries = const [];

  @override
  void initState() {
    super.initState();
    _store.load();
    _library.ensureLoaded();
    _library.addListener(_onLibraryChanged);
  }

  @override
  void dispose() {
    _library.removeListener(_onLibraryChanged);
    _urlController.dispose();
    _textController.dispose();
    _newListController.dispose();
    super.dispose();
  }

  void _onLibraryChanged() {
    if (_content.isNotEmpty) _recompute();
    if (mounted) setState(() {});
  }

  SongMatcher? _matcher;
  int _matcherSongCount = -1;

  SongMatcher _ensureMatcher() {
    final songs = _library.songs;
    final cached = _matcher;
    if (cached != null && _matcherSongCount == songs.length) return cached;
    final built = SongMatcher(songs);
    _matcher = built;
    _matcherSongCount = songs.length;
    return built;
  }

  void _recompute() {
    if (_content.isEmpty) {
      _entries = const [];
      return;
    }
    _entries = _ensureMatcher().matchAll(ImportParser.extractNames(_content));
  }

  void _setContent(String content, {String? name}) {
    setState(() {
      _content = content;
      if (name != null) _fileName = name;
      _recompute();
    });
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: const Color(0xFF1F1F24),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
  }

  // -------------------------------------------------------------- seçimler

  Future<void> _pickFile() async {
    final picked = await _fileIo.pickTextFile();
    if (picked == null) {
      _snack('Dosya seçilmedi.');
      return;
    }
    _setContent(picked.content, name: picked.name);
    _snack(
      picked.truncated
          ? '${picked.name} (ilk 15 MB) yüklendi.'
          : '${picked.name} yüklendi.',
    );
  }

  Future<void> _fetchUrl() async {
    final raw = _urlController.text.trim();
    final uri = Uri.tryParse(raw);
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
      _snack('Geçerli bir http/https bağlantısı girin.');
      return;
    }
    setState(() => _loadingUrl = true);
    HttpClient? client;
    try {
      client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
      final request = await client.getUrl(uri);
      request.headers.set(HttpHeaders.userAgentHeader, 'UltimateAsistan/1.0');
      final response = await request.close().timeout(
            const Duration(seconds: 25),
          );
      if (response.statusCode != 200) {
        _snack('Sunucu hatası: ${response.statusCode}');
        return;
      }
      final bytes = await response.fold<List<int>>(
        <int>[],
        (prev, chunk) => prev..addAll(chunk),
      );
      final body = utf8.decode(bytes, allowMalformed: true);
      if (!mounted) return;
      _setContent(
        body,
        name: uri.pathSegments.isNotEmpty ? uri.pathSegments.last : raw,
      );
      _snack('${_entries.length} satır alındı.');
    } catch (e) {
      _snack('Bağlantı alınamadı: $e');
    } finally {
      client?.close(force: true);
      if (mounted) setState(() => _loadingUrl = false);
    }
  }

  // ------------------------------------------------------------ içe aktar

  Future<void> _doImport() async {
    final matched = <int, SongInfo>{};
    for (final e in _entries) {
      final song = e.song;
      if (song != null) matched[song.id] = song;
    }
    final songs = matched.values.toList();
    if (songs.isEmpty) {
      _snack('Eşleşen şarkı bulunamadı.');
      return;
    }
    final ids = songs.map((s) => s.id).toList();

    if (_target == PlaylistStore.reservedQueue) {
      final added = PlayerController.instance.enqueueAll(songs);
      _snack(
        added == songs.length
            ? '${songs.length} şarkı çalma sırasına eklendi.'
            : '$added şarkı eklendi (${songs.length - added} zaten sıradaydı).',
      );
    } else if (_target == PlaylistStore.reservedNew) {
      final name = _newListController.text.trim();
      if (name.isEmpty) {
        _snack('Yeni liste adı girin.');
        return;
      }
      if (!_store.has(name) && !_store.canCreate(name)) {
        _snack('Bu ad kullanılamaz.');
        return;
      }
      if (!_store.has(name)) await _store.create(name);
      final added = await _store.addAll(name, ids);
      _snack('"$name" listesine $added şarkı eklendi.');
    } else {
      if (!_store.has(_target)) {
        _snack('Hedef liste bulunamadı.');
        return;
      }
      final added = await _store.addAll(_target, ids);
      _snack(
        added == 0
            ? 'Tümü "$_target" listesinde zaten vardı.'
            : '$added şarkı "$_target" listesine eklendi.',
      );
    }
    if (mounted) Navigator.of(context).pop(true);
  }

  // --------------------------------------------------------------- arayüz

  @override
  Widget build(BuildContext context) {
    final matchedCount = _entries.where((e) => e.matched).length;
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              _buildHeader(),
              const SizedBox(height: 16),
              Expanded(
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    _buildTabs(),
                    const SizedBox(height: 16),
                    _buildSourceInput(),
                    const SizedBox(height: 16),
                    _buildTargetPicker(),
                    const SizedBox(height: 16),
                    _buildPreview(matchedCount),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _buildFooter(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: _surface,
            shape: BoxShape.circle,
            border: Border.all(color: _border),
          ),
          child: IconButton(
            padding: EdgeInsets.zero,
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(
              Icons.chevron_left,
              size: 20,
              color: Color(0xFFD4D4D8),
            ),
            tooltip: 'Geri',
          ),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'İçe Aktar (Import)',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.2,
                ),
              ),
              SizedBox(height: 2),
              Text(
                'TXT dosyası, link veya metin ile şarkı ekleyin',
                style: TextStyle(color: _subtle, fontSize: 12),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: _surface,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: _border),
          ),
          child: const Text(
            'v1.2',
            style: TextStyle(
              color: _subtle,
              fontSize: 11,
              fontFamily: 'monospace',
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTabs() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _border),
      ),
      child: Row(
        children: [
          _tab(_ImportSource.file, Icons.description_outlined, 'TXT Dosyası'),
          _tab(_ImportSource.url, Icons.link, 'URL / Link'),
          _tab(_ImportSource.text, Icons.notes, 'Düz Metin'),
        ],
      ),
    );
  }

  Widget _tab(_ImportSource value, IconData icon, String label) {
    final active = _source == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _source = value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: active ? const Color(0xFF262626) : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 14,
                color: active ? const Color(0xFFD4D4D8) : _subtle,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: active ? Colors.white : _subtle,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSourceInput() {
    switch (_source) {
      case _ImportSource.file:
        return GestureDetector(
          onTap: _pickFile,
          child: CustomPaint(
            painter: const _DashedBorderPainter(color: _border, radius: 16),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 16),
              decoration: BoxDecoration(
                color: const Color(0x80121212),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: _card,
                      shape: BoxShape.circle,
                      border: Border.all(color: _border),
                    ),
                    child: const Icon(
                      Icons.cloud_upload_outlined,
                      size: 24,
                      color: Color(0xFFD4D4D8),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'TXT veya Liste Dosyasını Seçin',
                    style: TextStyle(
                      color: Color(0xFFE5E5E5),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'cihazınızdan seçmek için dokunun',
                    style: TextStyle(color: _subtle, fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: _card,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: _border),
                    ),
                    child: const Text(
                      '.txt, .csv, .m3u (Maks. 15MB)',
                      style: TextStyle(
                        color: _subtle,
                        fontSize: 11,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                  if (_fileName.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      'Seçilen: $_fileName',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF34D399),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );

      case _ImportSource.url:
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Bağlantı (m3u / txt)',
                style: TextStyle(
                  color: Color(0xFFD4D4D8),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: _plainField(_urlController, 'https://...')),
                  const SizedBox(width: 8),
                  SizedBox(
                    height: 40,
                    child: ElevatedButton(
                      onPressed: _loadingUrl ? null : _fetchUrl,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: _loadingUrl
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.black,
                              ),
                            )
                          : const Text(
                              'Getir',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
              if (_fileName.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  'Kaynak: $_fileName',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: _subtle, fontSize: 11),
                ),
              ],
            ],
          ),
        );

      case _ImportSource.text:
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Şarkı adlarını yapıştırın (her satıra bir şarkı)',
                style: TextStyle(
                  color: Color(0xFFD4D4D8),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _textController,
                onChanged: (v) => _setContent(v),
                maxLines: 7,
                minLines: 5,
                style: const TextStyle(
                  color: Color(0xFFE5E5E5),
                  fontSize: 13,
                  fontFamily: 'monospace',
                ),
                decoration: InputDecoration(
                  hintText: 'Örn:\nA Cruel Angel\'s Thesis\nZoltraak\n...',
                  hintStyle: const TextStyle(color: _subtle, fontSize: 12),
                  filled: true,
                  fillColor: _surface,
                  contentPadding: const EdgeInsets.all(12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: _border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: _border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Color(0xFF525252)),
                  ),
                ),
              ),
            ],
          ),
        );
    }
  }

  Widget _plainField(TextEditingController controller, String hint) {
    return TextField(
      controller: controller,
      style: const TextStyle(color: Color(0xFFE5E5E5), fontSize: 12),
      decoration: InputDecoration(
        isDense: true,
        hintText: hint,
        hintStyle: const TextStyle(color: _subtle, fontSize: 12),
        filled: true,
        fillColor: _surface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _border),
        ),
      ),
    );
  }

  Widget _buildTargetPicker() {
    final names = _store.names;
    final items = <DropdownMenuItem<String>>[
      const DropdownMenuItem(
        value: PlaylistStore.reservedQueue,
        child: Text('Doğrudan Çalma Sırasına (Queue) Ekle'),
      ),
      const DropdownMenuItem(
        value: PlaylistStore.reservedNew,
        child: Text('+ Yeni Liste Oluşturarak Aktar...'),
      ),
      for (final n in names)
        DropdownMenuItem(
          value: n,
          child: Text('$n (${_store.countOf(n)} şarkı)'),
        ),
    ];

    final validValue = items.any((e) => e.value == _target)
        ? _target
        : PlaylistStore.reservedQueue;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Hedef Çalma Listesi',
                style: TextStyle(
                  color: Color(0xFFD4D4D8),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                'Nereye eklensin?',
                style: TextStyle(color: _subtle, fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _border),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: validValue,
                isExpanded: true,
                dropdownColor: _card,
                icon: const Icon(
                  Icons.expand_more,
                  size: 18,
                  color: _subtle,
                ),
                style: const TextStyle(
                  color: Color(0xFFE5E5E5),
                  fontSize: 12,
                ),
                items: items,
                onChanged: (v) {
                  if (v != null) setState(() => _target = v);
                },
              ),
            ),
          ),
          if (validValue == PlaylistStore.reservedNew) ...[
            const SizedBox(height: 10),
            _plainField(_newListController, 'Yeni liste adı...'),
          ],
        ],
      ),
    );
  }

  Widget _buildPreview(int matchedCount) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Color(0xFF10B981),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'İçerik Önizleme',
                    style: TextStyle(
                      color: Color(0xFFD4D4D8),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              Text(
                _entries.isEmpty
                    ? 'içerik bekleniyor'
                    : '${_entries.length} şarkı algılandı · $matchedCount eşleşti',
                style: const TextStyle(color: _subtle, fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            constraints: const BoxConstraints(minHeight: 120, maxHeight: 260),
            decoration: BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xB3262626)),
            ),
            child: _entries.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'Henüz içerik yok. Dosya seçin, bağlantı getirin veya\nmetin yapıştırın.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: _subtle, fontSize: 12),
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(10),
                    itemCount: _entries.length,
                    itemBuilder: (context, i) {
                      final e = _entries[i];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${i + 1}. ${e.raw}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Color(0xFFD4D4D8),
                                  fontSize: 12,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              e.matched ? 'Hazır' : 'Bulunamadı',
                              style: TextStyle(
                                color: e.matched
                                    ? const Color(0xFF34D399)
                                    : const Color(0xFF71717A),
                                fontSize: 10,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    final matched = _entries.where((e) => e.matched).length;
    final enabled = matched > 0;
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: enabled ? _doImport : null,
        icon: const Icon(Icons.file_upload_outlined, size: 18),
        label: Text(
          '$matched Şarkıyı İçe Aktar ve Kaydet',
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          disabledBackgroundColor: const Color(0xFF262626),
          disabledForegroundColor: const Color(0xFF6B6B6B),
          padding: const EdgeInsets.symmetric(vertical: 15),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }
}

/// Kesikli (dashed) yuvarlatılmış çerçeve — sürükle-bırak kutusu görünümü.
class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter({required this.color, this.radius = 16});

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    final path = Path()..addRRect(rrect);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    const dash = 6.0;
    const gap = 5.0;
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = math.min(distance + dash, metric.length);
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance = next + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter old) =>
      old.color != color || old.radius != radius;
}

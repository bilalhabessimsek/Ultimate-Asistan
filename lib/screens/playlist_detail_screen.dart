import 'package:flutter/material.dart';

import '../services/file_io.dart';
import '../services/local_music.dart';
import '../services/music_library.dart';
import '../services/player_controller.dart';
import '../services/playlist_store.dart';
import '../utils/music_format.dart';
import 'import_screen.dart';
import 'player_screen.dart';

/// Tasarım: "Liste Detay ve Şarkı Ekleme" ekranı.
///
/// Kütüphanedeki (arşiv) tüm şarkıları listeler; her satırdaki düğme ile
/// şarkıyı açık olan çalma listesine ekler/çıkarır.
class PlaylistDetailScreen extends StatefulWidget {
  const PlaylistDetailScreen({super.key, required this.playlistName});

  final String playlistName;

  @override
  State<PlaylistDetailScreen> createState() => _PlaylistDetailScreenState();
}

class _PlaylistDetailScreenState extends State<PlaylistDetailScreen> {
  // Tasarım renkleri (liste_detay_ve_ark_ekleme_ekran).
  static const Color _bg = Color(0xFF09090B);
  static const Color _card = Color(0xFF111113);
  static const Color _border = Color(0xFF1C1C1F);
  static const Color _muted = Color(0xFF8A8A93);
  static const Color _accent = Color(0xFF242429);

  final PlaylistStore _store = PlaylistStore.instance;
  final MusicLibrary _library = MusicLibrary.instance;
  final FileIo _fileIo = FileIo();
  final TextEditingController _searchController = TextEditingController();

  String _query = '';

  @override
  void initState() {
    super.initState();
    _store.load();
    _library.ensureLoaded();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<SongInfo> get _visibleSongs {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _library.songs;
    return _library.songs
        .where(
          (s) =>
              s.title.toLowerCase().contains(q) ||
              s.artist.toLowerCase().contains(q),
        )
        .toList();
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
          duration: const Duration(seconds: 2),
        ),
      );
  }

  Future<void> _toggle(SongInfo song) async {
    final added = await _store.toggle(widget.playlistName, song.id);
    _snack(added ? 'Eklendi: ${song.title}' : 'Çıkarıldı: ${song.title}');
  }

  Future<void> _addAll() async {
    final songs = _visibleSongs;
    if (songs.isEmpty) {
      _snack('Eklenecek şarkı yok.');
      return;
    }
    final added = await _store.addAll(
      widget.playlistName,
      songs.map((s) => s.id),
    );
    _snack(
      added == 0
          ? 'Tümü listede zaten vardı.'
          : '$added şarkı listeye eklendi.',
    );
  }

  /// Çalma listesini (ana player'ın birebir aynısı olan) tam ekran
  /// oynatıcıda açar. O ekrandaki **+** düğmesiyle listeye şarkı
  /// eklenip çıkarılabilir.
  Future<void> _playPlaylist() async {
    final songs = _library.songsForIds(_store.idsOf(widget.playlistName));
    if (songs.isEmpty) {
      _snack(
        _store.countOf(widget.playlistName) == 0
            ? 'Bu liste boş. Önce şarkı ekleyin.'
            : 'Listedeki şarkılar kütüphanede bulunamadı.',
      );
      return;
    }
    debugPrint('OYNAT[detay]: "${widget.playlistName}" (${songs.length})');
    try {
      await PlayerController.instance
          .setQueue(songs)
          .timeout(const Duration(seconds: 10));
      debugPrint('OYNAT[detay]: setQueue tamam');
    } catch (err, st) {
      debugPrint('OYNAT[detay]: setQueue HATASI $err\n$st');
    }
    if (!mounted) return;
    await _openPlayerScreen();
  }

  Future<void> _openPlayerScreen() {
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlayerScreen(playlistName: widget.playlistName),
      ),
    );
  }

  // ------------------------------------------------------- liste indir/sil

  /// Listeyi M3U8 olarak kaydeder (diğer uygulamalar açabilir).
  Future<void> _exportPlaylist() async {
    final songs = _library.songsForIds(_store.idsOf(widget.playlistName));
    if (songs.isEmpty) {
      _snack('Bu liste boş.');
      return;
    }
    final buffer = StringBuffer()..writeln('#EXTM3U');
    for (final s in songs) {
      buffer.writeln('#EXTINF:-1,${s.title}');
      buffer.writeln(s.uri);
    }
    final saved = await _fileIo.saveTextFile(
      name: '${MusicFormat.safeFileName(widget.playlistName)}.m3u8',
      content: buffer.toString(),
      mime: 'audio/x-mpegurl',
    );
    if (!mounted) return;
    _snack(saved == null ? 'Kaydetme iptal edildi.' : 'Kaydedildi: $saved');
  }

  Future<void> _deletePlaylist() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _card,
        title: const Text('Listeyi sil', style: TextStyle(color: Colors.white)),
        content: Text(
          '"${widget.playlistName}" listesi silinsin mi?',
          style: const TextStyle(color: _muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç', style: TextStyle(color: _muted)),
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
    if (ok != true || !mounted) return;
    await _store.delete(widget.playlistName);
    if (!mounted) return;
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: AnimatedBuilder(
          animation: Listenable.merge([_store, _library]),
          builder: (context, _) {
            final songs = _visibleSongs;
            final total = _store.countOf(widget.playlistName);
            return Column(
              children: [
                _buildHeader(total),
                Expanded(child: _buildPanel(songs)),
                _buildFooter(songs.length),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildHeader(int total) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                onPressed: () => Navigator.of(context).maybePop(),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                icon: const Icon(Icons.chevron_left, color: Color(0xFFD4D4D8)),
                tooltip: 'Geri',
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  widget.playlistName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
              IconButton(
                onPressed: _exportPlaylist,
                tooltip: 'Listeyi indir (M3U8)',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                icon: const Icon(
                  Icons.file_download_outlined,
                  size: 17,
                  color: _muted,
                ),
              ),
              IconButton(
                onPressed: _deletePlaylist,
                tooltip: 'Listeyi sil',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                icon: const Icon(
                  Icons.delete_outline,
                  size: 17,
                  color: _muted,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                '$total şarkı',
                style: const TextStyle(color: _muted, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Padding(
            padding: EdgeInsets.only(left: 4),
            child: Text(
              'Bu listeye kütüphanenden şarkı ekle veya çıkar.',
              style: TextStyle(color: _muted, fontSize: 12),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 38,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: _card,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _border),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.search, size: 16, color: _muted),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          onChanged: (v) => setState(() => _query = v),
                          style: const TextStyle(
                            color: Color(0xFFE4E4E7),
                            fontSize: 13,
                          ),
                          decoration: const InputDecoration(
                            isDense: true,
                            border: InputBorder.none,
                            hintText: 'Kütüphanede ara...',
                            hintStyle: TextStyle(color: _muted, fontSize: 13),
                          ),
                        ),
                      ),
                      if (_query.isNotEmpty)
                        GestureDetector(
                          onTap: () {
                            _searchController.clear();
                            setState(() => _query = '');
                          },
                          child: const Icon(
                            Icons.close,
                            size: 16,
                            color: _muted,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Material(
                color: const Color(0xFFF4F4F5),
                borderRadius: BorderRadius.circular(10),
                child: InkWell(
                  onTap: _playPlaylist,
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    height: 38,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.play_arrow_rounded,
                          size: 18,
                          color: Colors.black,
                        ),
                        SizedBox(width: 4),
                        Text(
                          'Çal',
                          style: TextStyle(
                            color: Colors.black,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Material(
                color: _accent,
                borderRadius: BorderRadius.circular(10),
                child: InkWell(
                  onTap: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const ImportScreen(),
                      ),
                    );
                  },
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    height: 38,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _border),
                    ),
                    child: const Row(
                      children: [
                        Icon(
                          Icons.file_upload_outlined,
                          size: 15,
                          color: Color(0xFFD4D4D8),
                        ),
                        SizedBox(width: 6),
                        Text(
                          'İçe Aktar',
                          style: TextStyle(
                            color: Color(0xFFD4D4D8),
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPanel(List<SongInfo> songs) {
    if (_library.loading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }
    if (songs.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _library.hasPermission
                ? 'Eşleşen şarkı bulunamadı.'
                : 'Müzik dosyalarını okumak için depolama izni gerekiyor.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: _muted, fontSize: 13),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      child: Container(
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _border),
        ),
        child: ListView.builder(
          padding: const EdgeInsets.all(10),
          itemCount: songs.length,
          itemBuilder: (context, index) => _songRow(songs[index]),
        ),
      ),
    );
  }

  Widget _songRow(SongInfo song) {
    final added = _store.contains(widget.playlistName, song.id);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: () => _toggle(song),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () async {
                        await PlayerController.instance.setQueue(
                          _visibleSongs,
                          startAt: _visibleSongs.indexOf(song),
                        );
                        if (!mounted) return;
                        await _openPlayerScreen();
                      },
                      child: const Padding(
                        padding: EdgeInsets.only(right: 10),
                        child: Icon(
                          Icons.music_note,
                          size: 16,
                          color: Color(0xFFA1A1AA),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        song.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFFE4E4E7),
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => _toggle(song),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color:
                    added ? const Color(0x1AF43F5E) : const Color(0xFFE4E4E7),
                borderRadius: BorderRadius.circular(999),
                border:
                    added ? Border.all(color: const Color(0x4DF43F5E)) : null,
              ),
              child: Text(
                added ? 'Çıkar' : 'Ekle',
                style: TextStyle(
                  color: added ? const Color(0xFFFB7185) : Colors.black,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(int listed) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFF18181B))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            '$listed şarkı listelendi',
            style: const TextStyle(color: Color(0xFFA1A1AA), fontSize: 12),
          ),
          InkWell(
            onTap: _addAll,
            borderRadius: BorderRadius.circular(6),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Text(
                'Tümünü Ekle',
                style: TextStyle(
                  color: Color(0xFFE4E4E7),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../services/file_io.dart';
import '../services/local_music.dart';
import '../services/music_library.dart';
import '../services/player_controller.dart';
import '../services/playlist_store.dart';
import 'import_screen.dart';
import 'player_screen.dart';

/// Tasarım: "Çalma Listelerim (İmport Destekli)" ekranı.
///
/// Kendi çalma listelerini oluşturur/yönetir, arşivi TXT olarak dışa aktarır,
/// içe aktarma ekranına ve liste detayına geçiş yapar.
class PlaylistsScreen extends StatefulWidget {
  const PlaylistsScreen({super.key});

  @override
  State<PlaylistsScreen> createState() => _PlaylistsScreenState();
}

class _PlaylistsScreenState extends State<PlaylistsScreen> {
  // Tasarım renkleri (alma_listelerim_import_destekli).
  static const Color _bg = Color(0xFF0E0E10);
  static const Color _card = Color(0xFF131316);
  static const Color _border = Color(0xFF232329);
  static const Color _subtle = Color(0xFF858591);

  final PlaylistStore _store = PlaylistStore.instance;
  final MusicLibrary _library = MusicLibrary.instance;
  final FileIo _fileIo = FileIo();
  final TextEditingController _nameController = TextEditingController();

  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    _store.load();
    _library.ensureLoaded().then((_) => _store.syncCloud());
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
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

  // ------------------------------------------------------------- oluştur

  Future<void> _createPlaylist() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      _snack('Liste adı boş olamaz.');
      return;
    }
    if (!_store.canCreate(name)) {
      _snack('Bu adda bir liste zaten var.');
      return;
    }
    await _store.create(name);
    _nameController.clear();
    if (mounted) FocusScope.of(context).unfocus();
    _snack('"$name" listesi oluşturuldu.');
  }

  // ------------------------------------------------------------ dışa aktar

  /// Listeleri masaüstü ("ULTİMATE") uygulamasıyla elle eşitler.
  Future<void> _syncNow() async {
    await _library.ensureLoaded();
    _snack('PC ile eşitleniyor...');
    await _store.syncCloud();
    if (!mounted) return;
    final err = _store.lastSyncError;
    _snack(err == null ? 'PC ile eşitlendi.' : 'Eşitlenemedi: $err');
  }

  Future<void> _exportArchive() async {
    if (_exporting) return;
    final songs = _library.songs;
    if (songs.isEmpty) {
      _snack('Arşivde şarkı yok.');
      return;
    }
    setState(() => _exporting = true);
    final buffer = StringBuffer()
      ..writeln('# Ultimate Asistan - Müzik Arşivi')
      ..writeln('# ${songs.length} şarkı');
    for (final s in songs) {
      buffer.writeln(s.title);
    }
    final saved = await _fileIo.saveTextFile(
      name: 'arsiv_sarkilar.txt',
      content: buffer.toString(),
      mime: 'text/plain',
    );
    if (!mounted) return;
    setState(() => _exporting = false);
    _snack(saved == null ? 'Kaydetme iptal edildi.' : 'Kaydedildi: $saved');
  }

  // ------------------------------------------------------------------ git

  Future<void> _openPlaylistPlayer(String name) async {
    final songs = _library.songsForIds(_store.idsOf(name));
    if (songs.isEmpty) {
      if (_store.countOf(name) == 0) {
        _snack('Bu liste boş. Önce şarkı ekleyin.');
      } else {
        _snack('Listedeki şarkılar kütüphanede bulunamadı.');
      }
      return;
    }
    try {
      await PlayerController.instance
          .setQueue(songs)
          .timeout(const Duration(seconds: 10));
    } catch (err, st) {
      debugPrint('PLAYLISTS->PLAY: $err\n$st');
    }
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlayerScreen(
          playlistName: name,
          openPlaylistEditor: false,
        ),
      ),
    );
  }

  Future<void> _openImport() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ImportScreen()),
    );
  }

  void _openDevicePlaylist(PlaylistInfo playlist) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: _card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _DevicePlaylistSheet(playlist: playlist),
    );
  }

  // --------------------------------------------------------------- arayüz

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: AnimatedBuilder(
          animation: Listenable.merge([_store, _library]),
          builder: (context, _) => ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
            children: [
              _buildHeader(),
              const SizedBox(height: 20),
              _buildCreateBar(),
              const SizedBox(height: 18),
              if (_store.isEmpty)
                _buildEmpty('Henüz liste oluşturulmadı.')
              else
                ..._buildPlaylistCards(),
              const SizedBox(height: 24),
              _buildDeviceSection(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            IconButton(
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.chevron_left, color: Colors.white),
              tooltip: 'Geri',
            ),
            const Expanded(
              child: Text(
                'Listelerim',
                style: TextStyle(
                  color: Color(0xFFF5F5F5),
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.3,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        const Padding(
          padding: EdgeInsets.only(left: 4),
          child: Text(
            'Şarkı kutularının yanındaki oklarla listeye ekleyip çıkarın, '
            'kartlara dokunarak listeyi düzenleyin.',
            style: TextStyle(color: _subtle, fontSize: 12, height: 1.4),
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: _actionButton(
                icon: Icons.file_download_outlined,
                label: 'TXT Çıkar',
                onTap: _exporting ? null : _exportArchive,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _actionButton(
                icon: Icons.file_upload_outlined,
                label: 'Aktar',
                onTap: _openImport,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _actionButton(
                icon: Icons.cloud_sync_outlined,
                label: _store.isSyncing ? 'Eşitleniyor' : 'Eşitle',
                onTap: _store.isSyncing ? null : _syncNow,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _buildSyncStatus(),
      ],
    );
  }

  /// Masaüstü (Supabase) senkron durumunu gösteren ince satır.
  Widget _buildSyncStatus() {
    final syncing = _store.isSyncing;
    final err = _store.lastSyncError;
    final Color color = syncing
        ? const Color(0xFF60A5FA)
        : (err == null ? const Color(0xFF4ADE80) : const Color(0xFFF87171));
    final String text = syncing
        ? 'PC (Supabase) ile eşitleniyor...'
        : (err == null
            ? 'Çalma listeleri PC ile ortak (Supabase) — elle eşitlemek için dokun.'
            : 'PC senkronu başarısız — internete bağlı olduğundan emin ol.');
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Row(
        children: [
          Icon(
            syncing
                ? Icons.sync
                : (err == null
                    ? Icons.cloud_done_outlined
                    : Icons.cloud_off_outlined),
            size: 14,
            color: color,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: color, fontSize: 11, height: 1.3),
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionButton({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
  }) {
    return Material(
      color: const Color(0xFF17171A),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            border: Border.all(color: _border),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 15, color: const Color(0xFFD4D4D8)),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFFD4D4D8),
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

  Widget _buildCreateBar() {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: _card,
        border: Border.all(color: _border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _nameController,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _createPlaylist(),
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: const InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: 'Yeni liste adı yazın...',
                hintStyle: TextStyle(color: _subtle, fontSize: 14),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Material(
            color: const Color(0xFF3F3F46),
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              onTap: _createPlaylist,
              borderRadius: BorderRadius.circular(8),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add, size: 15, color: Color(0xFFF4F4F5)),
                    SizedBox(width: 5),
                    Text(
                      'Oluştur',
                      style: TextStyle(
                        color: Color(0xFFF4F4F5),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildPlaylistCards() {
    final names = _store.names;
    return [
      LayoutBuilder(
        builder: (context, constraints) {
          final twoColumn = constraints.maxWidth >= 520;
          if (!twoColumn) {
            return Column(
              children: [
                for (final n in names) ...[
                  _playlistCard(n),
                  const SizedBox(height: 8),
                ],
              ],
            );
          }
          final rows = <Widget>[];
          for (var i = 0; i < names.length; i += 2) {
            final left = names[i];
            final right = i + 1 < names.length ? names[i + 1] : null;
            rows.add(
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _playlistCard(left)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: right == null
                          ? const SizedBox.shrink()
                          : _playlistCard(right),
                    ),
                  ],
                ),
              ),
            );
          }
          return Column(children: rows);
        },
      ),
    ];
  }

  Widget _playlistCard(String name) {
    final count = _store.countOf(name);
    return Material(
      color: _card,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: () => _openPlaylistPlayer(name),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            border: Border.all(color: _border),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFFF4F4F5),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '$count Şarkı',
                style: const TextStyle(
                  color: _subtle,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right, size: 18, color: _subtle),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDeviceSection() {
    final playlists = _library.devicePlaylists;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'DİĞER UYGULAMA LİSTELERİ',
          style: TextStyle(
            color: _subtle,
            fontSize: 11,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 10),
        if (playlists.isEmpty)
          _buildEmpty(
            'Cihazda başka uygulamaya ait çalma listesi bulunamadı.',
          )
        else
          for (final pl in playlists) ...[
            Material(
              color: _card,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                onTap: () => _openDevicePlaylist(pl),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(color: _border),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.queue_music,
                        size: 18,
                        color: Color(0xFFD4D4D8),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          pl.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFFF4F4F5),
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Text(
                        '${pl.count} Şarkı',
                        style: const TextStyle(color: _subtle, fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
      ],
    );
  }

  Widget _buildEmpty(String text) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _border),
        ),
        child: Text(
          text,
          style: const TextStyle(color: _subtle, fontSize: 13),
        ),
      );
}

/// Başka bir uygulamanın çalma listesini gösteren alt sayfa.
class _DevicePlaylistSheet extends StatelessWidget {
  const _DevicePlaylistSheet({required this.playlist});

  final PlaylistInfo playlist;

  static const Color _bg = Color(0xFF0E0E10);
  static const Color _border = Color(0xFF232329);
  static const Color _subtle = Color(0xFF858591);

  static final LocalMusicService _bridge = LocalMusicService();

  @override
  Widget build(BuildContext context) {
    final music = _bridge;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (context, scrollController) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    playlist.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, color: _subtle),
                ),
              ],
            ),
            const SizedBox(height: 6),
            FutureBuilder<List<SongInfo>>(
              future: music.queryPlaylistSongs(playlist.id),
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Padding(
                    padding: EdgeInsets.all(30),
                    child: Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    ),
                  );
                }
                final songs = snap.data ?? const <SongInfo>[];
                if (songs.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      'Bu listede şarkı bulunamadı.',
                      style: TextStyle(color: _subtle),
                    ),
                  );
                }
                return Expanded(
                  child: Column(
                    children: [
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            PlayerController.instance.enqueueAll(songs);
                            Navigator.pop(context);
                          },
                          icon: const Icon(Icons.playlist_add, size: 18),
                          label: Text('${songs.length} Şarkıyı Sıraya Ekle'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: ListView.builder(
                          controller: scrollController,
                          itemCount: songs.length,
                          itemBuilder: (context, i) {
                            final song = songs[i];
                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              decoration: BoxDecoration(
                                color: _bg,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: _border),
                              ),
                              child: ListTile(
                                dense: true,
                                onTap: () {
                                  PlayerController.instance.setQueue(
                                    songs,
                                    startAt: i,
                                  );
                                  Navigator.pop(context);
                                },
                                leading: const Icon(
                                  Icons.music_note,
                                  size: 18,
                                  color: Colors.white,
                                ),
                                title: Text(
                                  song.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                  ),
                                ),
                                subtitle: Text(
                                  song.artist,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: _subtle,
                                    fontSize: 11,
                                  ),
                                ),
                                trailing: const Icon(
                                  Icons.play_arrow_rounded,
                                  color: _subtle,
                                  size: 20,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

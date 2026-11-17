import 'package:flutter/material.dart';

import '../services/local_music.dart';
import '../services/music_library.dart';
import '../services/player_controller.dart';
import '../utils/music_format.dart';

/// Telefondaki tüm şarkıları (MediaStore) normal bir müzik çalar gibi
/// listeleyen "Kütüphane" ekranı.
///
/// Böylece müzik yalnızca çalma listelerinden değil, doğrudan telefondaki
/// her şarkıdan dinlenebilir: bir şarkıya dokununca tüm kütüphane çalma
/// sırasına alınır ve o şarkıdan itibaren çalar.
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  // Player ekranıyla aynı palet.
  static const Color _bg = Color(0xFF0B0B0E);
  static const Color _card = Color(0xFF131317);
  static const Color _border = Color(0xFF232327);
  static const Color _subtext = Color(0xFF76767C);

  final MusicLibrary _library = MusicLibrary.instance;
  final PlayerController _ctl = PlayerController.instance;
  final TextEditingController _search = TextEditingController();

  /// Bir kez oluşturulan birleşik dinleyici (her çizimde yeniden kurulmaz).
  late final Listenable _merged = Listenable.merge([_library, _ctl]);

  String _query = '';

  @override
  void initState() {
    super.initState();
    _library.ensureLoaded();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<SongInfo> get _filtered {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _library.songs;
    return _library.songs
        .where(
          (s) =>
              s.title.toLowerCase().contains(q) ||
              s.artist.toLowerCase().contains(q) ||
              (s.album ?? '').toLowerCase().contains(q),
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

  /// Tüm listeyi çalar ([shuffle] ise karışık sırada başlar).
  Future<void> _playAll(List<SongInfo> songs, {required bool shuffle}) async {
    if (songs.isEmpty) return;
    // Karışık durumunu kuyruğu kurmadan önce ayarla; setQueue yeni kuyruğa
    // gereken sırayı uygular.
    if (_ctl.shuffle != shuffle) _ctl.setShuffle(shuffle);
    await _ctl.setQueue(songs, startAt: 0);
    if (!mounted) return;
    _snack(
      shuffle
          ? '${songs.length} şarkı karışık çalınıyor.'
          : '${songs.length} şarkı çalınıyor.',
    );
  }

  Future<void> _playFrom(List<SongInfo> songs, int index) async {
    await _ctl.setQueue(songs, startAt: index);
    if (!mounted) return;
    _snack('Çalınıyor: ${songs[index].title}');
  }

  void _addToQueue(SongInfo song) {
    final added = _ctl.enqueue(song);
    _snack(
      added ? 'Sıraya eklendi: ${song.title}' : 'Zaten sırada: ${song.title}',
    );
  }

  Future<void> _retryPermission() async {
    await _library.reload();
    if (!mounted) return;
    if (_library.hasPermission) {
      _snack('${_library.songs.length} şarkı bulundu.');
    } else {
      _snack('Müzik izni verilmedi.');
    }
  }

  // ---------------------------------------------------------------- arayüz

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: AnimatedBuilder(
          animation: _merged,
          builder: (context, _) {
            final songs = _filtered;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeader(),
                _buildSearch(),
                _buildActions(songs),
                const Divider(height: 1, color: _border),
                Expanded(child: _buildBody(songs)),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 6, 16, 0),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            tooltip: 'Geri',
            icon: const Icon(Icons.arrow_back, color: Color(0xFFD4D4D8)),
          ),
          const SizedBox(width: 2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Telefondaki Şarkılar',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _library.loading
                      ? 'Taranıyor...'
                      : '${_library.songs.length} şarkı bulundu',
                  style: const TextStyle(color: _subtext, fontSize: 12),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => _library.reload(),
            tooltip: 'Yenile',
            icon: const Icon(Icons.refresh, color: Color(0xFFD4D4D8), size: 20),
          ),
        ],
      ),
    );
  }

  Widget _buildSearch() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _border),
        ),
        child: Row(
          children: [
            const Icon(Icons.search, size: 18, color: _subtext),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _search,
                onChanged: (v) => setState(() => _query = v),
                style: const TextStyle(color: Color(0xFFE5E5E5), fontSize: 13),
                decoration: const InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  hintText: 'Şarkı, sanatçı veya albüm ara...',
                  hintStyle: TextStyle(color: _subtext, fontSize: 13),
                ),
              ),
            ),
            if (_query.isNotEmpty)
              GestureDetector(
                onTap: () {
                  _search.clear();
                  setState(() => _query = '');
                },
                child: const Icon(Icons.close, size: 16, color: _subtext),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildActions(List<SongInfo> songs) {
    final hasSongs = songs.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Row(
        children: [
          Expanded(
            child: _BigButton(
              icon: Icons.play_arrow,
              label: 'Tümünü Çal',
              filled: true,
              onTap: hasSongs ? () => _playAll(songs, shuffle: false) : null,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _BigButton(
              icon: Icons.shuffle,
              label: 'Karışık Çal',
              filled: false,
              onTap: hasSongs ? () => _playAll(songs, shuffle: true) : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(List<SongInfo> songs) {
    if (_library.loading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }
    if (!_library.hasPermission) {
      return _EmptyState(
        icon: Icons.folder_off_outlined,
        title: 'Müzik izni gerekiyor',
        message:
            'Telefondaki şarkıları listelemek için müzik/depolama iznini vermen gerekiyor.',
        actionLabel: 'İzni Ver / Yeniden Dene',
        onAction: _retryPermission,
      );
    }
    if (_library.songs.isEmpty) {
      return _EmptyState(
        icon: Icons.music_off_outlined,
        title: 'Şarkı bulunamadı',
        message:
            'Telefonda ses dosyası bulunamadı. Müzikleri cihaza kopyalayıp "Yenile"ye dokun.',
        actionLabel: 'Yenile',
        onAction: () => _library.reload(),
      );
    }
    if (songs.isEmpty) {
      return const _EmptyState(
        icon: Icons.search_off,
        title: 'Eşleşen şarkı yok',
        message: 'Aramayı değiştirip tekrar dene.',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 20),
      itemCount: songs.length,
      itemBuilder: (context, i) => _songTile(songs, i),
    );
  }

  Widget _songTile(List<SongInfo> songs, int i) {
    final song = songs[i];
    final isCurrent = _ctl.current?.uri == song.uri;
    final duration = song.durationMs > 0
        ? MusicFormat.duration(Duration(milliseconds: song.durationMs))
        : '';

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: isCurrent ? const Color(0xFF191920) : _card,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: () => _playFrom(songs, i),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isCurrent ? const Color(0xFF3F3F46) : _border,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  isCurrent && _ctl.isPlaying
                      ? Icons.graphic_eq
                      : Icons.music_note,
                  size: 18,
                  color: isCurrent ? Colors.white : const Color(0xFFA3A3A3),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        song.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isCurrent
                              ? Colors.white
                              : const Color(0xFFE4E4E7),
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        [
                          if (song.artist.isNotEmpty) song.artist,
                          if (duration.isNotEmpty) duration,
                        ].join('  •  '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: _subtext, fontSize: 11.5),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                IconButton(
                  onPressed: () => _addToQueue(song),
                  tooltip: 'Sıraya ekle',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(
                    Icons.add_circle_outline,
                    size: 20,
                    color: Color(0xFFA3A3A3),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Kütüphanedeki geniş eylem düğmesi (Tümünü Çal / Karışık Çal).
class _BigButton extends StatelessWidget {
  const _BigButton({
    required this.icon,
    required this.label,
    required this.filled,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool filled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final bg = filled ? Colors.white : const Color(0xFF131317);
    final fg = filled ? Colors.black : const Color(0xFFD4D4D8);

    return Material(
      color: enabled ? bg : const Color(0xFF17171B),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 46,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: filled ? Colors.transparent : const Color(0xFF232327),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: enabled ? fg : const Color(0xFF525252),
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: enabled ? fg : const Color(0xFF525252),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Boş / izin bekleyen durumlar için ortak görünüm.
class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: const Color(0xFF525252)),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF76767C),
                fontSize: 13,
                height: 1.5,
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 18),
              FilledButton(
                onPressed: onAction,
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                ),
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

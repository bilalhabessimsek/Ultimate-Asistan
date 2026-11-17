import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/audio_spectrum.dart';
import '../services/favorites_store.dart';
import '../services/file_io.dart';
import '../services/local_music.dart';
import '../services/music_library.dart';
import '../services/player_controller.dart';
import '../services/playlist_store.dart';
import '../utils/music_format.dart';
import 'import_screen.dart';
import 'library_screen.dart';
import 'playlists_screen.dart';

/// Tasarım: "Müzik Çalar ve Sıraya Ekleme" ekranı.
///
/// Plak görseli, ilerleme çubuğu, oynatma denetimleri ve çalma sırası
/// (kuyruk) bu ekranda yönetilir. Oynatma durumu `PlayerController`
/// içinde tutulduğu için sekmeler arası geçişte müzik durmaz.
class PlayerScreen extends StatefulWidget {
  const PlayerScreen({
    super.key,
    this.playlistName,
    this.openPlaylistEditor = false,
  });

  /// Verilirse ekran bir çalma listesinin oynatıcısı olarak açılır:
  /// üstte liste adı ve **+ Ekle/Çıkar** düğmesi görünür; +"a basınca
  /// kütüphaneden bu listeye şarkı ekleme/çıkarma paneli açılır.
  final String? playlistName;

  /// Açılışta "Ekle/Çıkar" panelini kendiliğinden açar (boş liste için).
  final bool openPlaylistEditor;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  // Tasarım renkleri (m_zik_alar_ve_s_raya_ekleme_ekran).
  static const Color _bg = Color(0xFF0B0B0E);
  static const Color _card = Color(0xFF151518);
  static const Color _subtext = Color(0xFF76767C);

  final PlayerController _ctl = PlayerController.instance;
  final MusicLibrary _library = MusicLibrary.instance;
  final FavoritesStore _fav = FavoritesStore.instance;
  final TextEditingController _searchController = TextEditingController();

  /// Yüksek frekanslı güncellemeler için bir kez oluşturulan birleşik dinleyici.
  late final Listenable _merged = Listenable.merge([_ctl, _library, _fav]);

  String _query = '';
  double? _dragValue;

  QueueSort? _lastSort;
  bool _sortAscending = true;
  bool _filledFromLibrary = false;

  @override
  void initState() {
    super.initState();
    _ctl.init();
    _fav.load();
    _library.addListener(_onLibraryChanged);
    _library.ensureLoaded().then((_) => _onLibraryChanged());
    final playlist = widget.playlistName;
    if (playlist != null && widget.openPlaylistEditor) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showPlaylistEditSheet(playlist);
      });
    }
  }

  @override
  void dispose() {
    _library.removeListener(_onLibraryChanged);
    _searchController.dispose();
    super.dispose();
  }

  /// Açılışta kuyruk boşsa telefon müziklerini (çalmadan) yükler; böylece
  /// uygulama ilk açıldığında yerel müzikler doğrudan görünür.
  void _onLibraryChanged() {
    if (!mounted) return;
    // Liste modunda kuyruk listeye aittir; kütüphaneden otomatik doldurulmaz.
    if (widget.playlistName != null) return;
    if (_filledFromLibrary) return;
    if (_library.songs.isEmpty) return;
    _filledFromLibrary = true;
    if (_ctl.isEmpty) _ctl.loadQueue(_library.songs);
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

  void _addToQueue(SongInfo song) {
    final added = _ctl.enqueue(song);
    _snack(
      added ? 'Sıraya eklendi: ${song.title}' : 'Zaten sırada: ${song.title}',
    );
  }

  // ---------------------------------------------------------------- sayfalar

  Future<void> _openPlaylists() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const PlaylistsScreen()),
    );
  }

  Future<void> _openImport() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ImportScreen()),
    );
  }

  Future<void> _openLibrary() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const LibraryScreen()),
    );
  }

  // ---------------------------------------------------------------- arayüz

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        bottom: false,
        child: AnimatedBuilder(
          animation: _merged,
          builder: (context, _) => CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: _buildTopActions()),
              SliverToBoxAdapter(child: _buildVisualizer()),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    const SizedBox(height: 12),
                    _buildTrackMeta(),
                    const SizedBox(height: 24),
                    _buildProgress(),
                    const SizedBox(height: 32),
                    _buildControls(),
                    const SizedBox(height: 28),
                    _buildQueueHeader(),
                    if (_query.trim().isNotEmpty) _buildSuggestions(),
                    const SizedBox(height: 12),
                    _buildQueueSummary(),
                  ]),
                ),
              ),
              // Kuyruk tembel (lazy) bir sliver liste olarak çizilir; binlerce
              // şarkı olsa bile yalnızca görünen satırlar oluşturulur (kasma
              // sorunu burada çözülür).
              ..._buildQueueSlivers(),
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopActions() {
    final playlist = widget.playlistName;
    if (playlist != null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
        child: Row(
          children: [
            IconButton(
              onPressed: () => Navigator.of(context).maybePop(),
              tooltip: 'Geri',
              icon: const Icon(
                Icons.chevron_left,
                color: Color(0xFFD4D4D8),
                size: 26,
              ),
            ),
            const SizedBox(width: 2),
            Expanded(
              child: Text(
                playlist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFFF5F5F5),
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.2,
                ),
              ),
            ),
            Material(
              color: const Color(0xFF17171B),
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                onTap: () => _showPlaylistEditSheet(playlist),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF262626)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add, size: 16, color: Colors.white),
                      SizedBox(width: 4),
                      Text(
                        'Ekle/Çıkar',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
      child: Row(
        children: [
          IconButton(
            onPressed: _openPlaylists,
            tooltip: 'Çalma Listelerim',
            icon: const Icon(
              Icons.playlist_play,
              color: Color(0xFFD4D4D8),
              size: 22,
            ),
          ),
          IconButton(
            onPressed: _openLibrary,
            tooltip: 'Telefondaki Şarkılar',
            icon: const Icon(
              Icons.library_music,
              color: Color(0xFFD4D4D8),
              size: 22,
            ),
          ),
          const Spacer(),
          IconButton(
            onPressed: _openImport,
            tooltip: 'İçe Aktar',
            icon: const Icon(
              Icons.file_upload_outlined,
              color: Color(0xFFD4D4D8),
              size: 21,
            ),
          ),
        ],
      ),
    );
  }

  /// Üstteki görsel: çalan parçaya göre hareket eden 8 sütunlu ses
  /// görselleştiricisi (plak görseli kaldırıldı).
  Widget _buildVisualizer() {
    return SizedBox(
      height: 158,
      child: Center(
        child: _Visualizer(
          active: _ctl.isPlaying,
          volume: _ctl.volume,
          song: _ctl.current,
          position: _ctl.position,
        ),
      ),
    );
  }

  Widget _buildTrackMeta() {
    final song = _ctl.current;
    return Column(
      children: [
        Text(
          song?.title ?? 'Şarkı Seçilmedi',
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.bold,
            letterSpacing: -0.4,
            height: 1.15,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
          decoration: BoxDecoration(
            color: const Color(0xFF17171B),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: const Color(0x99404040)),
          ),
          child: Text(
            MusicFormat.formatLabel(song),
            style: const TextStyle(
              color: Color(0xFFA3A3A3),
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 2.0,
            ),
          ),
        ),
      ],
    );
  }

  /// İlerleme çubuğu yalnızca konum değişince yeniden çizilir; ekranın geri
  /// kalanını (ve listeyi) yeniden çizmez. Kasma çözümünün ikinci parçası.
  Widget _buildProgress() {
    return ValueListenableBuilder<Duration>(
      valueListenable: _ctl.position,
      builder: (context, pos, _) => _buildProgressBar(pos.inMilliseconds),
    );
  }

  Widget _buildProgressBar(int posMs) {
    final totalMs = _ctl.total.inMilliseconds;
    final value = (_dragValue ?? posMs.toDouble())
        .clamp(0.0, totalMs > 0 ? totalMs.toDouble() : 0.0);
    final frac = totalMs > 0 ? (value / totalMs).clamp(0.0, 1.0) : 0.0;
    final seekable = totalMs > 0;

    return Column(
      children: [
        SizedBox(
          height: 20,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Positioned(
                left: 0,
                right: 0,
                child: Container(
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFF262626),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: frac,
                    child: Container(
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                ),
              ),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 4,
                  activeTrackColor: Colors.transparent,
                  inactiveTrackColor: Colors.transparent,
                  disabledActiveTrackColor: Colors.transparent,
                  disabledInactiveTrackColor: Colors.transparent,
                  thumbColor: Colors.white,
                  disabledThumbColor: const Color(0xFF525252),
                  overlayColor: Colors.transparent,
                  thumbShape:
                      const RoundSliderThumbShape(enabledThumbRadius: 8),
                  overlayShape: SliderComponentShape.noOverlay,
                ),
                child: Slider(
                  value: seekable ? value : 0,
                  max: seekable ? totalMs.toDouble() : 1,
                  onChanged:
                      seekable ? (v) => setState(() => _dragValue = v) : null,
                  onChangeEnd: seekable
                      ? (v) {
                          setState(() => _dragValue = null);
                          _ctl.seek(Duration(milliseconds: v.round()));
                        }
                      : null,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              MusicFormat.duration(
                Duration(
                    milliseconds: (_dragValue ?? posMs.toDouble()).round()),
              ),
              style: const TextStyle(color: Color(0xFFA3A3A3), fontSize: 12),
            ),
            Text(
              MusicFormat.duration(_ctl.total),
              style: const TextStyle(color: Color(0xFFA3A3A3), fontSize: 12),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildControls() {
    final hasQueue = !_ctl.isEmpty;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _controlButton(
          icon: Icons.shuffle,
          size: 20,
          active: _ctl.shuffle,
          tooltip: 'Karışık Çal',
          onTap: () => _ctl.setShuffle(!_ctl.shuffle),
        ),
        _controlButton(
          icon: _ctl.repeat == RepeatMode.one ? Icons.repeat_one : Icons.repeat,
          size: 18,
          active: _ctl.repeat != RepeatMode.off,
          tooltip: _ctl.repeat == RepeatMode.off
              ? 'Tekrarla: Kapalı'
              : _ctl.repeat == RepeatMode.all
                  ? 'Tekrarla: Tümü'
                  : 'Tekrarla: Tek Şarkı',
          onTap: _ctl.cycleRepeat,
        ),
        _controlButton(
          icon: Icons.skip_previous,
          size: 30,
          color: hasQueue ? Colors.white : const Color(0xFF525252),
          tooltip: 'Önceki Parça',
          onTap: hasQueue ? () => _ctl.previous() : null,
        ),
        GestureDetector(
          onTap: hasQueue ? () => _ctl.togglePlayPause() : null,
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: hasQueue ? Colors.white : const Color(0xFF2A2A2E),
              boxShadow: const [
                BoxShadow(
                    color: Colors.black54, blurRadius: 16, spreadRadius: 1),
              ],
            ),
            child: Icon(
              _ctl.isPlaying ? Icons.pause : Icons.play_arrow,
              color: hasQueue ? Colors.black : const Color(0xFF6B6B70),
              size: 32,
            ),
          ),
        ),
        _controlButton(
          icon: Icons.skip_next,
          size: 30,
          color: hasQueue ? Colors.white : const Color(0xFF525252),
          tooltip: 'Sonraki Parça',
          onTap: hasQueue ? () => _ctl.next() : null,
        ),
        _controlButton(
          icon: _ctl.isMuted ? Icons.volume_off : Icons.volume_up,
          size: 20,
          active: _ctl.isMuted,
          tooltip: 'Ses Seviyesi',
          onTap: _showVolumeSheet,
        ),
        GestureDetector(
          onTap: _showOutputSheet,
          behavior: HitTestBehavior.opaque,
          child: Tooltip(
            message: 'Çıkış Aygıtı',
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Container(
                width: 14,
                height: 14,
                decoration: const BoxDecoration(
                  color: Color(0xFF525252),
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _controlButton({
    required IconData icon,
    required double size,
    required String tooltip,
    VoidCallback? onTap,
    Color? color,
    bool active = false,
  }) {
    return IconButton(
      onPressed: onTap,
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      icon: Icon(
        icon,
        size: size,
        color: color ?? (active ? Colors.white : const Color(0xFFA3A3A3)),
      ),
    );
  }

  Widget _buildQueueHeader() {
    return Row(
      children: [
        _buildSortButton(),
        const SizedBox(width: 8),
        Expanded(
          child: Container(
            height: 38,
            decoration: BoxDecoration(
              color: const Color(0xFF121216),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF262626)),
            ),
            child: Row(
              children: [
                const SizedBox(width: 10),
                const Icon(
                  Icons.search,
                  size: 16,
                  color: Color(0xFF737373),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    onChanged: (v) => setState(() => _query = v),
                    onSubmitted: (v) {
                      final q = v.trim().toLowerCase();
                      if (q.isEmpty) return;
                      if (_library.songs.isEmpty) {
                        _snack('Arşiv hâlâ yükleniyor...');
                        return;
                      }
                      final matches = _library.songs
                          .where(
                            (s) =>
                                s.title.toLowerCase().contains(q) ||
                                s.artist.toLowerCase().contains(q),
                          )
                          .toList();
                      if (matches.isEmpty) {
                        _snack('Eşleşen şarkı yok: $v');
                        return;
                      }
                      _searchController.clear();
                      setState(() => _query = '');
                      _addToQueue(matches.first);
                    },
                    style: const TextStyle(
                      color: Color(0xFFE5E5E5),
                      fontSize: 12,
                    ),
                    decoration: const InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      hintText: 'Sıraya şarkı ekle...',
                      hintStyle: TextStyle(
                        color: Color(0xFF737373),
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  onPressed: _showArchiveSheet,
                  tooltip: 'İçe Aktar / Ekle',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(
                    Icons.add_circle,
                    size: 18,
                    color: Color(0xFFA3A3A3),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSortButton() {
    final enabled = !_ctl.isEmpty;
    final color = enabled ? const Color(0xFFD4D4D4) : const Color(0xFF525252);
    return Material(
      color: const Color(0xFF121216),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: enabled ? _showSortSheet : null,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFF262626)),
          ),
          child: Row(
            children: [
              Icon(Icons.sort, size: 16, color: color),
              const SizedBox(width: 6),
              Text(
                'Sırala',
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQueueSummary() {
    return Row(
      children: [
        Text(
          '${_ctl.queueLength} şarkı',
          style: const TextStyle(color: _subtext, fontSize: 11),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              if (_ctl.shuffle) _chip('Karışık'),
              if (_lastSort != null)
                _chip(
                    '${_sortLabel(_lastSort!)} ${_sortAscending ? "↑" : "↓"}'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _chip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFF17171B),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0x99404040)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Color(0xFFA3A3A3),
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  String _sortLabel(QueueSort sort) {
    switch (sort) {
      case QueueSort.name:
        return 'Ada göre';
      case QueueSort.duration:
        return 'Süreye göre';
      case QueueSort.date:
        return 'Tarihe göre';
    }
  }

  Widget _buildSuggestions() {
    final q = _query.trim().toLowerCase();
    final matches = _library.songs
        .where(
          (s) =>
              s.title.toLowerCase().contains(q) ||
              s.artist.toLowerCase().contains(q),
        )
        .take(6)
        .toList();

    if (matches.isEmpty) {
      return const Padding(
        padding: EdgeInsets.only(top: 10),
        child: Text(
          'Eşleşen şarkı yok.',
          style: TextStyle(color: _subtext, fontSize: 12),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        children: [
          for (final s in matches)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Material(
                color: const Color(0xFF131317),
                borderRadius: BorderRadius.circular(10),
                child: InkWell(
                  onTap: () {
                    _searchController.clear();
                    setState(() => _query = '');
                    _addToQueue(s);
                  },
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0x80262626)),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.add,
                          size: 16,
                          color: Color(0xFFA3A3A3),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            s.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFFD4D4D4),
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Kuyruğu tembel çizen sliver listeler. Uzun kuyruklarda yalnızca görünen
  /// satırlar oluşturulur (kasma çözümü).
  List<Widget> _buildQueueSlivers() {
    if (_library.loading && _ctl.isEmpty) {
      return const [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 30),
            child:
                Center(child: CircularProgressIndicator(color: Colors.white)),
          ),
        ),
      ];
    }
    if (_ctl.isEmpty) {
      return [
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          sliver: SliverToBoxAdapter(child: _buildEmptyQueue()),
        ),
      ];
    }
    return [
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        sliver: SliverReorderableList(
          itemCount: _ctl.queueLength,
          onReorder: _ctl.reorder,
          itemBuilder: (context, i) {
            final song = _ctl.songAt(i);
            return _buildQueueItem(
              // Kuyrukta aynı şarkı iki kez bulunmaz (bkz. PlayerController),
              // bu yüzden id benzersiz anahtar olarak güvenlidir.
              key: ValueKey<int>(song.id),
              i: i,
              song: song,
            );
          },
        ),
      ),
    ];
  }

  Widget _buildEmptyQueue() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF131317),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0x80262626)),
      ),
      child: Column(
        children: [
          const Text(
            'Çalma sırası boş.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Telefondaki şarkılardan seç ya da yukarıdaki "+" ile arşivden ekle.',
            textAlign: TextAlign.center,
            style: TextStyle(color: _subtext, fontSize: 12, height: 1.5),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: _openLibrary,
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
            ),
            icon: const Icon(Icons.library_music, size: 18),
            label: Text(
              _library.songs.isEmpty
                  ? 'Telefondaki Şarkılar'
                  : 'Telefondaki ${_library.songs.length} Şarkı',
            ),
          ),
        ],
      ),
    );
  }

  /// Sürükle-bırak tutamacı (çift çizgi). Basılı tutup sürükleyince şarkı
  /// sırada yukarı/aşağı taşınır. Numara yerine bu gelir; böylece başlıkla
  /// arasında boşluk kalır.
  Widget _dragHandle(int i) {
    return ReorderableDelayedDragStartListener(
      index: i,
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 2, vertical: 6),
        child: Icon(
          Icons.drag_handle,
          size: 20,
          color: Color(0xFF6B6B70),
        ),
      ),
    );
  }

  /// Favori (kalp) düğmesi. Kaldırılan ileri/geri tuşlarının yerine geldi.
  Widget _favButton(SongInfo song) {
    final fav = _fav.contains(song.id);
    return IconButton(
      onPressed: () async {
        final added = await _fav.toggle(song.id);
        _snack(added ? 'Favorilere eklendi.' : 'Favorilerden çıkarıldı.');
      },
      tooltip: fav ? 'Favoriden çıkar' : 'Favorilere ekle',
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.all(4),
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      icon: Icon(
        fav ? Icons.favorite : Icons.favorite_border,
        size: 18,
        color: fav ? const Color(0xFFF43F5E) : const Color(0xFFA3A3A3),
      ),
    );
  }

  Widget _buildQueueItem({
    required Key key,
    required int i,
    required SongInfo song,
  }) {
    final isCurrent = i == _ctl.index;

    return Container(
      key: key,
      margin: const EdgeInsets.only(bottom: 8),
      padding: EdgeInsets.symmetric(
        horizontal: 10,
        vertical: isCurrent ? 12 : 9,
      ),
      decoration: BoxDecoration(
        color: isCurrent ? const Color(0xFF151519) : const Color(0xFF131317),
        border: Border.all(
          color: isCurrent ? const Color(0xCC46464E) : const Color(0xCC262626),
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          _dragHandle(i),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              song.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isCurrent ? Colors.white : const Color(0xFFD4D4D4),
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 6),
          if (isCurrent) ...[
            _PlayingBars(active: _ctl.isPlaying),
            const SizedBox(width: 4),
          ],
          // Tüm satırlarda aynı sıra: favori, çal/duraklat, kaldır.
          _favButton(song),
          if (isCurrent)
            _queueAction(
              _ctl.isPlaying ? Icons.pause : Icons.play_arrow,
              _ctl.isPlaying ? 'Duraklat' : 'Devam Et',
              _ctl.togglePlayPause,
              color: Colors.white,
            )
          else
            _queueAction(
              Icons.play_arrow,
              'Şimdi Çal',
              () => _ctl.playAt(i),
              color: const Color(0xFFD4D4D4),
            ),
          _queueAction(
            Icons.delete_outline,
            'Listeden Kaldır',
            () => _ctl.removeAt(i),
            danger: true,
          ),
        ],
      ),
    );
  }

  Widget _queueAction(
    IconData icon,
    String tooltip,
    VoidCallback onTap, {
    Color color = const Color(0xFFA3A3A3),
    bool danger = false,
  }) {
    return IconButton(
      onPressed: onTap,
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.all(4),
      constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
      icon: Icon(
        icon,
        size: 17,
        color: color,
      ),
      hoverColor: danger ? const Color(0x33F43F5E) : null,
    );
  }

  // ---------------------------------------------------------------- sayfalar

  void _showVolumeSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: _card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      _ctl.isMuted ? Icons.volume_off : Icons.volume_up,
                      color: Colors.white,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    const Text(
                      'Ses Seviyesi',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${(_ctl.volume * 100).round()}%',
                      style: const TextStyle(color: _subtext, fontSize: 13),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Slider(
                        value: _ctl.volume,
                        onChanged: (v) async {
                          await _ctl.setVolume(v);
                          setSheet(() {});
                        },
                        activeColor: Colors.white,
                        inactiveColor: const Color(0xFF2A2A2E),
                      ),
                    ),
                    IconButton(
                      onPressed: () async {
                        await _ctl.toggleMute();
                        setSheet(() {});
                      },
                      tooltip: _ctl.isMuted ? 'Sesi aç' : 'Sessize al',
                      icon: Icon(
                        _ctl.isMuted ? Icons.volume_up : Icons.volume_off,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showOutputSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: _card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Çıkış Aygıtı',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Cihazın kullanılabilir ses çıkışları',
                style: TextStyle(color: _subtext, fontSize: 12),
              ),
              const SizedBox(height: 12),
              FutureBuilder<List<AudioOutput>>(
                future: _ctl.audioOutputs(),
                builder: (ctx, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return const Padding(
                      padding: EdgeInsets.all(20),
                      child: Center(
                        child: CircularProgressIndicator(color: Colors.white),
                      ),
                    );
                  }
                  final outputs = snap.data ?? const <AudioOutput>[];
                  if (outputs.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Text(
                        'Çıkış aygıtı bilgisi alınamadı.',
                        style: TextStyle(color: _subtext, fontSize: 13),
                      ),
                    );
                  }
                  return Column(
                    children: [
                      for (final o in outputs)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            _outputIcon(o.type),
                            color: Colors.white,
                            size: 20,
                          ),
                          title: Text(
                            o.name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                            ),
                          ),
                          subtitle: Text(
                            'Tür kodu: ${o.type}',
                            style: const TextStyle(
                              color: _subtext,
                              fontSize: 11,
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _outputIcon(int type) {
    // AudioDeviceInfo tipleri (Android): 1=builtin earpiece, 2=speaker,
    // 3=wired headset, 4=wired headphones, 7=bluetooth sco, 8=bluetooth a2dp.
    switch (type) {
      case 1:
        return Icons.phone_in_talk;
      case 2:
        return Icons.speaker;
      case 3:
      case 4:
        return Icons.headphones;
      case 7:
      case 8:
        return Icons.bluetooth_audio;
      case 11:
        return Icons.usb;
      case 22:
        return Icons.cast;
      default:
        return Icons.speaker_group;
    }
  }

  void _showSortSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: _card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Sırala',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Ölçütü seç, oklarla artan/azalan sırala. Sıralama karışığı kapatır.',
                  style: TextStyle(color: _subtext, fontSize: 12),
                ),
                const SizedBox(height: 14),
                _sortRow(
                    setSheet, 'Ada göre', Icons.sort_by_alpha, QueueSort.name),
                _sortRow(setSheet, 'Süreye göre', Icons.timer_outlined,
                    QueueSort.duration),
                _sortRow(setSheet, 'Tarihe göre', Icons.calendar_today_outlined,
                    QueueSort.date),
                const Divider(color: Color(0xFF262626), height: 24),
                Row(
                  children: [
                    Icon(
                      Icons.shuffle,
                      size: 18,
                      color:
                          _ctl.shuffle ? Colors.white : const Color(0xFFA3A3A3),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Karışık Çal',
                        style: TextStyle(color: Colors.white, fontSize: 14),
                      ),
                    ),
                    Switch(
                      value: _ctl.shuffle,
                      activeThumbColor: Colors.white,
                      onChanged: (v) {
                        _ctl.setShuffle(v);
                        setSheet(() {});
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sortRow(
    void Function(void Function()) setSheet,
    String label,
    IconData icon,
    QueueSort field,
  ) {
    final isActive = _lastSort == field;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF121216),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isActive ? const Color(0x99404040) : const Color(0xFF262626),
        ),
      ),
      child: Row(
        children: [
          Icon(icon, size: 17, color: const Color(0xFFA3A3A3)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: isActive ? Colors.white : const Color(0xFFD4D4D4),
                fontSize: 14,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Artan',
            visualDensity: VisualDensity.compact,
            onPressed: () {
              _ctl.sortQueue(field, ascending: true);
              setSheet(() {
                _lastSort = field;
                _sortAscending = true;
              });
            },
            icon: Icon(
              Icons.arrow_upward,
              size: 18,
              color: isActive && _sortAscending
                  ? Colors.white
                  : const Color(0xFF76767C),
            ),
          ),
          IconButton(
            tooltip: 'Azalan',
            visualDensity: VisualDensity.compact,
            onPressed: () {
              _ctl.sortQueue(field, ascending: false);
              setSheet(() {
                _lastSort = field;
                _sortAscending = false;
              });
            },
            icon: Icon(
              Icons.arrow_downward,
              size: 18,
              color: isActive && !_sortAscending
                  ? Colors.white
                  : const Color(0xFF76767C),
            ),
          ),
        ],
      ),
    );
  }

  /// Çalma listesinin "Ekle/Çıkar" paneli (+ düğmesi).
  void _showPlaylistEditSheet(String playlistName) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: _card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.8,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (ctx, scrollController) => _PlaylistEditSheet(
          playlistName: playlistName,
          scrollController: scrollController,
        ),
      ),
    );
  }

  void _showArchiveSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: _card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (ctx, scrollController) => _ArchiveSheet(
          scrollController: scrollController,
          onAdd: _addToQueue,
          onOpenPlaylists: () {
            Navigator.pop(ctx);
            _openPlaylists();
          },
          onOpenImport: () {
            Navigator.pop(ctx);
            _openImport();
          },
        ),
      ),
    );
  }
}

/// Çalan parçaya göre hareket eden 8 sütunlu ses görselleştiricisi.
///
/// Çubuklar şarkının **kendi** sesinden (dosya yerelde bir kez çözülerek)
/// çıkarılan gerçek bas/tiz seviyeleriyle hareket eder; bu yüzden döngüsel bir
/// animasyon gibi görünmez. Mikrofon izni GEREKMEZ ve hiçbir ses kaydedilmez.
/// Zarf hazır olana kadar (ilk 1-2 saniye) ya da analiz desteklenmiyorsa
/// (MIDI) birbirine tam kat olmayan frekanslardan oluşan (bu yüzden tekrar
/// etmeyen) yedek animasyon çalışır.
class _Visualizer extends StatefulWidget {
  const _Visualizer({
    required this.active,
    required this.volume,
    required this.song,
    required this.position,
  });

  /// Çalıyor mu?
  final bool active;

  /// Uygulama ses seviyesi (0..1); yalnızca yedek animasyonda kullanılır.
  final double volume;

  /// Çalan parça; spektrum zarfı bunun dosyasından çıkarılır.
  final SongInfo? song;

  /// Çalma konumu (kaba aralıklarla güncellenir; burada yumuşatılır).
  final ValueListenable<Duration> position;

  @override
  State<_Visualizer> createState() => _VisualizerState();
}

class _VisualizerState extends State<_Visualizer>
    with SingleTickerProviderStateMixin {
  static const int _barCount = AudioSpectrum.bandCount;
  static const double _maxHeight = 112;
  static const double _minHeight = 8;

  /// Yedek animasyonun bant frekansları (Hz). Aralarında tam kat ilişki
  /// olmadığı için toplam desen kısa sürede tekrar etmez.
  static const List<double> _freqs = <double>[
    0.37,
    0.53,
    0.71,
    0.89,
    1.13,
    1.31,
    1.57,
    1.79,
  ];

  final AudioSpectrum _spectrum = AudioSpectrum.instance;
  final List<double> _targets = List<double>.filled(_barCount, 0);
  final List<double> _level = List<double>.filled(_barCount, 0);

  late final AnimationController _ticker = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 1),
  );

  final Stopwatch _clock = Stopwatch();
  final math.Random _random = math.Random();
  late final List<double> _phases = List<double>.generate(
      _barCount, (_) => _random.nextDouble() * math.pi * 2);

  /// Çalan şarkının çıkarılmış zarfı (hazır değilse `null`).
  SpectrumEnvelope? _envelope;
  int _envelopeSongId = -1;

  Duration _lastTick = Duration.zero;

  // Konum yumuşatma: konum akışı kaba (~5 Hz) gelir; burada 60 fps'e yayılır.
  Duration _lastPos = Duration.zero;
  Duration _lastPosAt = Duration.zero;

  double _t = 0;

  @override
  void initState() {
    super.initState();
    _ticker.addListener(_onTick);
    _spectrum.revision.addListener(_onSpectrumReady);
    _ensureSpectrum();
    _sync();
  }

  @override
  void didUpdateWidget(covariant _Visualizer oldWidget) {
    super.didUpdateWidget(oldWidget);
    _ensureSpectrum();
    _sync();
  }

  @override
  void dispose() {
    _spectrum.revision.removeListener(_onSpectrumReady);
    _ticker.dispose();
    super.dispose();
  }

  /// Çalma durumuna göre animasyonu çalıştırır/durdurur.
  void _sync() {
    if (!widget.active) {
      if (_ticker.isAnimating) _ticker.stop();
      for (var i = 0; i < _barCount; i++) {
        _targets[i] = 0;
      }
      return;
    }
    if (!_ticker.isAnimating) {
      _lastPos = widget.position.value;
      _lastPosAt = _clock.elapsed;
      _ticker.repeat();
    }
  }

  /// Çalan şarkı değiştiyse zarfını (varsa önbellekten) alır ve yoksa
  /// arka planda analiz başlatır.
  void _ensureSpectrum() {
    final song = widget.song;
    if (song == null) {
      _envelope = null;
      _envelopeSongId = -1;
      return;
    }
    if (_envelopeSongId == song.id) return;
    _envelopeSongId = song.id;
    final cached = _spectrum.envelopeOf(song.id);
    _envelope = cached;
    if (cached != null) return;
    // Analiz tamamlanınca `revision` artar ve zarfa geçilir.
    _spectrum.prepare(song);
  }

  void _onSpectrumReady() {
    if (!mounted) return;
    final song = widget.song;
    if (song == null) return;
    final env = _spectrum.envelopeOf(song.id);
    if (env != null && !identical(env, _envelope)) {
      setState(() {
        _envelope = env;
        _envelopeSongId = song.id;
      });
    }
  }

  /// Konum akışını, son geldiği andan bu yana geçen süreyle ileri taşır.
  Duration _smoothPosition(Duration now) {
    final p = widget.position.value;
    if (p != _lastPos) {
      _lastPos = p;
      _lastPosAt = now;
    }
    final extra = now - _lastPosAt;
    if (extra <= Duration.zero) return _lastPos;
    return _lastPos + extra;
  }

  void _onTick() {
    if (!_clock.isRunning) {
      _clock.start();
      _lastTick = Duration.zero;
      _lastPosAt = Duration.zero;
    }
    final now = _clock.elapsed;
    final dt = ((now - _lastTick).inMicroseconds / 1e6).clamp(0.0, 0.1);
    _lastTick = now;
    _t += dt;

    if (!widget.active) {
      return; // sabit/durgun; gereksiz çizim yok
    }

    final env = _envelope;
    if (env != null && env.frameCount > 0) {
      final index = env.frameIndexAt(_smoothPosition(now));
      final data = env.data;
      final base = index * _barCount;
      for (var i = 0; i < _barCount; i++) {
        final at = base + i;
        _targets[i] =
            at < data.length ? (data[at] / 255.0).clamp(0.0, 1.0) : 0.0;
      }
    } else {
      _fallbackTargets();
    }

    // Gerçek veride çıkış anında, inişte hafif yumuşak; yedekte daha yumuşak.
    final attack = env != null ? 1.0 : 0.38;
    final release = env != null ? 0.32 : 0.12;
    var changed = false;
    for (var i = 0; i < _barCount; i++) {
      final target = _targets[i];
      final cur = _level[i];
      final next = target > cur
          ? cur + (target - cur) * attack
          : cur + (target - cur) * release;
      if ((next - cur).abs() > 0.0008) {
        _level[i] = next;
        changed = true;
      } else if (cur != target) {
        _level[i] = target;
        changed = true;
      }
    }
    if (changed) setState(() {});
  }

  /// Yedek (veri yoksa) animasyon hedefleri: kısa sürede tekrar etmez.
  void _fallbackTargets() {
    final vol = widget.volume.clamp(0.0, 1.0);
    final amp = 0.28 + 0.72 * vol;
    for (var i = 0; i < _barCount; i++) {
      final f = _freqs[i];
      final p = _phases[i];
      final a = math.sin(_t * f + p) * 0.5 + 0.5;
      final b = math.sin(_t * f * 0.41 + p * 1.7) * 0.5 + 0.5;
      final c = math.sin(_t * f * 0.13 + p * 0.6) * 0.5 + 0.5;
      // Kenarlardaki çubuklar biraz daha kısa kalsın (doğal ekolayzer).
      final edge = 1.0 - (i - (_barCount - 1) / 2).abs() / _barCount * 0.5;
      _targets[i] = (a * 0.5 + b * 0.3 + c * 0.2) * amp * edge;
    }
  }

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (var i = 0; i < _barCount; i++) {
      if (i > 0) children.add(const SizedBox(width: 11));
      children.add(_bar(i));
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: _maxHeight,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: children,
          ),
        ),
      ],
    );
  }

  Widget _bar(int i) {
    final level = _level[i].clamp(0.0, 1.0);
    final height = _minHeight + (_maxHeight - _minHeight) * level;
    final opacity = 0.22 + 0.78 * level;
    return Container(
      width: 10,
      height: height.clamp(_minHeight, _maxHeight),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: opacity.clamp(0.0, 1.0)),
        borderRadius: BorderRadius.circular(999),
        boxShadow: const [
          BoxShadow(color: Color(0x22FFFFFF), blurRadius: 6, spreadRadius: 1),
        ],
      ),
    );
  }
}

/// Sıradaki çalan parçayı gösteren hareketli 3 çubuk.
class _PlayingBars extends StatefulWidget {
  const _PlayingBars({required this.active});

  final bool active;

  @override
  State<_PlayingBars> createState() => _PlayingBarsState();
}

class _PlayingBarsState extends State<_PlayingBars>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void initState() {
    super.initState();
    if (widget.active) _controller.repeat();
  }

  @override
  void didUpdateWidget(covariant _PlayingBars oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.active && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value * math.pi * 2;
        double h(int phase, double base) {
          if (!widget.active) return base;
          final value = math.sin(t + phase) * 0.5 + 0.5;
          return 6 + value * base;
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _bar(h(0, 10)),
            const SizedBox(width: 3),
            _bar(h(2, 14)),
            const SizedBox(width: 3),
            _bar(h(4, 8)),
          ],
        );
      },
    );
  }

  Widget _bar(double height) => Container(
        width: 3,
        height: height,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(999),
        ),
      );
}

/// Arşivden şarkı seçip sıraya ekleme sayfası.
class _ArchiveSheet extends StatefulWidget {
  const _ArchiveSheet({
    required this.scrollController,
    required this.onAdd,
    required this.onOpenPlaylists,
    required this.onOpenImport,
  });

  final ScrollController scrollController;
  final void Function(SongInfo song) onAdd;
  final VoidCallback onOpenPlaylists;
  final VoidCallback onOpenImport;

  @override
  State<_ArchiveSheet> createState() => _ArchiveSheetState();
}

class _ArchiveSheetState extends State<_ArchiveSheet> {
  static const Color _bg = Color(0xFF0B0B0E);
  static const Color _subtle = Color(0xFF76767C);

  final MusicLibrary _library = MusicLibrary.instance;
  final TextEditingController _controller = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _library.addListener(_onLibraryChanged);
  }

  void _onLibraryChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _library.removeListener(_onLibraryChanged);
    _controller.dispose();
    super.dispose();
  }

  List<SongInfo> get _filtered {
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

  @override
  Widget build(BuildContext context) {
    final songs = _filtered;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Sıraya Şarkı Ekle',
            style: TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _MiniAction(
                  icon: Icons.playlist_play,
                  label: 'Çalma Listelerim',
                  onTap: widget.onOpenPlaylists,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _MiniAction(
                  icon: Icons.file_upload_outlined,
                  label: 'İçe Aktar',
                  onTap: widget.onOpenImport,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: _bg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF262626)),
            ),
            child: Row(
              children: [
                const Icon(Icons.search, size: 16, color: _subtle),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    onChanged: (v) => setState(() => _query = v),
                    style: const TextStyle(
                      color: Color(0xFFE5E5E5),
                      fontSize: 13,
                    ),
                    decoration: const InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      hintText: 'Arşivde ara...',
                      hintStyle: TextStyle(color: _subtle, fontSize: 13),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${songs.length} şarkı',
            style: const TextStyle(color: _subtle, fontSize: 11),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.builder(
              controller: widget.scrollController,
              itemCount: songs.length,
              itemBuilder: (context, i) {
                final song = songs[i];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Material(
                    color: _bg,
                    borderRadius: BorderRadius.circular(10),
                    child: InkWell(
                      onTap: () => widget.onAdd(song),
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFF232327)),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.music_note,
                              size: 16,
                              color: Color(0xFFA3A3A3),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                song.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Color(0xFFD4D4D4),
                                  fontSize: 13,
                                ),
                              ),
                            ),
                            const Icon(
                              Icons.add_circle_outline,
                              size: 18,
                              color: Color(0xFFA3A3A3),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Çalma listesinin şarkı ekleme/çıkarma paneli (oynatıcıdaki "+" düğmesi).
///
/// Kütüphanedeki tüm şarkıları listeler; her satırdaki düğmeyle şarkı
/// açık olan çalma listesine eklenir/çıkarılır.
class _PlaylistEditSheet extends StatefulWidget {
  const _PlaylistEditSheet({
    required this.playlistName,
    required this.scrollController,
  });

  final String playlistName;
  final ScrollController scrollController;

  @override
  State<_PlaylistEditSheet> createState() => _PlaylistEditSheetState();
}

class _PlaylistEditSheetState extends State<_PlaylistEditSheet> {
  static const Color _bg = Color(0xFF0B0B0E);
  static const Color _subtle = Color(0xFF76767C);

  final PlaylistStore _store = PlaylistStore.instance;
  final MusicLibrary _library = MusicLibrary.instance;
  final TextEditingController _controller = TextEditingController();

  String _query = '';

  @override
  void initState() {
    super.initState();
    _store.load();
    _library.ensureLoaded();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<SongInfo> get _filtered {
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

  Future<void> _toggle(SongInfo song) async {
    await _store.toggle(widget.playlistName, song.id);
  }

  Future<void> _addAll() async {
    final songs = _filtered;
    if (songs.isEmpty) return;
    await _store.addAll(widget.playlistName, songs.map((s) => s.id));
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_store, _library]),
      builder: (context, _) {
        final songs = _filtered;
        final count = _store.countOf(widget.playlistName);
        return Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Listeye Şarkı Ekle / Çıkar',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${widget.playlistName} · $count şarkı',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: _subtle,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: _subtle),
                    tooltip: 'Kapat',
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: _bg,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF262626)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.search, size: 16, color: _subtle),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        onChanged: (v) => setState(() => _query = v),
                        style: const TextStyle(
                          color: Color(0xFFE5E5E5),
                          fontSize: 13,
                        ),
                        decoration: const InputDecoration(
                          isDense: true,
                          border: InputBorder.none,
                          hintText: 'Kütüphanede ara...',
                          hintStyle: TextStyle(color: _subtle, fontSize: 13),
                        ),
                      ),
                    ),
                    if (_query.isNotEmpty)
                      GestureDetector(
                        onTap: () {
                          _controller.clear();
                          setState(() => _query = '');
                        },
                        child: const Icon(
                          Icons.close,
                          size: 16,
                          color: _subtle,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: songs.isEmpty
                    ? const Center(
                        child: Text(
                          'Eşleşen şarkı bulunamadı.',
                          style: TextStyle(color: _subtle, fontSize: 13),
                        ),
                      )
                    : ListView.builder(
                        controller: widget.scrollController,
                        itemCount: songs.length,
                        itemBuilder: (context, i) => _row(songs[i]),
                      ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${songs.length} şarkı listelendi',
                    style: const TextStyle(color: _subtle, fontSize: 11),
                  ),
                  TextButton.icon(
                    onPressed: _addAll,
                    icon: const Icon(Icons.playlist_add, size: 16),
                    label: const Text('Tümünü Ekle'),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _row(SongInfo song) {
    final added = _store.contains(widget.playlistName, song.id);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: _bg,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: () => _toggle(song),
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF232327)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.music_note,
                  size: 16,
                  color: Color(0xFFA3A3A3),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        song.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFFD4D4D4),
                          fontSize: 13,
                        ),
                      ),
                      if (song.artist.isNotEmpty)
                        Text(
                          song.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: _subtle,
                            fontSize: 11,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => _toggle(song),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: added
                          ? const Color(0x1AF43F5E)
                          : const Color(0xFFE4E4E7),
                      borderRadius: BorderRadius.circular(999),
                      border: added
                          ? Border.all(color: const Color(0x4DF43F5E))
                          : null,
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
          ),
        ),
      ),
    );
  }
}

class _MiniAction extends StatelessWidget {
  const _MiniAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF0B0B0E),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFF232327)),
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
}

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import 'file_io.dart';
import 'local_music.dart';
import 'media_notification.dart';
import 'midi_player.dart';

/// Tekrar çalma kipi.
enum RepeatMode { off, all, one }

/// Çalma sırasını sıralama ölçütü.
enum QueueSort { name, duration, date }

/// Uygulamanın tek müzik motoru: kuyruk, oynatma, karıştırma/tekrar, ses
/// seviyesi ve ilerleme. Hem normal parçaları (just_audio) hem de MIDI
/// dosyalarını (yerleşik MediaPlayer) yönetir.
///
/// Ekranlar yalnızca bu denetleyiciyi dinler; böylece sekme değiştirilse veya
/// ekran kapansa bile çalma devam eder.
class PlayerController extends ChangeNotifier {
  PlayerController._();

  static final PlayerController instance = PlayerController._();

  final AudioPlayer _audio = AudioPlayer();
  final MidiPlayer _midi = MidiPlayer();
  final FileIo _fileIo = FileIo();
  final MediaNotification _media = MediaNotification.instance;

  final List<SongInfo> _queue = [];
  int _index = -1;
  bool _isPlaying = false;
  bool _shuffle = false;
  RepeatMode _repeat = RepeatMode.off;
  double _volume = 1.0;
  Duration _progress = Duration.zero;
  Duration _total = Duration.zero;

  /// Saniyede birkaç kez güncellenen ilerleme için AYRI bir bildirim kanalı.
  /// Böylece konum değişimi tüm ekranı (özellikle binlerce satırlık listeyi)
  /// yeniden çizmez; sadece ilerleme çubuğu güncellenir. (Kasma çözümü.)
  final ValueNotifier<Duration> position = ValueNotifier(Duration.zero);

  /// Karışık çalma açılmadan önceki sıra (kapatınca geri dönmek için).
  List<SongInfo>? _savedOrder;

  /// Ekrandaki ses çubuklarının bağlanacağı Android ses oturumu kimliği.
  int? _androidSessionId;
  int? _midiSessionId;

  Timer? _midiTicker;
  Timer? _mediaTicker;
  bool _initialized = false;
  bool _busy = false;
  bool _askedNotificationPermission = false;

  // ------------------------------------------------------------------ getters

  List<SongInfo> get queue => List<SongInfo>.unmodifiable(_queue);
  int get queueLength => _queue.length;
  SongInfo songAt(int i) => _queue[i];
  int get index => _index;
  bool get isPlaying => _isPlaying;
  bool get shuffle => _shuffle;
  RepeatMode get repeat => _repeat;
  double get volume => _volume;
  Duration get progress => _progress;
  Duration get total => _total;
  bool get isEmpty => _queue.isEmpty;
  bool get isMuted => _volume <= 0.001;

  SongInfo? get current =>
      (_index >= 0 && _index < _queue.length) ? _queue[_index] : null;

  /// Geçerli parçanın sıra numarası (1 tabanlı); yoksa 0.
  int get nowPlayingNumber => _index >= 0 ? _index + 1 : 0;

  bool get _currentIsMidi {
    final c = current;
    return c != null && c.isMidi;
  }

  /// Çalan parçanın Android ses oturumu kimliği (görselleştirici için).
  /// Bilinmiyorsa `null` döner.
  int? get androidAudioSessionId =>
      _currentIsMidi ? _midiSessionId : _androidSessionId;

  // -------------------------------------------------------------------- init

  void init() {
    if (_initialized) return;
    _initialized = true;

    _audio.positionStream.listen((p) {
      if (_currentIsMidi) return;
      _progress = p;
      if (position.value != p) position.value = p;
    });

    _audio.durationStream.listen((d) {
      if (_currentIsMidi || d == null) return;
      _total = d;
      notifyListeners();
    });

    _audio.playerStateStream.listen((state) {
      if (_currentIsMidi) return;
      final playing =
          state.playing && state.processingState != ProcessingState.completed;
      if (playing != _isPlaying) {
        _isPlaying = playing;
        notifyListeners();
      }
      if (state.processingState == ProcessingState.completed) {
        _onCompleted();
      }
    });

    _midi.events.listen((event) {
      if (event == 'completed') _onCompleted();
    });

    // Parça değişince ExoPlayer yeni bir ses oturumu açar; görselleştiricinin
    // yeni oturuma bağlanabilmesi için dinleyicilere haber ver.
    _audio.androidAudioSessionIdStream.listen((id) {
      if (id == null || id == _androidSessionId) return;
      _androidSessionId = id;
      notifyListeners();
    });

    // Bildirim paneli: durum değişimlerinde anında, çalarken konumu saniyede
    // bir tazele (medya panelindeki ilerleme çubuğu için).
    _media.bind();
    _media.onAction = _onMediaAction;
    addListener(_syncMediaNotification);
    _mediaTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_isPlaying) _syncMediaNotification();
    });
  }

  /// Bildirimdeki düğmelerden gelen komutları uygular.
  Future<void> _onMediaAction(String action) async {
    if (action.startsWith('seek:')) {
      final ms = int.tryParse(action.substring(5));
      if (ms != null) await seek(Duration(milliseconds: ms));
      return;
    }
    switch (action) {
      case 'play':
        if (!_isPlaying) await togglePlayPause();
      case 'pause':
        if (_isPlaying) await togglePlayPause();
      case 'toggle':
        await togglePlayPause();
      case 'next':
        await next();
      case 'previous':
        await previous();
      case 'stop':
        if (_isPlaying) await togglePlayPause();
        _media.stop();
    }
  }

  /// Bildirim panelindeki içeriği günceller (şarkı, durum, ilerleme).
  void _syncMediaNotification() {
    final song = current;
    if (song == null) {
      _media.stop();
      return;
    }
    // Bildirim izni ilk çalmada bir kez istenir (kullanıcı müziği başlatınca).
    if (_isPlaying && !_askedNotificationPermission) {
      _askedNotificationPermission = true;
      _media.requestPermission();
    }
    final hasNext = _index + 1 < _queue.length || _repeat == RepeatMode.all;
    _media.update(
      title: song.title,
      artist: _notificationArtist(song),
      playing: _isPlaying,
      positionMs: position.value.inMilliseconds,
      durationMs: _total.inMilliseconds,
      hasNext: hasNext,
      hasPrev: _index > 0,
    );
  }

  /// Bildirimde gösterilecek sanatçı adı. MediaStore bilinmeyenler için
  /// `<unknown>` yazdığından o değer yerine albüm adı (varsa) kullanılır.
  String _notificationArtist(SongInfo song) {
    final artist = song.artist.trim();
    final unknown = artist.isEmpty ||
        artist == '<unknown>' ||
        artist.toLowerCase() == 'unknown';
    if (!unknown) return artist;
    final album = song.album?.trim() ?? '';
    return album.isEmpty ? '' : album;
  }

  // --------------------------------------------------------------- oynatma

  Future<void> playAt(int i) async {
    if (i < 0 || i >= _queue.length) return;
    final song = _queue[i];
    if (song.uri.isEmpty) return;

    _index = i;
    _progress = Duration.zero;
    _total = Duration.zero;
    position.value = Duration.zero;
    notifyListeners();

    try {
      if (song.isMidi) {
        _stopMidiTicker();
        await _audio.stop();
        final ok = await _midi.play(song.uri);
        if (!ok) {
          _isPlaying = false;
          notifyListeners();
          return;
        }
        await _midi.setVolume(_volume);
        _midiSessionId = await _midi.audioSessionId();
        _isPlaying = true;
        _startMidiTicker();
        notifyListeners();
      } else {
        _stopMidiTicker();
        await _midi.stop();
        await _audio.setUrl(song.uri);
        await _audio.setVolume(_volume);
        await _audio.play();
        _isPlaying = true;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Şarkı çalınamadı: $e');
      _isPlaying = false;
      notifyListeners();
    }
  }

  Future<void> togglePlayPause() async {
    if (_queue.isEmpty) return;
    if (_index < 0) {
      await playAt(0);
      return;
    }

    if (_currentIsMidi) {
      if (_isPlaying) {
        await _midi.pause();
        _isPlaying = false;
        _stopMidiTicker();
      } else {
        await _midi.resume();
        _isPlaying = true;
        _startMidiTicker();
      }
      notifyListeners();
      return;
    }

    if (_audio.playing) {
      await _audio.pause();
    } else {
      if (_audio.processingState == ProcessingState.completed) {
        await playAt(_index);
        return;
      }
      await _audio.play();
    }
  }

  int? _nextIndex() {
    if (_queue.isEmpty) return null;
    // Karışık çalma açıkken kuyruk fiziksel olarak karıştırıldığı için
    // sıradaki parça her zaman _index + 1'dir.
    if (_index + 1 < _queue.length) return _index + 1;
    if (_repeat == RepeatMode.all) return 0;
    return null;
  }

  Future<void> next() async {
    final i = _nextIndex();
    if (i != null) await playAt(i);
  }

  Future<void> previous() async {
    if (_queue.isEmpty) return;
    if (_progress.inSeconds > 3) {
      await seek(Duration.zero);
      return;
    }
    if (_index > 0) {
      await playAt(_index - 1);
    } else if (_repeat == RepeatMode.all && _queue.isNotEmpty) {
      await playAt(_queue.length - 1);
    }
  }

  Future<void> seek(Duration position) async {
    if (_currentIsMidi) {
      final ms = position.inMilliseconds;
      if (ms < 0) return;
      await _midi.seek(ms);
      _progress = position;
      this.position.value = position;
      return;
    }
    try {
      await _audio.seek(position);
    } catch (_) {}
  }

  /// Parça bittiğinde sıradakine geçer (tekrar/karıştırma kurallarına göre).
  Future<void> _onCompleted() async {
    if (_busy) return;
    _busy = true;
    try {
      if (_repeat == RepeatMode.one) {
        await playAt(_index);
        return;
      }
      final i = _nextIndex();
      if (i == null) {
        _isPlaying = false;
        _stopMidiTicker();
        notifyListeners();
        return;
      }
      await playAt(i);
    } finally {
      _busy = false;
    }
  }

  // ------------------------------------------------------------------- ses

  Future<void> setVolume(double v) async {
    _volume = v.clamp(0.0, 1.0);
    try {
      await _audio.setVolume(_volume);
    } catch (_) {}
    if (_currentIsMidi) await _midi.setVolume(_volume);
    notifyListeners();
  }

  Future<void> toggleMute() => setVolume(isMuted ? 1.0 : 0.0);

  // ------------------------------------------------------------ karıştır/tekrar

  void setShuffle(bool value) {
    if (_shuffle == value) return;
    _shuffle = value;
    if (value) {
      // Karışıktan önceki sırayı sakla; kapatınca geri döneceğiz.
      _savedOrder = List<SongInfo>.from(_queue);
      _applyShuffleOrder();
    } else {
      _restoreSavedOrder();
    }
    notifyListeners();
  }

  /// Kuyruğu fiziksel olarak karıştırır; çalan parça en başta kalır.
  /// Böylece "sıradaki şarkılar" listesi gerçek karışık çalma sırasını gösterir.
  void _applyShuffleOrder() {
    final cur = current;
    _shuffleOrderKeeping(cur);
    _index = cur != null ? 0 : -1;
  }

  /// Kuyruğu karıştırır ama [keep] parçasını (varsa) en başta tutar.
  void _shuffleOrderKeeping(SongInfo? keep) {
    if (_queue.length < 2) return;
    final rest = List<SongInfo>.from(_queue);
    if (keep != null) rest.remove(keep);
    rest.shuffle(math.Random());
    _queue
      ..clear()
      ..addAll(<SongInfo>[
        if (keep != null) keep,
        ...rest,
      ]);
  }

  /// Karışık kapatılınca saklanan özgün sıraya döner; çalan parça korunur.
  void _restoreSavedOrder() {
    final saved = _savedOrder;
    _savedOrder = null;
    if (saved == null || _queue.isEmpty) return;
    final cur = current;
    final currentItems = List<SongInfo>.from(_queue);
    final restored = <SongInfo>[];
    for (final s in saved) {
      if (currentItems.contains(s)) restored.add(s);
    }
    for (final s in currentItems) {
      if (!restored.contains(s)) restored.add(s);
    }
    _queue
      ..clear()
      ..addAll(restored);
    _index = cur != null ? _queue.indexOf(cur) : -1;
  }

  /// Kuyruğu verilen ölçüte göre sıralar; çalan parça seçili kalır.
  void sortQueue(QueueSort field, {bool ascending = true}) {
    if (_queue.length < 2) return;
    final cur = current;

    int compare(SongInfo a, SongInfo b) {
      final int r;
      switch (field) {
        case QueueSort.name:
          r = a.title.toLowerCase().compareTo(b.title.toLowerCase());
        case QueueSort.duration:
          r = a.durationMs.compareTo(b.durationMs);
        case QueueSort.date:
          r = a.dateAdded.compareTo(b.dateAdded);
      }
      return ascending ? r : -r;
    }

    _queue.sort(compare);
    // Açık bir sıralama, karışık çalmayı geçersiz kılar; listeyi gösterilen
    // sırayla çalmak için karışığı kapat.
    _shuffle = false;
    _savedOrder = null;
    _index = cur != null ? _queue.indexOf(cur) : _index;
    notifyListeners();
  }

  void cycleRepeat() {
    _repeat = switch (_repeat) {
      RepeatMode.off => RepeatMode.all,
      RepeatMode.all => RepeatMode.one,
      RepeatMode.one => RepeatMode.off,
    };
    notifyListeners();
  }

  // ----------------------------------------------------------------- kuyruk

  /// Şarkıyı kuyruğa ekler. Zaten sıradaysa eklenmez (`false` döner).
  ///
  /// Kuyrukta aynı şarkı iki kez bulunmaz; böylece sürükle-bırak sıralaması
  /// için her satırın benzersiz bir anahtarı olur.
  bool enqueue(SongInfo song) {
    if (_queue.any((s) => s.id == song.id)) return false;
    _queue.add(song);
    notifyListeners();
    if (_index < 0) playAt(_queue.length - 1);
    return true;
  }

  /// Birden çok şarkıyı kuyruğa ekler; eklenen (yeni) şarkı sayısını döner.
  int enqueueAll(Iterable<SongInfo> songs) {
    final existing = _queue.map((s) => s.id).toSet();
    final fresh = <SongInfo>[];
    for (final s in songs) {
      if (existing.add(s.id)) fresh.add(s);
    }
    if (fresh.isEmpty) return 0;
    _queue.addAll(fresh);
    notifyListeners();
    if (_index < 0) playAt(0);
    return fresh.length;
  }

  /// Geçerli parçanın hemen ardına ekler (sıradaki yap).
  void playNext(SongInfo song) {
    if (_index < 0) {
      enqueue(song);
      return;
    }
    final existing = _queue.indexWhere((s) => s.id == song.id);
    if (existing >= 0) {
      _queue.removeAt(existing);
      if (existing < _index) _index -= 1;
    }
    _queue.insert((_index + 1).clamp(0, _queue.length), song);
    notifyListeners();
  }

  Future<void> removeAt(int i) async {
    if (i < 0 || i >= _queue.length) return;
    final wasCurrent = i == _index;
    _queue.removeAt(i);

    if (_queue.isEmpty) {
      _index = -1;
      _isPlaying = false;
      _progress = Duration.zero;
      _total = Duration.zero;
      _stopMidiTicker();
      try {
        await _audio.stop();
      } catch (_) {}
      await _midi.stop();
      notifyListeners();
      return;
    }

    if (i < _index) {
      _index--;
    } else if (wasCurrent) {
      if (_index >= _queue.length) _index = _queue.length - 1;
      await playAt(_index);
      return;
    }
    notifyListeners();
  }

  /// Sürükle-bırak ile çalma sırasını değiştirir.
  ///
  /// [newIndex], `SliverReorderableList`'in verdiği "bu indeksin önüne ekle"
  /// değeridir; burada gerekli düzeltme yapılır.
  void reorder(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= _queue.length) return;
    var target = newIndex;
    if (target > oldIndex) target -= 1;
    if (target < 0) target = 0;
    if (target >= _queue.length) target = _queue.length - 1;
    if (target == oldIndex) return;

    final song = _queue.removeAt(oldIndex);
    _queue.insert(target, song);

    // Çalan parçanın konumunu koru.
    if (_index == oldIndex) {
      _index = target;
    } else {
      var cur = _index;
      if (oldIndex < cur) cur -= 1;
      if (target <= cur) cur += 1;
      _index = cur;
    }
    notifyListeners();
  }

  /// Kuyruğu tamamen değiştirir ve [startAt]'ten çalmaya başlar.
  /// [autoPlay] false ise kuyruk yüklenir ama çalma başlamaz
  /// (açılışta yerel müzikleri göstermek için kullanılır).
  Future<void> setQueue(
    List<SongInfo> songs, {
    int startAt = 0,
    bool autoPlay = true,
  }) async {
    _queue
      ..clear()
      ..addAll(_dedupe(songs));
    _index = -1;
    _savedOrder = null;

    var target = _queue.isEmpty ? -1 : startAt.clamp(0, _queue.length - 1);

    if (_shuffle) {
      // Karışık açıkken yeni kuyruğa da karışık sıra uygula; istenen şarkıyı
      // başa al ki kullanıcının dokunduğu/başlatmak istediği parça çalsın.
      _savedOrder = List<SongInfo>.from(_queue);
      final startSong = target >= 0 ? _queue[target] : null;
      _shuffleOrderKeeping(startSong);
      target = startSong != null ? 0 : -1;
    }

    notifyListeners();
    if (_queue.isEmpty) {
      await clearQueue();
      return;
    }
    if (!autoPlay) return;
    await playAt(target < 0 ? 0 : target);
  }

  /// Aynı şarkının birden çok kez eklenmesini engeller (sürükle-bırak
  /// sıralaması için her satırın benzersiz anahtarı olması gerekir).
  static List<SongInfo> _dedupe(Iterable<SongInfo> songs) {
    final seen = <int>{};
    final out = <SongInfo>[];
    for (final s in songs) {
      if (seen.add(s.id)) out.add(s);
    }
    return out;
  }

  /// Kuyruğu çalmadan yükler (açılışta yerel müzik listesi için).
  Future<void> loadQueue(List<SongInfo> songs) =>
      setQueue(songs, autoPlay: false);

  Future<void> clearQueue() async {
    _queue.clear();
    _index = -1;
    _savedOrder = null;
    _isPlaying = false;
    _progress = Duration.zero;
    _total = Duration.zero;
    position.value = Duration.zero;
    _stopMidiTicker();
    try {
      await _audio.stop();
    } catch (_) {}
    await _midi.stop();
    notifyListeners();
  }

  // ------------------------------------------------------------ çıkış aygıtı

  Future<List<AudioOutput>> audioOutputs() => _fileIo.audioOutputs();

  // ------------------------------------------------------------------ MIDI

  void _startMidiTicker() {
    _midiTicker?.cancel();
    _midiTicker = Timer.periodic(const Duration(milliseconds: 500), (_) async {
      if (!_currentIsMidi) return;
      final pos = await _midi.position();
      final dur = await _midi.duration();
      var changed = false;
      if (pos != null && pos != _progress.inMilliseconds) {
        _progress = Duration(milliseconds: pos);
        changed = true;
      }
      if (dur != null && dur > 0 && dur != _total.inMilliseconds) {
        _total = Duration(milliseconds: dur);
        changed = true;
      }
      if (pos != null && pos != position.value.inMilliseconds) {
        position.value = Duration(milliseconds: pos);
      }
      if (changed) notifyListeners();
    });
  }

  void _stopMidiTicker() {
    _midiTicker?.cancel();
    _midiTicker = null;
  }

  @override
  void dispose() {
    _stopMidiTicker();
    _mediaTicker?.cancel();
    _mediaTicker = null;
    removeListener(_syncMediaNotification);
    _media.onAction = null;
    _media.stop();
    super.dispose();
  }
}

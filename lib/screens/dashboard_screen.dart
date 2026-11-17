import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/network_link.dart';
import '../utils/system_metrics.dart';
import 'career_screen.dart';
import 'note_detail_screen.dart';

class DashboardScreen extends StatefulWidget {
  /// Bir alt ekrandan ana sekmeye geçmek için
  /// (0=Dashboard, 1=Notlar, 2=Takvim, 3=Player, 4=Kariyer).
  final void Function(int index)? onNavigate;

  const DashboardScreen({super.key, this.onNavigate});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _pinnedNotes = [];
  List<Map<String, dynamic>> _todayEvents = [];
  List<Map<String, dynamic>> _tomorrowEvents = [];
  bool _isLoading = true;

  String _currentTime = '';
  String _userName = 'BİLAL';
  Timer? _timer;

  // --- 2x2 ince sistem kartları için anlık metrikler ---
  SystemMetrics _metrics = const SystemMetrics();
  NetworkLink _networkLink = const NetworkLink();
  NetworkLink? _prevLink;
  DateTime _lastStatsAt = DateTime.now();
  double _downloadSpeed = 0; // bayt/saniye (TrafficStats farkından)
  Timer? _statsTimer;
  ConnectivityResult _connectivity = ConnectivityResult.none;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

  @override
  void initState() {
    super.initState();
    _loadUserName();
    // Saati initState icinde setState cagirmadan kur.
    _currentTime = _formatNow();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() => _currentTime = _formatNow());
      }
    });
    _initConnectivity();
    _refreshStats();
    _statsTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _refreshStats(),
    );
    _fetchDashboardData();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _statsTimer?.cancel();
    _connectivitySub?.cancel();
    super.dispose();
  }

  String _formatNow() {
    final now = DateTime.now();
    final hour = now.hour.toString().padLeft(2, '0');
    final minute = now.minute.toString().padLeft(2, '0');
    final second = now.second.toString().padLeft(2, '0');
    return '$hour:$minute:$second';
  }

  // --- Sistem metrikleri (RAM, depolama, ağ) ---

  Future<void> _initConnectivity() async {
    try {
      final result = await Connectivity().checkConnectivity();
      if (mounted) setState(() => _connectivity = _primaryResult(result));
    } catch (err) {
      debugPrint('Bağlantı durumu okunamadı: $err');
    }
    _connectivitySub = Connectivity().onConnectivityChanged.listen((result) {
      if (mounted) setState(() => _connectivity = _primaryResult(result));
    });
  }

  /// Birden fazla sonuç dönerse (ör. wifi + vpn) en anlamlısını seç.
  ConnectivityResult _primaryResult(List<ConnectivityResult> results) {
    if (results.isEmpty) return ConnectivityResult.none;
    for (final candidate in const [
      ConnectivityResult.wifi,
      ConnectivityResult.ethernet,
      ConnectivityResult.mobile,
      ConnectivityResult.vpn,
      ConnectivityResult.bluetooth,
    ]) {
      if (results.contains(candidate)) return candidate;
    }
    return results.first;
  }

  Future<void> _refreshStats() async {
    final metrics = await readSystemMetrics();
    final link = await readNetworkLink();
    if (!mounted) return;

    final now = DateTime.now();
    final elapsed = now.difference(_lastStatsAt).inMilliseconds / 1000.0;
    _lastStatsAt = now;

    final previous = _prevLink;
    if (previous != null && elapsed > 0) {
      final rxDelta = link.rxBytes - previous.rxBytes;
      // Sayaç sıfırlanırsa negatif çıkabilir.
      _downloadSpeed = rxDelta < 0 ? 0 : rxDelta / elapsed;
    }
    _prevLink = link;

    setState(() {
      _metrics = metrics;
      _networkLink = link;
    });
  }

  static const double _bytesPerGb = 1024 * 1024 * 1024;

  String _formatGb(int bytes) => (bytes / _bytesPerGb).toStringAsFixed(1);

  String _ramText() {
    if (_metrics.ramTotal <= 0) return '--';
    final used =
        (_metrics.ramTotal - _metrics.ramFree).clamp(0, _metrics.ramTotal);
    return '${_formatGb(used)} / ${_formatGb(_metrics.ramTotal)} GB';
  }

  String _storageText() {
    if (_metrics.storageTotal <= 0) return '--';
    final used = (_metrics.storageTotal - _metrics.storageFree)
        .clamp(0, _metrics.storageTotal);
    return '${_formatGb(used)} / ${_formatGb(_metrics.storageTotal)} GB';
  }

  String _formatSpeed(double bytesPerSec) {
    const kb = 1024.0;
    const mb = 1024.0 * 1024.0;
    if (bytesPerSec >= mb) {
      return '${(bytesPerSec / mb).toStringAsFixed(1)} MB/s';
    }
    if (bytesPerSec >= kb) {
      return '${(bytesPerSec / kb).toStringAsFixed(0)} KB/s';
    }
    return '${bytesPerSec.toStringAsFixed(0)} B/s';
  }

  String _networkValue() {
    if (_connectivity == ConnectivityResult.none &&
        _networkLink.type == 'none') {
      return 'Bağlantı yok';
    }
    // Tahmini bağlantı hızını öncelikli göster (Mbps).
    if (_networkLink.downMbps > 0.01) {
      final mbps = _networkLink.downMbps;
      return '↓ ${mbps.toStringAsFixed(mbps >= 100 ? 0 : 1)} Mbps';
    }
    // Link hızı bilinmiyorsa TrafficStats'ten anlık hız (B/s bazlı).
    if (_downloadSpeed > 0) {
      return '↓ ${_formatSpeed(_downloadSpeed)}';
    }
    return '—';
  }

  String _networkLabel() {
    // Kanalın döndürdüğü type'ı öncelik ver; yoksa connectivity sonucu.
    final t = _networkLink.type;
    switch (t) {
      case 'wifi':
        return 'Wİ-Fİ';
      case 'ethernet':
        return 'KABLOLU';
      case 'mobile':
        return 'MOBİL VERİ';
      case 'vpn':
        return 'VPN';
      default:
        break;
    }
    switch (_connectivity) {
      case ConnectivityResult.wifi:
        return 'Wİ-Fİ';
      case ConnectivityResult.ethernet:
        return 'KABLOLU';
      case ConnectivityResult.mobile:
        return 'MOBİL VERİ';
      case ConnectivityResult.vpn:
        return 'VPN';
      case ConnectivityResult.bluetooth:
        return 'BLUETOOTH';
      case ConnectivityResult.none:
        return 'ÇEVRİMDIŞI';
      default:
        return 'AĞ';
    }
  }

  IconData _networkIcon() {
    final t = _networkLink.type;
    if (t == 'wifi') return Icons.wifi_rounded;
    if (t == 'ethernet') return Icons.settings_ethernet_rounded;
    if (t == 'mobile') return Icons.signal_cellular_alt_rounded;
    if (t == 'vpn') return Icons.vpn_lock_rounded;

    switch (_connectivity) {
      case ConnectivityResult.wifi:
        return Icons.wifi_rounded;
      case ConnectivityResult.ethernet:
        return Icons.settings_ethernet_rounded;
      case ConnectivityResult.mobile:
        return Icons.signal_cellular_alt_rounded;
      case ConnectivityResult.vpn:
        return Icons.vpn_lock_rounded;
      case ConnectivityResult.bluetooth:
        return Icons.bluetooth_rounded;
      case ConnectivityResult.none:
        return Icons.wifi_off_rounded;
      default:
        return Icons.public_rounded;
    }
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour >= 6 && hour < 12) return 'GÜNAYDIN';
    if (hour >= 12 && hour < 18) return 'İYİ GÜNLER';
    if (hour >= 18 && hour < 22) return 'İYİ AKŞAMLAR';
    return 'İYİ GECELER';
  }

  Future<void> _loadUserName() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString('user_display_name');
      if (saved != null && saved.trim().isNotEmpty && mounted) {
        setState(() => _userName = saved.trim().toUpperCase());
      }
    } catch (err) {
      debugPrint('Kullanıcı adı okunamadı: $err');
    }
  }

  Future<void> _saveUserName(String newName) async {
    final trimmed = newName.trim();
    if (trimmed.isEmpty) return;
    final upper = trimmed.toUpperCase();

    // Önce arayüzü güncelle, kayıt başarısız olsa bile isim görünsün.
    if (mounted) setState(() => _userName = upper);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_display_name', upper);
    } catch (err) {
      debugPrint('Kullanıcı adı kaydedilemedi: $err');
    }
  }

  Future<void> _showEditNameDialog() async {
    final controller = TextEditingController(text: _userName);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161B22),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Colors.white12),
        ),
        title: const Text(
          'Kullanıcı Adını Değiştir',
          style: TextStyle(color: Colors.white, fontSize: 16),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Adını gir...',
            hintStyle: const TextStyle(color: Colors.grey),
            filled: true,
            fillColor: const Color(0xFF0D1117),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('İptal', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
            ),
            onPressed: () {
              _saveUserName(controller.text);
              Navigator.pop(ctx);
            },
            child: const Text('Kaydet',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    controller.dispose();
  }

  Future<void> _fetchDashboardData() async {
    try {
      // 1. Sabitlenmiş notları çek
      final notesResp = await supabase
          .from('notes')
          .select()
          .eq('pinned', true)
          .order('updated_at', ascending: false);

      // 2. Takvim etkinliklerini çek ve bugün/yarın olarak ayır
      final eventsResp = await supabase
          .from('calendar_events')
          .select()
          .order('id', ascending: true);

      final now = DateTime.now();
      final tomorrow = now.add(const Duration(days: 1));

      final todayKey = '${now.year}-${now.month}-${now.day}';
      final tomorrowKey = '${tomorrow.year}-${tomorrow.month}-${tomorrow.day}';

      final allEvents = List<Map<String, dynamic>>.from(eventsResp);
      final todayList =
          allEvents.where((e) => e['event_date'] == todayKey).toList();
      final tomorrowList =
          allEvents.where((e) => e['event_date'] == tomorrowKey).toList();

      if (mounted) {
        setState(() {
          _pinnedNotes = List<Map<String, dynamic>>.from(notesResp);
          _todayEvents = todayList;
          _tomorrowEvents = tomorrowList;
          _isLoading = false;
        });
      }
    } catch (err) {
      debugPrint('Dashboard verileri çekilemedi: $err');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _formatDateHeader() {
    final now = DateTime.now();
    const months = [
      'Ocak',
      'Şubat',
      'Mart',
      'Nisan',
      'Mayıs',
      'Haziran',
      'Temmuz',
      'Ağustos',
      'Eylül',
      'Ekim',
      'Kasım',
      'Aralık'
    ];
    const days = [
      'Pazartesi',
      'Salı',
      'Çarşamba',
      'Perşembe',
      'Cuma',
      'Cumartesi',
      'Pazar'
    ];
    return '${now.day} ${months[now.month - 1]} ${now.year}, '
        '${days[now.weekday - 1]}';
  }

  Future<void> _logout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161B22),
        title: const Text('Çıkış yap', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Hesabından çıkmak istediğine emin misin?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child:
                const Text('Çıkış', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await supabase.auth.signOut();
    } catch (err) {
      debugPrint('Çıkış yapılamadı: $err');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Çıkış yapılamadı.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _fetchDashboardData,
          color: Colors.white,
          backgroundColor: const Color(0xFF161B22),
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Üst Header (Dinamik Mesaj ve İsim)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          GestureDetector(
                            onTap: _showEditNameDialog,
                            behavior: HitTestBehavior.opaque,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '${_getGreeting()}, $_userName',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    letterSpacing: 1.5,
                                    color: Colors.grey,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                const Icon(
                                  Icons.edit_outlined,
                                  color: Colors.grey,
                                  size: 13,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Bugün ne yapıyoruz?',
                            style: TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _formatDateHeader(),
                            style: const TextStyle(
                              fontSize: 13,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Row(
                      children: [
                        GestureDetector(
                          onTap: () => widget.onNavigate?.call(2),
                          behavior: HitTestBehavior.opaque,
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Container(
                                height: 50,
                                width: 50,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF161B22),
                                  borderRadius: BorderRadius.circular(18),
                                  border: Border.all(color: Colors.white12),
                                ),
                                child: const Icon(
                                  Icons.notifications_none_rounded,
                                  color: Colors.white,
                                  size: 24,
                                ),
                              ),
                              if (_todayEvents.isNotEmpty)
                                Positioned(
                                  right: 4,
                                  top: 4,
                                  child: Container(
                                    padding: const EdgeInsets.all(5),
                                    decoration: const BoxDecoration(
                                      color: Colors.redAccent,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Text(
                                      '${_todayEvents.length}',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        GestureDetector(
                          onTap: _logout,
                          child: Container(
                            height: 50,
                            width: 50,
                            decoration: BoxDecoration(
                              color: const Color(0xFF161B22),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(color: Colors.white12),
                            ),
                            child: const Icon(
                              Icons.logout_rounded,
                              color: Colors.white,
                              size: 22,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // --- 1. PLANLAR BÖLÜMÜ (Bugün & Yarın) ---
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Planlar (Bugün & Yarın)',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    GestureDetector(
                      onTap: () => widget.onNavigate?.call(2),
                      behavior: HitTestBehavior.opaque,
                      child: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 6),
                        child: Text(
                          'Takvimi aç',
                          style: TextStyle(color: Colors.grey, fontSize: 13),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                if (_isLoading)
                  const Center(
                      child: CircularProgressIndicator(color: Colors.white))
                else ...[
                  // Bugün Başlığı ve Etkinlikleri
                  const Text(
                    '• Bugün',
                    style: TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  if (_todayEvents.isEmpty)
                    _buildEmptyBox('Bugün için plan bulunmuyor.')
                  else
                    ..._todayEvents.map((e) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _buildPlanItemCard(
                            dotColor: Colors.white,
                            title: (e['title'] ?? '').toString(),
                            subtitle: 'Bugün — Planlayıcı',
                            onTap: () => widget.onNavigate?.call(2),
                          ),
                        )),
                  const SizedBox(height: 14),

                  // Yarın Başlığı ve Etkinlikleri
                  const Text(
                    '• Yarın',
                    style: TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  if (_tomorrowEvents.isEmpty)
                    _buildEmptyBox('Yarın için plan bulunmuyor.')
                  else
                    ..._tomorrowEvents.map((e) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _buildPlanItemCard(
                            dotColor: Colors.grey,
                            title: (e['title'] ?? '').toString(),
                            subtitle: 'Yarın — Planlayıcı',
                            onTap: () => widget.onNavigate?.call(2),
                          ),
                        )),
                ],
                const SizedBox(height: 20),

                // --- ATS UYGUNLUK KISAYOLU ---
                _buildAtsCard(),
                const SizedBox(height: 24),

                // --- 2. SABİTLENMİŞ NOTLAR BÖLÜMÜ ---
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Sabitlenmiş notlar',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    GestureDetector(
                      onTap: () => widget.onNavigate?.call(1),
                      behavior: HitTestBehavior.opaque,
                      child: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 6),
                        child: Text(
                          'Tümünü gör',
                          style: TextStyle(color: Colors.grey, fontSize: 13),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                if (_pinnedNotes.isEmpty)
                  const Text(
                    'Sabitlenmiş not bulunmuyor.',
                    style: TextStyle(color: Colors.grey, fontSize: 13),
                  )
                else
                  ..._pinnedNotes.map((note) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _buildPinnedNoteCard(
                          title: (note['title'] ?? 'İsimsiz Not').toString(),
                          subtitle: 'Önemli · #${(note['tag'] ?? 'genel')}',
                          onTap: () => _openNote(note),
                        ),
                      )),
                const SizedBox(height: 24),

                // --- 3. SİSTEM DURUMU (2x2 ince kartlar: ağ, bellek, depolama, saat) ---
                Row(
                  children: [
                    Expanded(
                      child: _buildStatCard(
                        icon: _networkIcon(),
                        label: _networkLabel(),
                        value: _networkValue(),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildStatCard(
                        icon: Icons.memory_rounded,
                        label: 'BELLEK',
                        value: _ramText(),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _buildStatCard(
                        icon: Icons.storage_rounded,
                        label: 'DEPOLAMA',
                        value: _storageText(),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildStatCard(
                        icon: Icons.access_time_rounded,
                        value: _currentTime,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAtsCard() {
    return GestureDetector(
      onTap: () {
        widget.onNavigate?.call(4);
        CareerScreen.requestAtsCheck();
      },
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF1B2A3A), Color(0xFF161B22)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: const Color(0xFF38BDF8).withValues(alpha: 0.35),
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF38BDF8).withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(
                Icons.fact_check_outlined,
                color: Color(0xFF38BDF8),
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'ATS Uygunluk İncelemesi',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    "CV'ni puanla, eksik alanları ve anahtar kelimeleri gör.",
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: 11.5,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.arrow_forward_ios_rounded,
              color: Colors.grey,
              size: 15,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyBox(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white12),
      ),
      child: Text(
        text,
        style: const TextStyle(color: Colors.grey, fontSize: 12),
      ),
    );
  }

  /// İnce (kare olmayan) tek sistem kartı: ikon + değer (+ küçük etiket).
  Widget _buildStatCard({
    required IconData icon,
    required String value,
    String? label,
  }) {
    final hasLabel = label != null && label.isNotEmpty;
    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.white70, size: 16),
          const SizedBox(width: 10),
          Expanded(
            child: hasLabel
                ? Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 9,
                          letterSpacing: 0.8,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  )
                : Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.0,
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  /// Sabitlenmiş nota dokununca detay ekranını açar.
  void _openNote(Map<String, dynamic> note) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => NoteDetailScreen(
          noteId: note['id'].toString(),
          initialTitle: (note['title'] ?? '').toString(),
          initialContent: (note['content'] ?? '').toString(),
          initialTag: (note['tag'] ?? 'genel').toString(),
        ),
      ),
    ).then((_) {
      if (mounted) _fetchDashboardData();
    });
  }

  Widget _buildPinnedNoteCard({
    required String title,
    required String subtitle,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF161B22),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white12),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white10,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(
                Icons.sell_outlined,
                color: Colors.white,
                size: 20,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: Colors.grey,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.arrow_forward_ios_rounded,
              color: Colors.grey,
              size: 16,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlanItemCard({
    required Color dotColor,
    required String title,
    required String subtitle,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF161B22),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white12),
        ),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: dotColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: Colors.grey,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              height: 34,
              width: 34,
              decoration: BoxDecoration(
                color: Colors.white10,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.chevron_right,
                color: Colors.white,
                size: 18,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'screens/calendar_screen.dart';
import 'screens/career_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/login_screen.dart';
import 'screens/notes_screen.dart';
import 'screens/player_screen.dart';
import 'utils/home_widget_util.dart';

/// Bildirim, paylaş menüsü ve kısayoldan gelen hızlı not isteklerinin kanalı
/// (Kotlin tarafındaki `QuickNoteBridge.CHANNEL` ile aynı olmalı).
const MethodChannel _quickNoteChannel =
    MethodChannel('ultimate_mobile/quick_note');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Hızlı not isteklerini erkenden yakala: süreç soğuk başlatıldığında bile
  // bildirim/paylaşım isteği ilk kareyi beklemeden karşılanır.
  _quickNoteChannel.setMethodCallHandler(_handleQuickNoteCall);

  // Masaüstü ile ortak Supabase bilgileri
  await Supabase.initialize(
    url: 'https://imkdfbdcpthzmnqgftfl.supabase.co', // Proje URL'niz
    publishableKey:
        'sb_publishable_TCFxyDJD2PK-Oeb_8ayDVQ_G19jZHck', // Publishable Key
  );

  runApp(const UltimateApp());
}

/// Bildirimden (RemoteInput), paylaş menüsünden veya simge kısayolundan gelen
/// hızlı not isteklerini işler. Kotlin tarafı yanıt olarak `{ok: bool}` bekler.
Future<Map<String, Object?>> _handleQuickNoteCall(MethodCall call) async {
  switch (call.method) {
    case 'save':
      final args = (call.arguments as Map?)?.cast<String, dynamic>() ?? {};
      final text = (args['text'] ?? '').toString();
      final open = args['open'] == true;
      final saved = await _insertQuickNote(text);
      if (saved && open) {
        // Paylaşımdan geldiyse kullanıcıyı Notlar'da karşıla.
        MainLayoutScreen.goToTab(1);
      }
      return {'ok': saved};

    case 'openNew':
      MainLayoutScreen.goToTab(1);
      NotesScreen.requestQuickNewNote();
      return {'ok': true};
  }
  return {'ok': false};
}

/// Hızlı notu doğrudan Supabase'e ekler; başarı durumunu döner.
Future<bool> _insertQuickNote(String raw) async {
  final text = raw.trim();
  if (text.isEmpty) return false;
  try {
    await Supabase.instance.client.from('notes').insert({
      'id': DateTime.now().microsecondsSinceEpoch.toString(),
      'title': _quickNoteTitle(text),
      'content': text,
      'tag': 'genel',
      'pinned': false,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    });
    return true;
  } catch (err) {
    debugPrint('Hızlı not kaydedilemedi: $err');
    return false;
  }
}

/// Başlığı notun ilk dolu satırından üretir (yoksa "Hızlı Not").
String _quickNoteTitle(String text) {
  final firstLine = text
      .split('\n')
      .map((line) => line.trim())
      .firstWhere((line) => line.isNotEmpty, orElse: () => '');
  if (firstLine.isEmpty) return 'Hızlı Not';
  return firstLine.length <= 40 ? firstLine : '${firstLine.substring(0, 40)}…';
}

class UltimateApp extends StatelessWidget {
  const UltimateApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ultimate Asistan',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor:
            const Color(0xFF0D1117), // Ekranlardaki koyu ton
        cardColor: const Color(0xFF161B22),
        primaryColor: Colors.white,
        colorScheme: const ColorScheme.dark(
          primary: Colors.white,
          surface: Color(0xFF161B22),
        ),
        // Koyu arka planlı SnackBar'larda varsayılan metin rengi de koyu
        // kaldığı için mesajlar okunmuyordu; tüm bildirimleri beyaz metinle
        // göster.
        snackBarTheme: const SnackBarThemeData(
          backgroundColor: Color(0xFF161B22),
          contentTextStyle: TextStyle(color: Colors.white, fontSize: 13.5),
          actionTextColor: Colors.white,
        ),
        fontFamily: 'Segoe UI',
      ),
      home: const AuthGate(),
    );
  }
}

/// Oturum durumuna göre Login veya Ana Ekranı açan kapı (Auth Gate)
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _isAuthenticated = false;
  bool _isLoading = true;
  StreamSubscription<AuthState>? _authSubscription;

  @override
  void initState() {
    super.initState();
    _checkSession();
    _authSubscription =
        Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      final session = data.session;
      if (mounted) {
        setState(() {
          _isAuthenticated = session != null;
          _isLoading = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  Future<void> _checkSession() async {
    final session = Supabase.instance.client.auth.currentSession;
    if (mounted) {
      setState(() {
        _isAuthenticated = session != null;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFF0D1117),
        body: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }
    return _isAuthenticated ? const MainLayoutScreen() : const LoginScreen();
  }
}

class MainLayoutScreen extends StatefulWidget {
  const MainLayoutScreen({super.key});

  /// Alt menüdeki player (çalar) sekmesinin indeksi.
  static const int playerTab = 3;

  /// Alt menüdeki Notlar sekmesinin indeksi.
  static const int notesTab = 1;

  /// Alt menüdeki Takvim sekmesinin indeksi.
  static const int calendarTab = 2;

  /// Alt sayfalardan liste, bildirimden not, paylaşımdan not, widget'tan
  /// etkinlik gibi istekler için ana sekme yönlendiricisi.
  /// Yalnızca [_MainLayoutScreenState] yaşam döngüsü boyunca doludur.
  static void Function(int)? _jumpTo;

  /// Ekran hazır değilken (ör. soğuk başlangıçta paylaşımdan açılma) gelen
  /// sekme isteği burada tutulur ve ekran kurulunca uygulanır.
  static int? _pendingTab;

  /// Verilen alt menü sekmesine geçer; ana düzen henüz yüklenmediyse isteği
  /// saklar ve ekran kurulunca uygular.
  static void goToTab(int index) {
    final jump = _jumpTo;
    if (jump != null) {
      jump(index);
    } else {
      _pendingTab = index;
    }
  }

  @override
  State<MainLayoutScreen> createState() => _MainLayoutScreenState();
}

class _MainLayoutScreenState extends State<MainLayoutScreen> {
  int _currentIndex = 0;
  StreamSubscription<WidgetAction>? _widgetActionSub;

  // 5 Ana Ekranın Tümü Aktif Bağlı
  late final List<Widget> _screens = [
    DashboardScreen(onNavigate: _goToTab),
    const NotesScreen(),
    const CalendarScreen(),
    const PlayerScreen(),
    const CareerScreen(),
  ];

  /// Dashboard içindeki kısayolların ("Takvimi aç", "Tümünü gör", plan
  /// kartları) ilgili sekmeye geçebilmesi için.
  void _goToTab(int index) {
    if (index < 0 || index >= _screens.length) return;
    setState(() => _currentIndex = index);
  }

  @override
  void initState() {
    super.initState();
    MainLayoutScreen._jumpTo = _goToTab;
    // Ekran hazır değilken gelen sekme isteği varsa (soğuk başlangıçta
    // paylaşım/kısayol) burada uygula.
    final pendingTab = MainLayoutScreen._pendingTab;
    if (pendingTab != null) {
      MainLayoutScreen._pendingTab = null;
      if (pendingTab >= 0 && pendingTab < _screens.length) {
        _currentIndex = pendingTab;
      }
    }
    // Uygulama açılırken ana ekran widget'ını tazele (takvim sekmesi hiç
    // açılmasa bile "Yükleniyor..." yazısında kalmasın).
    refreshCalendarWidget();

    // Ana ekran widget'ı tıklamaları (mavi "+" / gün / yeşil not): uygulama
    // açıkken akıştan, kapalıyken başlangıç intent'inden tek noktadan dinlenir.
    // (home_widget'ın olay kanalının TEK sink'i vardır; iki abonelik açmak
    // ilkinin tıklamalarını yutardı.)
    _widgetActionSub = widgetActions.listen(_handleWidgetAction);
    initialWidgetAction().then((action) {
      if (action != null) _handleWidgetAction(action);
    });
  }

  /// Widget tıklaması -> ilgili sekmeye geç, günü aç / etkinlik ekle / not aç.
  void _handleWidgetAction(WidgetAction action) {
    if (!mounted) return;
    if (action.type == 'note') {
      _goToTab(MainLayoutScreen.notesTab);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        NotesScreen.requestQuickNewNote();
      });
      return;
    }
    _goToTab(MainLayoutScreen.calendarTab);
    // Sekme değişince Takvim ekranı (yeniden) kurulur; bir kare sonra işle.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (action.type == 'add') {
        CalendarScreen.openAddForDay(action.value);
      } else {
        CalendarScreen.openDateFor(action.value);
      }
    });
  }

  @override
  void dispose() {
    _widgetActionSub?.cancel();
    if (identical(MainLayoutScreen._jumpTo, _goToTab)) {
      MainLayoutScreen._jumpTo = null;
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Geri tuşu asla uygulamayı kapatmasın: başka sekmede basılırsa ana
    // Player sekmesine atlar, Player'da basılırsa hiçbir şey olmaz —
    // kullanıcı her zaman ana player'da kalır.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _currentIndex != MainLayoutScreen.playerTab) {
          _goToTab(MainLayoutScreen.playerTab);
        }
      },
      child: Scaffold(
        body: _screens[_currentIndex],
        bottomNavigationBar: Container(
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: Color(0x1FFFFFFF), width: 1)),
            color: Color(0xFF0D1117),
          ),
          child: BottomNavigationBar(
            currentIndex: _currentIndex,
            onTap: _goToTab,
            backgroundColor: Colors.transparent,
            type: BottomNavigationBarType.fixed,
            selectedItemColor: Colors.white,
            unselectedItemColor: Colors.grey,
            selectedFontSize: 11,
            unselectedFontSize: 11,
            items: const [
              BottomNavigationBarItem(
                  icon: Icon(Icons.dashboard_outlined), label: 'Dashboard'),
              BottomNavigationBarItem(
                  icon: Icon(Icons.note_alt_outlined), label: 'Notlar'),
              BottomNavigationBarItem(
                  icon: Icon(Icons.calendar_today_outlined), label: 'Takvim'),
              BottomNavigationBarItem(
                  icon: Icon(Icons.music_note_outlined), label: 'Player'),
              BottomNavigationBarItem(
                  icon: Icon(Icons.code_outlined), label: 'Kariyer'),
            ],
          ),
        ),
      ),
    );
  }
}

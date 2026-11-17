import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/home_widget_util.dart';

/// Supabase `calendar_events` tablosundaki bir satırı temsil eder.
///
/// Gerçek şema (masaüstü projedeki supabase/schema.sql):
///   id         bigint generated always as identity primary key
///   event_date text   not null   -> 'YYYY-M-D' (sıfır dolgusuz, ör. 2026-10-5)
///   title      text   not null
///   created_at timestamptz
///   user_id    uuid default auth.uid()
class CalendarEventModel {
  final int id;
  final String title;
  final String eventDate;

  CalendarEventModel({
    required this.id,
    required this.title,
    required this.eventDate,
  });

  factory CalendarEventModel.fromMap(Map<String, dynamic> map) {
    return CalendarEventModel(
      id: int.tryParse(map['id'].toString()) ?? 0,
      title: (map['title'] ?? '').toString(),
      eventDate: (map['event_date'] ?? '').toString(),
    );
  }
}

/// Masaüstü uygulamasıyla birebir aynı tarih anahtarı: 'YYYY-M-D' (sıfır dolgusuz).
String formatDateKey(DateTime date) => '${date.year}-${date.month}-${date.day}';

const List<String> _monthNames = [
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
  'Aralık',
];

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  /// Ana ekran widget'ındaki mavi "+" tıklanınca ilgili güne atlamak için.
  /// Yalnızca [_CalendarScreenState] yaşam döngüsü boyunca doludur.
  static void Function(String day)? _openAddForDay;

  /// Widget'tan gelen "+" için verilen günü seçip ekleme satırına odaklanır.
  /// Ekran yüklü değilse sessizce yoksayar.
  static void openAddForDay(String day) => _openAddForDay?.call(day);

  /// Widget'taki takvim hücresi tıklaması için verilen tarihe geçer
  /// ('2026-10-19' gibi). Ekran yüklü değilse sessizce yoksayar.
  static void Function(String date)? _openDateFor;
  static void openDateFor(String date) => _openDateFor?.call(date);

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  final supabase = Supabase.instance.client;
  List<CalendarEventModel> _events = [];
  bool _isLoading = true;
  DateTime _selectedDate = DateTime.now();
  late DateTime _displayedMonth;
  final TextEditingController _newEventController = TextEditingController();
  final FocusNode _newEventFocus = FocusNode();
  final ScrollController _scrollController = ScrollController();
  RealtimeChannel? _eventsChannel;

  @override
  void initState() {
    super.initState();
    _displayedMonth = DateTime(_selectedDate.year, _selectedDate.month, 1);
    CalendarScreen._openAddForDay = _openAddForDay;
    CalendarScreen._openDateFor = _openDateFor;
    _fetchEvents();
    _setupRealtime();
  }

  @override
  void dispose() {
    if (identical(CalendarScreen._openAddForDay, _openAddForDay)) {
      CalendarScreen._openAddForDay = null;
    }
    if (identical(CalendarScreen._openDateFor, _openDateFor)) {
      CalendarScreen._openDateFor = null;
    }
    if (_eventsChannel != null) supabase.removeChannel(_eventsChannel!);
    _newEventController.dispose();
    _newEventFocus.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// Widget'taki "+" tıklamasıyla ilgili güne geçer ve ekleme satırına
  /// odaklanıp klavyeyi açar; kullanıcı doğrudan başlığı yazabilir.
  /// Gelen değer 'today' / 'tomorrow' ya da 'yyyy-M-d' tarihi olabilir.
  void _openAddForDay(String day) {
    if (!mounted) return;
    final target = _resolveDay(day) ?? DateTime.now();
    setState(() {
      _selectedDate = target;
      _displayedMonth = DateTime(target.year, target.month, 1);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
      _newEventFocus.requestFocus();
      // Uygulama widget'tan yeni açıldığında sistem klavye açma isteğini
      // pencere geçişinde düşürebilir; odaktayken kısa süre sonra tekrar dene.
      Future<void>.delayed(const Duration(milliseconds: 350), () {
        if (!mounted || !_newEventFocus.hasFocus) return;
        SystemChannels.textInput.invokeMethod<void>('TextInput.show');
      });
    });
  }

  /// 'today' / 'tomorrow' / 'yyyy-M-d' -> DateTime; çözülemezse null.
  DateTime? _resolveDay(String day) {
    final now = DateTime.now();
    if (day == 'today') return now;
    if (day == 'tomorrow') return now.add(const Duration(days: 1));
    final parts = day.split('-');
    if (parts.length != 3) return null;
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final dayNum = int.tryParse(parts[2]);
    if (year == null || month == null || dayNum == null) return null;
    if (month < 1 || month > 12 || dayNum < 1 || dayNum > 31) return null;
    return DateTime(year, month, dayNum);
  }

  /// Widget'tan gelen tarih ('yyyy-M-d') -> o günü seçer, ayını gösterir ve
  /// günün etkinlik listesine kaydırır.
  void _openDateFor(String date) {
    if (!mounted) return;
    final parts = date.split('-');
    if (parts.length != 3) return;
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final day = int.tryParse(parts[2]);
    if (year == null || month == null || day == null) return;
    if (month < 1 || month > 12 || day < 1 || day > 31) return;
    final target = DateTime(year, month, day);
    setState(() {
      _selectedDate = target;
      _displayedMonth = DateTime(target.year, target.month, 1);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _fetchEvents() async {
    try {
      final response = await supabase
          .from('calendar_events')
          .select('id, event_date, title')
          .order('id', ascending: true);

      if (mounted) {
        setState(() {
          _events = (response as List)
              .map((e) => CalendarEventModel.fromMap(e))
              .toList();
          _isLoading = false;
        });
        _updateHomeWidget();
      }
    } catch (err) {
      debugPrint('Takvim etkinlikleri çekilemedi: $err');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _setupRealtime() {
    _eventsChannel = supabase
        .channel('public:calendar_events')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'calendar_events',
          callback: (_) => _fetchEvents(),
        )
        .subscribe();
  }

  Future<void> _updateHomeWidget() async {
    final now = DateTime.now();
    final todayKey = formatDateKey(now);
    final tomorrowKey = formatDateKey(now.add(const Duration(days: 1)));

    String summaryOf(String key, String emptyLabel) {
      final events = _events.where((e) => e.eventDate == key).toList();
      if (events.isEmpty) return emptyLabel;
      return events.map((e) => '• ${e.title}').join('\n');
    }

    await saveCalendarWidgetData(
      today: summaryOf(todayKey, 'Bugün etkinlik yok'),
      tomorrow: summaryOf(tomorrowKey, 'Yarın etkinlik yok'),
      // Yerel taraf bu listeyi o anki tarihe göre süzer; böylece uygulama
      // günlerce açılmasa da widget "BUGÜN"/"YARIN" için doğru kalır.
      upcoming: <Map<String, String>>[
        for (final e in _events)
          if (e.title.trim().isNotEmpty)
            <String, String>{'date': e.eventDate, 'title': e.title},
      ],
    );
    await refreshCalendarWidget();
  }

  Future<void> _addEvent() async {
    final title = _newEventController.text.trim();
    if (title.isEmpty) {
      _toast('Etkinlik başlığı boş olamaz.', error: true);
      return;
    }

    try {
      await supabase.from('calendar_events').insert({
        'event_date': formatDateKey(_selectedDate),
        'title': title,
      });
      _newEventController.clear();
      await _fetchEvents();
      _toast('Etkinlik eklendi.');
    } catch (err) {
      debugPrint('Etkinlik eklenemedi: $err');
      _toast('Etkinlik eklenemedi.', error: true);
    }
  }

  Future<void> _deleteEvent(CalendarEventModel event) async {
    try {
      await supabase.from('calendar_events').delete().eq('id', event.id);
      await _fetchEvents();
      _toast('Etkinlik silindi.');
    } catch (err) {
      debugPrint('Etkinlik silinemedi: $err');
      _toast('Etkinlik silinemedi.', error: true);
    }
  }

  Future<void> _confirmDelete(CalendarEventModel event) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161B22),
        title:
            const Text('Etkinliği sil', style: TextStyle(color: Colors.white)),
        content: Text(
          '"${event.title}" silinsin mi?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sil', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (ok == true) await _deleteEvent(event);
  }

  void _toast(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor:
              error ? const Color(0xFF7F1D1D) : const Color(0xFF161B22),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
  }

  void _changeMonth(int delta) {
    setState(() {
      _displayedMonth =
          DateTime(_displayedMonth.year, _displayedMonth.month + delta, 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    final selectedKey = formatDateKey(_selectedDate);
    final dayEvents = _events.where((e) => e.eventDate == selectedKey).toList();

    final firstDayOffset =
        DateTime(_displayedMonth.year, _displayedMonth.month, 1).weekday - 1;
    final daysInMonth =
        DateTime(_displayedMonth.year, _displayedMonth.month + 1, 0).day;

    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      resizeToAvoidBottomInset: true, // Klavye açıldığında taşmayı önler
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _fetchEvents,
          color: Colors.white,
          backgroundColor: const Color(0xFF161B22),
          child: SingleChildScrollView(
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Üst Başlık
                const Text(
                  'PLANLAYICI',
                  style: TextStyle(
                    fontSize: 11,
                    letterSpacing: 1.5,
                    color: Colors.grey,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Takvim',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 15),

                // Takvim Grid Kartı
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFF161B22),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.arrow_back,
                                color: Colors.white, size: 20),
                            onPressed: () => _changeMonth(-1),
                          ),
                          Text(
                            '${_monthNames[_displayedMonth.month - 1]} '
                                    '${_displayedMonth.year}'
                                .toUpperCase(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.2,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.arrow_forward,
                                color: Colors.white, size: 20),
                            onPressed: () => _changeMonth(1),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          Text('Pt',
                              style:
                                  TextStyle(color: Colors.grey, fontSize: 12)),
                          Text('Sa',
                              style:
                                  TextStyle(color: Colors.grey, fontSize: 12)),
                          Text('Ça',
                              style:
                                  TextStyle(color: Colors.grey, fontSize: 12)),
                          Text('Pe',
                              style:
                                  TextStyle(color: Colors.grey, fontSize: 12)),
                          Text('Cu',
                              style:
                                  TextStyle(color: Colors.grey, fontSize: 12)),
                          Text('Ct',
                              style:
                                  TextStyle(color: Colors.grey, fontSize: 12)),
                          Text('Pz',
                              style:
                                  TextStyle(color: Colors.grey, fontSize: 12)),
                        ],
                      ),
                      const SizedBox(height: 10),
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 7,
                          mainAxisSpacing: 8,
                          crossAxisSpacing: 8,
                        ),
                        itemCount: firstDayOffset + daysInMonth,
                        itemBuilder: (context, index) {
                          if (index < firstDayOffset) {
                            return const SizedBox.shrink();
                          }

                          final dayNum = index - firstDayOffset + 1;
                          final cellDate = DateTime(_displayedMonth.year,
                              _displayedMonth.month, dayNum);
                          final isSelected =
                              formatDateKey(cellDate) == selectedKey;
                          final hasEvents = _events.any(
                              (e) => e.eventDate == formatDateKey(cellDate));

                          return GestureDetector(
                            onTap: () =>
                                setState(() => _selectedDate = cellDate),
                            child: Container(
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? Colors.white
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    '$dayNum',
                                    style: TextStyle(
                                      color: isSelected
                                          ? Colors.black
                                          : Colors.white70,
                                      fontWeight: isSelected
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                      fontSize: 13,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Container(
                                    width: 5,
                                    height: 5,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: hasEvents
                                          ? (isSelected
                                              ? Colors.black54
                                              : Colors.white)
                                          : Colors.transparent,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Seçilen Gün Etkinlikleri Başlığı
                Text(
                  '${_selectedDate.day} ${_monthNames[_selectedDate.month - 1]} '
                  'Etkinlikleri',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 10),

                // Etkinlik Listesi
                if (_isLoading)
                  const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  )
                else if (dayEvents.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 10),
                    child: Text(
                      'Bu tarihte etkinlik bulunmuyor.',
                      style: TextStyle(color: Colors.grey, fontSize: 13),
                    ),
                  )
                else
                  Column(
                    children: dayEvents
                        .map(
                          (event) => GestureDetector(
                            onLongPress: () => _confirmDelete(event),
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: const Color(0xFF161B22),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: Colors.white12),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.event_available_outlined,
                                      color: Colors.grey, size: 20),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      event.title,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  GestureDetector(
                                    onTap: () => _confirmDelete(event),
                                    child: const Icon(Icons.close,
                                        color: Colors.grey, size: 18),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                const SizedBox(height: 15),

                // Yeni Etkinlik Ekleme Satırı
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF161B22),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _newEventController,
                          focusNode: _newEventFocus,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 14),
                          decoration: const InputDecoration(
                            hintText: 'Yeni etkinlik ekle...',
                            hintStyle: TextStyle(color: Colors.grey),
                            border: InputBorder.none,
                          ),
                          onSubmitted: (_) => _addEvent(),
                        ),
                      ),
                      GestureDetector(
                        onTap: _addEvent,
                        child: Container(
                          height: 40,
                          width: 40,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.add,
                              color: Colors.black, size: 22),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 30),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

/// Android ana ekran takvim widget'ının sınıfı (Kotlin tarafıyla aynı olmalı).
const String _androidWidgetName = 'CalendarWidgetReceiver';
const String _qualifiedAndroidWidgetName =
    'com.bilalhabessimsek.ultimate_mobile.CalendarWidgetReceiver';

/// Widget'a yazılacak takvim verisini kaydeder.
///
/// [today] / [tomorrow] metinleri doğrudan gösterilir. Ayrıca [upcoming]
/// (tarih + başlık listesi) JSON olarak saklanır; yerel taraf bu listeyi cihazın
/// **o anki** tarihine göre süzer. Böylece uygulama günlerce açılmasa da widget
/// "BUGÜN"/"YARIN" bölümlerini doğru gösterir.
Future<void> saveCalendarWidgetData({
  required String today,
  required String tomorrow,
  List<Map<String, String>> upcoming = const <Map<String, String>>[],
}) async {
  try {
    await HomeWidget.saveWidgetData<String>('calendar_summary_today', today);
    await HomeWidget.saveWidgetData<String>(
      'calendar_summary_tomorrow',
      tomorrow,
    );
    // Eski widget sürümüyle geriye dönük uyumluluk.
    await HomeWidget.saveWidgetData<String>('calendar_summary', today);
    await HomeWidget.saveWidgetData<String>(
      'calendar_events_json',
      jsonEncode(upcoming),
    );
  } catch (err) {
    debugPrint('Widget verisi kaydedilemedi: $err');
  }
}

/// Widget'ı yeniden çizdirir. Veri yoksa da hata vermez.
Future<void> refreshCalendarWidget() async {
  try {
    await HomeWidget.updateWidget(
      androidName: _androidWidgetName,
      qualifiedAndroidName: _qualifiedAndroidWidgetName,
    );
  } catch (err) {
    debugPrint('Widget yenilenemedi: $err');
  }
}

/// Widget'taki mavi "+" ve yeşil not düğmesi için kullanılan URI şeması
/// (Kotlin tarafıyla aynı).
const String _addEventUriPath = '/add';
const String _openDateUriPath = '/open';
const String _calendarHost = 'calendar';
const String _notesHost = 'notes';

/// Widget'tan gelen tıklama eylemi.
///
/// [type] `add` (etkinlik ekle satırını aç), `open` (takvimde günü seç) veya
/// `note` (yeni not ekranını aç). [value]; add için `'today'`/`'tomorrow'` ya da
/// `'yyyy-M-d'` tarihi, open için `'yyyy-M-d'` tarihi, note için `'new'`'dir.
class WidgetAction {
  final String type;
  final String value;
  const WidgetAction(this.type, this.value);
}

/// Gelen tıklama URI'sini eyleme çevirir; bizim URI'miz değilse null.
WidgetAction? parseWidgetAction(Uri? uri) {
  if (uri == null || uri.scheme != 'ultimate') return null;
  // ultimate://notes/add -> Notlar sekmesinde yeni not.
  if (uri.host == _notesHost && uri.path == _addEventUriPath) {
    return const WidgetAction('note', 'new');
  }
  if (uri.host != _calendarHost) return null;
  if (uri.path == _addEventUriPath) {
    // Eski sürüm ?day=today|tomorrow gönderir; yenisi ?date=yyyy-M-d.
    final value =
        uri.queryParameters['day'] ?? uri.queryParameters['date'] ?? 'today';
    return WidgetAction('add', value);
  }
  if (uri.path == _openDateUriPath) {
    final date = uri.queryParameters['date'];
    if (date == null || date.isEmpty) return null;
    return WidgetAction('open', date);
  }
  return null;
}

/// Widget tıklamalarını yayınlar. **Tek abonelik** açılmalıdır: home_widget
/// native tarafında olay kanalının tek bir sink'i vardır, ikinci abonelik
/// ilkinin yerine geçer (ilk tıklamalar kaybolur).
Stream<WidgetAction> get widgetActions => HomeWidget.widgetClicked
    .map(parseWidgetAction)
    .where((action) => action != null)
    .cast<WidgetAction>();

/// Uygulama bir widget tıklamasıyla açıldıysa eylemi döner; aksi halde null.
Future<WidgetAction?> initialWidgetAction() async {
  try {
    return parseWidgetAction(
      await HomeWidget.initiallyLaunchedFromHomeWidget(),
    );
  } catch (err) {
    debugPrint('Widget başlangıç tıklaması okunamadı: $err');
    return null;
  }
}

package com.bilalhabessimsek.ultimate_mobile

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.graphics.Color
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider
import org.json.JSONArray
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale
import java.util.TreeSet

class CalendarWidgetReceiver : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        // Bildirim panelindeki "Hızlı not" bildirimini canlı tut (izin varsa).
        QuickNoteNotification.post(context)

        val format = SimpleDateFormat("yyyy-M-d", Locale.US)
        val now = Calendar.getInstance()
        val todayDay = now.get(Calendar.DAY_OF_MONTH)
        val daysInMonth = now.getActualMaximum(Calendar.DAY_OF_MONTH)

        // Widget'ta seçili gün (güne tıklayınca CalendarDaySelectReceiver yazar).
        val selectedDay = readSelectedDay(widgetData, format, now).coerceIn(1, daysInMonth)

        val monthTitle = monthCalTitle(now)
        val displayMonthTitle = "$monthTitle ${now.get(Calendar.YEAR)}"

        val firstDayOfMonth = Calendar.getInstance().apply {
            set(Calendar.DAY_OF_MONTH, 1)
        }
        val firstWeekDay = firstDayOfMonth.get(Calendar.DAY_OF_WEEK)
        val offset = when (firstWeekDay) {
            Calendar.MONDAY -> 0
            Calendar.TUESDAY -> 1
            Calendar.WEDNESDAY -> 2
            Calendar.THURSDAY -> 3
            Calendar.FRIDAY -> 4
            Calendar.SATURDAY -> 5
            Calendar.SUNDAY -> 6
            else -> 0
        }

        val eventKeys = readEventKeys(widgetData)

        // Seçili gün + ertesi gün (ay sonunda bir sonraki aya taşar).
        val selCal = (now.clone() as Calendar).apply {
            set(Calendar.DAY_OF_MONTH, selectedDay)
        }
        val nextCal = (selCal.clone() as Calendar).apply {
            add(Calendar.DAY_OF_MONTH, 1)
        }
        val selKey = format.format(selCal.time)
        val nextKey = format.format(nextCal.time)
        val selLabel = dayLabel(selCal)
        val nextLabel = dayLabel(nextCal)
        val headerLabel = when (selectedDay) {
            todayDay -> "BUGÜN • $selLabel"
            todayDay + 1 -> "YARIN • $selLabel"
            else -> selLabel
        }
        val sections = readSections(widgetData, selKey, nextKey, selLabel, nextLabel)

        for (appWidgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.calendar_widget)
            views.setTextViewText(R.id.widget_month_title, displayMonthTitle)
            views.setTextViewText(R.id.widget_day_header, headerLabel)
            views.setTextViewText(R.id.widget_text_today, sections)
            views.setOnClickPendingIntent(
                R.id.widget_add_today,
                launchAddIntent(context, selKey)
            )
            views.setOnClickPendingIntent(
                R.id.widget_add_note,
                launchAddNoteIntent(context)
            )
            populateCalendar(context, views, offset, daysInMonth, selectedDay, eventKeys)
            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }

    private fun monthCalTitle(now: Calendar): String {
        val monthTitle = now.getDisplayName(
            Calendar.MONTH,
            Calendar.LONG,
            Locale("tr", "TR")
        )?.uppercase(Locale("tr", "TR")) ?: ""
        return monthTitle
    }

    private fun dayLabel(cal: Calendar): String {
        val month = cal.getDisplayName(
            Calendar.MONTH,
            Calendar.LONG,
            Locale("tr", "TR")
        )?.uppercase(Locale("tr", "TR")) ?: ""
        return "${cal.get(Calendar.DAY_OF_MONTH)} $month"
    }

    /// Kayıtlı seçili gün; bu ait ait değilse (ay/yıl değişmişse) bugüne döner.
    private fun readSelectedDay(
        widgetData: SharedPreferences,
        format: SimpleDateFormat,
        now: Calendar
    ): Int {
        val key = widgetData.getString(PREF_SELECTED_DATE, null)
        if (!key.isNullOrBlank()) {
            try {
                val d = format.parse(key)
                if (d != null) {
                    val cal = Calendar.getInstance().apply { time = d }
                    if (cal.get(Calendar.YEAR) == now.get(Calendar.YEAR) &&
                        cal.get(Calendar.MONTH) == now.get(Calendar.MONTH)
                    ) {
                        return cal.get(Calendar.DAY_OF_MONTH)
                    }
                }
            } catch (_: Exception) {
            }
        }
        return now.get(Calendar.DAY_OF_MONTH)
    }

    private fun readEventKeys(widgetData: SharedPreferences): TreeSet<Int> {
        val keys = TreeSet<Int>()
        val json = widgetData.getString("calendar_events_json", null)
        if (!json.isNullOrBlank()) {
            try {
                val array = JSONArray(json)
                val cal = Calendar.getInstance()
                val format = SimpleDateFormat("yyyy-M-d", Locale.US)
                val now = Calendar.getInstance()
                for (i in 0 until array.length()) {
                    val item = array.optJSONObject(i) ?: continue
                    val date = item.optString("date")
                    val title = item.optString("title").trim()
                    if (title.isEmpty()) continue
                    try {
                        val d = format.parse(date) ?: continue
                        cal.time = d
                        if (cal.get(Calendar.YEAR) == now.get(Calendar.YEAR) &&
                            cal.get(Calendar.MONTH) == now.get(Calendar.MONTH)
                        ) {
                            keys.add(cal.get(Calendar.DAY_OF_MONTH))
                        }
                    } catch (_: Exception) {
                    }
                }
            } catch (_: Exception) {
            }
        }
        return keys
    }

    /// Seçili gün ve ertesi günün etkinlik listesi:
    ///   19 EKİM
    ///   • etkinlik
    ///   20 EKİM
    ///   • etkinlik yok
    private fun readSections(
        widgetData: SharedPreferences,
        selKey: String,
        nextKey: String,
        selLabel: String,
        nextLabel: String
    ): String {
        val eventsFor = HashMap<String, MutableList<String>>()
        val json = widgetData.getString("calendar_events_json", null)
        if (!json.isNullOrBlank()) {
            try {
                val array = JSONArray(json)
                for (i in 0 until array.length()) {
                    val item = array.optJSONObject(i) ?: continue
                    val date = item.optString("date")
                    val title = item.optString("title").trim()
                    if (title.isEmpty()) continue
                    if (date == selKey || date == nextKey) {
                        eventsFor.getOrPut(date) { mutableListOf() }.add(title)
                    }
                }
            } catch (_: Exception) {
            }
        }
        val builder = StringBuilder()
        builder.append(selLabel)
        appendEvents(builder, eventsFor[selKey])
        builder.append('\n').append(nextLabel)
        appendEvents(builder, eventsFor[nextKey])
        return builder.toString()
    }

    private fun appendEvents(builder: StringBuilder, events: MutableList<String>?) {
        if (events.isNullOrEmpty()) {
            builder.append('\n').append("• Etkinlik yok")
            return
        }
        for (title in events) appendLine(builder, title)
    }

    private fun appendLine(builder: StringBuilder, title: String) {
        builder.append('\n').append("• ").append(title)
    }

    private fun populateCalendar(
        context: Context,
        views: RemoteViews,
        offset: Int,
        daysInMonth: Int,
        selectedDay: Int,
        eventKeys: TreeSet<Int>
    ) {
        for (i in 0..41) {
            val cellId = getCellId(i)
            val dotId = getDotId(i)
            if (cellId == 0 || dotId == 0) continue
            val dayNum = i - offset + 1
            if (dayNum < 1 || dayNum > daysInMonth) {
                views.setTextViewText(cellId, "")
                views.setViewVisibility(dotId, View.GONE)
                views.setInt(cellId, "setBackgroundColor", Color.TRANSPARENT)
            } else {
                views.setTextViewText(cellId, dayNum.toString())
                if (dayNum == selectedDay) {
                    views.setInt(cellId, "setTextColor", Color.BLACK)
                    views.setInt(cellId, "setBackgroundResource", R.drawable.widget_today_bg)
                } else {
                    views.setInt(cellId, "setTextColor", Color.parseColor("#FFFFFF"))
                    views.setInt(cellId, "setBackgroundColor", Color.TRANSPARENT)
                }
                if (eventKeys.contains(dayNum)) {
                    views.setViewVisibility(dotId, View.VISIBLE)
                } else {
                    views.setViewVisibility(dotId, View.GONE)
                }
                // Güne tıklayınca widget kendi içinde o güne geçer.
                views.setOnClickPendingIntent(cellId, selectDayIntent(context, dayNum, i))
            }
        }
    }

    private fun getCellId(index: Int): Int = when (index) {
        0 -> R.id.cell_0; 1 -> R.id.cell_1; 2 -> R.id.cell_2; 3 -> R.id.cell_3; 4 -> R.id.cell_4; 5 -> R.id.cell_5; 6 -> R.id.cell_6
        7 -> R.id.cell_7; 8 -> R.id.cell_8; 9 -> R.id.cell_9; 10 -> R.id.cell_10; 11 -> R.id.cell_11; 12 -> R.id.cell_12; 13 -> R.id.cell_13
        14 -> R.id.cell_14; 15 -> R.id.cell_15; 16 -> R.id.cell_16; 17 -> R.id.cell_17; 18 -> R.id.cell_18; 19 -> R.id.cell_19; 20 -> R.id.cell_20
        21 -> R.id.cell_21; 22 -> R.id.cell_22; 23 -> R.id.cell_23; 24 -> R.id.cell_24; 25 -> R.id.cell_25; 26 -> R.id.cell_26; 27 -> R.id.cell_27
        28 -> R.id.cell_28; 29 -> R.id.cell_29; 30 -> R.id.cell_30; 31 -> R.id.cell_31; 32 -> R.id.cell_32; 33 -> R.id.cell_33; 34 -> R.id.cell_34
        35 -> R.id.cell_35; 36 -> R.id.cell_36; 37 -> R.id.cell_37; 38 -> R.id.cell_38; 39 -> R.id.cell_39; 40 -> R.id.cell_40; 41 -> R.id.cell_41
        else -> 0
    }

    private fun getDotId(index: Int): Int = when (index) {
        0 -> R.id.dot_0; 1 -> R.id.dot_1; 2 -> R.id.dot_2; 3 -> R.id.dot_3; 4 -> R.id.dot_4; 5 -> R.id.dot_5; 6 -> R.id.dot_6
        7 -> R.id.dot_7; 8 -> R.id.dot_8; 9 -> R.id.dot_9; 10 -> R.id.dot_10; 11 -> R.id.dot_11; 12 -> R.id.dot_12; 13 -> R.id.dot_13
        14 -> R.id.dot_14; 15 -> R.id.dot_15; 16 -> R.id.dot_16; 17 -> R.id.dot_17; 18 -> R.id.dot_18; 19 -> R.id.dot_19; 20 -> R.id.dot_20
        21 -> R.id.dot_21; 22 -> R.id.dot_22; 23 -> R.id.dot_23; 24 -> R.id.dot_24; 25 -> R.id.dot_25; 26 -> R.id.dot_26; 27 -> R.id.dot_27
        28 -> R.id.dot_28; 29 -> R.id.dot_29; 30 -> R.id.dot_30; 31 -> R.id.dot_31; 32 -> R.id.dot_32; 33 -> R.id.dot_33; 34 -> R.id.dot_34
        35 -> R.id.dot_35; 36 -> R.id.dot_36; 37 -> R.id.dot_37; 38 -> R.id.dot_38; 39 -> R.id.dot_39; 40 -> R.id.dot_40; 41 -> R.id.dot_41
        else -> 0
    }

    companion object {
        const val ADD_EVENT_URI = "ultimate://calendar/add"
        const val ADD_NOTE_URI = "ultimate://notes/add"
        const val PREF_SELECTED_DATE = "calendar_selected_day"
        const val EXTRA_SELECTED_DAY = "day"

        private fun launchAddIntent(context: Context, dateKey: String): PendingIntent {
            val uri = Uri.parse(ADD_EVENT_URI).buildUpon()
                .appendQueryParameter("date", dateKey)
                .build()
            return HomeWidgetLaunchIntent.getActivity(
                context,
                MainActivity::class.java,
                uri
            )
        }

        private fun launchAddNoteIntent(context: Context): PendingIntent {
            return HomeWidgetLaunchIntent.getActivity(
                context,
                MainActivity::class.java,
                Uri.parse(ADD_NOTE_URI)
            )
        }

        private fun selectDayIntent(context: Context, day: Int, requestCode: Int): PendingIntent {
            val intent = Intent(context, CalendarDaySelectReceiver::class.java)
                .putExtra(EXTRA_SELECTED_DAY, day)
            return PendingIntent.getBroadcast(
                context,
                requestCode,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
        }
    }
}

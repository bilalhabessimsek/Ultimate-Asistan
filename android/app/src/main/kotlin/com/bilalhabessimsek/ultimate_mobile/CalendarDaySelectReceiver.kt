package com.bilalhabessimsek.ultimate_mobile

import android.appwidget.AppWidgetManager
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent

/**
 * Widget takviminde bir güne tıklandığında seçili günü kaydedip widget'ı
 * yeniden çizer. Uygulama açık olmak zorunda DEĞİLDİR; broadcast çalışır,
 * widget seçilen günün + ertesi günün etkinliklerini gösterir.
 */
class CalendarDaySelectReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val day = intent.getIntExtra(CalendarWidgetReceiver.EXTRA_SELECTED_DAY, -1)
        if (day < 1) return

        val prefs = context.getSharedPreferences(
            "HomeWidgetPreferences",
            Context.MODE_PRIVATE
        )
        val now = java.util.Calendar.getInstance()
        val dateKey = java.text.SimpleDateFormat("yyyy-M-d", java.util.Locale.US)
            .format(
                now.apply { set(java.util.Calendar.DAY_OF_MONTH, day) }.time
            )
        prefs.edit().putString(CalendarWidgetReceiver.PREF_SELECTED_DATE, dateKey).apply()

        val manager = AppWidgetManager.getInstance(context)
        val ids = manager.getAppWidgetIds(
            ComponentName(context, CalendarWidgetReceiver::class.java)
        )
        if (ids.isEmpty()) return
        CalendarWidgetReceiver().onUpdate(context, manager, ids, prefs)
    }
}

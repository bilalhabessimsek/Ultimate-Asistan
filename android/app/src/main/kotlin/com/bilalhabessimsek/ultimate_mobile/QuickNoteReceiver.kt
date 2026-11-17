package com.bilalhabessimsek.ultimate_mobile

import android.app.RemoteInput
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Bildirimdeki "Not al" alanına yazılan metni alıp [QuickNoteBridge] üzerinden
 * Dart'a (Notlar/Supabase) gönderir. Uygulama kapalı olsa bile çalışır: süreç
 * [UltimateApplication] ile birlikte açılır ve motor önbellekten kullanılır.
 *
 * Dışa kapalıdır (`exported=false`): yalnızca bildirim eylemi tetikleyebilir.
 */
class QuickNoteReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        val text = extractText(intent)
        if (text.isNullOrBlank()) return
        QuickNoteBridge.deliver(context, text, open = false)
    }

    private fun extractText(intent: Intent): String? {
        // Bildirimdeki "Not al" alanına yazılan metin RemoteInput sonucu gelir.
        val results = RemoteInput.getResultsFromIntent(intent)
        val typed = results?.getCharSequence(KEY_TEXT)?.toString()
        if (!typed.isNullOrBlank()) return typed
        // Düz ekstra: otomasyon/test kolaylığı (dışarıdan erişilemez).
        return intent.getStringExtra(KEY_TEXT)
    }

    companion object {
        const val KEY_TEXT = "quick_note_text"
        const val ACTION = "com.bilalhabessimsek.ultimate_mobile.action.QUICK_NOTE"
    }
}

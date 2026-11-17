package com.bilalhabessimsek.ultimate_mobile

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.RemoteInput
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.drawable.Icon
import android.os.Build

/**
 * Bildirim panelinde duran "Hızlı not" bildirimi.
 *
 * Kullanıcı bildirimi açar, "Not al" satırına yazar ve gönderir; metin
 * [QuickNoteReceiver] üzerinden Notlar'a düşer — uygulamayı hiç açmadan.
 * SwiftKey'in klavye üstü araçlarına benzer "her an elinin altında" bir
 * not alma yolu sağlar (üçüncü taraf klavye araç çubuğuna düğme eklemek
 * Android'de mümkün olmadığı için en yakın ve en sağlam çözüm budur).
 */
object QuickNoteNotification {
    private const val CHANNEL_ID = "ultimate_mobile_quick_note"
    private const val NOTIFICATION_ID = 7311
    private const val ACTION_REQUEST_CODE = 7312
    private const val CONTENT_REQUEST_CODE = 7313

    /** Bildirimi gösterir. İzin yoksa sessizce çıkar. */
    fun post(context: Context) {
        createChannel(context)
        if (!canPost(context)) return
        val manager =
            context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        try {
            manager.notify(NOTIFICATION_ID, build(context))
        } catch (_: Exception) {
            // Bildirim gösterilemedi: sessizce yut.
        }
    }

    private fun canPost(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return true
        return context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
    }

    private fun createChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager =
            context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Hızlı not",
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "Bildirim panelinden anında not alma"
            setShowBadge(false)
            enableVibration(false)
            setSound(null, null)
        }
        manager.createNotificationChannel(channel)
    }

    private fun build(context: Context): Notification {
        // "Not al" satırı: kullanıcı yazıp gönderince metin receiver'a gider.
        val remoteInput = RemoteInput.Builder(QuickNoteReceiver.KEY_TEXT)
            .setLabel("Notunu yaz…")
            .build()

        val actionIntent = Intent(context, QuickNoteReceiver::class.java).apply {
            action = QuickNoteReceiver.ACTION
        }
        // RemoteInput sonuçları fill-in ile geldiği için PendingIntent mutable olmalı.
        val actionPending = PendingIntent.getBroadcast(
            context,
            ACTION_REQUEST_CODE,
            actionIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE,
        )
        val noteAction = Notification.Action.Builder(
            Icon.createWithResource(context, R.drawable.ic_stat_note),
            "Not al",
            actionPending,
        ).addRemoteInput(remoteInput).build()

        val contentIntent = Intent(context, MainActivity::class.java).apply {
            setAction(Intent.ACTION_MAIN)
            addCategory(Intent.CATEGORY_LAUNCHER)
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_NEW_TASK
        }
        val contentPending = PendingIntent.getActivity(
            context,
            CONTENT_REQUEST_CODE,
            contentIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(context, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(context)
        }

        return builder
            .setSmallIcon(R.drawable.ic_stat_note)
            .setContentTitle("Hızlı not")
            .setContentText("Not almak için “Not al”a dokun, yaz ve gönder.")
            .setContentIntent(contentPending)
            .addAction(noteAction)
            .setOnlyAlertOnce(true)
            .setShowWhen(false)
            .build()
    }
}

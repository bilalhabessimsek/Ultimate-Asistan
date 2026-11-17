package com.bilalhabessimsek.ultimate_mobile

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.drawable.Icon
import android.media.MediaMetadata
import android.media.session.MediaSession
import android.media.session.PlaybackState
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import io.flutter.plugin.common.MethodChannel

/**
 * Bildirim panelindeki (ve kilit ekranındaki) müzik kontrolü.
 *
 * Ön plan servisi olarak çalışır; böylece uygulama arka plana atılsa bile
 * müzik çalmaya devam eder ve bildirim kalıcı olur.
 *
 * Yerleşik `MediaSession` + `Notification.MediaStyle` kullanılır: Android
 * 11+ medya panelinde, kilit ekranında ve Bluetooth kulaklık tuşlarında
 * çal/duraklat/ileri/geri kontrolleri görünür.
 *
 * Bildirim düğmelerine basıldığında komutlar Flutter tarafına
 * (`ultimate_mobile/media_notification` kanalı) iletilir; çalma mantığı
 * tamamen Dart tarafındadır.
 */
class MediaPlaybackService : Service() {

    companion object {
        private const val TAG = "MediaNotification"

        const val ACTION_UPDATE =
            "com.bilalhabessimsek.ultimate_mobile.action.MEDIA_UPDATE"
        const val ACTION_TOGGLE =
            "com.bilalhabessimsek.ultimate_mobile.action.MEDIA_TOGGLE"
        const val ACTION_NEXT =
            "com.bilalhabessimsek.ultimate_mobile.action.MEDIA_NEXT"
        const val ACTION_PREV =
            "com.bilalhabessimsek.ultimate_mobile.action.MEDIA_PREV"

        /** Kullanıcı bildirimi kapattığında (Dart da çalmayı durdurur). */
        const val ACTION_STOP =
            "com.bilalhabessimsek.ultimate_mobile.action.MEDIA_STOP"

        /** Uygulama tarafından gizleme isteği (Dart'a komut gönderilmez). */
        const val ACTION_HIDE =
            "com.bilalhabessimsek.ultimate_mobile.action.MEDIA_HIDE"

        private const val CHANNEL_ID = "ultimate_mobile_playback"
        private const val NOTIFICATION_ID = 4711

        /** Flutter tarafına komut göndermek için kanal (MainActivity kurar). */
        @Volatile
        var commandChannel: MethodChannel? = null

        /** Bildirimdeki düğmelerden gelen komutu Dart'a iletir. */
        fun sendCommand(action: String) {
            Handler(Looper.getMainLooper()).post {
                try {
                    commandChannel?.invokeMethod("action", action)
                } catch (e: Exception) {
                    android.util.Log.w(TAG, "Komut iletilemedi: ${e.message}")
                }
            }
        }
    }

    private var session: MediaSession? = null
    private var isForeground = false

    /** Son bildirimdeki çalma durumu: görev silinince servisi yaşatmak için. */
    @Volatile
    private var songPlaying = false

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        session = MediaSession(this, "UltimateMobilePlayback").apply {
            setCallback(object : MediaSession.Callback() {
                override fun onPlay() = sendCommand("play")
                override fun onPause() = sendCommand("pause")
                override fun onSkipToNext() = sendCommand("next")
                override fun onSkipToPrevious() = sendCommand("previous")
                override fun onStop() = sendCommand("stop")
                override fun onSeekTo(pos: Long) = sendCommand("seek:$pos")
            })
            isActive = true
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_TOGGLE -> sendCommand("toggle")
            ACTION_NEXT -> sendCommand("next")
            ACTION_PREV -> sendCommand("previous")

            ACTION_STOP -> {
                sendCommand("stop")
                hide()
                return START_NOT_STICKY
            }

            ACTION_HIDE -> {
                hide()
                return START_NOT_STICKY
            }

            ACTION_UPDATE -> {
                showNotification(
                    title = intent.getStringExtra("title") ?: "",
                    artist = intent.getStringExtra("artist") ?: "",
                    playing = intent.getBooleanExtra("playing", false),
                    positionMs = intent.getLongExtra("positionMs", 0L),
                    durationMs = intent.getLongExtra("durationMs", 0L),
                    hasNext = intent.getBooleanExtra("hasNext", false),
                    hasPrev = intent.getBooleanExtra("hasPrev", false),
                )
            }
        }
        // Süreç öldükten sonra (kullanıcı uygulamayı temizledikten sonra)
        // servisin hayalet olarak yeniden başmasını istemeyiz.
        return if (intent == null) START_NOT_STICKY else START_STICKY
    }

    /**
     * Kullanıcı uygulamayı son uygulamalar ekranından kaydırdığında
     * (görev silindiğinde) çağrılır.
     *
     * Müzik çalıyorsa servis BİLEREK yaşatılır: motor önbelleğe alındığı
     * için çalma sürer ve bildirim kontrolü çalışır. Müzik çalmıyorsa
     * bildirim temizlenip servis durdurulur.
     */
    override fun onTaskRemoved(rootIntent: Intent?) {
        if (!songPlaying) {
            hide()
        }
        super.onTaskRemoved(rootIntent)
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        try {
            session?.isActive = false
            session?.release()
        } catch (_: Exception) {
        }
        session = null
        isForeground = false
        super.onDestroy()
    }

    // ------------------------------------------------------------- bildirim

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Müzik çalar",
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "Çalan şarkı ve kontrol düğmeleri"
            setShowBadge(false)
            lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            enableVibration(false)
            setSound(null, null)
        }
        manager.createNotificationChannel(channel)
    }

    private fun newBuilder(): Notification.Builder =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }

    private fun serviceAction(action: String, requestCode: Int): PendingIntent {
        val intent = Intent(this, MediaPlaybackService::class.java).setAction(action)
        var flags = PendingIntent.FLAG_UPDATE_CURRENT
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            flags = flags or PendingIntent.FLAG_IMMUTABLE
        }
        return PendingIntent.getService(this, requestCode, intent, flags)
    }

    private fun contentIntent(): PendingIntent {
        val intent = Intent(this, MainActivity::class.java).apply {
            action = Intent.ACTION_MAIN
            addCategory(Intent.CATEGORY_LAUNCHER)
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_NEW_TASK
        }
        var flags = PendingIntent.FLAG_UPDATE_CURRENT
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            flags = flags or PendingIntent.FLAG_IMMUTABLE
        }
        return PendingIntent.getActivity(this, 0, intent, flags)
    }

    private fun showNotification(
        title: String,
        artist: String,
        playing: Boolean,
        positionMs: Long,
        durationMs: Long,
        hasNext: Boolean,
        hasPrev: Boolean,
    ) {
        val s = session ?: return
        songPlaying = playing

        // Medya oturumu: kilit ekranı / medya paneli buradan beslenir.
        s.setMetadata(
            MediaMetadata.Builder()
                .putString(MediaMetadata.METADATA_KEY_TITLE, title)
                .putString(MediaMetadata.METADATA_KEY_ARTIST, artist)
                .putLong(MediaMetadata.METADATA_KEY_DURATION, durationMs)
                .build()
        )
        var actions = PlaybackState.ACTION_PLAY or
            PlaybackState.ACTION_PAUSE or
            PlaybackState.ACTION_PLAY_PAUSE or
            PlaybackState.ACTION_SEEK_TO or
            PlaybackState.ACTION_STOP
        if (hasPrev) actions = actions or PlaybackState.ACTION_SKIP_TO_PREVIOUS
        if (hasNext) actions = actions or PlaybackState.ACTION_SKIP_TO_NEXT
        s.setPlaybackState(
            PlaybackState.Builder()
                .setActions(actions)
                .setState(
                    if (playing) PlaybackState.STATE_PLAYING else PlaybackState.STATE_PAUSED,
                    positionMs.coerceAtLeast(0L),
                    if (playing) 1f else 0f,
                )
                .build()
        )

        val playPauseIcon = if (playing) {
            android.R.drawable.ic_media_pause
        } else {
            android.R.drawable.ic_media_play
        }

        val builder = newBuilder()
            .setSmallIcon(R.drawable.ic_stat_music)
            .setContentTitle(title.ifEmpty { "Müzik" })
            .setContentText(artist)
            .setContentIntent(contentIntent())
            .setDeleteIntent(serviceAction(ACTION_STOP, 4))
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setOnlyAlertOnce(true)
            .setShowWhen(false)
            .setOngoing(playing)
            .addAction(
                Notification.Action.Builder(
                    Icon.createWithResource(this, android.R.drawable.ic_media_previous),
                    "Önceki",
                    serviceAction(ACTION_PREV, 1),
                ).build()
            )
            .addAction(
                Notification.Action.Builder(
                    Icon.createWithResource(this, playPauseIcon),
                    if (playing) "Duraklat" else "Çal",
                    serviceAction(ACTION_TOGGLE, 2),
                ).build()
            )
            .addAction(
                Notification.Action.Builder(
                    Icon.createWithResource(this, android.R.drawable.ic_media_next),
                    "Sonraki",
                    serviceAction(ACTION_NEXT, 3),
                ).build()
            )
            .setStyle(
                Notification.MediaStyle()
                    .setMediaSession(s.sessionToken)
                    .setShowActionsInCompactView(0, 1, 2)
            )

        if (durationMs > 0) {
            builder.setProgress(
                durationMs.coerceAtMost(Int.MAX_VALUE.toLong()).toInt(),
                positionMs.coerceIn(0L, durationMs).toInt(),
                false,
            )
        }

        val notification = builder.build()
        try {
            if (!isForeground) {
                isForeground = true
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    startForeground(
                        NOTIFICATION_ID,
                        notification,
                        ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK,
                    )
                } else {
                    startForeground(NOTIFICATION_ID, notification)
                }
            } else {
                val manager =
                    getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                manager.notify(NOTIFICATION_ID, notification)
            }
        } catch (e: Exception) {
            android.util.Log.e(TAG, "Bildirim gösterilemedi: ${e.message}")
        }
    }

    private fun hide() {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                stopForeground(STOP_FOREGROUND_REMOVE)
            } else {
                @Suppress("DEPRECATION")
                stopForeground(true)
            }
        } catch (_: Exception) {
        }
        isForeground = false
        stopSelf()
    }
}

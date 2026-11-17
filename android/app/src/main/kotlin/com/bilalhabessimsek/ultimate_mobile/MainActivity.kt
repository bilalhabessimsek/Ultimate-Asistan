package com.bilalhabessimsek.ultimate_mobile

import android.Manifest
import android.content.ContentUris
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaPlayer
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.TrafficStats
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.nio.ByteBuffer
import java.nio.charset.Charset
import java.nio.charset.CodingErrorAction
import java.util.UUID
import java.util.concurrent.Executors

/**
 * Yerel müzik taraması için köprü.
 *
 * `on_audio_query` eklentisi yeni Android Gradle Plugin (AGP 8+) ile
 * derlenemediği için (namespace tanımsız) MediaStore taramasını doğrudan
 * burada yapıyoruz. Şarkı çalma işini Dart tarafındaki `just_audio` yürütür.
 *
 * Kanal: "ultimate_mobile/media"
 *   hasPermission   -> Boolean
 *   requestPermission -> Boolean
 *   querySongs      -> List<Map> (id, title, artist, album, duration, uri, dateAdded)
 *   queryPlaylists  -> List<Map> (id, name, count)
 *   queryPlaylistSongs(playlistId) -> List<Map> (id, title, artist, album, duration, uri, dateAdded)
 *
 * Kanal: "ultimate_mobile/network"
 *   getLinkInfo -> Map (type, downKbps, upKbps, rxBytes, txBytes)
 *
 * Kanal: "ultimate_mobile/midi"  (ExoPlayer MIDI çalamadığı için)
 *   play(uri) -> Boolean, pause, resume, stop, isPlaying -> Boolean,
 *   setVolume(volume), position -> Int, duration -> Int, seek(ms)
 * Kanal: "ultimate_mobile/midi_events"
 *   parça bitince "completed" yayınlar
 *
 * Kanal: "ultimate_mobile/files"  (SAF ile dosya seçme/kaydetme)
 *   pickTextFile            -> Map? (name, content, truncated)
 *   saveTextFile(name, content, mime) -> Map? (name, uri)
 *   getAudioDevices         -> List<Map> (id, name, type)
 */
class MainActivity : FlutterActivity() {
    private val channelName = "ultimate_mobile/media"
    private val networkChannelName = "ultimate_mobile/network"
    private val midiChannelName = "ultimate_mobile/midi"
    private val midiEventsChannelName = "ultimate_mobile/midi_events"
    private val filesChannelName = "ultimate_mobile/files"
    private val spectrumChannelName = "ultimate_mobile/spectrum"
    private val mediaNotificationChannelName = "ultimate_mobile/media_notification"
    private val permissionRequestCode = 4311
    private val pickFileRequestCode = 4312
    private val createFileRequestCode = 4313
    private val pickImageRequestCode = 4314
    private val notificationRequestCode = 4315
    private val quickNotePermissionCode = 4316
    private var pendingPermissionResult: MethodChannel.Result? = null
    private var pendingNotificationResult: MethodChannel.Result? = null
    private var pendingImageResult: MethodChannel.Result? = null

    // --- Ses spektrumu (mikrofonsuz) -------------------------------------
    // Şarkı dosyası arka planda bir kez çözülüp 8 bantlık (bas -> tiz)
    // seviye zarfı çıkarılır. Mikrofon izni GEREKMEZ, hiçbir şey kaydedilmez;
    // sadece dosyanın kendi sesi okunur.
    private val spectrumBandCount = 8
    private val spectrumFftSize = 2048

    // 8 logaritmik bandın sınır frekansları (Hz): bas -> tiz.
    private val spectrumBandEdges = doubleArrayOf(
        30.0, 90.0, 180.0, 350.0, 700.0, 1400.0, 2800.0, 5600.0, 12000.0,
    )

    // Aynı anda tek analiz çalışır; yeni istek gelince eskisi iptal edilir.
    private var spectrumToken = 0

    // Bir çözülen tamponda en fazla işlenecek örnek (sonsuz döngü koruması).
    private val maxSamplesPerBuffer = 4 * 1024 * 1024

    // SAK (Storage Access Framework) için bekleyen çağrılar.
    private var pendingPickResult: MethodChannel.Result? = null
    private var pendingCreateResult: MethodChannel.Result? = null
    private var pendingCreateName: String? = null
    private var pendingCreateContent: String? = null

    // İçe aktarmada okunacak en fazla bayt (15 MB).
    private val maxImportBytes = 15 * 1024 * 1024

    // MIDI çalmak için yerleşik MediaPlayer (ExoPlayer MIDI desteklemez).
    private var midiPlayer: MediaPlayer? = null
    private var midiEventSink: EventChannel.EventSink? = null
    private var pendingMidiResult: MethodChannel.Result? = null

    // MediaStore sorgularını ana iş parçacığından ayırır; 1000+ şarkılık
    // sorgular ana thread'de olsa uygulama atlar/kasardı.
    private val queryExecutor = Executors.newSingleThreadExecutor()

    /**
     * [work]'ü arka planda çalıştırır, sonucu/ hatasını ana iş parçacığına
     * geri bildirir (MethodChannel.Result ana thread'de çağrılmalıdır).
     */
    private fun runAsync(
        result: MethodChannel.Result,
        error: String,
        work: () -> Any?,
    ) {
        queryExecutor.execute {
            val outcome = runCatching { work() }
            Handler(Looper.getMainLooper()).post {
                if (outcome.isFailure) {
                    result.error(error, outcome.exceptionOrNull()?.message, null)
                } else {
                    result.success(outcome.getOrNull())
                }
            }
        }
    }

    /**
     * Motor [UltimateApplication] tarafından oluşturulup önbelleğe alındığı için
     * Activity yok olsa bile (kullanıcı uygulamayı son uygulamalardan kaydırsa
     * bile) Dart izolatı ve müzik motoru yaşamaya devam eder. Activity yeniden
     * yaratılınca aynı motor üzerine bağlanır; uygulama sıfırdan başlamaz.
     */
    override fun getCachedEngineId(): String = UltimateApplication.ENGINE_ID

    // ------------------------------------------------- hızlı not (bildirim/paylaşım)

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        // Önceki oturumda gönderilememiş notlar varsa Dart'a ilet.
        QuickNoteBridge.drain(this)
        QuickNoteNotification.post(this)
        requestQuickNoteNotificationPermission()
        handleQuickNoteIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        QuickNoteNotification.post(this)
        handleQuickNoteIntent(intent)
    }

    /**
     * Paylaş menüsünden ("Paylaş -> ultimate_mobile") veya `ultimate://notes/add`
     * bağlantısından (simge kısayolu) gelen isteği işler.
     */
    private fun handleQuickNoteIntent(intent: Intent?) {
        when (intent?.action) {
            Intent.ACTION_SEND -> {
                val subject = intent.getStringExtra(Intent.EXTRA_SUBJECT)?.trim().orEmpty()
                val body = intent.getStringExtra(Intent.EXTRA_TEXT)?.trim().orEmpty()
                val text = when {
                    body.isEmpty() -> subject
                    subject.isEmpty() -> body
                    else -> "$subject\n$body"
                }
                if (text.isNotEmpty()) {
                    QuickNoteBridge.deliver(this, text, open = true)
                }
                // Aynı Intent tekrar işlenmesin (Activity yeniden yaratılırsa).
                intent.action = Intent.ACTION_MAIN
            }

            Intent.ACTION_VIEW -> {
                val data = intent.data
                if (data != null && data.scheme == "ultimate" && data.host == "notes") {
                    QuickNoteBridge.openNewNote(this)
                    intent.action = Intent.ACTION_MAIN
                }
            }
        }
    }

    /** Hızlı not bildirimi için Android 13+ bildirim iznini ister. */
    private fun requestQuickNoteNotificationPermission() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
        if (checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
        ) {
            return
        }
        requestPermissions(
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            quickNotePermissionCode,
        )
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "hasPermission" -> result.success(hasAudioPermission())

                    "requestPermission" -> {
                        if (hasAudioPermission()) {
                            result.success(true)
                        } else if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
                            result.success(true)
                        } else {
                            pendingPermissionResult = result
                            requestPermissions(audioPermissions(), permissionRequestCode)
                        }
                    }

                    "querySongs" -> {
                        if (!hasAudioPermission()) {
                            result.error("no_permission", "Ses izni verilmedi.", null)
                        } else {
                            runAsync(result, "query_failed") { querySongs() }
                        }
                    }

                    // Diğer uygulamaların (Samsung Music, YouTube Music vb.)
                    // MediaStore'a kaydettiği çalma listeleri.
                    "queryPlaylists" -> {
                        if (!hasAudioPermission()) {
                            result.error("no_permission", "Ses izni verilmedi.", null)
                        } else {
                            runAsync(result, "playlists_failed") { queryPlaylists() }
                        }
                    }

                    "queryPlaylistSongs" -> {
                        if (!hasAudioPermission()) {
                            result.error("no_permission", "Ses izni verilmedi.", null)
                        } else {
                            val id = call.argument<Number>("playlistId")?.toLong() ?: -1L
                            runAsync(result, "playlist_songs_failed") { queryPlaylistSongs(id) }
                        }
                    }

                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, networkChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getLinkInfo" -> {
                        try {
                            result.success(linkInfo())
                        } catch (e: Exception) {
                            result.error("link_info_failed", e.message, null)
                        }
                    }

                    else -> result.notImplemented()
                }
            }

        // MIDI tamamlanma olayları.
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, midiEventsChannelName)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    midiEventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    midiEventSink = null
                }
            })

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, midiChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "play" -> {
                        val uri = call.argument<String>("uri")
                        if (uri.isNullOrEmpty()) {
                            result.error("bad_uri", "Geçersiz uri.", null)
                        } else {
                            playMidi(uri, result)
                        }
                    }

                    "pause" -> {
                        midiPlayer?.let { if (it.isPlaying) it.pause() }
                        result.success(true)
                    }

                    "resume" -> {
                        midiPlayer?.let { if (!it.isPlaying) it.start() }
                        result.success(true)
                    }

                    "stop" -> {
                        stopMidi()
                        result.success(true)
                    }

                    "isPlaying" -> result.success(midiPlayer?.isPlaying ?: false)

                    "setVolume" -> {
                        val volume = call.argument<Number>("volume")?.toFloat() ?: 1f
                        try {
                            midiPlayer?.setVolume(volume, volume)
                        } catch (_: Exception) {
                        }
                        result.success(true)
                    }

                    "position" -> {
                        val pos = try {
                            midiPlayer?.currentPosition ?: 0
                        } catch (_: Exception) {
                            0
                        }
                        result.success(pos)
                    }

                    "duration" -> {
                        val dur = try {
                            midiPlayer?.duration ?: 0
                        } catch (_: Exception) {
                            0
                        }
                        result.success(dur)
                    }

                    "seek" -> {
                        val ms = call.argument<Number>("ms")?.toInt() ?: 0
                        try {
                            midiPlayer?.seekTo(ms)
                        } catch (_: Exception) {
                        }
                        result.success(true)
                    }

                    // Görselleştiricinin bağlanacağı ses oturumu (API 26+).
                    "sessionId" -> {
                        val id = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            try {
                                midiPlayer?.audioSessionId ?: 0
                            } catch (_: Exception) {
                                0
                            }
                        } else {
                            0
                        }
                        result.success(id)
                    }

                    else -> result.notImplemented()
                }
            }

        // Storage Access Framework: dosya seçme/kaydetme + çıkış aygıtları.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, filesChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pickTextFile" -> pickTextFile(result)

                    "saveTextFile" -> {
                        val name = call.argument<String>("name") ?: "cikti.txt"
                        val content = call.argument<String>("content") ?: ""
                        val mime = call.argument<String>("mime") ?: "text/plain"
                        saveTextFile(name, content, mime, result)
                    }

                    "getAudioDevices" -> result.success(audioDevices())

                    "pickImage" -> pickImage(result)

                    else -> result.notImplemented()
                }
            }

        // Şarkının kendi sesinden (dosya çözülerek) 8 bantlık spektrum.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, spectrumChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "analyze" -> {
                        val uri = call.argument<String>("uri")
                        if (uri.isNullOrEmpty()) {
                            result.success(null)
                        } else {
                            analyzeSpectrum(uri, result)
                        }
                    }

                    else -> result.notImplemented()
                }
            }

        // Bildirim panelindeki müzik kontrolü (MediaSession + MediaStyle).
        val notificationChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            mediaNotificationChannelName,
        )
        MediaPlaybackService.commandChannel = notificationChannel
        notificationChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "update" -> {
                    val args = call.arguments as? Map<*, *> ?: emptyMap<String, Any>()
                    val intent = Intent(this, MediaPlaybackService::class.java).apply {
                        action = MediaPlaybackService.ACTION_UPDATE
                        putExtra("title", args["title"]?.toString() ?: "")
                        putExtra("artist", args["artist"]?.toString() ?: "")
                        putExtra("playing", args["playing"] == true)
                        putExtra(
                            "positionMs",
                            (args["positionMs"] as? Number)?.toLong() ?: 0L,
                        )
                        putExtra(
                            "durationMs",
                            (args["durationMs"] as? Number)?.toLong() ?: 0L,
                        )
                        putExtra("hasNext", args["hasNext"] == true)
                        putExtra("hasPrev", args["hasPrev"] == true)
                    }
                    try {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startForegroundService(intent)
                        } else {
                            startService(intent)
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("service", e.message, null)
                    }
                }

                "stop" -> {
                    try {
                        startService(
                            Intent(this, MediaPlaybackService::class.java).apply {
                                action = MediaPlaybackService.ACTION_HIDE
                            }
                        )
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("service", e.message, null)
                    }
                }

                "requestPermission" -> requestNotificationPermission(result)

                else -> result.notImplemented()
            }
        }
    }

    /**
     * Android 13+ için bildirim izni (POST_NOTIFICATIONS) ister.
     * İzin verilmezse müzik çalar ama bildirim görünmez.
     */
    private fun requestNotificationPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            result.success(true)
            return
        }
        if (checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
        ) {
            result.success(true)
            return
        }
        pendingNotificationResult?.success(false)
        pendingNotificationResult = result
        requestPermissions(
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            notificationRequestCode,
        )
    }

    // ----------------------------------- ses spektrumu (mikrofonsuz analiz)

    /**
     * Şarkı dosyasını arka planda çözüp 8 bantlık (bas -> tiz) seviye zarfı
     * çıkarır. Mikrofon izni GEREKMEZ; hiçbir şey kaydedilmez, yalnızca
     * dosyanın kendi sesi bir kez okunur.
     *
     * Dönen harita: { fps: Double, bands: Int, data: ByteArray }
     * `data` uzunluğu `kareSayısı * bands` olup her bayt 0..255 arası
     * normalize edilmiş seviyedir.
     */
    private fun analyzeSpectrum(uriString: String, result: MethodChannel.Result) {
        val token = ++spectrumToken
        Thread {
            val payload = try {
                buildSpectrum(uriString, token)
            } catch (e: Exception) {
                android.util.Log.e("Spectrum", "Analiz başarısız: ${e.message}")
                null
            }
            Handler(Looper.getMainLooper()).post {
                result.success(payload)
            }
        }.start()
    }

    /** Radix-2 yinelemeli FFT (yerinde). */
    private fun fftInPlace(re: DoubleArray, im: DoubleArray) {
        val n = re.size
        var j = 0
        for (i in 1 until n) {
            var bit = n shr 1
            while (j and bit != 0) {
                j = j xor bit
                bit = bit shr 1
            }
            j = j or bit
            if (i < j) {
                var t = re[i]; re[i] = re[j]; re[j] = t
                t = im[i]; im[i] = im[j]; im[j] = t
            }
        }
        var len = 2
        while (len <= n) {
            val ang = -2.0 * Math.PI / len
            val wr = Math.cos(ang)
            val wi = Math.sin(ang)
            val half = len / 2
            var i = 0
            while (i < n) {
                var cr = 1.0
                var ci = 0.0
                for (k in 0 until half) {
                    val ur = re[i + k]
                    val ui = im[i + k]
                    val jr = re[i + k + half]
                    val ji = im[i + k + half]
                    val vr = jr * cr - ji * ci
                    val vi = jr * ci + ji * cr
                    re[i + k] = ur + vr
                    im[i + k] = ui + vi
                    re[i + k + half] = ur - vr
                    im[i + k + half] = ui - vi
                    val ncr = cr * wr - ci * wi
                    ci = cr * wi + ci * wr
                    cr = ncr
                }
                i += len
            }
            len = len shl 1
        }
    }

    /**
     * Dosyayı çözüp tüm parça için 8 bantlık dB zarfını üretir, sonra her
     * bandı kendi %3-%97 aralığına göre 0..255'e ölçekler.
     */
    private fun buildSpectrum(uriString: String, token: Int): HashMap<String, Any>? {
        val extractor = MediaExtractor()
        var codec: MediaCodec? = null
        try {
            extractor.setDataSource(this, Uri.parse(uriString), null)

            var trackIndex = -1
            var audioFormat: MediaFormat? = null
            for (i in 0 until extractor.trackCount) {
                val f = extractor.getTrackFormat(i)
                val m = f.getString(MediaFormat.KEY_MIME) ?: continue
                if (m.startsWith("audio/")) {
                    trackIndex = i
                    audioFormat = f
                    break
                }
            }
            val format = audioFormat ?: return null
            if (trackIndex < 0) return null
            extractor.selectTrack(trackIndex)

            val mime = format.getString(MediaFormat.KEY_MIME) ?: return null
            val sampleRate = if (format.containsKey(MediaFormat.KEY_SAMPLE_RATE)) {
                format.getInteger(MediaFormat.KEY_SAMPLE_RATE)
            } else {
                44100
            }
            var channelCount = if (format.containsKey(MediaFormat.KEY_CHANNEL_COUNT)) {
                format.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
            } else {
                2
            }
            if (sampleRate <= 0) return null
            if (channelCount <= 0) channelCount = 1

            val fftSize = spectrumFftSize
            val bands = spectrumBandCount

            // Kare atlama: 2048 örnekte bir pencere, %50 örtüşme.
            var hop = fftSize / 2
            // Çok uzun dosyalarda bellek/CPU sınırı için kareyi seyrelt.
            if (format.containsKey(MediaFormat.KEY_DURATION)) {
                val durationSec = format.getLong(MediaFormat.KEY_DURATION) / 1_000_000.0
                if (durationSec > 0) {
                    val needed = (durationSec * sampleRate / 90000.0).toInt()
                    if (needed > hop) hop = needed
                }
            }
            if (hop < 1) hop = 1

            // Hann penceresi (önceden hesaplanır).
            val hann = DoubleArray(fftSize)
            for (i in 0 until fftSize) {
                hann[i] = 0.5 - 0.5 * Math.cos(2.0 * Math.PI * i / (fftSize - 1))
            }

            // Bant kenarlarını bin indeksine çevir (fs/2'ye kadar).
            val bandLo = IntArray(bands)
            val bandHi = IntArray(bands)
            val nyquistBin = fftSize / 2
            for (b in 0 until bands) {
                var lo = (spectrumBandEdges[b] * fftSize / sampleRate).toInt()
                var hi = (spectrumBandEdges[b + 1] * fftSize / sampleRate).toInt()
                if (hi <= lo) hi = lo + 1
                lo = lo.coerceIn(1, nyquistBin - 1)
                hi = hi.coerceIn(lo + 1, nyquistBin)
                bandLo[b] = lo
                bandHi[b] = hi
            }

            codec = MediaCodec.createDecoderByType(mime)
            val decoder = codec!!
            decoder.configure(format, null, null, 0)
            decoder.start()

            val info = MediaCodec.BufferInfo()
            var inputDone = false
            var outputDone = false
            var isFloat = false

            val window = DoubleArray(fftSize)
            val re = DoubleArray(fftSize)
            val im = DoubleArray(fftSize)
            // Çözülen PCM parçası buraya yazılır (tek kanala indirgenmiş).
            val pcmChunk = DoubleArray(8192)

            // Kayan örnek tamponu.
            var buf = DoubleArray(fftSize * 4)
            var bufLen = 0

            // Kare başına bant dB değerleri (büyüyebilir).
            var frameCapacity = 2048
            var dbData = FloatArray(frameCapacity * bands)
            var frameCount = 0

            fun emitFrame() {
                for (i in 0 until fftSize) window[i] = buf[i] * hann[i]
                System.arraycopy(window, 0, re, 0, fftSize)
                java.util.Arrays.fill(im, 0.0)
                fftInPlace(re, im)
                if (frameCount >= frameCapacity) {
                    frameCapacity *= 2
                    val grown = FloatArray(frameCapacity * bands)
                    System.arraycopy(dbData, 0, grown, 0, frameCount * bands)
                    dbData = grown
                }
                val base = frameCount * bands
                for (b in 0 until bands) {
                    var sum = 0.0
                    for (k in bandLo[b] until bandHi[b]) {
                        sum += Math.hypot(re[k], im[k])
                    }
                    val avg = sum / (bandHi[b] - bandLo[b])
                    dbData[base + b] = (20.0 * Math.log10(avg + 1.0)).toFloat()
                }
                frameCount++
            }

            fun pushSamples(count: Int) {
                if (bufLen + count > buf.size) {
                    var cap = buf.size * 2
                    while (cap < bufLen + count) cap *= 2
                    val grown = DoubleArray(cap)
                    System.arraycopy(buf, 0, grown, 0, bufLen)
                    buf = grown
                }
                System.arraycopy(pcmChunk, 0, buf, bufLen, count)
                bufLen += count
                while (bufLen >= fftSize) {
                    emitFrame()
                    val remaining = bufLen - hop
                    System.arraycopy(buf, hop, buf, 0, remaining)
                    bufLen = remaining
                }
            }

            while (!outputDone) {
                if (token != spectrumToken) return null // yeni istek geldi

                if (!inputDone) {
                    val inIndex = decoder.dequeueInputBuffer(10000)
                    if (inIndex >= 0) {
                        val inBuf = decoder.getInputBuffer(inIndex)
                        if (inBuf == null) {
                            inputDone = true
                        } else {
                            val size = extractor.readSampleData(inBuf, 0)
                            if (size < 0) {
                                decoder.queueInputBuffer(
                                    inIndex, 0, 0, 0,
                                    MediaCodec.BUFFER_FLAG_END_OF_STREAM,
                                )
                                inputDone = true
                            } else {
                                decoder.queueInputBuffer(inIndex, 0, size, extractor.sampleTime, 0)
                                extractor.advance()
                            }
                        }
                    }
                }

                val outIndex = decoder.dequeueOutputBuffer(info, 10000)
                if (outIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                    val outFormat = decoder.outputFormat
                    if (outFormat.containsKey(MediaFormat.KEY_PCM_ENCODING)) {
                        isFloat = outFormat.getInteger(MediaFormat.KEY_PCM_ENCODING) ==
                            android.media.AudioFormat.ENCODING_PCM_FLOAT
                    }
                } else if (outIndex >= 0) {
                    val outBuf = decoder.getOutputBuffer(outIndex)
                    if (outBuf != null && info.size > 0 &&
                        (info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG) == 0
                    ) {
                        outBuf.position(info.offset)
                        outBuf.limit(info.offset + info.size)
                        var pushed = 0
                        if (isFloat) {
                            val fb = outBuf.asFloatBuffer()
                            while (fb.remaining() >= channelCount) {
                                var frames = fb.remaining() / channelCount
                                if (frames > pcmChunk.size) frames = pcmChunk.size
                                for (i in 0 until frames) {
                                    if (channelCount == 1) {
                                        pcmChunk[i] = fb.get().toDouble()
                                    } else {
                                        var sum = 0.0
                                        for (c in 0 until channelCount) {
                                            sum += fb.get().toDouble()
                                        }
                                        pcmChunk[i] = sum / channelCount
                                    }
                                }
                                pushSamples(frames)
                                pushed += frames
                                if (pushed > maxSamplesPerBuffer) break
                            }
                        } else {
                            val sb = outBuf.asShortBuffer()
                            while (sb.remaining() >= channelCount) {
                                var frames = sb.remaining() / channelCount
                                if (frames > pcmChunk.size) frames = pcmChunk.size
                                for (i in 0 until frames) {
                                    if (channelCount == 1) {
                                        pcmChunk[i] = sb.get().toDouble()
                                    } else {
                                        var sum = 0.0
                                        for (c in 0 until channelCount) {
                                            sum += sb.get().toDouble()
                                        }
                                        pcmChunk[i] = sum / channelCount
                                    }
                                }
                                pushSamples(frames)
                                pushed += frames
                                if (pushed > maxSamplesPerBuffer) break
                            }
                        }
                    }
                    decoder.releaseOutputBuffer(outIndex, false)
                    if ((info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) {
                        outputDone = true
                    }
                }
            }

            // Bant başına %3-%97 aralığı -> 0..255 (+ hafif yumuşatma).
            val out = ByteArray(frameCount * bands)
            if (frameCount > 0) {
                val sorted = FloatArray(frameCount)
                for (b in 0 until bands) {
                    for (i in 0 until frameCount) sorted[i] = dbData[i * bands + b]
                    java.util.Arrays.sort(sorted)
                    val loIdx = (frameCount * 0.03).toInt().coerceIn(0, frameCount - 1)
                    val hiIdx = (frameCount * 0.97).toInt().coerceIn(0, frameCount - 1)
                    val lo = sorted[loIdx]
                    val hi = sorted[hiIdx]
                    val range = maxOf(hi - lo, 6f)
                    var cur = 0f
                    for (i in 0 until frameCount) {
                        val target = ((dbData[i * bands + b] - lo) / range).coerceIn(0f, 1f)
                        // Yükselme hızlı, düşme yavaş: titremeyi azaltır.
                        cur = if (target > cur) {
                            cur + (target - cur) * 0.65f
                        } else {
                            cur + (target - cur) * 0.25f
                        }
                        out[i * bands + b] = (cur * 255f).toInt().coerceIn(0, 255).toByte()
                    }
                }
            }

            val payload = HashMap<String, Any>()
            payload["bands"] = bands
            payload["fps"] = sampleRate.toDouble() / hop
            payload["data"] = out
            android.util.Log.i(
                "Spectrum",
                "Analiz tamam: ${frameCount} kare, ${sampleRate}Hz, " +
                    "kanal=$channelCount, ${out.size} bayt",
            )
            return payload
        } finally {
            try {
                codec?.stop()
            } catch (_: Exception) {
            }
            try {
                codec?.release()
            } catch (_: Exception) {
            }
            extractor.release()
        }
    }

    // ------------------------------------------------------------------ SAF

    /** Kullanıcıya bir metin/liste dosyası seçtirir. */
    private fun pickTextFile(result: MethodChannel.Result) {
        pendingPickResult?.success(null)
        pendingPickResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
            putExtra(
                Intent.EXTRA_MIME_TYPES,
                arrayOf(
                    "text/plain",
                    "text/csv",
                    "text/comma-separated-values",
                    "application/x-mpegurl",
                    "audio/x-mpegurl",
                    "audio/mpegurl",
                    "application/vnd.apple.mpegurl",
                    "application/octet-stream",
                ),
            )
        }
        try {
            startActivityForResult(intent, pickFileRequestCode)
        } catch (e: Exception) {
            pendingPickResult = null
            result.error("no_picker", e.message, null)
        }
    }

    /** İçeriği kullanıcının seçtiği konuma kaydeder. */
    private fun saveTextFile(
        name: String,
        content: String,
        mime: String,
        result: MethodChannel.Result,
    ) {
        pendingCreateResult?.success(null)
        pendingCreateResult = result
        pendingCreateName = name
        pendingCreateContent = content
        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = mime
            putExtra(Intent.EXTRA_TITLE, name)
        }
        try {
            startActivityForResult(intent, createFileRequestCode)
        } catch (e: Exception) {
            pendingCreateResult = null
            pendingCreateName = null
            pendingCreateContent = null
            result.error("no_saver", e.message, null)
        }
    }

    /**
     * Kullanıcıya galeriden bir görsel seçtirir, seçilen görseli uygulamanın
     * kendi özel klasörüne kopyalar ve **yerel dosya yolunu** döndürür.
     * Böylece not içeriğinde kalıcı bir yol saklanabilir; geniş depolama
     * izni gerekmez.
     */
    private fun pickImage(result: MethodChannel.Result) {
        pendingImageResult?.success(null)
        pendingImageResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "image/*"
        }
        try {
            startActivityForResult(intent, pickImageRequestCode)
        } catch (e: Exception) {
            pendingImageResult = null
            result.error("no_picker", e.message, null)
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)

        if (requestCode == pickFileRequestCode) {
            val pending = pendingPickResult
            pendingPickResult = null
            if (pending == null) return
            val uri: Uri? = if (resultCode == RESULT_OK) data?.data else null
            if (uri == null) {
                pending.success(null)
                return
            }
            try {
                val bytes = contentResolver.openInputStream(uri)?.use { it.readBytes() }
                if (bytes == null) {
                    pending.success(null)
                    return
                }
                val truncated = bytes.size > maxImportBytes
                val slice = if (truncated) bytes.copyOf(maxImportBytes) else bytes
                pending.success(
                    mapOf(
                        "name" to (displayName(uri) ?: uri.lastPathSegment ?: "dosya"),
                        "content" to decodeText(slice),
                        "truncated" to truncated,
                    )
                )
            } catch (e: Exception) {
                pending.error("read_failed", e.message, null)
            }
            return
        }

        if (requestCode == createFileRequestCode) {
            val pending = pendingCreateResult
            val content = pendingCreateContent ?: ""
            val name = pendingCreateName ?: "cikti.txt"
            pendingCreateResult = null
            pendingCreateContent = null
            pendingCreateName = null
            if (pending == null) return
            val uri: Uri? = if (resultCode == RESULT_OK) data?.data else null
            if (uri == null) {
                pending.success(null)
                return
            }
            try {
                contentResolver.openOutputStream(uri, "wt")?.use { out ->
                    out.write(content.toByteArray(Charsets.UTF_8))
                    out.flush()
                }
                pending.success(
                    mapOf(
                        "name" to (displayName(uri) ?: name),
                        "uri" to uri.toString(),
                    )
                )
            } catch (e: Exception) {
                pending.error("write_failed", e.message, null)
            }
        }

        if (requestCode == pickImageRequestCode) {
            val pending = pendingImageResult
            pendingImageResult = null
            if (pending == null) return
            val uri: Uri? = if (resultCode == RESULT_OK) data?.data else null
            if (uri == null) {
                pending.success(null)
                return
            }
            try {
                val dir = File(filesDir, "note_images")
                if (!dir.exists()) dir.mkdirs()
                val file = File(dir, "${UUID.randomUUID()}.${imageExtension(uri)}")
                val stream = contentResolver.openInputStream(uri)
                if (stream == null) {
                    pending.success(null)
                    return
                }
                stream.use { input ->
                    file.outputStream().use { out -> input.copyTo(out) }
                }
                pending.success(file.absolutePath)
            } catch (e: Exception) {
                pending.error("image_failed", e.message, null)
            }
        }
    }

    /** Seçilen görselin uzantısını MIME türünden tahmin eder. */
    private fun imageExtension(uri: Uri): String {
        val mime = contentResolver.getType(uri) ?: ""
        return when {
            mime.contains("png") -> "png"
            mime.contains("webp") -> "webp"
            mime.contains("gif") -> "gif"
            mime.contains("bmp") -> "bmp"
            else -> "jpg"
        }
    }

    private fun displayName(uri: Uri): String? {
        return try {
            contentResolver
                .query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
                ?.use { cursor ->
                    if (cursor.moveToFirst()) {
                        val idx = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                        if (idx >= 0) cursor.getString(idx) else null
                    } else {
                        null
                    }
                }
        } catch (_: Exception) {
            null
        }
    }

    /** UTF-8 dener; bozuksa Windows-1254 (Türkçe) olarak çözer. */
    private fun decodeText(bytes: ByteArray): String {
        var data = bytes
        // UTF-8 BOM'u at.
        if (data.size >= 3 &&
            data[0] == 0xEF.toByte() &&
            data[1] == 0xBB.toByte() &&
            data[2] == 0xBF.toByte()
        ) {
            data = data.copyOfRange(3, data.size)
        }
        return try {
            val decoder = Charsets.UTF_8.newDecoder()
                .onMalformedInput(CodingErrorAction.REPORT)
                .onUnmappableCharacter(CodingErrorAction.REPORT)
            decoder.decode(ByteBuffer.wrap(data)).toString()
        } catch (_: Exception) {
            try {
                String(data, Charset.forName("windows-1254"))
            } catch (_: Exception) {
                String(data, Charsets.ISO_8859_1)
            }
        }
    }

    /** Cihazın ses çıkış aygıtları. */
    private fun audioDevices(): List<Map<String, Any?>> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return emptyList()
        return try {
            val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
            am.getDevices(AudioManager.GET_DEVICES_OUTPUTS).map { device ->
                mapOf(
                    "id" to device.id,
                    "name" to (device.productName?.toString() ?: "Aygıt"),
                    "type" to device.type,
                )
            }
        } catch (e: Exception) {
            android.util.Log.e("FilesBridge", "Çıkış aygıtları alınamadı: ${e.message}")
            emptyList()
        }
    }

    /**
     * MIDI/XMF gibi sentezlenen dosyaları yerleşik MediaPlayer ile çalar.
     * Hazır olduğunda `true`, çalınamazsa `false` döner.
     *
     * Aynı anda yalnızca bir MediaPlayer tutulur; eski çağrıların/parçaların
     * geri çağrıları `midiPlayer` kimlik kontrolü ile yok sayılır. Böylece
     * MIDI parça bitip sıradaki MIDI başlarken eski oynatıcının temizliği
     * yeni oynatıcıyı yanlışlıkla durduramaz.
     */
    private fun playMidi(uriString: String, result: MethodChannel.Result) {
        pendingMidiResult?.success(false)
        pendingMidiResult = null
        stopMidi()
        pendingMidiResult = result
        try {
            val player = MediaPlayer()
            player.setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                    .build()
            )
            player.setDataSource(this, Uri.parse(uriString))
            player.setOnPreparedListener { mp ->
                if (midiPlayer !== mp) return@setOnPreparedListener
                mp.start()
                if (pendingMidiResult === result) {
                    pendingMidiResult = null
                    result.success(true)
                }
            }
            player.setOnCompletionListener { mp ->
                if (midiPlayer !== mp) return@setOnCompletionListener
                midiEventSink?.success("completed")
                releasePlayer(mp)
            }
            player.setOnErrorListener { mp, what, extra ->
                android.util.Log.e("MidiBridge", "MIDI hata: what=$what extra=$extra")
                if (midiPlayer === mp) {
                    if (pendingMidiResult === result) {
                        pendingMidiResult = null
                        result.success(false)
                    }
                    releasePlayer(mp)
                }
                true
            }
            midiPlayer = player
            player.prepareAsync()
        } catch (e: Exception) {
            android.util.Log.e("MidiBridge", "MIDI çalınamadı: ${e.message}", e)
            if (pendingMidiResult === result) {
                pendingMidiResult = null
                result.success(false)
            }
            stopMidi()
        }
    }

    /** Sadece verilen oynatıcıyı serbest bırakır. */
    private fun releasePlayer(player: MediaPlayer) {
        try {
            player.release()
        } catch (_: Exception) {
        }
        if (midiPlayer === player) midiPlayer = null
    }

    private fun stopMidi() {
        pendingMidiResult?.success(false)
        pendingMidiResult = null
        val player = midiPlayer ?: return
        // Kimlik kontrolü için önce null'a çek, sonra serbest bırak.
        midiPlayer = null
        try {
            player.stop()
        } catch (_: Exception) {
        }
        try {
            player.release()
        } catch (_: Exception) {
        }
    }

    /**
     * Aktif bağlantının türünü, tahmini bağlantı hızını (Kbps) ve toplam
     * trafik sayaçlarını döner. TrafficStats cihaz geneli olduğu için
     * çağıran taraf iki ölçüm arasındaki farktan anlık hızı hesaplar.
     */
    private fun linkInfo(): Map<String, Any> {
        val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val caps = cm.getNetworkCapabilities(cm.activeNetwork)

        val type = when {
            caps == null -> "none"
            caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> "wifi"
            caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> "mobile"
            caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> "ethernet"
            caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN) -> "vpn"
            else -> "other"
        }

        val rx = TrafficStats.getTotalRxBytes().let { if (it < 0) 0L else it }
        val tx = TrafficStats.getTotalTxBytes().let { if (it < 0) 0L else it }

        return mapOf(
            "type" to type,
            "downKbps" to (caps?.linkDownstreamBandwidthKbps ?: 0),
            "upKbps" to (caps?.linkUpstreamBandwidthKbps ?: 0),
            "rxBytes" to rx,
            "txBytes" to tx,
        )
    }

    private fun hasAudioPermission(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return true
        return checkSelfPermission(audioPermission()) == PackageManager.PERMISSION_GRANTED
    }

    private fun audioPermission(): String =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            Manifest.permission.READ_MEDIA_AUDIO
        } else {
            Manifest.permission.READ_EXTERNAL_STORAGE
        }

    private fun audioPermissions(): Array<String> =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            arrayOf(Manifest.permission.READ_MEDIA_AUDIO)
        } else {
            arrayOf(Manifest.permission.READ_EXTERNAL_STORAGE)
        }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == permissionRequestCode) {
            val granted = grantResults.isNotEmpty() &&
                grantResults[0] == PackageManager.PERMISSION_GRANTED
            pendingPermissionResult?.success(granted)
            pendingPermissionResult = null
        } else if (requestCode == notificationRequestCode) {
            val granted = grantResults.isNotEmpty() &&
                grantResults[0] == PackageManager.PERMISSION_GRANTED
            pendingNotificationResult?.success(granted)
            pendingNotificationResult = null
        } else if (requestCode == quickNotePermissionCode) {
            val granted = grantResults.isNotEmpty() &&
                grantResults[0] == PackageManager.PERMISSION_GRANTED
            if (granted) {
                // İzin yeni verildi: hızlı not bildirimini hemen göster.
                QuickNoteNotification.post(this)
            }
        }
    }

    private fun audioCollection(): android.net.Uri =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            MediaStore.Audio.Media.getContentUri(MediaStore.VOLUME_EXTERNAL)
        } else {
            MediaStore.Audio.Media.EXTERNAL_CONTENT_URI
        }

    private fun playlistCollection(): android.net.Uri =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            MediaStore.Audio.Playlists.getContentUri(MediaStore.VOLUME_EXTERNAL)
        } else {
            MediaStore.Audio.Playlists.EXTERNAL_CONTENT_URI
        }

    /**
     * Masaüstü ("ULTİMATE") uygulamasının ürettiği "track id" ile aynı biçim:
     * depolama köküne göre göreli yol + dosya adı, küçük harf, eğik çizgi
     * (ör. `music/rock/parca.mp3`). Böylece çalma listeleri iki tarafta da
     * aynı anahtarları kullanır.
     *
     * Masaüstü kökü telefonun depolama köküyle eşlenir:
     * `C:\Users\bilal\Music`  <->  `/storage/emulated/0/`
     */
    private fun pcTrackId(relativePath: String?, displayName: String?): String {
        var rel = (relativePath ?: "").replace('\\', '/')
        val marker = "/storage/emulated/0/"
        val idx = rel.indexOf(marker)
        if (idx >= 0) rel = rel.substring(idx + marker.length)
        while (rel.startsWith("/")) rel = rel.substring(1)
        val full = rel + (displayName ?: "")
        return full.replace('\\', '/').lowercase()
    }

    private fun querySongs(): List<Map<String, Any?>> {
        val songs = mutableListOf<Map<String, Any?>>()
        val collection = audioCollection()

        val projection = arrayOf(
            MediaStore.Audio.Media._ID,
            MediaStore.Audio.Media.TITLE,
            MediaStore.Audio.Media.ARTIST,
            MediaStore.Audio.Media.ALBUM,
            MediaStore.Audio.Media.DURATION,
            MediaStore.Audio.Media.MIME_TYPE,
            MediaStore.Audio.Media.DATE_ADDED,
            MediaStore.Audio.Media.DISPLAY_NAME,
        )
        // Masaüstüyle ortak "track id" için göreli yol (Android Q+).
        val relPathColumn = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            MediaStore.Audio.Media.RELATIVE_PATH
        } else {
            MediaStore.Audio.Media.DATA
        }
        val projectionWithPath = projection + relPathColumn
        val selection = "${MediaStore.Audio.Media.IS_MUSIC} != 0"
        val sortOrder = "${MediaStore.Audio.Media.TITLE} COLLATE NOCASE ASC"

        contentResolver.query(collection, projectionWithPath, selection, null, sortOrder)?.use { cursor ->
            val idCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media._ID)
            val titleCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.TITLE)
            val artistCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.ARTIST)
            val albumCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.ALBUM)
            val durationCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DURATION)
            val mimeCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.MIME_TYPE)
            val dateCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DATE_ADDED)
            val nameCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DISPLAY_NAME)
            val pathCol = cursor.getColumnIndex(relPathColumn)

            while (cursor.moveToNext()) {
                val id = cursor.getLong(idCol)
                val uri = ContentUris.withAppendedId(collection, id).toString()
                val displayName = cursor.getString(nameCol) ?: ""
                val rawPath = if (pathCol >= 0) cursor.getString(pathCol) else null
                songs.add(
                    mapOf(
                        "id" to id,
                        "title" to (cursor.getString(titleCol) ?: "Bilinmeyen Parça"),
                        "artist" to (cursor.getString(artistCol) ?: "Bilinmeyen Sanatçı"),
                        "album" to cursor.getString(albumCol),
                        "duration" to cursor.getLong(durationCol),
                        "uri" to uri,
                        "mime" to cursor.getString(mimeCol),
                        "dateAdded" to cursor.getLong(dateCol),
                        "trackId" to pcTrackId(rawPath, displayName),
                    )
                )
            }
        }
        return songs
    }

    private fun queryPlaylists(): List<Map<String, Any?>> {
        val playlists = mutableListOf<Map<String, Any?>>()
        val projection = arrayOf(
            MediaStore.Audio.Playlists._ID,
            MediaStore.Audio.Playlists.NAME,
        )
        val sortOrder = "${MediaStore.Audio.Playlists.NAME} COLLATE NOCASE ASC"

        contentResolver.query(playlistCollection(), projection, null, null, sortOrder)?.use { cursor ->
            val idCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Playlists._ID)
            val nameCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Playlists.NAME)

            while (cursor.moveToNext()) {
                val id = cursor.getLong(idCol)
                val name = cursor.getString(nameCol) ?: continue
                playlists.add(
                    mapOf(
                        "id" to id,
                        "name" to name,
                        "count" to playlistSongCount(id),
                    )
                )
            }
        }
        return playlists
    }

    private fun playlistSongCount(playlistId: Long): Int {
        val uri = MediaStore.Audio.Playlists.Members.getContentUri("external", playlistId)
        return contentResolver
            .query(uri, arrayOf(MediaStore.Audio.Playlists.Members._ID), null, null, null)
            ?.use { it.count } ?: 0
    }

    private fun queryPlaylistSongs(playlistId: Long): List<Map<String, Any?>> {
        val songs = mutableListOf<Map<String, Any?>>()
        if (playlistId < 0) return songs

        val uri = MediaStore.Audio.Playlists.Members.getContentUri("external", playlistId)
        val projection = arrayOf(
            MediaStore.Audio.Playlists.Members.AUDIO_ID,
            MediaStore.Audio.Playlists.Members.TITLE,
            MediaStore.Audio.Playlists.Members.ARTIST,
            MediaStore.Audio.Playlists.Members.ALBUM,
            MediaStore.Audio.Playlists.Members.DURATION,
            MediaStore.Audio.Playlists.Members.MIME_TYPE,
            MediaStore.Audio.Playlists.Members.DATE_ADDED,
        )
        val media = audioCollection()

        contentResolver.query(uri, projection, null, null, null)?.use { cursor ->
            val audioIdCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Playlists.Members.AUDIO_ID)
            val titleCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Playlists.Members.TITLE)
            val artistCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Playlists.Members.ARTIST)
            val albumCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Playlists.Members.ALBUM)
            val durationCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Playlists.Members.DURATION)
            val mimeCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Playlists.Members.MIME_TYPE)
            val dateCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Playlists.Members.DATE_ADDED)

            while (cursor.moveToNext()) {
                val audioId = cursor.getLong(audioIdCol)
                songs.add(
                    mapOf(
                        "id" to audioId,
                        "title" to (cursor.getString(titleCol) ?: "Bilinmeyen Parça"),
                        "artist" to (cursor.getString(artistCol) ?: "Bilinmeyen Sanatçı"),
                        "album" to cursor.getString(albumCol),
                        "duration" to cursor.getLong(durationCol),
                        "uri" to ContentUris.withAppendedId(media, audioId).toString(),
                        "mime" to cursor.getString(mimeCol),
                        "dateAdded" to cursor.getLong(dateCol),
                    )
                )
            }
        }
        return songs
    }
}

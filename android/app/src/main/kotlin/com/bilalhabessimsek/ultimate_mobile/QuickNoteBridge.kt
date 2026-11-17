package com.bilalhabessimsek.ultimate_mobile

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject

/**
 * Bildirim, paylaş menüsü ve uygulama kısayolu üzerinden gelen "hızlı not"
 * isteklerini Dart tarafına iletir.
 *
 * [UltimateApplication] sayesinde süreç her zaman önbellekte bir
 * [io.flutter.embedding.engine.FlutterEngine] tutar; bu yüzden notlar doğrudan
 * Dart'a (oradan Supabase'e) gönderilebilir ve uygulama hiç açılmadan Notlar'a
 * düşer. Dart tarafı henüz hazır değilse (ör. süreç soğuk başlatıldı) istek
 * kısa aralıklarla yeniden denenir; yine başarısız olursa not diske kuyruklanır
 * ve uygulama açılışında iletilir.
 *
 * Dart kanalı: `ultimate_mobile/quick_note`
 *   save(text, open) -> {ok: Boolean}   (Supabase'e not ekler)
 *   openNew          -> {ok: Boolean}   (Notlar sekmesinde yeni not açar)
 */
object QuickNoteBridge {
    const val CHANNEL = "ultimate_mobile/quick_note"

    private const val PREFS = "QuickNotePrefs"
    private const val KEY_QUEUE = "pending_notes"

    /** Dart hazır olana kadar yapılan deneme sayısı ve iki deneme arası süre. */
    private const val MAX_ATTEMPTS = 24
    private const val RETRY_DELAY_MS = 250L

    private val handler = Handler(Looper.getMainLooper())

    /** Notu Dart'a iletir; başarısız olursa kuyruğa alır. */
    fun deliver(context: Context, text: String, open: Boolean) {
        val trimmed = text.trim()
        if (trimmed.isEmpty()) return
        tryDeliver(context.applicationContext, trimmed, open, 0)
    }

    /** Notlar sekmesinde yeni not ekranını açar (not metni gerekmez). */
    fun openNewNote(context: Context) {
        val engineId = UltimateApplication.ENGINE_ID
        if (FlutterEngineCache.getInstance().get(engineId) == null) {
            // Motor henüz yoksa sürecin kurulmasını bekle.
            retryOpen(context.applicationContext, 0)
            return
        }
        invokeOpenNew(context.applicationContext, 0)
    }

    /** Uygulama açılışında bekleyen (gönderilememiş) notları Dart'a gönderir. */
    fun drain(context: Context) {
        val ctx = context.applicationContext
        val pending = readQueue(ctx)
        if (pending.isEmpty()) return
        writeQueue(ctx, emptyList())
        for (item in pending) {
            tryDeliver(ctx, item.first, item.second, 0)
        }
    }

    // ------------------------------------------------------------- gönderim

    private fun tryDeliver(context: Context, text: String, open: Boolean, attempt: Int) {
        val engine = FlutterEngineCache.getInstance().get(UltimateApplication.ENGINE_ID)
        if (engine == null) {
            enqueue(context, text, open)
            return
        }
        val args = HashMap<String, Any>()
        args["text"] = text
        args["open"] = open

        try {
            MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
                .invokeMethod("save", args, object : MethodChannel.Result {
                    override fun success(result: Any?) {
                        // Dart "ok=false" dönerse (ör. ağ/oturum hatası) kuyruğa al.
                        val ok = result is Map<*, *> && result["ok"] == true
                        if (!ok) enqueue(context, text, open)
                    }

                    override fun error(
                        errorCode: String,
                        errorMessage: String?,
                        errorDetails: Any?,
                    ) {
                        // Dart işleyicisi henüz kayıtlı değil -> yeniden dene.
                        retryDeliver(context, text, open, attempt)
                    }

                    override fun notImplemented() {
                        retryDeliver(context, text, open, attempt)
                    }
                })
        } catch (_: Exception) {
            enqueue(context, text, open)
        }
    }

    private fun retryDeliver(context: Context, text: String, open: Boolean, attempt: Int) {
        if (attempt >= MAX_ATTEMPTS) {
            enqueue(context, text, open)
            return
        }
        handler.postDelayed({ tryDeliver(context, text, open, attempt + 1) }, RETRY_DELAY_MS)
    }

    private fun retryOpen(context: Context, attempt: Int) {
        if (attempt >= MAX_ATTEMPTS) return
        handler.postDelayed({ invokeOpenNew(context, attempt + 1) }, RETRY_DELAY_MS)
    }

    private fun invokeOpenNew(context: Context, attempt: Int) {
        val engine = FlutterEngineCache.getInstance().get(UltimateApplication.ENGINE_ID) ?: run {
            retryOpen(context, attempt)
            return
        }
        try {
            MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
                .invokeMethod("openNew", null, object : MethodChannel.Result {
                    override fun success(result: Any?) = Unit

                    override fun error(
                        errorCode: String,
                        errorMessage: String?,
                        errorDetails: Any?,
                    ) {
                        if (attempt < MAX_ATTEMPTS) {
                            handler.postDelayed(
                                { invokeOpenNew(context, attempt + 1) },
                                RETRY_DELAY_MS,
                            )
                        }
                    }

                    override fun notImplemented() {
                        if (attempt < MAX_ATTEMPTS) {
                            handler.postDelayed(
                                { invokeOpenNew(context, attempt + 1) },
                                RETRY_DELAY_MS,
                            )
                        }
                    }
                })
        } catch (_: Exception) {
        }
    }

    // ---------------------------------------------------------------- kuyruk

    private fun enqueue(context: Context, text: String, open: Boolean) {
        val queue = readQueue(context).toMutableList()
        queue.add(text to open)
        writeQueue(context, queue)
    }

    private fun readQueue(context: Context): List<Pair<String, Boolean>> {
        val raw = prefs(context).getString(KEY_QUEUE, null) ?: return emptyList()
        val result = mutableListOf<Pair<String, Boolean>>()
        try {
            val array = JSONArray(raw)
            for (i in 0 until array.length()) {
                val item = array.optJSONObject(i) ?: continue
                val text = item.optString("text")
                if (text.isBlank()) continue
                result.add(text to item.optBoolean("open", false))
            }
        } catch (_: Exception) {
            // Bozuk kayıt: kuyruğu yok say.
        }
        return result
    }

    private fun writeQueue(context: Context, queue: List<Pair<String, Boolean>>) {
        val array = JSONArray()
        for (item in queue) {
            val obj = JSONObject()
            obj.put("text", item.first)
            obj.put("open", item.second)
            array.put(obj)
        }
        prefs(context).edit().putString(KEY_QUEUE, array.toString()).apply()
    }

    private fun prefs(context: Context) =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
}

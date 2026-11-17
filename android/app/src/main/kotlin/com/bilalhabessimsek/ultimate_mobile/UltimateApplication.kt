package com.bilalhabessimsek.ultimate_mobile

import android.app.Application
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor

/**
 * Uygulama süreci açılırken TEK bir [FlutterEngine] oluşturur ve önbelleğe alır.
 *
 * Motor artık herhangi bir Activity'ye bağlı olmadığı için kullanıcı uygulamayı
 * son uygulamalar ekranından kaydırsa bile (Activity yok olsa bile) Dart
 * izolatı ve müzik motoru (just_audio) yaşamaya devam eder.
 * [MediaPlaybackService] ön plan servisi de süreçle birlikte ayakta kalır;
 * böylece "önbellek/son uygulamalar temizlense bile" müzik durmaz.
 *
 * [MainActivity] bu motoru `getCachedEngineId()` ile üzerine bağlanır; Activity
 * yeniden yaratıldığında uygulama sıfırdan değil, aynı Dart durumundan devam eder.
 */
class UltimateApplication : Application() {

    override fun onCreate() {
        super.onCreate()
        val engine = FlutterEngine(this)
        engine.dartExecutor.executeDartEntrypoint(
            DartExecutor.DartEntrypoint.createDefault(),
        )
        FlutterEngineCache.getInstance().put(ENGINE_ID, engine)
    }

    companion object {
        /** [FlutterEngineCache] içindeki tek motorun kimliği. */
        const val ENGINE_ID = "ultimate_mobile_engine"
    }
}

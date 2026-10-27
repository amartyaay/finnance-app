package com.amartyaay.finnance_app

import android.content.BroadcastReceiver
import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Runs one Dart entry point in a headless engine from a broadcast receiver,
 * so background work uses the app's single (Dart) parser instead of a second
 * copy in Kotlin. Dart talks back on [CHANNEL]; calling "done" (or the 9 s
 * budget a broadcast gets) tears the engine down and finishes the broadcast.
 */
object HeadlessDart {
    const val CHANNEL = "finnance_app/headless"

    fun run(
        receiver: BroadcastReceiver,
        context: Context,
        entrypoint: String,
        args: List<String>,
        onCall: (Context, MethodCall) -> Unit,
    ) {
        val app = context.applicationContext
        val pending = receiver.goAsync()
        val main = Handler(Looper.getMainLooper())
        main.post {
            var engine: FlutterEngine? = null
            var finished = false
            fun finish() {
                if (finished) return
                finished = true
                engine?.destroy()
                pending.finish()
            }
            try {
                val loader = FlutterInjector.instance().flutterLoader()
                loader.startInitialization(app)
                loader.ensureInitializationComplete(app, null)
                engine = FlutterEngine(app)
                MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
                    .setMethodCallHandler { call, result ->
                        if (call.method == "done") {
                            result.success(null)
                            finish()
                        } else {
                            onCall(app, call)
                            result.success(null)
                        }
                    }
                engine.dartExecutor.executeDartEntrypoint(
                    DartExecutor.DartEntrypoint(loader.findAppBundlePath(), entrypoint),
                    args,
                )
                main.postDelayed({ finish() }, 9_000)
            } catch (error: Throwable) {
                finish()
            }
        }
    }
}

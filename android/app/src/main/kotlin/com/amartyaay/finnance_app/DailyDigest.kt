package com.amartyaay.finnance_app

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import java.util.Calendar

/**
 * The 10 pm spending summary.
 *
 * An inexact alarm (no exact-alarm permission needed; Android may deliver it
 * a few minutes late in Doze) wakes [DailyDigestReceiver], which starts a
 * headless Flutter engine on `digestMain`. Dart parses the alerts the SMS
 * receiver stored today, measures the month against the budget and calls
 * back with the text; this side posts it and re-arms the next day.
 */
object DailyDigest {
    const val CHANNEL = "finnance_app/digest"
    private const val NOTIFICATION_CHANNEL = "daily_digest"
    private const val NOTIFICATION_ID = 2200
    private const val PREFS = "daily_digest"
    private const val HOUR = 22

    fun setEnabled(context: Context, enabled: Boolean) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit().putBoolean("enabled", enabled).apply()
        if (enabled) schedule(context) else cancel(context)
    }

    fun isEnabled(context: Context): Boolean =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getBoolean("enabled", true)

    /** Arms the next 10 pm (today if it is still before 10 pm). */
    fun schedule(context: Context) {
        if (!isEnabled(context)) return
        val next = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, HOUR)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
            if (timeInMillis <= System.currentTimeMillis() + 60_000) {
                add(Calendar.DAY_OF_YEAR, 1)
            }
        }
        val manager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        // setAndAllowWhileIdle alone gave a one-hour window (10-11 pm) on the
        // S24 FE. A 10-minute window needs no exact-alarm permission; Doze
        // can still hold it to the next maintenance window.
        manager.setWindow(
            AlarmManager.RTC_WAKEUP,
            next.timeInMillis,
            10 * 60 * 1000L,
            pendingIntent(context),
        )
    }

    fun cancel(context: Context) {
        val manager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        manager.cancel(pendingIntent(context))
    }

    fun post(context: Context, title: String, body: String) {
        if (Build.VERSION.SDK_INT >= 33 &&
            context.checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            return
        }
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= 26) {
            manager.createNotificationChannel(
                NotificationChannel(
                    NOTIFICATION_CHANNEL,
                    "Daily summary",
                    NotificationManager.IMPORTANCE_DEFAULT,
                ).apply {
                    description = "How much you spent today and how the month's budget looks, at 10 pm."
                    setShowBadge(false)
                },
            )
        }
        val open = PendingIntent.getActivity(
            context,
            NOTIFICATION_ID,
            Intent(context, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                .putExtra("open", "budget"),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val builder = if (Build.VERSION.SDK_INT >= 26) {
            Notification.Builder(context, NOTIFICATION_CHANNEL)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(context)
        }
        manager.notify(
            NOTIFICATION_ID,
            builder
                .setSmallIcon(R.mipmap.ic_launcher)
                .setContentTitle(title)
                .setContentText(body)
                .setStyle(Notification.BigTextStyle().bigText(body))
                .setContentIntent(open)
                .setAutoCancel(true)
                .build(),
        )
    }

    private fun pendingIntent(context: Context): PendingIntent =
        PendingIntent.getBroadcast(
            context,
            NOTIFICATION_ID,
            Intent(context, DailyDigestReceiver::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
}

/** Fired at 10 pm: runs `digestMain` headless, posts its text, re-arms. */
class DailyDigestReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val app = context.applicationContext
        // Re-arm first, so a crash below never loses tomorrow's summary.
        DailyDigest.schedule(app)
        if (!DailyDigest.isEnabled(app)) return

        val pending = goAsync()
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
                MethodChannel(engine.dartExecutor.binaryMessenger, DailyDigest.CHANNEL)
                    .setMethodCallHandler { call, result ->
                        when (call.method) {
                            "post" -> {
                                DailyDigest.post(
                                    app,
                                    call.argument<String>("title") ?: "Hisaab",
                                    call.argument<String>("body") ?: "",
                                )
                                result.success(null)
                            }
                            "schedule" -> result.success(null)
                            "done" -> {
                                result.success(null)
                                finish()
                            }
                            else -> result.notImplemented()
                        }
                    }
                engine.dartExecutor.executeDartEntrypoint(
                    DartExecutor.DartEntrypoint(loader.findAppBundlePath(), "digestMain"),
                )
                // A broadcast gets about 10 s of goAsync time; never hold it.
                main.postDelayed({ finish() }, 9_000)
            } catch (error: Throwable) {
                finish()
            }
        }
    }
}

/** Re-arms the alarm after a reboot or an app update (alarms do not survive). */
class DailyDigestBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        DailyDigest.schedule(context.applicationContext)
    }
}

package com.amartyaay.finnance_app

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build

object TransactionNotificationHelper {
    const val CHANNEL_ID = "transaction_spend"
    const val ACTION_CLASSIFY = "com.amartyaay.finnance_app.ACTION_CLASSIFY"
    const val EXTRA_SMS_REF = "sms_ref"
    const val EXTRA_CATEGORY_NAME = "category_name"

    /**
     * Shows the spend with quick categories. Tapping a category writes a pending
     * category that the Flutter side applies on next open, so the user never has
     * to wait for the app to start.
     */
    fun showSpendNotification(
        context: Context,
        smsId: String,
        title: String,
        subtitle: String?
    ) {
        if (!canPostNotifications(context)) {
            return
        }

        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        ensureChannel(manager)

        // Title and subtitle come from Dart (amount formatted as ₹1,05,590).
        val text = subtitle?.takeIf { it.isNotBlank() } ?: "Tap to categorise"

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(context, CHANNEL_ID)
        } else {
            Notification.Builder(context)
        }

        val base = smsId.hashCode() * 10
        val notification = builder
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(text)
            .setAutoCancel(true)
            .setContentIntent(openApp(context, base + 1))
            .addAction(action(context, smsId, "Food", base + 2))
            .addAction(action(context, smsId, "Travel", base + 3))
            .addAction(action(context, smsId, "Shopping", base + 4))
            .build()

        manager.notify(smsId.hashCode(), notification)
    }

    fun cancel(context: Context, smsId: String) {
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.cancel(smsId.hashCode())
    }

    private fun action(
        context: Context,
        smsId: String,
        category: String,
        requestCode: Int
    ): Notification.Action {
        val intent = Intent(context, CategoryActionReceiver::class.java).apply {
            action = ACTION_CLASSIFY
            putExtra(EXTRA_SMS_REF, smsId)
            putExtra(EXTRA_CATEGORY_NAME, category)
        }
        val pending = PendingIntent.getBroadcast(context, requestCode, intent, flags())
        return Notification.Action.Builder(R.mipmap.ic_launcher, category, pending).build()
    }

    private fun openApp(context: Context, requestCode: Int): PendingIntent {
        val intent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        return PendingIntent.getActivity(context, requestCode, intent, flags())
    }

    private fun ensureChannel(manager: NotificationManager) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        manager.createNotificationChannel(
            NotificationChannel(
                CHANNEL_ID,
                "Spending alerts",
                NotificationManager.IMPORTANCE_DEFAULT
            ).apply {
                description = "New card and UPI payments, with one-tap categories."
            }
        )
    }

    private fun canPostNotifications(context: Context): Boolean {
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
    }

    private fun flags(): Int {
        var value = PendingIntent.FLAG_UPDATE_CURRENT
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            value = value or PendingIntent.FLAG_IMMUTABLE
        }
        return value
    }
}

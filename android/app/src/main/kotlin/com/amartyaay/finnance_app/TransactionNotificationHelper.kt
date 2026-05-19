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
    const val CHANNEL_ID = "transaction_classification"
    const val ACTION_CLASSIFY = "com.amartyaay.finnance_app.ACTION_CLASSIFY"
    const val EXTRA_TRANSACTION_ID = "transaction_id"
    const val EXTRA_CATEGORY_NAME = "category_name"

    fun showClassificationNotification(
        context: Context,
        transaction: InsertedTransaction
    ) {
        if (!canPostNotifications(context)) {
            return
        }

        val notificationManager =
            context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        ensureChannel(notificationManager)

        val title = "Classify ${formatAmount(transaction.amountPaise)}"
        val merchant = transaction.merchant ?: transaction.instrument.replaceFirstChar {
            if (it.isLowerCase()) it.titlecase() else it.toString()
        }

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(context, CHANNEL_ID)
        } else {
            Notification.Builder(context)
        }

        val notification = builder
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(merchant)
            .setAutoCancel(true)
            .setContentIntent(openAppPendingIntent(context, transaction.id, "Other"))
            .addAction(
                R.mipmap.ic_launcher,
                "Food",
                classifyPendingIntent(context, transaction.id, "Food", 1)
            )
            .addAction(
                R.mipmap.ic_launcher,
                "Travel",
                classifyPendingIntent(context, transaction.id, "Travel", 2)
            )
            .addAction(
                R.mipmap.ic_launcher,
                "Other",
                openAppPendingIntent(context, transaction.id, "Other")
            )
            .build()

        notificationManager.notify(transaction.id.toInt(), notification)
    }

    fun cancel(context: Context, transactionId: Long) {
        val notificationManager =
            context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        notificationManager.cancel(transactionId.toInt())
    }

    private fun classifyPendingIntent(
        context: Context,
        transactionId: Long,
        categoryName: String,
        requestOffset: Int
    ): PendingIntent {
        val intent = Intent(context, CategoryActionReceiver::class.java).apply {
            action = ACTION_CLASSIFY
            putExtra(EXTRA_TRANSACTION_ID, transactionId)
            putExtra(EXTRA_CATEGORY_NAME, categoryName)
        }
        return PendingIntent.getBroadcast(
            context,
            transactionId.toInt() * 10 + requestOffset,
            intent,
            pendingIntentFlags()
        )
    }

    private fun openAppPendingIntent(
        context: Context,
        transactionId: Long,
        categoryName: String
    ): PendingIntent {
        val intent = Intent(context, MainActivity::class.java).apply {
            action = Intent.ACTION_VIEW
            putExtra(EXTRA_TRANSACTION_ID, transactionId)
            putExtra(EXTRA_CATEGORY_NAME, categoryName)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        return PendingIntent.getActivity(
            context,
            transactionId.toInt() * 10 + 3,
            intent,
            pendingIntentFlags()
        )
    }

    private fun ensureChannel(notificationManager: NotificationManager) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return
        }

        val channel = NotificationChannel(
            CHANNEL_ID,
            "Transaction classification",
            NotificationManager.IMPORTANCE_DEFAULT
        ).apply {
            description = "Prompts to categorize new expense SMS alerts."
        }
        notificationManager.createNotificationChannel(channel)
    }

    private fun canPostNotifications(context: Context): Boolean {
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
    }

    private fun pendingIntentFlags(): Int {
        return PendingIntent.FLAG_UPDATE_CURRENT or
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                PendingIntent.FLAG_IMMUTABLE
            } else {
                0
            }
    }

    private fun formatAmount(amountPaise: Long): String {
        val rupees = amountPaise / 100
        val paise = amountPaise % 100
        return if (paise == 0L) {
            "Rs.$rupees"
        } else {
            "Rs.$rupees.${paise.toString().padStart(2, '0')}"
        }
    }
}

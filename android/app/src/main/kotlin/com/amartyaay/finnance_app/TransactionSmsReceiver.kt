package com.amartyaay.finnance_app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.provider.Telephony

/**
 * Captures every SMS while the app is closed and asks the app's own Dart
 * parser (headless, `smsAlertMain`) whether it is a real spend worth a
 * notification. The same classifier and ledger guards as the app decide, so
 * a promotion ("Rs.500 benefits", "Rs.50 expire tonight") is never a spend.
 */
class TransactionSmsReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Telephony.Sms.Intents.SMS_RECEIVED_ACTION) {
            return
        }

        val messages = Telephony.Sms.Intents.getMessagesFromIntent(intent)
        if (messages.isEmpty()) {
            return
        }

        val sender = messages.firstOrNull()?.displayOriginatingAddress.orEmpty()
        val timestampMillis = messages.maxOfOrNull { it.timestampMillis } ?: System.currentTimeMillis()
        val body = messages.joinToString(separator = "") { it.displayMessageBody.orEmpty() }
        if (body.isBlank()) {
            return
        }

        val store = RawSmsStore(context)
        val smsId = store.insertSms(sender, body, timestampMillis) ?: return

        HeadlessDart.run(
            this,
            context,
            "smsAlertMain",
            listOf(sender, body, timestampMillis.toString()),
        ) { ctx, call ->
            if (call.method == "spend") {
                TransactionNotificationHelper.showSpendNotification(
                    context = ctx,
                    smsId = smsId,
                    title = call.argument<String>("title") ?: return@run,
                    subtitle = call.argument<String>("subtitle"),
                )
            }
        }
    }
}

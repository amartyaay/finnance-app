package com.amartyaay.finnance_app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.provider.Telephony

/**
 * Captures transaction SMS while the app is closed.
 *
 * It only stores the raw message; Dart classifies and parses it on next open.
 * The notification is a convenience preview so the user sees the spend now.
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

        // Preview only: a cheap parse so the notification can show an amount.
        val parsed = NativeSmsParser.parse(sender, body, timestampMillis) ?: return
        if (parsed.direction != "expense") {
            return
        }
        TransactionNotificationHelper.showSpendNotification(
            context = context,
            smsId = smsId,
            amountPaise = parsed.amountPaise,
            merchant = parsed.merchant
        )
    }
}

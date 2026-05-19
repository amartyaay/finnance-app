package com.amartyaay.finnance_app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.provider.Telephony

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

        val parsed = NativeSmsParser.parse(sender, body, timestampMillis) ?: return
        val inserted = NativeFinanceDatabase(context).insertTransaction(parsed) ?: return

        if (inserted.direction == "expense") {
            TransactionNotificationHelper.showClassificationNotification(context, inserted)
        }
    }
}

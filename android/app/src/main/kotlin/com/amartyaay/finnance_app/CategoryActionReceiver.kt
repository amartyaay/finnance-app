package com.amartyaay.finnance_app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Handles a category tapped in the spend notification.
 *
 * It queues the choice rather than writing the transaction: Dart owns the
 * transactions table and will apply this when it next loads.
 */
class CategoryActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != TransactionNotificationHelper.ACTION_CLASSIFY) {
            return
        }

        val smsRef = intent.getStringExtra(TransactionNotificationHelper.EXTRA_SMS_REF)
        val category = intent.getStringExtra(TransactionNotificationHelper.EXTRA_CATEGORY_NAME)
        if (smsRef.isNullOrBlank() || category.isNullOrBlank()) {
            return
        }

        RawSmsStore(context).addPendingCategory(smsRef, category)
        TransactionNotificationHelper.cancel(context, smsRef)
    }
}

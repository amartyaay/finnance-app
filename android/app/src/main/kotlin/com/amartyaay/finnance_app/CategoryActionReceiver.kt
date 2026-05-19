package com.amartyaay.finnance_app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class CategoryActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != TransactionNotificationHelper.ACTION_CLASSIFY) {
            return
        }

        val transactionId = intent.getLongExtra(
            TransactionNotificationHelper.EXTRA_TRANSACTION_ID,
            -1L
        )
        val categoryName = intent.getStringExtra(
            TransactionNotificationHelper.EXTRA_CATEGORY_NAME
        )

        if (transactionId <= 0L || categoryName.isNullOrBlank()) {
            return
        }

        NativeFinanceDatabase(context).assignCategory(transactionId, categoryName)
        TransactionNotificationHelper.cancel(context, transactionId)
    }
}

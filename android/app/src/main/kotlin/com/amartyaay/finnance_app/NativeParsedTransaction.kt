package com.amartyaay.finnance_app

/** Result of the lightweight Kotlin parse, used only for the notification preview. */
data class NativeParsedTransaction(
    val sourceSmsId: String,
    val sender: String,
    val normalizedSender: String,
    val timestampMillis: Long,
    val amountPaise: Long,
    val direction: String,
    val instrument: String,
    val accountHint: String?,
    val merchant: String?,
    val referenceId: String?,
    val cardIssuer: String?,
    val cardLastDigits: String?,
    val confidence: Double
)
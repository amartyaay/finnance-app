package com.amartyaay.finnance_app

import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToLong

object NativeSmsParser {
    private val otpPattern =
        Regex("\\b(otp|one time password|verification code|do not share|never share)\\b", RegexOption.IGNORE_CASE)
    private val statementPattern =
        Regex("\\b(statement|mini statement|e-statement|account summary)\\b", RegexOption.IGNORE_CASE)
    private val promoPattern =
        Regex("\\b(offer|loan|pre-approved|promo|promotion|advertisement|apply now|limited time)\\b", RegexOption.IGNORE_CASE)
    private val creditLikePattern =
        Regex("\\b(credited|credit received|received|refund|reversal|reversed|cashback|cash back|returned|deposited|failed|declined|unsuccessful)\\b", RegexOption.IGNORE_CASE)
    private val debitLikePattern =
        Regex("\\b(debited|spent|paid|payment|purchase|purchased|charged|withdrawn|sent|transferred|used|billed)\\b", RegexOption.IGNORE_CASE)
    private val amountPattern =
        Regex("(?:rs\\.?|inr|\\u20B9)\\s*([0-9][0-9,]*(?:\\.[0-9]{1,2})?)", RegexOption.IGNORE_CASE)
    private val accountHintPattern =
        Regex("\\b(?:a/?c|acct|account|card|debit card|credit card|ending)\\s*[x*#-]*\\s*([0-9]{2,4})\\b", RegexOption.IGNORE_CASE)
    private val merchantPattern =
        Regex("\\b(?:at|to|towards|for|on)\\s+([A-Za-z0-9][A-Za-z0-9 .&@_-]{2,50})", RegexOption.IGNORE_CASE)

    fun parse(sender: String, body: String, timestampMillis: Long): NativeParsedTransaction? {
        val trimmedBody = body.trim()
        if (trimmedBody.isEmpty()) {
            return null
        }

        val lowerBody = trimmedBody.lowercase()
        if (
            otpPattern.containsMatchIn(lowerBody) ||
            statementPattern.containsMatchIn(lowerBody) ||
            promoPattern.containsMatchIn(lowerBody) ||
            creditLikePattern.containsMatchIn(lowerBody)
        ) {
            return null
        }

        if (
            !debitLikePattern.containsMatchIn(lowerBody) &&
            !lowerBody.contains("upi") &&
            !lowerBody.contains("wallet") &&
            !lowerBody.contains("card")
        ) {
            return null
        }

        val amountMatch = bestAmountMatch(trimmedBody, lowerBody) ?: return null
        val amountPaise = amountToPaise(amountMatch.groupValues[1])
        if (amountPaise <= 0L) {
            return null
        }

        val normalizedSender = normalizeSender(sender)
        val instrument = detectInstrument(lowerBody)
        val merchant = extractMerchant(trimmedBody)
        val confidence = confidenceScore(normalizedSender, lowerBody, instrument, merchant)

        return NativeParsedTransaction(
            sourceSmsId = sourceSmsId(normalizedSender, timestampMillis, amountPaise, trimmedBody),
            sender = sender,
            normalizedSender = normalizedSender,
            timestampMillis = timestampMillis,
            amountPaise = amountPaise,
            instrument = instrument,
            accountHint = accountHintPattern.find(trimmedBody)?.groupValues?.getOrNull(1),
            merchant = merchant,
            confidence = confidence
        )
    }

    private fun bestAmountMatch(body: String, lowerBody: String): MatchResult? {
        return amountPattern.findAll(body).maxByOrNull { scoreAmountMatch(it, lowerBody) }
    }

    private fun scoreAmountMatch(match: MatchResult, lowerBody: String): Int {
        val start = max(0, match.range.first - 70)
        val end = min(lowerBody.length, match.range.last + 71)
        val window = lowerBody.substring(start, end)

        var score = 0
        if (debitLikePattern.containsMatchIn(window)) score += 4
        if (window.contains("upi")) score += 2
        if (window.contains("card")) score += 2
        if (window.contains("wallet")) score += 1
        if (
            window.contains("balance") ||
            window.contains("available") ||
            window.contains("avl") ||
            window.contains("minimum")
        ) {
            score -= 3
        }
        return score
    }

    private fun amountToPaise(rawAmount: String): Long {
        return ((rawAmount.replace(",", "").toDoubleOrNull() ?: 0.0) * 100).roundToLong()
    }

    fun normalizeSender(sender: String): String {
        val cleaned = sender.uppercase().trim().replace(Regex("[^A-Z0-9-]"), "")
        if (cleaned.isEmpty()) {
            return cleaned
        }

        val parts = cleaned.split("-").filter { it.isNotEmpty() }.toMutableList()
        if (parts.size > 1 && Regex("^[A-Z]{2}$").matches(parts.first())) {
            parts.removeAt(0)
        }
        while (parts.size > 1 && Regex("^[TSPG]$").matches(parts.last())) {
            parts.removeAt(parts.lastIndex)
        }
        return if (parts.isEmpty()) cleaned.replace("-", "") else parts.joinToString("-")
    }

    private fun detectInstrument(lowerBody: String): String {
        return when {
            lowerBody.contains("upi") ||
                lowerBody.contains("@upi") ||
                lowerBody.contains(" vpa ") ||
                lowerBody.contains("upi ref") ||
                lowerBody.contains("upiid") -> "upi"
            lowerBody.contains("wallet") ||
                lowerBody.contains("paytm") ||
                lowerBody.contains("phonepe") ||
                lowerBody.contains("google pay") ||
                lowerBody.contains("gpay") ||
                lowerBody.contains("amazon pay") -> "wallet"
            lowerBody.contains("credit card") || lowerBody.contains("card used") -> "creditCard"
            lowerBody.contains("debit card") ||
                lowerBody.contains("atm card") ||
                lowerBody.contains("card ending") ||
                lowerBody.contains("card xx") ||
                lowerBody.contains("card x") -> "debitCard"
            lowerBody.contains("account") || lowerBody.contains("a/c") -> "account"
            else -> "unknown"
        }
    }

    private fun extractMerchant(body: String): String? {
        for (match in merchantPattern.findAll(body)) {
            val candidate = cleanMerchant(match.groupValues[1])
            val lowerCandidate = candidate.lowercase()
            if (
                candidate.isNotEmpty() &&
                !lowerCandidate.contains("your account") &&
                !lowerCandidate.contains("a/c") &&
                !lowerCandidate.contains("bank") &&
                !lowerCandidate.contains("transaction") &&
                !lowerCandidate.contains("payment") &&
                !lowerCandidate.contains("inr") &&
                !lowerCandidate.contains("rs.") &&
                !Regex("\\d").containsMatchIn(lowerCandidate)
            ) {
                return candidate
            }
        }
        return null
    }

    private fun cleanMerchant(value: String): String {
        return value
            .trim()
            .replace(Regex("\\s+"), " ")
            .replace(Regex("[.,;:!?]+$"), "")
            .replace(Regex("\\s+on\\s+\\d.*$", RegexOption.IGNORE_CASE), "")
            .replace(
                Regex("\\b(via|ref|upi|imps|neft|rtgs|txn|transaction)\\b.*$", RegexOption.IGNORE_CASE),
                ""
            )
            .trim()
    }

    private fun confidenceScore(
        normalizedSender: String,
        lowerBody: String,
        instrument: String,
        merchant: String?
    ): Double {
        var score = 0.45
        if (normalizedSender.isNotEmpty()) score += 0.15
        if (debitLikePattern.containsMatchIn(lowerBody)) score += 0.15
        if (instrument != "unknown") score += 0.1
        if (!merchant.isNullOrBlank()) score += 0.1
        return score.coerceIn(0.0, 0.99)
    }

    private fun sourceSmsId(
        normalizedSender: String,
        timestampMillis: Long,
        amountPaise: Long,
        body: String
    ): String {
        val fingerprint = "$normalizedSender|${timestampMillis / 60000}|$amountPaise|${body.trim()}"
        return "sms_${fnv1a64(fingerprint)}"
    }

    private fun fnv1a64(value: String): String {
        var hash = 0xcbf29ce484222325UL
        val prime = 0x100000001b3UL
        for (char in value) {
            hash = hash xor char.code.toULong()
            hash *= prime
        }
        return hash.toString(16).padStart(16, '0')
    }
}

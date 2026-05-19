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
        Regex("\\b(offer|loan offer|pre-approved|promo|promotion|advertisement|apply now|limited time)\\b", RegexOption.IGNORE_CASE)
    private val creditLikePattern =
        Regex("\\b(credited|credit received|received|refund|reversal|reversed|cashback|cash back|returned|deposited|failed|declined|unsuccessful)\\b", RegexOption.IGNORE_CASE)
    private val debitLikePattern =
        Regex("\\b(debited|spent|paid|payment|purchase|purchased|charged|withdrawn|sent|transferred|used|billed)\\b", RegexOption.IGNORE_CASE)
    private val creditCardBillPaymentPattern =
        Regex(
            "\\b(?:credit\\s*card|cc|card)\\s*(?:bill|payment|repayment|dues?|outstanding|statement)\\b|" +
                "\\b(?:billpay|billdesk|bbps|bharat\\s+bill\\s*pay|cred|cheq)\\b.{0,80}\\b(?:credit\\s*card|card\\s*bill|cc)\\b|" +
                "\\b(?:paid|payment|debited|sent|transferred)\\b.{0,80}\\b(?:sbi\\s*card|hdfc\\s*(?:bank\\s*)?credit\\s*card|icici\\s*(?:bank\\s*)?credit\\s*card|axis\\s*(?:bank\\s*)?credit\\s*card|kotak\\s*credit\\s*card)\\b",
            RegexOption.IGNORE_CASE
        )
    private val storedValueLoadPattern =
        Regex(
            "\\b(?:upi\\s*lite|wallet)\\b.{0,60}\\b(?:top\\s*up|load(?:ed)?|add(?:ed)?\\s+money|recharge)\\b|" +
                "\\b(?:top\\s*up|load(?:ed)?|add(?:ed)?\\s+money|recharge)\\b.{0,60}\\b(?:upi\\s*lite|wallet)\\b",
            RegexOption.IGNORE_CASE
        )
    private val selfTransferPattern =
        Regex("\\b(?:self\\s*transfer|own\\s+account|to\\s+your\\s+(?:own\\s+)?a/?c|between\\s+your\\s+accounts|to\\s+self)\\b", RegexOption.IGNORE_CASE)
    private val investmentTransferPattern =
        Regex("\\b(?:mutual\\s*fund|sip|systematic\\s+investment|demat|broker|zerodha|groww|upstox|indmoney|smallcase|nps|ppf|fixed\\s+deposit|recurring\\s+deposit|fd|rd)\\b", RegexOption.IGNORE_CASE)
    private val amountPattern =
        Regex("(?:rs\\.?|inr|\\u20B9)\\s*([0-9][0-9,]*(?:\\.[0-9]{1,2})?)", RegexOption.IGNORE_CASE)
    private val accountHintPattern =
        Regex("\\b(?:a/?c|acct|account|card|debit card|credit card|ending)\\s*[x*#-]*\\s*([0-9]{2,4})\\b", RegexOption.IGNORE_CASE)
    private val cardDigitsPattern =
        Regex("\\b(?:card(?:\\s*ending)?|ending|xx|x)\\s*[x*#-]*\\s*([0-9]{4,6})\\b", RegexOption.IGNORE_CASE)
    private val merchantPattern =
        Regex("\\b(?:at|to|towards|for|on)\\s+([A-Za-z0-9][A-Za-z0-9 .&@_-]{2,50})", RegexOption.IGNORE_CASE)
    private val referencePattern =
        Regex("\\b(?:upi\\s*(?:ref(?:erence)?|txn|transaction)?\\s*(?:no\\.?|id)?|utr|rrn|ref(?:erence)?\\s*(?:no\\.?|id)?|txn\\s*(?:id|no\\.?)|transaction\\s*(?:id|no\\.?))\\s*[:#-]?\\s*([A-Z0-9]{6,24})\\b", RegexOption.IGNORE_CASE)
    private val issuerPatterns = listOf(
        "HDFC Bank" to Regex("\\bhdfc\\b", RegexOption.IGNORE_CASE),
        "ICICI Bank" to Regex("\\bicici\\b", RegexOption.IGNORE_CASE),
        "SBI Card" to Regex("\\b(?:sbi\\s*card|sbicard)\\b", RegexOption.IGNORE_CASE),
        "Axis Bank" to Regex("\\baxis\\b", RegexOption.IGNORE_CASE),
        "Kotak" to Regex("\\bkotak\\b", RegexOption.IGNORE_CASE),
        "RBL Bank" to Regex("\\brbl\\b", RegexOption.IGNORE_CASE),
        "IndusInd Bank" to Regex("\\bindusind\\b", RegexOption.IGNORE_CASE),
        "IDFC FIRST Bank" to Regex("\\bidfc\\b", RegexOption.IGNORE_CASE),
        "Yes Bank" to Regex("\\byes\\s*bank\\b", RegexOption.IGNORE_CASE),
        "AU Bank" to Regex("\\bau\\s*(?:small\\s*finance\\s*)?bank\\b", RegexOption.IGNORE_CASE),
        "American Express" to Regex("\\b(?:american\\s*express|amex)\\b", RegexOption.IGNORE_CASE),
        "Standard Chartered" to Regex("\\b(?:standard\\s*chartered|stanchart)\\b", RegexOption.IGNORE_CASE)
    )

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
        val instrument = detectInstrument(lowerBody, normalizedSender)
        val merchant = extractMerchant(trimmedBody)
        val cardLastDigits = extractCardLastDigits(trimmedBody, lowerBody, instrument)
        val cardIssuer = extractCardIssuer(trimmedBody, normalizedSender, lowerBody, instrument, cardLastDigits)
        val confidence = confidenceScore(normalizedSender, lowerBody, instrument, merchant)

        return NativeParsedTransaction(
            sourceSmsId = sourceSmsId(normalizedSender, timestampMillis, amountPaise, trimmedBody),
            sender = sender,
            normalizedSender = normalizedSender,
            timestampMillis = timestampMillis,
            amountPaise = amountPaise,
            direction = detectDirection(lowerBody),
            instrument = instrument,
            accountHint = accountHintPattern.find(trimmedBody)?.groupValues?.getOrNull(1),
            merchant = merchant,
            referenceId = referencePattern.find(trimmedBody)?.groupValues?.getOrNull(1)?.uppercase(),
            cardIssuer = cardIssuer,
            cardLastDigits = cardLastDigits,
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

    private fun detectInstrument(lowerBody: String, normalizedSender: String): String {
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
            lowerBody.contains("credit card") ||
                lowerBody.contains("card used") ||
                (suggestedInstrument(normalizedSender) == "creditCard" && lowerBody.contains("card")) -> "creditCard"
            lowerBody.contains("debit card") ||
                lowerBody.contains("atm card") ||
                lowerBody.contains("card ending") ||
                lowerBody.contains("card xx") ||
                lowerBody.contains("card x") -> "debitCard"
            lowerBody.contains("account") || lowerBody.contains("a/c") -> "account"
            else -> suggestedInstrument(normalizedSender)
        }
    }

    private fun suggestedInstrument(normalizedSender: String): String {
        return when (normalizedSender.replace("-", "")) {
            "ICICIC", "SBICRD", "KOTAKC", "CCARD" -> "creditCard"
            "DEBITC" -> "debitCard"
            "SBIUPI", "UPI" -> "upi"
            "PAYTMB", "PHONEP", "GPAY", "GOOGLEP", "AMZNPAY", "AMAZON" -> "wallet"
            else -> "unknown"
        }
    }

    private fun cardIssuerForSender(normalizedSender: String): String? {
        return when (normalizedSender.replace("-", "")) {
            "ICICIC" -> "ICICI Bank"
            "SBICRD" -> "SBI Card"
            "KOTAKC" -> "Kotak"
            else -> null
        }
    }

    private fun detectDirection(lowerBody: String): String {
        return if (
            creditCardBillPaymentPattern.containsMatchIn(lowerBody) ||
            storedValueLoadPattern.containsMatchIn(lowerBody) ||
            selfTransferPattern.containsMatchIn(lowerBody) ||
            investmentTransferPattern.containsMatchIn(lowerBody)
        ) {
            "transfer"
        } else {
            "expense"
        }
    }

    private fun extractCardLastDigits(
        body: String,
        lowerBody: String,
        instrument: String
    ): String? {
        val isCreditCardRelated = instrument == "creditCard" ||
            creditCardBillPaymentPattern.containsMatchIn(lowerBody)
        if (!isCreditCardRelated) {
            return null
        }

        val digits = cardDigitsPattern.find(body)?.groupValues?.getOrNull(1)
            ?: accountHintPattern.find(body)?.groupValues?.getOrNull(1)
        return if (!digits.isNullOrBlank() && digits.length >= 4) digits else null
    }

    private fun extractCardIssuer(
        body: String,
        normalizedSender: String,
        lowerBody: String,
        instrument: String,
        cardLastDigits: String?
    ): String? {
        val isCreditCardRelated = instrument == "creditCard" ||
            creditCardBillPaymentPattern.containsMatchIn(lowerBody)
        if (!isCreditCardRelated || cardLastDigits.isNullOrBlank()) {
            return null
        }

        cardIssuerForSender(normalizedSender)?.let { return it }
        for ((issuer, pattern) in issuerPatterns) {
            if (pattern.containsMatchIn(body)) {
                return issuer
            }
        }
        return null
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

package com.amartyaay.finnance_app

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper

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

data class InsertedTransaction(
    val id: Long,
    val amountPaise: Long,
    val merchant: String?,
    val direction: String,
    val instrument: String
)

class NativeFinanceDatabase(context: Context) :
    SQLiteOpenHelper(context, DATABASE_NAME, null, DATABASE_VERSION) {

    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL(
            """
            CREATE TABLE IF NOT EXISTS transactions (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              source_sms_id TEXT NOT NULL UNIQUE,
              sender TEXT NOT NULL,
              normalized_sender TEXT NOT NULL,
              timestamp_millis INTEGER NOT NULL,
              amount_paise INTEGER NOT NULL,
              direction TEXT NOT NULL,
              instrument TEXT NOT NULL,
              account_hint TEXT,
              merchant TEXT,
              reference_id TEXT,
              card_issuer TEXT,
              card_last_digits TEXT,
              confidence REAL NOT NULL,
              category_id INTEGER,
              category_name TEXT,
              classified_at_millis INTEGER,
              created_at_millis INTEGER NOT NULL
            )
            """.trimIndent()
        )
        db.execSQL(
            """
            CREATE INDEX IF NOT EXISTS transactions_timestamp_idx
            ON transactions(timestamp_millis DESC)
            """.trimIndent()
        )
        db.execSQL(
            """
            CREATE INDEX IF NOT EXISTS transactions_reference_idx
            ON transactions(reference_id)
            """.trimIndent()
        )
        db.execSQL(
            """
            CREATE INDEX IF NOT EXISTS transactions_card_idx
            ON transactions(card_issuer, card_last_digits)
            """.trimIndent()
        )
        db.execSQL(
            """
            CREATE TABLE IF NOT EXISTS app_meta (
              key TEXT PRIMARY KEY,
              value TEXT NOT NULL
            )
            """.trimIndent()
        )
        createCategoriesTable(db)
        ensureDefaultCategories(db)
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
        if (oldVersion < 2) {
            addColumnIfMissing(db, "transactions", "category_id", "INTEGER")
            addColumnIfMissing(db, "transactions", "category_name", "TEXT")
            addColumnIfMissing(db, "transactions", "classified_at_millis", "INTEGER")
            createCategoriesTable(db)
            ensureDefaultCategories(db)
        }
        if (oldVersion < 3) {
            addColumnIfMissing(db, "transactions", "reference_id", "TEXT")
            db.execSQL(
                """
                CREATE INDEX IF NOT EXISTS transactions_reference_idx
                ON transactions(reference_id)
                """.trimIndent()
            )
        }
        if (oldVersion < 4) {
            addColumnIfMissing(db, "transactions", "card_issuer", "TEXT")
            addColumnIfMissing(db, "transactions", "card_last_digits", "TEXT")
            db.execSQL(
                """
                CREATE INDEX IF NOT EXISTS transactions_card_idx
                ON transactions(card_issuer, card_last_digits)
                """.trimIndent()
            )
        }
    }

    override fun onOpen(db: SQLiteDatabase) {
        super.onOpen(db)
        createCategoriesTable(db)
        ensureDefaultCategories(db)
    }

    fun insertTransaction(parsed: NativeParsedTransaction): InsertedTransaction? {
        val db = writableDatabase
        if (hasDuplicateTransaction(db, parsed)) {
            return null
        }

        val values = ContentValues().apply {
            put("source_sms_id", parsed.sourceSmsId)
            put("sender", parsed.sender)
            put("normalized_sender", parsed.normalizedSender)
            put("timestamp_millis", parsed.timestampMillis)
            put("amount_paise", parsed.amountPaise)
            put("direction", parsed.direction)
            put("instrument", parsed.instrument)
            put("account_hint", parsed.accountHint)
            put("merchant", parsed.merchant)
            put("reference_id", parsed.referenceId)
            put("card_issuer", parsed.cardIssuer)
            put("card_last_digits", parsed.cardLastDigits)
            put("confidence", parsed.confidence)
            put("created_at_millis", System.currentTimeMillis())
        }

        val id = db.insertWithOnConflict(
            "transactions",
            null,
            values,
            SQLiteDatabase.CONFLICT_IGNORE
        )
        if (id <= 0L) {
            return null
        }
        return InsertedTransaction(
            id = id,
            amountPaise = parsed.amountPaise,
            merchant = parsed.merchant,
            direction = parsed.direction,
            instrument = parsed.instrument
        )
    }

    fun assignCategory(transactionId: Long, categoryName: String) {
        val db = writableDatabase
        val categoryId = categoryIdForName(db, categoryName)
        db.update(
            "transactions",
            ContentValues().apply {
                put("category_id", categoryId)
                put("category_name", categoryName)
                put("classified_at_millis", System.currentTimeMillis())
            },
            "id = ?",
            arrayOf(transactionId.toString())
        )
    }

    private fun categoryIdForName(db: SQLiteDatabase, categoryName: String): Long {
        val normalizedName = normalizeCategoryName(categoryName)
        db.query(
            "categories",
            arrayOf("id"),
            "normalized_name = ?",
            arrayOf(normalizedName),
            null,
            null,
            null,
            "1"
        ).use { cursor ->
            if (cursor.moveToFirst()) {
                return cursor.getLong(0)
            }
        }

        return db.insert(
            "categories",
            null,
            ContentValues().apply {
                put("name", categoryName)
                put("normalized_name", normalizedName)
                put("is_default", 0)
                put("created_at_millis", System.currentTimeMillis())
            }
        )
    }

    private fun createCategoriesTable(db: SQLiteDatabase) {
        db.execSQL(
            """
            CREATE TABLE IF NOT EXISTS categories (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL UNIQUE,
              normalized_name TEXT NOT NULL UNIQUE,
              is_default INTEGER NOT NULL,
              created_at_millis INTEGER NOT NULL
            )
            """.trimIndent()
        )
    }

    private fun ensureDefaultCategories(db: SQLiteDatabase) {
        for (category in DEFAULT_CATEGORIES) {
            db.insertWithOnConflict(
                "categories",
                null,
                ContentValues().apply {
                    put("name", category)
                    put("normalized_name", normalizeCategoryName(category))
                    put("is_default", 1)
                    put("created_at_millis", System.currentTimeMillis())
                },
                SQLiteDatabase.CONFLICT_IGNORE
            )
        }
    }

    private fun addColumnIfMissing(
        db: SQLiteDatabase,
        table: String,
        column: String,
        type: String
    ) {
        db.rawQuery("PRAGMA table_info($table)", null).use { cursor ->
            while (cursor.moveToNext()) {
                if (cursor.getString(cursor.getColumnIndexOrThrow("name")) == column) {
                    return
                }
            }
        }
        db.execSQL("ALTER TABLE $table ADD COLUMN $column $type")
    }

    private fun hasDuplicateTransaction(
        db: SQLiteDatabase,
        parsed: NativeParsedTransaction
    ): Boolean {
        db.query(
            "transactions",
            arrayOf("id"),
            "source_sms_id = ?",
            arrayOf(parsed.sourceSmsId),
            null,
            null,
            null,
            "1"
        ).use { cursor ->
            if (cursor.moveToFirst()) {
                return true
            }
        }

        val referenceId = parsed.referenceId
        if (!referenceId.isNullOrBlank() && referenceId.length >= 6) {
            db.query(
                "transactions",
                arrayOf("id"),
                "reference_id = ? AND amount_paise = ?",
                arrayOf(referenceId, parsed.amountPaise.toString()),
                null,
                null,
                null,
                "1"
            ).use { cursor ->
                if (cursor.moveToFirst()) {
                    return true
                }
            }
        }

        val merchantKey = normalizeMatchText(parsed.merchant)
        if (merchantKey.length < 3) {
            return false
        }

        val duplicateWindowMillis = 2 * 60 * 1000L
        db.query(
            "transactions",
            arrayOf("normalized_sender", "merchant"),
            """
            amount_paise = ?
            AND direction = ?
            AND timestamp_millis BETWEEN ? AND ?
            """.trimIndent(),
            arrayOf(
                parsed.amountPaise.toString(),
                parsed.direction,
                (parsed.timestampMillis - duplicateWindowMillis).toString(),
                (parsed.timestampMillis + duplicateWindowMillis).toString()
            ),
            null,
            null,
            null
        ).use { cursor ->
            val senderIndex = cursor.getColumnIndexOrThrow("normalized_sender")
            val merchantIndex = cursor.getColumnIndexOrThrow("merchant")
            while (cursor.moveToNext()) {
                if (cursor.getString(senderIndex) == parsed.normalizedSender) {
                    continue
                }
                val existingMerchant = normalizeMatchText(cursor.getString(merchantIndex))
                if (similarMatchText(merchantKey, existingMerchant)) {
                    return true
                }
            }
        }
        return false
    }

    companion object {
        const val DATABASE_NAME = "finance_sms_mvp.db"
        private const val DATABASE_VERSION = 4
        val DEFAULT_CATEGORIES = listOf("Food", "Travel", "Lifestyle", "Education", "Bills")

        fun normalizeCategoryName(name: String): String {
            return name.trim().replace(Regex("\\s+"), " ").lowercase()
        }

        private fun normalizeMatchText(value: String?): String {
            return value.orEmpty().lowercase().replace(Regex("[^a-z0-9]+"), "").trim()
        }

        private fun similarMatchText(left: String, right: String): Boolean {
            if (left.isEmpty() || right.isEmpty()) return false
            if (left == right) return true
            if (left.length < 5 || right.length < 5) return false
            return left.contains(right) || right.contains(left)
        }
    }
}

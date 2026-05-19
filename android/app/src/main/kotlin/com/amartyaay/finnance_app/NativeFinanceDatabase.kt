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
    val instrument: String,
    val accountHint: String?,
    val merchant: String?,
    val confidence: Double
)

data class InsertedTransaction(
    val id: Long,
    val amountPaise: Long,
    val merchant: String?,
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
    }

    override fun onOpen(db: SQLiteDatabase) {
        super.onOpen(db)
        createCategoriesTable(db)
        ensureDefaultCategories(db)
    }

    fun insertTransaction(parsed: NativeParsedTransaction): InsertedTransaction? {
        val db = writableDatabase
        val values = ContentValues().apply {
            put("source_sms_id", parsed.sourceSmsId)
            put("sender", parsed.sender)
            put("normalized_sender", parsed.normalizedSender)
            put("timestamp_millis", parsed.timestampMillis)
            put("amount_paise", parsed.amountPaise)
            put("direction", "expense")
            put("instrument", parsed.instrument)
            put("account_hint", parsed.accountHint)
            put("merchant", parsed.merchant)
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

    companion object {
        const val DATABASE_NAME = "finance_sms_mvp.db"
        private const val DATABASE_VERSION = 2
        val DEFAULT_CATEGORIES = listOf("Food", "Travel", "Lifestyle", "Education", "Bills")

        fun normalizeCategoryName(name: String): String {
            return name.trim().replace(Regex("\\s+"), " ").lowercase()
        }
    }
}

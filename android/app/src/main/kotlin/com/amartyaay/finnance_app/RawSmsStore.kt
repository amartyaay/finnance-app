package com.amartyaay.finnance_app

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper

/**
 * The only table Kotlin writes: raw SMS captured in real time.
 *
 * Dart owns `transactions` and does all parsing, so there is exactly one parser
 * and no chance of the two sides drifting apart. This class deliberately does
 * not create or touch the transaction tables.
 */
class RawSmsStore(context: Context) :
    SQLiteOpenHelper(context.applicationContext, DATABASE_NAME, null, DATABASE_VERSION) {

    override fun onCreate(db: SQLiteDatabase) {
        createTables(db)
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
        createTables(db)
    }

    override fun onOpen(db: SQLiteDatabase) {
        super.onOpen(db)
        createTables(db)
    }

    private fun createTables(db: SQLiteDatabase) {
        db.execSQL(
            """
            CREATE TABLE IF NOT EXISTS sms_messages (
              id TEXT PRIMARY KEY,
              sender TEXT NOT NULL,
              body TEXT NOT NULL,
              received_at INTEGER NOT NULL,
              sender_normalized TEXT,
              class TEXT,
              score REAL,
              processed INTEGER NOT NULL DEFAULT 0
            )
            """.trimIndent()
        )
        db.execSQL(
            """
            CREATE INDEX IF NOT EXISTS sms_messages_processed_idx
            ON sms_messages(processed, received_at DESC)
            """.trimIndent()
        )
        db.execSQL(
            """
            CREATE TABLE IF NOT EXISTS pending_categories (
              sms_id TEXT PRIMARY KEY,
              category_name TEXT NOT NULL,
              created_at INTEGER NOT NULL
            )
            """.trimIndent()
        )
    }

    /**
     * Inserts a message and returns its content id (the same 16-hex hash the
     * Dart side uses as a transaction key), or null when it already existed.
     */
    fun insertSms(sender: String, body: String, receivedAtMs: Long): String? {
        val contentId = contentIdOf(sender, body, receivedAtMs)
        val values = ContentValues().apply {
            put("id", "rcv:$contentId")
            put("sender", sender)
            put("body", body)
            put("received_at", receivedAtMs)
            put("processed", 0)
        }
        val row = writableDatabase.insertWithOnConflict(
            "sms_messages",
            null,
            values,
            SQLiteDatabase.CONFLICT_IGNORE
        )
        return if (row > 0L) contentId else null
    }

    /** Queues a category chosen from the notification shade. */
    fun addPendingCategory(smsId: String, categoryName: String) {
        writableDatabase.insertWithOnConflict(
            "pending_categories",
            null,
            ContentValues().apply {
                put("sms_id", smsId)
                put("category_name", categoryName)
                put("created_at", System.currentTimeMillis())
            },
            SQLiteDatabase.CONFLICT_REPLACE
        )
    }

    companion object {
        const val DATABASE_NAME = "finance_sms.db"
        private const val DATABASE_VERSION = 6

        /** Identity of a message independent of the inbox row id. */
        fun contentIdOf(sender: String, body: String, receivedAtMs: Long): String {
            return Fnv1a.hash("$sender|$receivedAtMs|${body.trim()}")
        }
    }
}

/** Same algorithm as `lib/domain/hashing.dart`. */
object Fnv1a {
    fun hash(value: String): String {
        var hash = 0xcbf29ce484222325UL
        val prime = 0x100000001b3UL
        for (char in value) {
            hash = hash xor char.code.toULong()
            hash *= prime
        }
        return hash.toString(16).padStart(16, '0')
    }
}

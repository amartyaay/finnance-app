package com.amartyaay.finnance_app

import android.Manifest
import android.content.ContentValues
import android.content.pm.PackageManager
import android.os.Build
import android.os.Environment
import android.provider.BaseColumns
import android.provider.MediaStore
import android.provider.Telephony
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val smsReaderChannel = "finnance_app/sms_reader"
    private val exportChannel = "finnance_app/export"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, smsReaderChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "readInbox" -> {
                        if (!hasReadSmsPermission()) {
                            result.error(
                                "permission_denied",
                                "READ_SMS permission has not been granted.",
                                null
                            )
                            return@setMethodCallHandler
                        }

                        val limit = (call.argument<Int>("limit") ?: 1000).coerceIn(1, 5000)
                        val sinceMillis = call.argument<Number>("sinceMillis")?.toLong()
                        result.success(readInbox(limit, sinceMillis))
                    }

                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, exportChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "exportCsv" -> {
                        val fileName = call.argument<String>("fileName") ?: "finance-transactions.csv"
                        val csv = call.argument<String>("csv") ?: ""
                        try {
                            result.success(exportCsv(fileName, csv))
                        } catch (error: Exception) {
                            result.error("export_failed", error.message, null)
                        }
                    }

                    else -> result.notImplemented()
                }
            }
    }

    private fun hasReadSmsPermission(): Boolean {
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.M ||
            checkSelfPermission(Manifest.permission.READ_SMS) == PackageManager.PERMISSION_GRANTED
    }

    private fun readInbox(limit: Int, sinceMillis: Long?): List<Map<String, Any?>> {
        val messages = mutableListOf<Map<String, Any?>>()
        val projection = arrayOf(
            BaseColumns._ID,
            Telephony.Sms.ADDRESS,
            Telephony.Sms.BODY,
            Telephony.Sms.DATE
        )
        val selection = sinceMillis?.let { "${Telephony.Sms.DATE} >= ?" }
        val selectionArgs = sinceMillis?.let { arrayOf(it.toString()) }
        val sortOrder = "${Telephony.Sms.DATE} DESC"

        contentResolver.query(
            Telephony.Sms.Inbox.CONTENT_URI,
            projection,
            selection,
            selectionArgs,
            sortOrder
        )?.use { cursor ->
            val idIndex = cursor.getColumnIndexOrThrow(BaseColumns._ID)
            val senderIndex = cursor.getColumnIndexOrThrow(Telephony.Sms.ADDRESS)
            val bodyIndex = cursor.getColumnIndexOrThrow(Telephony.Sms.BODY)
            val dateIndex = cursor.getColumnIndexOrThrow(Telephony.Sms.DATE)

            while (cursor.moveToNext() && messages.size < limit) {
                messages.add(
                    mapOf(
                        "id" to cursor.getLong(idIndex).toString(),
                        "sender" to cursor.getString(senderIndex).orEmpty(),
                        "body" to cursor.getString(bodyIndex).orEmpty(),
                        "timestampMillis" to cursor.getLong(dateIndex)
                    )
                )
            }
        }

        return messages
    }

    private fun exportCsv(fileName: String, csv: String): String {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val values = ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
                put(MediaStore.MediaColumns.MIME_TYPE, "text/csv")
                put(
                    MediaStore.MediaColumns.RELATIVE_PATH,
                    Environment.DIRECTORY_DOWNLOADS + "/Finance SMS"
                )
            }
            val uri = contentResolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                ?: throw IllegalStateException("Could not create export file.")
            contentResolver.openOutputStream(uri)?.use { outputStream ->
                outputStream.write(csv.toByteArray(Charsets.UTF_8))
            } ?: throw IllegalStateException("Could not write export file.")
            uri.toString()
        } else {
            val directory = getExternalFilesDir(Environment.DIRECTORY_DOCUMENTS) ?: filesDir
            if (!directory.exists()) {
                directory.mkdirs()
            }
            val file = File(directory, fileName)
            file.writeText(csv, Charsets.UTF_8)
            file.absolutePath
        }
    }
}

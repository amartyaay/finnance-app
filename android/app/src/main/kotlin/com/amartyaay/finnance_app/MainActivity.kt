package com.amartyaay.finnance_app

import android.Manifest
import android.app.Activity
import android.content.ContentValues
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.BaseColumns
import android.provider.MediaStore
import android.provider.OpenableColumns
import android.provider.Telephony
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File

class MainActivity : FlutterActivity() {
    private val smsReaderChannel = "finnance_app/sms_reader"
    private val exportChannel = "finnance_app/export"
    private val importFileChannel = "finnance_app/import_file"
    private val importFileRequestCode = 4107
    private var pendingImportResult: MethodChannel.Result? = null

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

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, importFileChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pickImportFile" -> pickImportFile(result)
                    else -> result.notImplemented()
                }
            }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != importFileRequestCode) {
            return
        }

        val result = pendingImportResult ?: return
        pendingImportResult = null

        if (resultCode != Activity.RESULT_OK) {
            result.success(null)
            return
        }

        val uri = data?.data
        if (uri == null) {
            result.success(null)
            return
        }

        try {
            result.success(readImportFile(uri))
        } catch (error: Exception) {
            result.error("import_file_read_failed", error.message, null)
        }
    }

    private fun hasReadSmsPermission(): Boolean {
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.M ||
            checkSelfPermission(Manifest.permission.READ_SMS) == PackageManager.PERMISSION_GRANTED
    }

    private fun pickImportFile(result: MethodChannel.Result) {
        if (pendingImportResult != null) {
            result.error("picker_active", "Another import picker is already open.", null)
            return
        }

        pendingImportResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
            putExtra(
                Intent.EXTRA_MIME_TYPES,
                arrayOf(
                    "text/csv",
                    "text/comma-separated-values",
                    "application/pdf",
                    "image/png",
                    "image/jpeg",
                    "image/webp"
                )
            )
        }

        try {
            startActivityForResult(intent, importFileRequestCode)
        } catch (error: Exception) {
            pendingImportResult = null
            result.error("picker_unavailable", error.message, null)
        }
    }

    private fun readImportFile(uri: Uri): Map<String, Any?> {
        val name = displayNameFor(uri) ?: "import-file"
        val bytes = contentResolver.openInputStream(uri)?.use { input ->
            val output = ByteArrayOutputStream()
            input.copyTo(output)
            output.toByteArray()
        } ?: ByteArray(0)

        return mapOf(
            "name" to name,
            "bytes" to bytes
        )
    }

    private fun displayNameFor(uri: Uri): String? {
        contentResolver.query(
            uri,
            arrayOf(OpenableColumns.DISPLAY_NAME),
            null,
            null,
            null
        )?.use { cursor ->
            if (cursor.moveToFirst()) {
                val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (index >= 0) {
                    return cursor.getString(index)
                }
            }
        }

        return uri.lastPathSegment
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

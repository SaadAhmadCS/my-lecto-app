package com.lecto.lecto

import android.content.ContentValues
import android.os.Build
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {

    private val mergeExecutor = Executors.newSingleThreadExecutor()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            AUDIO_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "mergeChunks" -> {
                    val inputs = call.argument<List<String>>("inputs")
                    val output = call.argument<String>("output")

                    if (inputs.isNullOrEmpty() || output.isNullOrBlank()) {
                        result.error("bad_args", "inputs and output are required", null)
                        return@setMethodCallHandler
                    }

                    // Merging a 3-hour lecture copies tens of megabytes, which
                    // would jank the UI on the main thread.
                    mergeExecutor.execute {
                        val merged = runCatching { AudioMerger.merge(inputs, output) }
                        runOnUiThread {
                            merged.fold(
                                onSuccess = { result.success(it) },
                                onFailure = {
                                    result.error(
                                        "merge_failed",
                                        it.message ?: "Could not merge the audio",
                                        null,
                                    )
                                },
                            )
                        }
                    }
                }

                "saveToDownloads" -> {
                    val bytes = call.argument<ByteArray>("bytes")
                    val filename = call.argument<String>("filename")
                    val mimeType = call.argument<String>("mimeType") ?: "application/pdf"

                    if (bytes == null || filename.isNullOrBlank()) {
                        result.error("bad_args", "bytes and filename are required", null)
                        return@setMethodCallHandler
                    }
                    // MediaStore's Downloads collection needs Android 10;
                    // older phones share instead.
                    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
                        result.success(false)
                        return@setMethodCallHandler
                    }

                    mergeExecutor.execute {
                        val saved = runCatching { saveToDownloads(bytes, filename, mimeType) }
                        runOnUiThread {
                            saved.fold(
                                onSuccess = { result.success(true) },
                                onFailure = {
                                    result.error("save_failed", it.message, null)
                                },
                            )
                        }
                    }
                }

                else -> result.notImplemented()
            }
        }
    }

    /** Write [bytes] to Downloads through MediaStore — no storage permission needed. */
    @android.annotation.TargetApi(Build.VERSION_CODES.Q)
    private fun saveToDownloads(bytes: ByteArray, filename: String, mimeType: String) {
        val values = ContentValues().apply {
            put(MediaStore.Downloads.DISPLAY_NAME, filename)
            put(MediaStore.Downloads.MIME_TYPE, mimeType)
            put(MediaStore.Downloads.IS_PENDING, 1)
        }
        val resolver = contentResolver
        val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
            ?: throw IllegalStateException("Could not create the file in Downloads")

        try {
            resolver.openOutputStream(uri)?.use { it.write(bytes) }
                ?: throw IllegalStateException("Could not open the file for writing")
            values.clear()
            values.put(MediaStore.Downloads.IS_PENDING, 0)
            resolver.update(uri, values, null, null)
        } catch (e: Exception) {
            resolver.delete(uri, null, null)
            throw e
        }
    }

    override fun onDestroy() {
        mergeExecutor.shutdown()
        super.onDestroy()
    }

    private companion object {
        const val AUDIO_CHANNEL = "com.lecto.lecto/audio"
    }
}

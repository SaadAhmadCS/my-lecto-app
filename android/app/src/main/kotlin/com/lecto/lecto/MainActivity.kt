package com.lecto.lecto

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

                else -> result.notImplemented()
            }
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

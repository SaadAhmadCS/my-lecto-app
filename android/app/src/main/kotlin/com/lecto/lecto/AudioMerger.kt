package com.lecto.lecto

import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMuxer
import java.io.File
import java.nio.ByteBuffer

/**
 * Joins a recording's chunks into a single .m4a.
 *
 * Lecture audio is recorded in chunks so a crash can only ever cost the chunk
 * in progress. Sharing wants the opposite: AI apps take a limited number of
 * files per chat — Gemini takes 10 — so a long lecture has to arrive as one
 * file or its tail is silently dropped.
 *
 * The samples are copied across as they are. Every chunk comes from the same
 * recorder configuration, so no decoding or re-encoding is needed, which keeps
 * this fast and lossless.
 */
object AudioMerger {

    /** Bytes read at a time. Comfortably larger than any AAC frame. */
    private const val BUFFER_SIZE = 1 shl 20

    /**
     * Merge [inputPaths], in order, into [outputPath].
     *
     * Returns the output path. Throws if no input holds a readable audio track.
     */
    fun merge(inputPaths: List<String>, outputPath: String): String {
        require(inputPaths.isNotEmpty()) { "No audio to merge" }

        val readable = inputPaths.filter { File(it).let { f -> f.exists() && f.length() > 0 } }
        require(readable.isNotEmpty()) { "None of the audio files exist" }

        val output = File(outputPath)
        output.parentFile?.mkdirs()
        if (output.exists()) output.delete()

        val muxer = MediaMuxer(outputPath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
        val buffer = ByteBuffer.allocate(BUFFER_SIZE)
        val bufferInfo = MediaCodec.BufferInfo()

        var trackIndex = -1
        var started = false
        // Chunks each start at zero, so every one is offset past the last.
        var timeOffsetUs = 0L

        try {
            for (path in readable) {
                val extractor = MediaExtractor()
                try {
                    extractor.setDataSource(path)

                    val audioTrack = (0 until extractor.trackCount).firstOrNull { index ->
                        extractor.getTrackFormat(index)
                            .getString(MediaFormat.KEY_MIME)
                            ?.startsWith("audio/") == true
                    } ?: continue

                    extractor.selectTrack(audioTrack)
                    val format = extractor.getTrackFormat(audioTrack)

                    if (!started) {
                        trackIndex = muxer.addTrack(format)
                        muxer.start()
                        started = true
                    }

                    var lastSampleUs = 0L
                    while (true) {
                        val size = extractor.readSampleData(buffer, 0)
                        if (size < 0) break

                        val sampleTimeUs = extractor.sampleTime
                        bufferInfo.offset = 0
                        bufferInfo.size = size
                        bufferInfo.presentationTimeUs = timeOffsetUs + sampleTimeUs
                        bufferInfo.flags = extractor.sampleFlags

                        muxer.writeSampleData(trackIndex, buffer, bufferInfo)
                        lastSampleUs = sampleTimeUs
                        extractor.advance()
                    }

                    // Start the next chunk after this one's final sample. Without
                    // this every chunk would overwrite the first's timeline and
                    // the merged file would report the duration of one chunk.
                    timeOffsetUs += lastSampleUs + sampleGapUs(format)
                } finally {
                    extractor.release()
                }
            }

            if (!started) throw IllegalStateException("No audio track found to merge")
        } catch (e: Exception) {
            runCatching { if (started) muxer.stop() }
            muxer.release()
            output.delete()
            throw e
        }

        muxer.stop()
        muxer.release()
        return outputPath
    }

    /**
     * How long one encoded frame lasts, so the next chunk starts after the last
     * sample rather than on top of it.
     *
     * AAC encodes 1024 samples per frame; at 22.05kHz that is ~46ms.
     */
    private fun sampleGapUs(format: MediaFormat): Long {
        val sampleRate = runCatching {
            format.getInteger(MediaFormat.KEY_SAMPLE_RATE)
        }.getOrDefault(44100)
        return 1_024_000_000L / sampleRate
    }
}

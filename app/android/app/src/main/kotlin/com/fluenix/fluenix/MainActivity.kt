package com.fluenix.fluenix

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTrack
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.LinkedBlockingQueue

/**
 * Native PCM sink for the coach's voice on the VOICE_COMMUNICATION path.
 *
 * flutter_soloud outputs a media-usage stream, which Android refuses to route
 * to the earpiece and excludes from the hardware echo canceller. Playing
 * through an AudioTrack tagged USAGE_VOICE_COMMUNICATION makes
 * earpiece/speaker toggling and AEC work like a real call.
 */
class MainActivity : FlutterActivity() {
    private var sink: VoiceSink? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "fluenix/voice_out")
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "init" -> {
                            sink?.release()
                            sink = VoiceSink(call.argument<Int>("sampleRate") ?: 24000)
                            result.success(null)
                        }
                        "write" -> {
                            sink?.write(call.arguments as ByteArray)
                            result.success(null)
                        }
                        "flush" -> {
                            sink?.flush()
                            result.success(null)
                        }
                        "dispose" -> {
                            sink?.release()
                            sink = null
                            result.success(null)
                        }
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    result.error("voice_out", e.message, null)
                }
            }
    }

    override fun onDestroy() {
        sink?.release()
        sink = null
        super.onDestroy()
    }
}

private class VoiceSink(sampleRate: Int) {
    private val queue = LinkedBlockingQueue<ByteArray>()
    @Volatile private var running = true
    private val track: AudioTrack
    private val worker: Thread

    init {
        val minBuf = AudioTrack.getMinBufferSize(
            sampleRate, AudioFormat.CHANNEL_OUT_MONO, AudioFormat.ENCODING_PCM_16BIT
        )
        track = AudioTrack(
            AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION)
                .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                .build(),
            AudioFormat.Builder()
                .setSampleRate(sampleRate)
                .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                .build(),
            // ≥ 0.5 s of 16-bit mono to absorb network burstiness.
            maxOf(minBuf * 4, sampleRate),
            AudioTrack.MODE_STREAM,
            AudioManager.AUDIO_SESSION_ID_GENERATE
        )
        track.play()
        // Blocking writes on a worker thread pace playback without janking UI.
        worker = Thread {
            while (running) {
                val chunk = queue.take()
                if (chunk.isEmpty()) continue // poison pill / wake-up
                try {
                    track.write(chunk, 0, chunk.size)
                } catch (_: Exception) {
                    // Track released mid-write during teardown — loop will exit.
                }
            }
        }.apply {
            isDaemon = true
            name = "fluenix-voice-out"
            start()
        }
    }

    fun write(data: ByteArray) {
        queue.offer(data)
    }

    /** Drop everything queued — the user interrupted the coach. */
    fun flush() {
        queue.clear()
        try {
            track.pause()
            track.flush()
            track.play()
        } catch (_: Exception) {
        }
    }

    fun release() {
        running = false
        queue.clear()
        queue.offer(ByteArray(0)) // wake the worker so it can exit
        try {
            track.pause()
            track.flush()
        } catch (_: Exception) {
        }
        track.release()
    }
}

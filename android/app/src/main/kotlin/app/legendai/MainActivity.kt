package app.legendai

import android.media.AudioFormat
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodChannel
import java.io.BufferedOutputStream
import java.io.FileOutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder

class MainActivity : FlutterActivity() {
    private val diagChannel = "legendai/diag"
    private val audioChannel = "legendai/audio"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Re-registra plugins essenciais blindados contra Throwable (defensivo).
        // add() é idempotente por classe.
        safeAdd(flutterEngine, "path_provider") {
            io.flutter.plugins.pathprovider.PathProviderPlugin()
        }
        safeAdd(flutterEngine, "file_selector") {
            dev.flutter.packages.file_selector_android.FileSelectorAndroidPlugin()
        }
        safeAdd(flutterEngine, "mlkit_commons") {
            com.google_mlkit_commons.GoogleMlKitCommonsPlugin()
        }
        safeAdd(flutterEngine, "mlkit_language_id") {
            com.google_mlkit_language_id.GoogleMlKitLanguageIdPlugin()
        }
        safeAdd(flutterEngine, "mlkit_translation") {
            com.google_mlkit_translation.GoogleMlKitTranslationPlugin()
        }
        safeAdd(flutterEngine, "share_plus") {
            dev.fluttercommunity.plus.share.SharePlusPlugin()
        }

        val messenger = flutterEngine.dartExecutor.binaryMessenger

        // Extração de áudio NATIVA (MediaCodec). Substitui o ffmpeg-kit, que
        // tem lib nativa quebrada no Android 15. Decodifica a trilha de áudio
        // do vídeo e gera WAV 16 kHz mono 16-bit para o Whisper.
        MethodChannel(messenger, audioChannel).setMethodCallHandler { call, result ->
            when (call.method) {
                "toWav16kMono" -> {
                    val input = call.argument<String>("input")
                    val output = call.argument<String>("output")
                    if (input == null || output == null) {
                        result.error("ARG", "input/output nulo", null)
                        return@setMethodCallHandler
                    }
                    Thread {
                        try {
                            WavAudioExtractor.extractToWav16kMono(input, output)
                            runOnUiThread { result.success(output) }
                        } catch (t: Throwable) {
                            runOnUiThread { result.error("EXTRACT_FAIL", t.message, null) }
                        }
                    }.start()
                }
                else -> result.notImplemented()
            }
        }

        // Diagnóstico: logcat do próprio processo.
        MethodChannel(messenger, diagChannel).setMethodCallHandler { call, result ->
            when (call.method) {
                "logcat" -> {
                    try {
                        val proc = Runtime.getRuntime().exec("logcat -d -v time")
                        val text = proc.inputStream.bufferedReader().use { it.readText() }
                        result.success(text)
                    } catch (e: Exception) {
                        result.error("LOGCAT_ERR", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun safeAdd(
        engine: FlutterEngine,
        name: String,
        create: () -> FlutterPlugin,
    ) {
        try {
            engine.plugins.add(create())
        } catch (t: Throwable) {
            android.util.Log.e("LegendAiReg", "Falha ao registrar $name: ${t.message}", t)
        }
    }
}

/// Cresce um buffer de floats sem autoboxing.
private class FloatList(initial: Int = 1 shl 16) {
    var data = FloatArray(initial)
    var size = 0
    fun add(v: Float) {
        if (size == data.size) data = data.copyOf(data.size * 2)
        data[size++] = v
    }
    fun toArray(): FloatArray = data.copyOf(size)
}

object WavAudioExtractor {
    private const val TARGET_RATE = 16000

    fun extractToWav16kMono(inputPath: String, outputPath: String) {
        val extractor = MediaExtractor()
        try {
            extractor.setDataSource(inputPath)
        } catch (e: Exception) {
            extractor.release()
            throw IllegalStateException("Não consegui ler o vídeo: ${e.message}")
        }

        var trackIndex = -1
        var inputFormat: MediaFormat? = null
        for (i in 0 until extractor.trackCount) {
            val f = extractor.getTrackFormat(i)
            val mime = f.getString(MediaFormat.KEY_MIME) ?: continue
            if (mime.startsWith("audio/")) {
                trackIndex = i
                inputFormat = f
                break
            }
        }
        if (trackIndex < 0 || inputFormat == null) {
            extractor.release()
            throw IllegalStateException("O vídeo não tem trilha de áudio.")
        }
        extractor.selectTrack(trackIndex)

        val mime = inputFormat.getString(MediaFormat.KEY_MIME)!!
        val codec = MediaCodec.createDecoderByType(mime)
        codec.configure(inputFormat, null, null, 0)
        codec.start()

        var srcRate =
            if (inputFormat.containsKey(MediaFormat.KEY_SAMPLE_RATE))
                inputFormat.getInteger(MediaFormat.KEY_SAMPLE_RATE) else TARGET_RATE
        var channels =
            if (inputFormat.containsKey(MediaFormat.KEY_CHANNEL_COUNT))
                inputFormat.getInteger(MediaFormat.KEY_CHANNEL_COUNT) else 1
        var pcmEncoding =
            if (inputFormat.containsKey(MediaFormat.KEY_PCM_ENCODING))
                inputFormat.getInteger(MediaFormat.KEY_PCM_ENCODING)
            else AudioFormat.ENCODING_PCM_16BIT

        val mono = FloatList()
        val info = MediaCodec.BufferInfo()
        var sawInputEOS = false
        var sawOutputEOS = false

        while (!sawOutputEOS) {
            if (!sawInputEOS) {
                val inIndex = codec.dequeueInputBuffer(10000)
                if (inIndex >= 0) {
                    val inBuf = codec.getInputBuffer(inIndex)!!
                    val sampleSize = extractor.readSampleData(inBuf, 0)
                    if (sampleSize < 0) {
                        codec.queueInputBuffer(
                            inIndex, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM
                        )
                        sawInputEOS = true
                    } else {
                        codec.queueInputBuffer(inIndex, 0, sampleSize, extractor.sampleTime, 0)
                        extractor.advance()
                    }
                }
            }
            val outIndex = codec.dequeueOutputBuffer(info, 10000)
            when {
                outIndex >= 0 -> {
                    if (info.size > 0) {
                        val outBuf = codec.getOutputBuffer(outIndex)!!
                        outBuf.position(info.offset)
                        outBuf.limit(info.offset + info.size)
                        appendMono(outBuf, channels, pcmEncoding, mono)
                    }
                    codec.releaseOutputBuffer(outIndex, false)
                    if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) {
                        sawOutputEOS = true
                    }
                }
                outIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                    val of = codec.outputFormat
                    if (of.containsKey(MediaFormat.KEY_SAMPLE_RATE))
                        srcRate = of.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                    if (of.containsKey(MediaFormat.KEY_CHANNEL_COUNT))
                        channels = of.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                    if (of.containsKey(MediaFormat.KEY_PCM_ENCODING))
                        pcmEncoding = of.getInteger(MediaFormat.KEY_PCM_ENCODING)
                }
            }
        }

        try {
            codec.stop()
        } catch (_: Throwable) {
        }
        codec.release()
        extractor.release()

        val samples = mono.toArray()
        val resampled = resample(samples, srcRate, TARGET_RATE)
        writeWav(outputPath, resampled, TARGET_RATE)
    }

    private fun appendMono(buf: ByteBuffer, channels: Int, pcmEncoding: Int, out: FloatList) {
        buf.order(ByteOrder.LITTLE_ENDIAN)
        val ch = if (channels <= 0) 1 else channels
        if (pcmEncoding == AudioFormat.ENCODING_PCM_FLOAT) {
            val fb = buf.asFloatBuffer()
            val n = fb.remaining()
            var i = 0
            while (i + ch <= n) {
                var s = 0f
                for (c in 0 until ch) s += fb.get(i + c)
                out.add(s / ch)
                i += ch
            }
        } else {
            // 16-bit PCM (padrão dos decoders de áudio)
            val sb = buf.asShortBuffer()
            val n = sb.remaining()
            var i = 0
            while (i + ch <= n) {
                var s = 0
                for (c in 0 until ch) s += sb.get(i + c).toInt()
                out.add((s.toFloat() / ch) / 32768f)
                i += ch
            }
        }
    }

    private fun resample(input: FloatArray, srcRate: Int, dstRate: Int): FloatArray {
        if (input.isEmpty()) return FloatArray(0)
        if (srcRate == dstRate) return input
        val ratio = dstRate.toDouble() / srcRate
        val outLen = (input.size * ratio).toInt()
        val out = FloatArray(outLen)
        val last = input.size - 1
        for (i in 0 until outLen) {
            val srcPos = i / ratio
            val idx = srcPos.toInt()
            val frac = (srcPos - idx).toFloat()
            val a = input[idx.coerceIn(0, last)]
            val b = input[(idx + 1).coerceIn(0, last)]
            out[i] = a + (b - a) * frac
        }
        return out
    }

    private fun writeWav(path: String, samples: FloatArray, rate: Int) {
        val dataSize = samples.size * 2
        BufferedOutputStream(FileOutputStream(path)).use { out ->
            val header = ByteBuffer.allocate(44).order(ByteOrder.LITTLE_ENDIAN)
            header.put("RIFF".toByteArray(Charsets.US_ASCII))
            header.putInt(36 + dataSize)
            header.put("WAVE".toByteArray(Charsets.US_ASCII))
            header.put("fmt ".toByteArray(Charsets.US_ASCII))
            header.putInt(16)
            header.putShort(1)            // PCM
            header.putShort(1)            // mono
            header.putInt(rate)
            header.putInt(rate * 2)       // byte rate
            header.putShort(2)            // block align
            header.putShort(16)           // bits per sample
            header.put("data".toByteArray(Charsets.US_ASCII))
            header.putInt(dataSize)
            out.write(header.array())

            val body = ByteBuffer.allocate(dataSize).order(ByteOrder.LITTLE_ENDIAN)
            for (s in samples) {
                val v = (s.coerceIn(-1f, 1f) * 32767f).toInt()
                body.putShort(v.toShort())
            }
            out.write(body.array())
            out.flush()
        }
    }
}

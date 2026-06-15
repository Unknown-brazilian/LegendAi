package app.legendai

import android.content.Context
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMuxer
import android.os.Bundle
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.Locale
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/**
 * Gera um vídeo DUBLADO no idioma alvo: sintetiza (TTS nativo do Android) a
 * fala de cada legenda, monta uma trilha de áudio sincronizada pelos tempos do
 * .srt, codifica em AAC e remuxa com o vídeo original (sem reencodar o vídeo).
 */
object Dubber {
    fun interface Progress {
        fun onProgress(fraction: Double)
    }

    private const val MASTER_RATE = 44100

    fun dub(
        context: Context,
        videoPath: String,
        srtPath: String,
        lang: String,
        outputPath: String,
        cacheDir: File,
        progress: Progress,
    ) {
        val cues = VideoSubtitleBurner.parseSrt(File(srtPath).readText())
        if (cues.isEmpty()) throw IllegalStateException("Nenhuma legenda para dublar.")

        val tts = initTts(context, Locale(lang))
        val segWavs = ArrayList<Pair<SubCue, File>>()
        try {
            for ((i, cue) in cues.withIndex()) {
                val f = File(cacheDir, "dub_$i.wav")
                if (f.exists()) f.delete()
                val ok = synth(tts, cue.text, f)
                if (ok) segWavs.add(cue to f)
                progress.onProgress(0.5 * (i + 1) / cues.size)
            }
        } finally {
            tts.stop()
            tts.shutdown()
        }
        if (segWavs.isEmpty()) {
            throw IllegalStateException("A síntese de voz não gerou áudio.")
        }

        // Duração total = max(fim da última legenda, duração do vídeo)
        var totalUs = cues.maxOf { it.endUs }
        val videoDurUs = videoDurationUs(videoPath)
        if (videoDurUs > totalUs) totalUs = videoDurUs
        val totalSamples = (totalUs * MASTER_RATE / 1_000_000L).toInt() + MASTER_RATE
        // 16-bit p/ usar metade da memória de um FloatArray.
        val master = ShortArray(totalSamples)

        // Mixa cada segmento na posição do seu tempo de início
        for ((cue, wav) in segWavs) {
            val (rate, samples) = readWavMono(wav)
            val res = resample(samples, rate, MASTER_RATE)
            var pos = (cue.startUs * MASTER_RATE / 1_000_000L).toInt()
            for (s in res) {
                if (pos >= master.size) break
                var v = master[pos].toInt() + (s.coerceIn(-1f, 1f) * 32767f).toInt()
                if (v > 32767) v = 32767 else if (v < -32768) v = -32768
                master[pos] = v.toShort()
                pos++
            }
            wav.delete()
        }
        progress.onProgress(0.6)

        // Codifica master -> AAC
        val aacPackets = encodeAac(master, MASTER_RATE) { p ->
            progress.onProgress(0.6 + 0.3 * p)
        }
        progress.onProgress(0.9)

        // Mux: copia vídeo original + AAC dublado
        muxVideoWithAudio(videoPath, aacPackets.first, aacPackets.second, outputPath)
        progress.onProgress(1.0)
    }

    // ---------------- TTS ----------------

    private fun initTts(context: Context, locale: Locale): TextToSpeech {
        val latch = CountDownLatch(1)
        var status = TextToSpeech.ERROR
        var ttsRef: TextToSpeech? = null
        ttsRef = TextToSpeech(context.applicationContext) { st ->
            status = st
            latch.countDown()
        }
        if (!latch.await(15, TimeUnit.SECONDS) || status != TextToSpeech.SUCCESS) {
            ttsRef?.shutdown()
            throw IllegalStateException("Não foi possível iniciar a voz (TTS) do aparelho.")
        }
        val tts = ttsRef!!
        val res = tts.setLanguage(locale)
        if (res == TextToSpeech.LANG_MISSING_DATA || res == TextToSpeech.LANG_NOT_SUPPORTED) {
            tts.shutdown()
            throw IllegalStateException(
                "A voz do idioma '${locale.language}' não está instalada. " +
                    "Instale em Ajustes > Sistema > Idiomas > Texto para fala (saída)."
            )
        }
        return tts
    }

    private fun synth(tts: TextToSpeech, text: String, file: File): Boolean {
        val latch = CountDownLatch(1)
        var ok = false
        val id = "u" + System.nanoTime()
        tts.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
            override fun onStart(utteranceId: String?) {}
            override fun onDone(utteranceId: String?) {
                ok = true; latch.countDown()
            }
            @Deprecated("deprecated")
            override fun onError(utteranceId: String?) {
                latch.countDown()
            }
            override fun onError(utteranceId: String?, errorCode: Int) {
                latch.countDown()
            }
        })
        val params = Bundle()
        val r = tts.synthesizeToFile(text, params, file, id)
        if (r != TextToSpeech.SUCCESS) return false
        latch.await(45, TimeUnit.SECONDS)
        return ok && file.exists() && file.length() > 44
    }

    // ---------------- WAV ----------------

    private fun readWavMono(file: File): Pair<Int, FloatArray> {
        val bytes = file.readBytes()
        val bb = ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN)
        // RIFF(4) size(4) WAVE(4)
        var pos = 12
        var sampleRate = 22050
        var channels = 1
        var bits = 16
        var dataOffset = -1
        var dataLen = 0
        while (pos + 8 <= bytes.size) {
            val id = String(bytes, pos, 4, Charsets.US_ASCII)
            val size = bb.getInt(pos + 4)
            val body = pos + 8
            if (id == "fmt ") {
                channels = bb.getShort(body + 2).toInt()
                sampleRate = bb.getInt(body + 4)
                bits = bb.getShort(body + 14).toInt()
            } else if (id == "data") {
                dataOffset = body
                dataLen = size
                break
            }
            pos = body + size + (size and 1)
        }
        if (dataOffset < 0) return sampleRate to FloatArray(0)
        if (dataLen <= 0 || dataOffset + dataLen > bytes.size) dataLen = bytes.size - dataOffset
        val ch = if (channels <= 0) 1 else channels
        val out = FloatArray(dataLen / (2 * ch))
        var oi = 0
        var p = dataOffset
        if (bits == 16) {
            while (p + 2 * ch <= dataOffset + dataLen) {
                var s = 0
                for (c in 0 until ch) {
                    s += bb.getShort(p + c * 2).toInt()
                }
                out[oi++] = (s.toFloat() / ch) / 32768f
                p += 2 * ch
            }
        }
        return sampleRate to out.copyOf(oi)
    }

    private fun resample(input: FloatArray, srcRate: Int, dstRate: Int): FloatArray {
        if (input.isEmpty() || srcRate == dstRate) return input
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

    // ---------------- AAC ----------------

    /** Codifica [master] (PCM 16-bit mono, [rate]) em AAC, alimentando o
     *  encoder direto do ShortArray (sem buffer intermediário gigante). */
    private fun encodeAac(
        master: ShortArray,
        rate: Int,
        progress: (Double) -> Unit,
    ): Pair<MediaFormat, List<AacPacket>> {
        val format = MediaFormat.createAudioFormat(
            MediaFormat.MIMETYPE_AUDIO_AAC, rate, 1
        ).apply {
            setInteger(MediaFormat.KEY_AAC_PROFILE, MediaCodecInfo.CodecProfileLevel.AACObjectLC)
            setInteger(MediaFormat.KEY_BIT_RATE, 96000)
            setInteger(MediaFormat.KEY_MAX_INPUT_SIZE, 16384)
        }
        val codec = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_AUDIO_AAC)
        codec.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
        codec.start()

        val packets = ArrayList<AacPacket>()
        var outFormat: MediaFormat? = null
        val info = MediaCodec.BufferInfo()

        val totalSamples = master.size
        var samplePos = 0
        var inputDone = false
        var outputDone = false
        var presentationUs = 0L
        val bytesPerUs = rate * 2.0 / 1_000_000.0

        while (!outputDone) {
            if (!inputDone) {
                val inIndex = codec.dequeueInputBuffer(10000)
                if (inIndex >= 0) {
                    val inBuf = codec.getInputBuffer(inIndex)!!
                    inBuf.clear()
                    val capShorts = inBuf.capacity() / 2
                    val remaining = totalSamples - samplePos
                    if (remaining <= 0) {
                        codec.queueInputBuffer(
                            inIndex, 0, 0, presentationUs, MediaCodec.BUFFER_FLAG_END_OF_STREAM
                        )
                        inputDone = true
                    } else {
                        val n = minOf(capShorts, remaining)
                        inBuf.order(ByteOrder.LITTLE_ENDIAN).asShortBuffer()
                            .put(master, samplePos, n)
                        val bytes = n * 2
                        codec.queueInputBuffer(inIndex, 0, bytes, presentationUs, 0)
                        samplePos += n
                        presentationUs += (bytes / bytesPerUs).toLong()
                        progress(samplePos.toDouble() / totalSamples)
                    }
                }
            }
            val outIndex = codec.dequeueOutputBuffer(info, 10000)
            if (outIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                outFormat = codec.outputFormat
            } else if (outIndex >= 0) {
                val buf = codec.getOutputBuffer(outIndex)!!
                if (info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0) {
                    info.size = 0
                }
                if (info.size > 0) {
                    val data = ByteArray(info.size)
                    buf.position(info.offset)
                    buf.get(data, 0, info.size)
                    packets.add(AacPacket(data, info.presentationTimeUs, info.flags))
                }
                codec.releaseOutputBuffer(outIndex, false)
                if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) outputDone = true
            }
        }
        codec.stop()
        codec.release()
        return (outFormat ?: format) to packets
    }

    class AacPacket(val data: ByteArray, val ptsUs: Long, val flags: Int)

    // ---------------- Mux ----------------

    private fun muxVideoWithAudio(
        videoPath: String,
        audioFormat: MediaFormat,
        audioPackets: List<AacPacket>,
        outputPath: String,
    ) {
        val extractor = MediaExtractor()
        extractor.setDataSource(videoPath)
        var videoTrack = -1
        var videoFormat: MediaFormat? = null
        for (i in 0 until extractor.trackCount) {
            val f = extractor.getTrackFormat(i)
            val mime = f.getString(MediaFormat.KEY_MIME) ?: continue
            if (mime.startsWith("video/")) { videoTrack = i; videoFormat = f; break }
        }
        if (videoTrack < 0 || videoFormat == null) {
            extractor.release()
            throw IllegalStateException("Vídeo sem trilha de vídeo.")
        }
        extractor.selectTrack(videoTrack)
        val rotation = if (videoFormat.containsKey(MediaFormat.KEY_ROTATION))
            videoFormat.getInteger(MediaFormat.KEY_ROTATION) else 0

        val muxer = MediaMuxer(outputPath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
        muxer.setOrientationHint(rotation)
        val muxVideo = muxer.addTrack(videoFormat)
        val muxAudio = muxer.addTrack(audioFormat)
        muxer.start()
        try {
            // vídeo (cópia)
            val maxSize = if (videoFormat.containsKey(MediaFormat.KEY_MAX_INPUT_SIZE))
                videoFormat.getInteger(MediaFormat.KEY_MAX_INPUT_SIZE) else 1 shl 20
            val buffer = ByteBuffer.allocate(maxSize)
            val info = MediaCodec.BufferInfo()
            while (true) {
                val size = extractor.readSampleData(buffer, 0)
                if (size < 0) break
                info.offset = 0
                info.size = size
                info.presentationTimeUs = extractor.sampleTime
                info.flags = if (extractor.sampleFlags and MediaExtractor.SAMPLE_FLAG_SYNC != 0)
                    MediaCodec.BUFFER_FLAG_KEY_FRAME else 0
                muxer.writeSampleData(muxVideo, buffer, info)
                extractor.advance()
            }
            // áudio dublado
            val aInfo = MediaCodec.BufferInfo()
            for (p in audioPackets) {
                val bb = ByteBuffer.wrap(p.data)
                aInfo.offset = 0
                aInfo.size = p.data.size
                aInfo.presentationTimeUs = p.ptsUs
                aInfo.flags = p.flags
                muxer.writeSampleData(muxAudio, bb, aInfo)
            }
        } finally {
            try { muxer.stop() } catch (_: Throwable) {}
            muxer.release()
            extractor.release()
        }
    }

    private fun videoDurationUs(videoPath: String): Long {
        val ex = MediaExtractor()
        return try {
            ex.setDataSource(videoPath)
            var dur = 0L
            for (i in 0 until ex.trackCount) {
                val f = ex.getTrackFormat(i)
                if (f.containsKey(MediaFormat.KEY_DURATION)) {
                    dur = maxOf(dur, f.getLong(MediaFormat.KEY_DURATION))
                }
            }
            dur
        } catch (_: Throwable) {
            0L
        } finally {
            ex.release()
        }
    }
}

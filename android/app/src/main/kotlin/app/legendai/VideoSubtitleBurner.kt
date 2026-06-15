package app.legendai

import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMuxer
import android.opengl.EGL14
import android.opengl.EGLConfig
import android.opengl.EGLContext
import android.opengl.EGLDisplay
import android.opengl.EGLSurface
import android.view.Surface
import java.io.File
import java.nio.ByteBuffer

/** Um segmento de legenda em microssegundos. */
data class SubCue(val startUs: Long, val endUs: Long, val text: String)

/**
 * Queima legendas (.srt) num vídeo usando MediaCodec + OpenGL (sem ffmpeg).
 * Decodifica o vídeo numa textura OES, desenha o quadro + a legenda ativa via
 * GL na superfície de entrada do encoder H.264, e remuxa com o áudio original.
 */
object VideoSubtitleBurner {

    fun interface Progress {
        fun onProgress(fraction: Double)
    }

    fun burn(
        videoPath: String,
        srtPath: String,
        outputPath: String,
        style: SubtitleStyle,
        progress: Progress,
    ) {
        val cues = parseSrt(File(srtPath).readText())

        val extractor = MediaExtractor()
        extractor.setDataSource(videoPath)
        var videoTrack = -1
        var inputFormat: MediaFormat? = null
        for (i in 0 until extractor.trackCount) {
            val f = extractor.getTrackFormat(i)
            val mime = f.getString(MediaFormat.KEY_MIME) ?: continue
            if (mime.startsWith("video/")) {
                videoTrack = i; inputFormat = f; break
            }
        }
        if (videoTrack < 0 || inputFormat == null) {
            extractor.release()
            throw IllegalStateException("Vídeo sem trilha de vídeo.")
        }
        extractor.selectTrack(videoTrack)

        val storedW = inputFormat.getInteger(MediaFormat.KEY_WIDTH)
        val storedH = inputFormat.getInteger(MediaFormat.KEY_HEIGHT)
        val rotation =
            if (inputFormat.containsKey(MediaFormat.KEY_ROTATION))
                inputFormat.getInteger(MediaFormat.KEY_ROTATION) else 0
        val durationUs =
            if (inputFormat.containsKey(MediaFormat.KEY_DURATION))
                inputFormat.getLong(MediaFormat.KEY_DURATION) else 0L
        val frameRate =
            if (inputFormat.containsKey(MediaFormat.KEY_FRAME_RATE))
                inputFormat.getInteger(MediaFormat.KEY_FRAME_RATE) else 30

        // --- Encoder (H.264) ---
        val outFormat = MediaFormat.createVideoFormat(
            MediaFormat.MIMETYPE_VIDEO_AVC, storedW, storedH
        ).apply {
            setInteger(
                MediaFormat.KEY_COLOR_FORMAT,
                MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface
            )
            val bitrate = (storedW.toLong() * storedH * 4).coerceIn(2_000_000, 20_000_000).toInt()
            setInteger(MediaFormat.KEY_BIT_RATE, bitrate)
            setInteger(MediaFormat.KEY_FRAME_RATE, if (frameRate <= 0) 30 else frameRate)
            setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1)
        }
        val encoder = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_VIDEO_AVC)
        encoder.configure(outFormat, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
        val inputSurface = CodecInputSurface(encoder.createInputSurface())
        encoder.start()

        // --- GL output (decoder -> OES texture) ---
        inputSurface.makeCurrent()
        val outputSurface = OutputSurface(storedW, storedH, rotation, style)

        // --- Decoder ---
        val videoMime = inputFormat.getString(MediaFormat.KEY_MIME)!!
        val decoder = MediaCodec.createDecoderByType(videoMime)
        decoder.configure(inputFormat, outputSurface.surface, null, 0)
        decoder.start()

        // --- Muxer ---
        val muxer = MediaMuxer(outputPath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
        muxer.setOrientationHint(rotation)
        var muxerVideoTrack = -1
        var muxerStarted = false

        val bufferInfo = MediaCodec.BufferInfo()
        var sawInputEOS = false
        var sawDecodeEOS = false
        var encoderDone = false

        fun drainEncoder(endOfStream: Boolean) {
            if (endOfStream) encoder.signalEndOfInputStream()
            while (true) {
                val outIndex = encoder.dequeueOutputBuffer(bufferInfo, 10000)
                if (outIndex == MediaCodec.INFO_TRY_AGAIN_LATER) {
                    if (!endOfStream) break else continue
                } else if (outIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                    if (muxerStarted) throw IllegalStateException("format changed twice")
                    muxerVideoTrack = muxer.addTrack(encoder.outputFormat)
                    // áudio antes de start
                    addAudioTrackAndStart(videoPath, muxer)
                    muxerStarted = true
                } else if (outIndex >= 0) {
                    val encoded = encoder.getOutputBuffer(outIndex)!!
                    if (bufferInfo.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0) {
                        bufferInfo.size = 0
                    }
                    if (bufferInfo.size > 0 && muxerStarted) {
                        encoded.position(bufferInfo.offset)
                        encoded.limit(bufferInfo.offset + bufferInfo.size)
                        muxer.writeSampleData(muxerVideoTrack, encoded, bufferInfo)
                    }
                    encoder.releaseOutputBuffer(outIndex, false)
                    if (bufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) {
                        encoderDone = true
                        break
                    }
                }
            }
        }

        try {
            while (!encoderDone) {
                // feed decoder
                if (!sawInputEOS) {
                    val inIndex = decoder.dequeueInputBuffer(10000)
                    if (inIndex >= 0) {
                        val inBuf = decoder.getInputBuffer(inIndex)!!
                        val sampleSize = extractor.readSampleData(inBuf, 0)
                        if (sampleSize < 0) {
                            decoder.queueInputBuffer(
                                inIndex, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM
                            )
                            sawInputEOS = true
                        } else {
                            decoder.queueInputBuffer(
                                inIndex, 0, sampleSize, extractor.sampleTime, 0
                            )
                            extractor.advance()
                        }
                    }
                }
                // drain decoder -> surface
                if (!sawDecodeEOS) {
                    val outIndex = decoder.dequeueOutputBuffer(bufferInfo, 10000)
                    if (outIndex == MediaCodec.INFO_TRY_AGAIN_LATER) {
                        // nada agora
                    } else if (outIndex >= 0) {
                        val eos = bufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0
                        val render = bufferInfo.size != 0
                        val ptsUs = bufferInfo.presentationTimeUs
                        decoder.releaseOutputBuffer(outIndex, render)
                        if (render) {
                            outputSurface.awaitNewImage()
                            val text = activeText(cues, ptsUs)
                            outputSurface.drawFrame(text, storedW, storedH, rotation)
                            inputSurface.setPresentationTime(ptsUs * 1000)
                            inputSurface.swapBuffers()
                            drainEncoder(false)
                            if (durationUs > 0) {
                                progress.onProgress((ptsUs.toDouble() / durationUs).coerceIn(0.0, 0.99))
                            }
                        }
                        if (eos) {
                            sawDecodeEOS = true
                            drainEncoder(true)
                        }
                    }
                }
            }
        } finally {
            try { decoder.stop() } catch (_: Throwable) {}
            decoder.release()
            try { encoder.stop() } catch (_: Throwable) {}
            encoder.release()
            outputSurface.release()
            inputSurface.release()
            extractor.release()
            try {
                if (muxerStarted) muxer.stop()
            } catch (_: Throwable) {}
            muxer.release()
        }
        progress.onProgress(1.0)
    }

    /** Copia a trilha de áudio original para o muxer (sem reencodar). */
    private fun addAudioTrackAndStart(videoPath: String, muxer: MediaMuxer) {
        val audioEx = MediaExtractor()
        audioEx.setDataSource(videoPath)
        var audioTrack = -1
        var audioFormat: MediaFormat? = null
        for (i in 0 until audioEx.trackCount) {
            val f = audioEx.getTrackFormat(i)
            val mime = f.getString(MediaFormat.KEY_MIME) ?: continue
            if (mime.startsWith("audio/")) { audioTrack = i; audioFormat = f; break }
        }
        if (audioTrack < 0 || audioFormat == null) {
            audioEx.release()
            muxer.start()
            return
        }
        val muxerAudioTrack = muxer.addTrack(audioFormat)
        muxer.start()
        audioEx.selectTrack(audioTrack)
        val maxSize = if (audioFormat.containsKey(MediaFormat.KEY_MAX_INPUT_SIZE))
            audioFormat.getInteger(MediaFormat.KEY_MAX_INPUT_SIZE) else 256 * 1024
        val buffer = ByteBuffer.allocate(maxSize)
        val info = MediaCodec.BufferInfo()
        while (true) {
            val size = audioEx.readSampleData(buffer, 0)
            if (size < 0) break
            info.offset = 0
            info.size = size
            info.presentationTimeUs = audioEx.sampleTime
            info.flags = if (audioEx.sampleFlags and MediaExtractor.SAMPLE_FLAG_SYNC != 0)
                MediaCodec.BUFFER_FLAG_KEY_FRAME else 0
            muxer.writeSampleData(muxerAudioTrack, buffer, info)
            audioEx.advance()
        }
        audioEx.release()
    }

    private fun activeText(cues: List<SubCue>, ptsUs: Long): String? {
        for (c in cues) {
            if (ptsUs >= c.startUs && ptsUs <= c.endUs) return c.text
        }
        return null
    }

    /** Parser simples de .srt -> lista de cues. */
    fun parseSrt(content: String): List<SubCue> {
        val cues = ArrayList<SubCue>()
        val blocks = content.replace("\r\n", "\n").split(Regex("\n\\s*\n"))
        val timeRe = Regex(
            "(\\d{2}):(\\d{2}):(\\d{2})[,.](\\d{3})\\s*-->\\s*(\\d{2}):(\\d{2}):(\\d{2})[,.](\\d{3})"
        )
        for (block in blocks) {
            val lines = block.trim().split("\n")
            if (lines.size < 2) continue
            var timeLineIdx = 0
            if (lines[0].trim().matches(Regex("\\d+"))) timeLineIdx = 1
            if (timeLineIdx >= lines.size) continue
            val m = timeRe.find(lines[timeLineIdx]) ?: continue
            val g = m.groupValues
            val start = toUs(g[1], g[2], g[3], g[4])
            val end = toUs(g[5], g[6], g[7], g[8])
            val text = lines.drop(timeLineIdx + 1).joinToString("\n").trim()
            if (text.isNotEmpty()) cues.add(SubCue(start, end, text))
        }
        return cues
    }

    private fun toUs(h: String, m: String, s: String, ms: String): Long {
        return ((h.toLong() * 3600 + m.toLong() * 60 + s.toLong()) * 1000 + ms.toLong()) * 1000
    }
}

/** EGL na superfície de entrada do encoder. */
private class CodecInputSurface(private val surface: Surface) {
    private var eglDisplay: EGLDisplay = EGL14.EGL_NO_DISPLAY
    private var eglContext: EGLContext = EGL14.EGL_NO_CONTEXT
    private var eglSurface: EGLSurface = EGL14.EGL_NO_SURFACE

    init {
        eglDisplay = EGL14.eglGetDisplay(EGL14.EGL_DEFAULT_DISPLAY)
        val version = IntArray(2)
        EGL14.eglInitialize(eglDisplay, version, 0, version, 1)
        val attribList = intArrayOf(
            EGL14.EGL_RED_SIZE, 8,
            EGL14.EGL_GREEN_SIZE, 8,
            EGL14.EGL_BLUE_SIZE, 8,
            EGL14.EGL_ALPHA_SIZE, 8,
            EGL14.EGL_RENDERABLE_TYPE, EGL14.EGL_OPENGL_ES2_BIT,
            0x3142, 1, // EGL_RECORDABLE_ANDROID
            EGL14.EGL_NONE
        )
        val configs = arrayOfNulls<EGLConfig>(1)
        val numConfigs = IntArray(1)
        EGL14.eglChooseConfig(eglDisplay, attribList, 0, configs, 0, 1, numConfigs, 0)
        val ctxAttribs = intArrayOf(EGL14.EGL_CONTEXT_CLIENT_VERSION, 2, EGL14.EGL_NONE)
        eglContext = EGL14.eglCreateContext(
            eglDisplay, configs[0], EGL14.EGL_NO_CONTEXT, ctxAttribs, 0
        )
        val surfaceAttribs = intArrayOf(EGL14.EGL_NONE)
        eglSurface = EGL14.eglCreateWindowSurface(
            eglDisplay, configs[0], surface, surfaceAttribs, 0
        )
    }

    fun makeCurrent() {
        EGL14.eglMakeCurrent(eglDisplay, eglSurface, eglSurface, eglContext)
    }

    fun swapBuffers(): Boolean = EGL14.eglSwapBuffers(eglDisplay, eglSurface)

    fun setPresentationTime(nsecs: Long) {
        EGLExt14.setPresentationTime(eglDisplay, eglSurface, nsecs)
    }

    fun release() {
        if (eglDisplay != EGL14.EGL_NO_DISPLAY) {
            EGL14.eglMakeCurrent(
                eglDisplay, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_CONTEXT
            )
            EGL14.eglDestroySurface(eglDisplay, eglSurface)
            EGL14.eglDestroyContext(eglDisplay, eglContext)
            EGL14.eglTerminate(eglDisplay)
        }
        surface.release()
    }
}

private object EGLExt14 {
    fun setPresentationTime(display: EGLDisplay, surface: EGLSurface, nsecs: Long) {
        android.opengl.EGLExt.eglPresentationTimeANDROID(display, surface, nsecs)
    }
}

package pt.nunomartins.nuva.audio

import android.content.Context
import android.os.SystemClock
import androidx.media3.common.C
import androidx.media3.common.Format
import androidx.media3.common.MimeTypes
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.audio.AudioSink
import androidx.media3.exoplayer.audio.ForwardingAudioSink
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.roundToInt

/** What the screen needs from the audio thread: the equalizer, the measurements, and the output's clock. */
object Audio {
    lateinit var equalizer: Equalizer
        private set
    val spectrum = SpectrumShared()
    val clock = OutputClock()

    fun init(context: Context) {
        if (!::equalizer.isInitialized) equalizer = Equalizer(context.applicationContext)
    }
}

/**
 * The output's own clock, in seconds, on the same timeline as the measurements: what is being heard
 * now, after the output's buffer. Updated by the player many times a second while it plays.
 */
class OutputClock {
    @Volatile private var positionUs = 0L
    @Volatile private var atNanos = 0L

    fun update(positionUs: Long) {
        this.positionUs = positionUs
        atNanos = SystemClock.elapsedRealtimeNanos()
    }

    /** Now, carried forward from the last update (at most 100 ms, so a pause doesn't run on). */
    fun now(): Double {
        val ahead = ((SystemClock.elapsedRealtimeNanos() - atNanos) / 1000).coerceIn(0, 100_000)
        return (positionUs + ahead) / 1_000_000.0
    }
}

/**
 * Sits in front of the player's audio output and sees every decoded block before it is played: the
 * equalizer filters it and, while a meter is on screen, the analyzer measures it. This is where the
 * Mac app's tap is. Here rather than as a Media3 audio processor, because those are skipped for 24-bit
 * sources played in float, and the float path is what keeps a 24-bit FLAC whole. With the equalizer
 * off and no meter on screen, blocks pass untouched.
 */
@UnstableApi
class TapSink(sink: AudioSink) : ForwardingAudioSink(sink) {
    private var encoding = C.ENCODING_INVALID
    private var channels = 0
    private var sampleRate = 0
    private val filter = EqFilter()
    private var analyzer: SpectrumAnalyzer? = null
    private var source: ByteBuffer? = null
    private var sourceTime = C.TIME_UNSET
    private var processed: ByteBuffer? = null
    private var out: ByteBuffer = ByteBuffer.allocateDirect(0)
    private var floats = FloatArray(0)

    override fun configure(inputFormat: Format, specifiedBufferSize: Int, outputChannels: IntArray?) {
        val pcm = inputFormat.sampleMimeType == MimeTypes.AUDIO_RAW &&
            (inputFormat.pcmEncoding == C.ENCODING_PCM_16BIT || inputFormat.pcmEncoding == C.ENCODING_PCM_FLOAT)
        encoding = if (pcm) inputFormat.pcmEncoding else C.ENCODING_INVALID
        channels = inputFormat.channelCount
        sampleRate = inputFormat.sampleRate
        analyzer = if (pcm) SpectrumAnalyzer(sampleRate) else null
        filter.reset()
        forget()
        super.configure(inputFormat, specifiedBufferSize, outputChannels)
    }

    override fun handleBuffer(buffer: ByteBuffer, presentationTimeUs: Long, encodedAccessUnitCount: Int): Boolean {
        if (encoding == C.ENCODING_INVALID) return super.handleBuffer(buffer, presentationTimeUs, encodedAccessUnitCount)
        // The player hands the same block again until the output takes all of it: process it once.
        if (buffer !== source || presentationTimeUs != sourceTime) {
            source = buffer
            sourceTime = presentationTimeUs
            processed = transform(buffer, presentationTimeUs)
        }
        val done = super.handleBuffer(processed ?: buffer, presentationTimeUs, encodedAccessUnitCount)
        if (done) forget()
        return done
    }

    override fun getCurrentPositionUs(sourceEnded: Boolean): Long {
        val position = super.getCurrentPositionUs(sourceEnded)
        if (position != AudioSink.CURRENT_POSITION_NOT_SET) Audio.clock.update(position)
        return position
    }

    override fun flush() {
        filter.reset()
        forget()
        Audio.spectrum.clear()
        super.flush()
    }

    override fun reset() {
        forget()
        super.reset()
    }

    private fun forget() {
        source = null
        sourceTime = C.TIME_UNSET
        processed = null
    }

    /** The block filtered and measured, in a buffer of its own; or null to play it as it is. */
    private fun transform(buffer: ByteBuffer, presentationTimeUs: Long): ByteBuffer? {
        val eq = Audio.equalizer.snapshot
        val measure = Audio.spectrum.isWatched
        if (!eq.enabled && !measure) return null
        val bytes = buffer.remaining()
        val width = if (encoding == C.ENCODING_PCM_FLOAT) 4 else 2
        val samples = bytes / width
        val frames = samples / channels.coerceAtLeast(1)
        if (frames == 0) return null
        if (floats.size < samples) floats = FloatArray(samples)

        val input = buffer.duplicate().order(ByteOrder.nativeOrder())
        if (width == 4) {
            input.asFloatBuffer().get(floats, 0, samples)
        } else {
            val shorts = input.asShortBuffer()
            for (i in 0 until samples) floats[i] = shorts.get(i) / 32768f
        }

        val filtered = filter.process(floats, frames, channels, sampleRate, eq)
        if (measure) analyzer?.process(floats, channels, frames, presentationTimeUs / 1_000_000.0 + frames.toDouble() / sampleRate, Audio.spectrum)
        if (!filtered) return null

        if (out.capacity() < bytes) out = ByteBuffer.allocateDirect(bytes).order(ByteOrder.nativeOrder())
        out.clear()
        if (width == 4) {
            out.asFloatBuffer().put(floats, 0, samples)
        } else {
            val shorts = out.asShortBuffer()
            for (i in 0 until samples) shorts.put(i, (floats[i] * 32768f).roundToInt().coerceIn(-32768, 32767).toShort())
        }
        out.position(0).limit(bytes)
        return out
    }
}

/** ExoPlayer's renderers, with the tap in front of the audio output and float output for 24-bit sources. */
@UnstableApi
class TapRenderersFactory(context: Context) : DefaultRenderersFactory(context) {
    init {
        setEnableAudioFloatOutput(true)
    }

    override fun buildAudioSink(context: Context, enableFloatOutput: Boolean, enableAudioTrackPlaybackParams: Boolean): AudioSink? =
        super.buildAudioSink(context, enableFloatOutput, enableAudioTrackPlaybackParams)?.let(::TapSink)
}

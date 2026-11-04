package pt.nunomartins.nuva.player

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ScrubAndQualityTest {
    private val start = Scrub(index = 0, origin = 60.0, target = 60.0, duration = 180.0)

    @Test fun aPressMovesTenSeconds() {
        assertEquals(50.0, start.step(-1, 0).target, 0.0)
        assertEquals(70.0, start.step(1, 0).target, 0.0)
    }

    @Test fun holdingGoesFasterTheLongerItIsHeld() {
        assertTrue(Scrub.stepSeconds(40) > Scrub.stepSeconds(1))
        assertEquals(15.0, Scrub.stepSeconds(10_000), 0.0)
    }

    @Test fun theTargetStaysInsideTheTrackAndTheOriginIsKept() {
        var s = start
        repeat(30) { s = s.step(-1, 0) }
        assertEquals(0.0, s.target, 0.0)
        repeat(30) { s = s.step(1, 0) }
        assertEquals(179.0, s.target, 0.0)
        assertEquals(60.0, s.origin, 0.0)
    }

    @Test fun theLabelSaysFormatBitrateDepthAndRate() {
        assertEquals("FLAC 905 kbps | 16-bit/44.1 kHz", Quality("FLAC", 16, 44100, 905).label)
        assertEquals("FLAC | 24-bit/96 kHz", Quality("FLAC", 24, 96000, null).label)
        assertEquals("MP3 320 kbps | 44.1 kHz", Quality("MP3", null, 44100, 320).label)
        assertEquals("FLAC", Quality("FLAC", null, null, null).label)
    }

    @Test fun theCompactLabelLeavesTheUnitsOff() {
        assertEquals("FLAC 905 kbps | 16/44.1", Quality("FLAC", 16, 44100, 905).compactLabel)
        assertEquals("MP3 320 kbps | 44.1 kHz", Quality("MP3", null, 44100, 320).compactLabel)
    }

    @Test fun theBitrateIsTheFilesAverage() {
        // 20 362 500 bytes over 180 s: 905 kbps.
        assertEquals(905, Quality.kbps(20_362_500, 180.0))
        assertNull(Quality.kbps(null, 180.0))
        assertNull(Quality.kbps(1000, 0.0))
    }
}

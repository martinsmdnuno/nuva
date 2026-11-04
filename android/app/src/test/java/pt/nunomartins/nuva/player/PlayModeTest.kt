package pt.nunomartins.nuva.player

import androidx.media3.common.Player
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test

class PlayModeTest {
    @Test fun eachPressMovesToTheNextModeAndBack() {
        val seen = generateSequence(PlayMode.Normal) { it.next }.take(5).toList()
        assertEquals(listOf(PlayMode.Normal, PlayMode.Shuffle, PlayMode.RepeatAll, PlayMode.RepeatOne, PlayMode.Normal), seen)
    }

    @Test fun everyModeReadsBackFromThePlayer() {
        for (mode in PlayMode.entries) assertEquals(mode, PlayMode.of(mode.shuffle, mode.repeat))
    }

    @Test fun repeatWinsOverShuffleSetElsewhere() {
        assertEquals(PlayMode.RepeatAll, PlayMode.of(true, Player.REPEAT_MODE_ALL))
        assertEquals(PlayMode.RepeatOne, PlayMode.of(true, Player.REPEAT_MODE_ONE))
    }

    @Test fun leavingShuffleTurnsItOff() {
        assertFalse(PlayMode.Shuffle.next.shuffle)
    }
}

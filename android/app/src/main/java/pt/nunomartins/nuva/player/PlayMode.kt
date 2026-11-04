package pt.nunomartins.nuva.player

import androidx.media3.common.Player

/**
 * The one mode key's modes, in the order each press moves through them: in order, shuffled, the
 * queue over and over, the track over and over. Each sets both the player's shuffle and its repeat.
 */
enum class PlayMode(val shuffle: Boolean, val repeat: Int) {
    Normal(false, Player.REPEAT_MODE_OFF),
    Shuffle(true, Player.REPEAT_MODE_OFF),
    RepeatAll(false, Player.REPEAT_MODE_ALL),
    RepeatOne(false, Player.REPEAT_MODE_ONE);

    val next: PlayMode get() = entries[(ordinal + 1) % entries.size]

    companion object {
        /** The mode for the player's state; repeat wins over shuffle when another controller set both. */
        fun of(shuffle: Boolean, repeat: Int): PlayMode = when (repeat) {
            Player.REPEAT_MODE_ONE -> RepeatOne
            Player.REPEAT_MODE_ALL -> RepeatAll
            else -> if (shuffle) Shuffle else Normal
        }
    }
}

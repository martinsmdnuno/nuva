package pt.nunomartins.nuva.player

/**
 * Moving through a track with the remote: from `origin`, each press of ← → moves `target` 10 s;
 * holding the key moves it faster the longer it is held. The display shows the target; the player
 * goes there when the key is let go, stays there with OK and goes back to `origin` with Back.
 */
data class Scrub(val index: Int, val origin: Double, val target: Double, val duration: Double) {
    /** One key event: `direction` -1 or 1, `repeat` the key's repeat count (0 for a press). */
    fun step(direction: Int, repeat: Int): Scrub =
        copy(target = (target + direction * stepSeconds(repeat)).coerceIn(0.0, (duration - 1).coerceAtLeast(0.0)))

    companion object {
        /** 10 s for a press; held, 2 s per repeat at first (about 40 s a second), up to 15 s per repeat. */
        fun stepSeconds(repeat: Int): Double = if (repeat <= 0) 10.0 else (2 + repeat / 8).coerceAtMost(15).toDouble()
    }
}

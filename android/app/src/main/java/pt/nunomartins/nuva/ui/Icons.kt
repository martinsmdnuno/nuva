package pt.nunomartins.nuva.ui

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.PathBuilder
import androidx.compose.ui.graphics.vector.path
import androidx.compose.ui.unit.dp

/** The keys' symbols, drawn after the SF Symbols the Mac uses: regular weight, filled only for play and pause. */
object Icons {
    private fun icon(name: String, filled: Boolean, block: PathBuilder.() -> Unit) =
        ImageVector.Builder(name, 24.dp, 24.dp, 24f, 24f).apply {
            if (filled) {
                path(fill = SolidColor(Color.Black), pathBuilder = block)
            } else {
                path(
                    stroke = SolidColor(Color.Black), strokeLineWidth = 1.8f,
                    strokeLineCap = StrokeCap.Round, strokeLineJoin = StrokeJoin.Round, pathBuilder = block,
                )
            }
        }.build()

    val play = icon("play", true) { moveTo(7f, 4.5f); lineTo(19f, 12f); lineTo(7f, 19.5f); close() }
    val pause = icon("pause", true) {
        moveTo(6.5f, 5f); lineTo(10f, 5f); lineTo(10f, 19f); lineTo(6.5f, 19f); close()
        moveTo(14f, 5f); lineTo(17.5f, 5f); lineTo(17.5f, 19f); lineTo(14f, 19f); close()
    }
    val previous = icon("previous", false) {
        moveTo(6f, 5f); lineTo(6f, 19f)
        moveTo(18f, 5f); lineTo(9f, 12f); lineTo(18f, 19f); close()
    }
    val next = icon("next", false) {
        moveTo(18f, 5f); lineTo(18f, 19f)
        moveTo(6f, 5f); lineTo(15f, 12f); lineTo(6f, 19f); close()
    }
    val shuffle = icon("shuffle", false) {
        moveTo(3f, 7f); lineTo(7f, 7f); curveTo(12f, 7f, 12f, 17f, 17f, 17f); lineTo(21f, 17f)
        moveTo(3f, 17f); lineTo(7f, 17f); curveTo(12f, 17f, 12f, 7f, 17f, 7f); lineTo(21f, 7f)
        moveTo(18f, 4f); lineTo(21f, 7f); lineTo(18f, 10f)
        moveTo(18f, 14f); lineTo(21f, 17f); lineTo(18f, 20f)
    }
    val repeat = icon("repeat", false) {
        moveTo(4f, 11f); lineTo(4f, 9f); curveTo(4f, 7.9f, 4.9f, 7f, 6f, 7f); lineTo(20f, 7f)
        moveTo(17f, 4f); lineTo(20f, 7f); lineTo(17f, 10f)
        moveTo(20f, 13f); lineTo(20f, 15f); curveTo(20f, 16.1f, 19.1f, 17f, 18f, 17f); lineTo(4f, 17f)
        moveTo(7f, 14f); lineTo(4f, 17f); lineTo(7f, 20f)
    }
    val folders = icon("folders", false) {
        moveTo(3f, 6f); lineTo(21f, 6f); lineTo(21f, 18f); lineTo(3f, 18f); close()
        moveTo(9f, 6f); lineTo(9f, 18f)
        moveTo(5f, 9f); lineTo(7f, 9f); moveTo(5f, 12f); lineTo(7f, 12f)
    }
    val back = icon("back", false) { moveTo(15f, 5f); lineTo(8f, 12f); lineTo(15f, 19f) }
    val folder = icon("folder", false) {
        moveTo(3f, 7f); lineTo(3f, 18f); lineTo(21f, 18f); lineTo(21f, 9f); lineTo(11f, 9f); lineTo(9f, 7f); close()
    }
    val ambient = icon("ambient", false) {
        moveTo(3f, 5f); lineTo(21f, 5f); lineTo(21f, 17f); lineTo(3f, 17f); close()
        moveTo(8f, 20f); lineTo(16f, 20f)
    }
}

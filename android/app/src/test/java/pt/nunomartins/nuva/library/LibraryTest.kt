package pt.nunomartins.nuva.library

import org.junit.Assert.assertEquals
import org.junit.Test

class LibraryTest {
    @Test fun naturalOrderPutsTwoBeforeTen() {
        val names = listOf("10 - Ten.flac", "2 - Two.flac", "1 - One.flac", "b.flac", "A.flac")
        assertEquals(listOf("1 - One.flac", "2 - Two.flac", "10 - Ten.flac", "A.flac", "b.flac"), names.sortedWith(NaturalOrder))
    }

    @Test fun foldersComeFirst() {
        val sorted = listOf(Entry("x/02.flac", "02.flac", false), Entry("x/CD1", "CD1", true)).naturallySorted()
        assertEquals("CD1", sorted.first().name)
    }

    @Test fun titleDropsTheNumberAndExtension() {
        assertEquals("Dreams", Entry("Rumours/02 - Dreams.flac", "02 - Dreams.flac", false).title)
        assertEquals("Rumours", Entry("Rumours/02 - Dreams.flac", "02 - Dreams.flac", false).folderName)
        assertEquals("FLAC", Entry("a/b.flac", "b.flac", false).format)
    }

    @Test fun relativePathFollowsTheServerFolders() {
        val item = JellyfinSource.Item("1", "Dreams", false, "/music/Fleetwood Mac/Rumours (1977)/02 - Dreams.flac", "flac", null, null)
        assertEquals(
            "Fleetwood Mac/Rumours (1977)/02 - Dreams.flac",
            JellyfinSource.relativePath(item, "Fleetwood Mac", "/music/Fleetwood Mac"),
        )
        // Windows servers use backslashes.
        val windows = item.copy(path = "D:\\Music\\Album\\01.flac")
        assertEquals("Album/01.flac", JellyfinSource.relativePath(windows, "", "D:/Music"))
    }

    @Test fun addressGetsAScheme() {
        assertEquals("https://cinema.example.com", JellyfinSource.normalise(" cinema.example.com/ "))
        assertEquals("http://192.168.1.2:8096", JellyfinSource.normalise("http://192.168.1.2:8096"))
        assertEquals("http://192.168.1.2:8096", JellyfinSource.normalise("192.168.1.2:8096"))
        assertEquals("https://jellyfin.local:8920", JellyfinSource.normalise("jellyfin.local:8920"))
    }
}

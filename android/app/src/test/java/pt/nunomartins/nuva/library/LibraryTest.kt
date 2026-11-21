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

    @Test fun theFilesSizeComesFromItsMediaSource() {
        val json = org.json.JSONObject("""{"Id":"1","Name":"Dreams","IsFolder":false,"MediaSources":[{"Id":"1","Size":20362500}]}""")
        assertEquals(20_362_500L, JellyfinSource.Item.from(json).size)
        assertEquals(null, JellyfinSource.Item.from(org.json.JSONObject("""{"Id":"2","IsFolder":false}""")).size)
    }

    @Test fun addressGetsAScheme() {
        assertEquals("https://cinema.example.com", JellyfinSource.normalise(" cinema.example.com/ "))
        assertEquals("http://192.168.1.2:8096", JellyfinSource.normalise("http://192.168.1.2:8096"))
        assertEquals("http://192.168.1.2:8096", JellyfinSource.normalise("192.168.1.2:8096"))
        assertEquals("https://jellyfin.local:8920", JellyfinSource.normalise("jellyfin.local:8920"))
    }

    @Test fun recentFirstPutsTheNewestFoldersFirstAndKeepsTracksInOrder() {
        val entries = listOf(
            Entry("Zé", "Zé", true), Entry("Old", "Old", true, added = 1_000), Entry("2 B.flac", "2 B.flac", false),
            Entry("New", "New", true, added = 9_000), Entry("Alva", "Alva", true), Entry("1 A.flac", "1 A.flac", false),
        )
        assertEquals(listOf("New", "Old", "Alva", "Zé", "1 A.flac", "2 B.flac"), entries.sortedBy(FolderOrder.Recent).map { it.name })
        assertEquals(listOf("Alva", "New", "Old", "Zé", "1 A.flac", "2 B.flac"), entries.sortedBy(FolderOrder.Name).map { it.name })
    }

    @Test fun readsJellyfinDates() {
        val expected = 1_731_582_413_000L // 2024-11-14T11:06:53Z
        assertEquals(expected + 123, JellyfinSource.date("2024-11-14T11:06:53.1234567Z"))
        assertEquals(expected, JellyfinSource.date("2024-11-14T11:06:53Z"))
        assertEquals(expected, JellyfinSource.date("2024-11-14T11:06:53"))
        assertEquals(expected + 500, JellyfinSource.date("2024-11-14T12:06:53.5+01:00"))
        assertEquals(null, JellyfinSource.date("0001-01-01"))
    }

    @Test fun aFolderIsAsNewAsTheLastMusicJellyfinFoundInIt() {
        val item = JellyfinSource.Item.from(org.json.JSONObject(
            """{"Id":"a","Name":"Artist","IsFolder":true,"DateCreated":"2024-01-02T03:04:05.1234567Z","DateLastMediaAdded":"2026-11-20T21:00:00.0000000Z"}""",
        ))
        assertEquals(JellyfinSource.date("2026-11-20T21:00:00Z"), item.added)
    }
}


class ArtistLineTest {
    @Test fun artistAndAlbumComeFromTheFolders() {
        val e = Entry("Fleetwood Mac/Rumours (1977)/02 - Dreams.flac", "02 - Dreams.flac", false)
        assertEquals("Fleetwood Mac", e.artistFolder)
        assertEquals("Fleetwood Mac · Rumours (1977)", e.folderLine)
        val disc = Entry("Pink Floyd/The Wall/CD 2/01 - Hey You.flac", "01 - Hey You.flac", false)
        assertEquals("Pink Floyd · The Wall", disc.folderLine)
        assertEquals("Album", Entry("Album/01.flac", "01.flac", false).folderLine)
        // A library-level folder is not an artist.
        assertEquals("Fleetwood Mac - Rumours", Entry("Music/Fleetwood Mac - Rumours/01.flac", "01.flac", false).folderLine)
    }

}

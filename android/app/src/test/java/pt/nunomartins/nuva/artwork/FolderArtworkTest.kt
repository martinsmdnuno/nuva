package pt.nunomartins.nuva.artwork

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class FolderArtworkTest {
    private val folder = "/music/Fleetwood Mac/Rumours (1977)"

    @Test fun anImageFileInTheFolderCounts() {
        val cover = FolderArtwork.Image("Primary", "$folder/Cover.JPG", null)
        assertEquals(cover, FolderArtwork.choose(listOf(cover), folder))
    }

    @Test fun anImageFromTheTagsOrDownloadedDoesNot() {
        // Jellyfin keeps an embedded or downloaded image in its own metadata folder.
        val embedded = FolderArtwork.Image("Primary", "/config/metadata/library/ab/cdef/folder.jpg", null)
        assertNull(FolderArtwork.choose(listOf(embedded), folder))
        assertNull(FolderArtwork.choose(listOf(FolderArtwork.Image("Primary", null, null)), folder))
    }

    @Test fun onlyArtworkNamesInTheMacsOrder() {
        val scan = FolderArtwork.Image("Primary", "$folder/scan.jpg", null)
        val front = FolderArtwork.Image("Backdrop", "$folder/front.png", 0)
        val capa = FolderArtwork.Image("Primary", "$folder/capa.jpeg", null)
        assertEquals(front, FolderArtwork.choose(listOf(scan, capa, front), folder))
        assertNull(FolderArtwork.choose(listOf(scan), folder))
    }

    @Test fun windowsServersUseBackslashes() {
        val cover = FolderArtwork.Image("Primary", "D:\\Music\\Album\\folder.jpg", null)
        assertEquals(cover, FolderArtwork.choose(listOf(cover), "D:\\Music\\Album"))
    }
}

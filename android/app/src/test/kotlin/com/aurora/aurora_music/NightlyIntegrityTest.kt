package com.aurora.aurora_music

import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test
import java.io.ByteArrayOutputStream
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

class NightlyIntegrityTest {
    private fun payload(names: List<String> = listOf("__main__.py", "yt_dlp/version.py", "yt_dlp_ejs/__init__.py")): ByteArray {
        val zipBytes = ByteArrayOutputStream()
        ZipOutputStream(zipBytes).use { zip ->
            names.forEach { name -> zip.putNextEntry(ZipEntry(name)); zip.write("fixture".toByteArray()); zip.closeEntry() }
        }
        return "#!/usr/bin/env python3\n".toByteArray() + zipBytes.toByteArray()
    }
    @Test fun validatesOfficialChecksumAndCompletePythonBundle() {
        val bytes = payload()
        val hash = NightlyIntegrity.sha256(bytes)
        assertEquals(hash, NightlyIntegrity.checksum("$hash  yt-dlp\n${"a".repeat(64)}  yt-dlp.exe\n"))
        NightlyIntegrity.verifyPayload(bytes, hash)
    }
    @Test fun refusesHashMismatchAndAmbiguousChecksum() {
        val bytes = payload()
        assertThrows(IllegalArgumentException::class.java) { NightlyIntegrity.verifyPayload(bytes, "a".repeat(64)) }
        assertThrows(IllegalArgumentException::class.java) { NightlyIntegrity.checksum("${"a".repeat(64)}  yt-dlp\n${"b".repeat(64)}  yt-dlp") }
    }
    @Test fun refusesIncompleteOrNonPythonPayload() {
        val bytes = payload(listOf("__main__.py"))
        assertThrows(IllegalArgumentException::class.java) { NightlyIntegrity.verifyPayload(bytes, NightlyIntegrity.sha256(bytes)) }
        val invalid = "not a zip".toByteArray()
        assertThrows(IllegalArgumentException::class.java) { NightlyIntegrity.verifyPayload(invalid, NightlyIntegrity.sha256(invalid)) }
    }
}

package com.aurora.aurora_music

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test

class SourceRequestPolicyTest {
    @Test fun extractionWaitsWithoutAddingDownloadsOrRetries() {
        val request = sourceRequest("https://www.youtube.com/watch?v=abcdefghijk")
        assertEquals("1", request.getOption("--sleep-requests"))
        assertEquals("0", request.getOption("--retries"))
        assertEquals("0", request.getOption("--extractor-retries"))
        assertEquals("0", request.getOption("--fragment-retries"))
        assertFalse(request.hasOption("--sleep-interval"))
        assertFalse(request.hasOption("--force-overwrites"))
    }
}

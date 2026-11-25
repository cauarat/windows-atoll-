package com.cauarati.notchy

import org.junit.Assert.assertEquals
import org.junit.Test

class AttributionTest {
    @Test fun nameAndRepoMatchPermission() {
        assertEquals("Notchy for Android", Attribution.APP_NAME)
        assertEquals("https://github.com/cauarat/windows-atoll-", Attribution.REPO_URL)
    }
}

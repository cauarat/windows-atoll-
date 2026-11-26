package com.cauarati.notchy

import java.io.File
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Guards for the sheet that rises over a screen (Compose cannot be rendered in a JVM test, so these read the sources): the pairing
 * link and the computer's address are typed in one, and it must always close and never let a tap through to the screen behind.
 */
class SheetsTest {
    private fun src(name: String) = File("src/main/kotlin/com/cauarati/notchy/$name").readText()
    private val sheets get() = src("ui/Sheets.kt")

    @Test fun theSheetCanBeClosedAndNeverCatchesTapsMeantForTheScrim() {
        assertTrue(sheets.contains("BackHandler(onBack = onDismiss)"))
        assertTrue(sheets.contains("detectTapGestures { }"))
        assertTrue("the scrim closes it", sheets.contains("indication = null, onClick = onDismiss"))
    }

    @Test fun aLargeFontNeverHidesTheButtons() {
        assertTrue(sheets.contains(".verticalScroll(rememberScrollState())"))
    }
}

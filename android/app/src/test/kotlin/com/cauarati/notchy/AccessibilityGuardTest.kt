package com.cauarati.notchy

import com.cauarati.notchy.core.Spacing
import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** TalkBack, touch size and large text: guards on the Compose sources, which cannot run on a JVM. */
class AccessibilityGuardTest {
    private val ui = File("src/main/kotlin/com/cauarati/notchy/ui")
    private fun src(name: String) = File(ui, name).readText()

    @Test fun theMinimumTouchTargetIs48dp() = assertEquals(48, Spacing.MIN_TOUCH)

    @Test fun everyTappableThingIsAtLeastAMinimumTouchTarget() {
        // Within the five lines above a click handler there must be a height (or size) of at least 48 dp, or the row is taller by design.
        val bigRows = Regex("""(heightIn\(min = (Spacing\.MIN_TOUCH|5\d|6\d|7\d)|sizeIn\(|\.size\((Spacing\.MIN_TOUCH|5\d|6\d)|ListRow\()""")
        for (f in ui.listFiles { it.extension == "kt" }!!.sortedBy { it.name }) {
            val lines = f.readLines()
            lines.forEachIndexed { i, line ->
                if (line.trimStart().startsWith("import")) return@forEachIndexed
                if (!(line.contains(".clickable(") || line.contains(".selectable(") || line.contains(".toggleable("))) return@forEachIndexed
                val window = lines.subList(maxOf(0, i - 5), i + 1).joinToString("\n")
                // The island's cards and the full-width settings rows are tall by construction; a scrim is not a control.
                val exempt = f.name == "IslandOverlay.kt" || line.contains("indication = null") || window.contains("fillMaxSize()")
                assertTrue("${f.name}:${i + 1} is tappable but its height is not at least 48 dp", exempt || bigRows.containsMatchIn(window))
            }
        }
    }

    @Test fun agentsAndTabsAreSpokenWithTheirStateNotOnlyAColour() {
        val home = src("HomePanel.kt")
        assertTrue(home.contains("SpokenLabels.agent(name, state, line)"))
        assertTrue(home.contains("SpokenLabels.agent(name, stringResource(stateLabel(s.state)), HomeText.line(s))"))
        // The island's tabs and buttons are drawn symbols: each says what it is, and Home says when a request waits.
        assertTrue(home.contains("SpokenLabels.tab("))
        val kit = src("IslandKit.kt")
        assertTrue(kit.contains("fun IslandTab(") && kit.substringAfter("fun IslandTab(").substringBefore("\n}").contains("contentDescription = label"))
        assertTrue(kit.substringAfter("fun IslandIconButton(").substringBefore("\n}").contains("contentDescription = label"))
        // The link's dot is said in words too.
        assertTrue(home.contains("contentDescription = said"))
    }

    @Test fun aRequestIsAnnouncedWhenItsSheetRises() {
        val sheets = src("Sheets.kt")
        assertTrue(sheets.contains("paneTitle = announce"))
        assertTrue(sheets.contains("SpokenLabels.approval("))
        // The scrim behind a sheet is a labelled button for TalkBack, not a silent area.
        assertTrue(sheets.contains("contentDescription = closeLabel"))
        // The island speaks too: a request at once.
        assertTrue(src("IslandOverlay.kt").contains("LiveRegionMode.Assertive"))
    }

    @Test fun aSheetScrollsSoALargeFontNeverHidesDenyOrAllow() {
        val sheets = src("Sheets.kt")
        val host = sheets.substringAfter("fun BottomSheetHost").substringBefore("/** The colour of an agent")
        assertTrue(host.contains(".verticalScroll(rememberScrollState())"))
    }

    @Test fun textThatCarriesAStateIsNotCutToOneLine() {
        // At a font scale of 1.3 these lines would lose their end; a pill's state word wraps instead, the link's status may take two lines.
        val home = src("HomePanel.kt")
        assertTrue(home.contains("Text(state, style = islandText(12.sp, islandStateColor(s.state)))"))
        assertTrue(home.contains("Text(linkStatusText(model), style = islandText(15.sp, IslandColors.text, FontWeight.SemiBold), maxLines = 2"))
        assertTrue(src("UsagePanel.kt").contains("maxLines = 2"))
        // A time and a count in a fixed 56 dp box would be cut by a large font.
        assertFalse(src("SettingsScreens.kt").contains("Modifier.width(56.dp)"))
    }

    @Test fun choicesAreReadAsSelectedRadioButtons() {
        val settings = src("SettingsScreens.kt")
        assertTrue(settings.contains("this.selected = value == selected") && settings.contains("role = Role.RadioButton"))
    }
}

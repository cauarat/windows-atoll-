package com.cauarati.notchy

import java.io.File
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Test

/** Every language has every string, with the same placeholders and the plural forms its rule needs; nothing is left in English by mistake. */
class TranslationsTest {
    private val source = JSONObject(File("../i18n/app-strings.json").readText())
    private val english = source.getJSONObject("strings")
    private val englishPlurals = source.getJSONObject("plurals")
    private val files = File("../i18n/translations").listFiles { f -> f.extension == "json" }!!.sortedBy { it.name }
    private fun placeholders(s: String) = Regex("""%(?:\d+\$)?[sd%]""").findAll(s).map { it.value }.sorted().toList()
    private val categories = mapOf(
        "fr" to listOf("one", "many", "other"), "es" to listOf("one", "many", "other"), "pt-BR" to listOf("one", "many", "other"),
        "zh-Hans" to listOf("other"), "hi" to listOf("one", "other"), "bn" to listOf("one", "other"),
        "ru" to listOf("one", "few", "many", "other"), "id" to listOf("other"), "ar" to listOf("zero", "one", "two", "few", "many", "other"),
        "tr" to listOf("one", "other"),
        "de" to listOf("one", "other"),
        "ja" to listOf("other"),
        "ko" to listOf("other"),
        "zh-Hant" to listOf("other"),
        "th" to listOf("other"),
        "it" to listOf("one", "many", "other"),
    )

    @Test fun thereIsAtLeastOneLanguage() = assertTrue(files.isNotEmpty())

    @Test fun everyLanguageHasEveryStringWithTheSamePlaceholders() {
        for (f in files) {
            val t = JSONObject(f.readText()).getJSONObject("strings")
            for (k in english.keys()) {
                assertTrue("${f.name}: missing $k", t.has(k) && t.getString(k).isNotBlank())
                assertEquals("${f.name}: $k", placeholders(english.getString(k)), placeholders(t.getString(k)))
            }
            for (k in t.keys()) assertTrue("${f.name}: $k is not in the English source", english.has(k))
        }
    }

    @Test fun everyLanguageHasEveryPluralWithItsForms() {
        for (f in files) {
            val p = JSONObject(f.readText()).getJSONObject("plurals")
            val needed = categories.getValue(f.nameWithoutExtension)
            for (k in englishPlurals.keys()) {
                assertTrue("${f.name}: missing plural $k", p.has(k))
                val forms = p.getJSONObject(k)
                assertEquals("${f.name}: $k", needed.sorted(), forms.keys().asSequence().toList().sorted())
                for (c in needed) assertEquals("${f.name}: $k $c", placeholders(englishPlurals.getJSONObject(k).getString("other")), placeholders(forms.getString(c)))
            }
        }
    }

    @Test fun onlyNamesNumbersAndShortWordsStayAsTheyAreInEnglish() {
        val allowed = setOf(
            "about_repo", "chat_count", "ago_minutes", "ago_hours", "ago_hours_minutes", "chat_model", "app_name", "tab_chat", "chat_title",
            "settings_volume", "diag_ok", "wardrobe_auto_tag",
            // The same word in the language (French "Licences").
            "licences_title",
        )
        // These are also German words (and "Computer" is Italian too). Keep the exceptions local to their language so other translations remain checked.
        val germanSameAsEnglish = setOf("settings_section_computer", "diag_problem", "theme_system", "motion_system")
        for (f in files) {
            val t = JSONObject(f.readText()).getJSONObject("strings")
            val same = english.keys().asSequence().filter { t.getString(it) == english.getString(it) }.toList()
            for (k in same) assertTrue("${f.name}: $k is still the English text", k in allowed || english.getString(k).length <= 5 || (f.nameWithoutExtension == "de" && k in germanSameAsEnglish) || (f.nameWithoutExtension == "it" && k == "settings_section_computer"))
        }
    }

    @Test fun theGeneratorAcceptsThemAll() {
        val ok = runCatching { ProcessBuilder("node", "--version").redirectErrorStream(true).start().also { it.inputStream.readBytes() }.waitFor() == 0 }.getOrDefault(false)
        assumeTrue("Node is needed to run the generator", ok)
        val p = ProcessBuilder("node", File("../scripts/gen-strings.mjs").absolutePath, "--check").redirectErrorStream(true).start()
        val out = p.inputStream.bufferedReader().readText()
        assertEquals(out, 0, p.waitFor())
    }

    @Test fun theReviewFileListsWhatIsNotTheDesktopAppsOwnWording() {
        val review = File("../i18n/REVIEW.md")
        if (!review.exists()) return
        val text = review.readText()
        for (f in files) assertTrue("${f.name} is in REVIEW.md", text.contains("(${f.nameWithoutExtension})"))
        assertFalse(text.contains("TODO"))
    }
}

package com.cauarati.notchy

import com.cauarati.notchy.core.PillCategory
import com.cauarati.notchy.core.Pills
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** Pill IDs are contract values: this fails if the catalog drifts from Notchy's NotchBuddy/Sources/App/PillCatalog.swift. */
class PillsTest {
    private data class Ref(val id: String, val name: String, val color: String, val category: String)

    private fun reference(): List<Ref> {
        val src = ReferenceFiles.read("NotchBuddy/Sources/App/PillCatalog.swift")
        val accents = Regex("""case \.(\w+):\s*return "(#[0-9A-Fa-f]{6})"""")
            .findAll(ReferenceFiles.read("NotchBuddy/Sources/App/MessageSource.swift")).associate { it.groupValues[1] to it.groupValues[2] }
        val re = Regex("""\.init\(id:\s*"([^"]+)",\s*name:\s*"([^"]+)",\s*color:\s*([^,]+),\s*category:\s*\.(\w+)""")
        return re.findAll(src).map { m ->
            val raw = m.groupValues[3].trim()
            val color = if (raw.startsWith("\"")) raw.trim('"') else accents.getValue(raw.removePrefix("MessageSource.").substringBefore('.'))
            Ref(m.groupValues[1], m.groupValues[2], color, m.groupValues[4])
        }.toList()
    }

    @Test fun catalogMatchesTheMacExceptNowPlaying() {
        val expected = reference().filter { it.id != "integration_music" }
        assertTrue("parsed too few pills from PillCatalog.swift", expected.size >= 4)
        assertEquals(expected.map { it.id }, Pills.notchy.map { it.id })
        for ((ref, mine) in expected.zip(Pills.notchy)) {
            assertEquals(ref.name, mine.name)
            assertEquals(ref.color.uppercase(), mine.colorHex.uppercase())
            assertEquals(ref.category, mine.category.name.lowercase())
        }
    }

    @Test fun theAgentsAreUpstreamsAndTheHookServerCanRouteThem() {
        val hooks = ReferenceFiles.read("NotchBuddy/Sources/App/HookServer.swift")
        assertTrue("agent_<name> routing", hooks.contains("agentId = \"agent_\\(agent)\""))
        for (id in listOf("agent_codex", "agent_cursor")) assertTrue(id, hooks.contains("\"$id\""))
        val upstream = ReferenceFiles.read("windows/src/core/pills.ts")
        val re = Regex("""\{\s*id:\s*"(agent_[^"]+)",\s*name:\s*"([^"]+)",\s*color:\s*"([^"]+)"""")
        val ref = re.findAll(upstream).associate { it.groupValues[1] to (it.groupValues[2] to it.groupValues[3]) }
        for (p in Pills.agents) {
            assertTrue(p.id, p.id.startsWith("agent_"))
            assertEquals(p.id, ref[p.id], p.name to p.colorHex)
        }
        assertEquals(ref.keys.toList(), Pills.agents.map { it.id })
    }

    @Test fun idsAreUniqueAndDefaultExists() {
        assertEquals(Pills.catalog.size, Pills.catalog.map { it.id }.toSet().size)
        assertEquals(PillCategory.WORKSPACE, Pills.byId(Pills.DEFAULT_MAIN_PILL)?.category)
    }
}

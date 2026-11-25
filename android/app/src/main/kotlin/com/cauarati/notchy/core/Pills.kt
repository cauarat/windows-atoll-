package com.cauarati.notchy.core

/**
 * Pill catalog. Two sources, kept apart so each can be checked against its own (PillsTest):
 *  - [notchy]: Notchy's own pills, a mirror of NotchBuddy/Sources/App/PillCatalog.swift, the single source of truth for every
 *    pill. Now Playing is left out: it has no Android equivalent.
 *  - [agents]: the agent pills a session can arrive under. The Mac's hook server routes Codex and Cursor to `agent_codex` and
 *    `agent_cursor`, and any hook payload tagged `coucou_agent: <name>` to `agent_<name>` (HookServer.swift); none of them is in
 *    PillCatalog.swift, so their names and colours come from upstream Coucou's catalog (android/reference/coucou), the one these
 *    ids were first given in.
 * IDs, names, colours and categories are contract values and never change once shipped.
 */
enum class PillCategory { WORKSPACE, AGENT, AI, SERVICE }

data class PillDefinition(
    val id: String,
    val name: String,
    val colorHex: String,
    val category: PillCategory,
)

object Pills {
    const val DEFAULT_MAIN_PILL = "integration_claude"

    /** PillCatalog.swift, in its order, without Now Playing. */
    val notchy: List<PillDefinition> = listOf(
        PillDefinition("integration_claude", "Claude Code", "#F5F6F8", PillCategory.WORKSPACE),
        PillDefinition("integration_mattermost", "Mattermost", "#1B6FF3", PillCategory.SERVICE),
        PillDefinition("integration_ato", "Ato", "#1B2FEB", PillCategory.SERVICE),
        PillDefinition("integration_whatsapp", "WhatsApp", "#25D366", PillCategory.SERVICE),
        PillDefinition("integration_notifications", "Notifications", "#FFFFFF", PillCategory.SERVICE),
    )

    /** Agents a session can be routed to without being in PillCatalog.swift. */
    val agents: List<PillDefinition> = listOf(
        PillDefinition("agent_cursor", "Cursor", "#C0C4CC", PillCategory.WORKSPACE),
        PillDefinition("agent_antigravity", "Antigravity", "#E879F9", PillCategory.WORKSPACE),
        PillDefinition("agent_codex", "Codex", "#2DD4BF", PillCategory.WORKSPACE),
        PillDefinition("agent_gemini", "Gemini CLI", "#8AB4F8", PillCategory.AGENT),
        PillDefinition("agent_copilot", "Copilot CLI", "#818CF8", PillCategory.AGENT),
        PillDefinition("agent_muse", "Muse Code", "#38BDF8", PillCategory.AGENT),
        PillDefinition("agent_opencode", "OpenCode", "#4ADE80", PillCategory.AGENT),
        PillDefinition("agent_amp", "Amp", "#F59E0B", PillCategory.AGENT),
        PillDefinition("agent_hermes", "Hermes", "#C084FC", PillCategory.AGENT),
        PillDefinition("agent_claude-desktop", "Claude Desktop", "#D97757", PillCategory.AGENT),
    )

    val catalog: List<PillDefinition> = notchy.take(1) + agents + notchy.drop(1)

    fun byId(id: String): PillDefinition? = catalog.firstOrNull { it.id == id }
}

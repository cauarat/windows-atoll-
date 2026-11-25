package com.cauarati.notchy

import java.io.File

/**
 * Locates the files tests compare the port against.
 *
 * Two places, because the app was ported from one repository into another:
 *  - `windows/...` is upstream Coucou's desktop TypeScript, the reference the Kotlin port was written against. Notchy's own
 *    `windows/` has diverged from it (different pills, characters instead of outfits), so the upstream files are vendored,
 *    unchanged, in `android/reference/coucou/` at the commit named in android/README.md.
 *  - everything else (`NotchBuddy/...`, `android/...`) is read from this repository.
 */
object ReferenceFiles {
    private fun repoRoot(): File {
        var dir: File? = File(System.getProperty("user.dir")).absoluteFile
        while (dir != null) {
            if (File(dir, "NotchBuddy/Sources/App/PillCatalog.swift").exists() && File(dir, "android").isDirectory) return dir
            dir = dir.parentFile
        }
        error("repository root not found from ${System.getProperty("user.dir")}")
    }

    private fun resolve(path: String): File =
        if (path == "windows" || path.startsWith("windows/")) File(repoRoot(), "android/reference/coucou/$path") else File(repoRoot(), path)

    fun read(path: String): String = resolve(path).readText()
    fun file(path: String): File = resolve(path)
}

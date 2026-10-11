import Foundation

// MARK: - Reader

/// Reads Claude Code's own transcripts (`~/.claude/projects/**/*.jsonl`) and
/// turns them into spend, tokens and activity.
///
/// Two things make this cheap enough to run live:
///
/// * **Incremental.** Every file is remembered by size + mtime + the byte
///   offset already folded in. An untouched file costs one `stat`; a file the
///   running session just appended to costs only the new bytes.
/// * **Bounded.** Only the last `windowDays` of history is kept, so the cache
///   and the dedup set do not grow without limit.
///
/// Deduplication is not optional. Resumed and forked sessions replay earlier
/// turns into new transcripts: on this machine 58% of all usage records are
/// replays, so counting them twice would inflate spend by roughly 2.3x. The
/// `message.id` is globally unique per assistant turn and is the key.
actor ClaudeUsageReader {
    static let shared = ClaudeUsageReader()

    /// Days of history kept on disk. A little more than the grid draws, so a
    /// timezone edge never empties the oldest column.
    static let windowDays = 100
    /// The activity grid is exactly 13 weeks, like Claude Code's own.
    static let activityDays = 91

    private struct Cursor: Codable {
        var size:   Int64
        var mtime:  Double
        var offset: UInt64
    }

    private struct Cache: Codable {
        var version      = 1
        var cursors:     [String: Cursor] = [:]
        /// message id → day key, so expired ids can be pruned with their day.
        var seenIds:     [String: String] = [:]
        var byDayModel:   [String: [String: TokenCounts]] = [:]
        var byHourModel:  [String: [String: TokenCounts]] = [:]
        /// day → project → model → counts. Keeping the model lets a project's
        /// spend be priced exactly instead of approximated.
        var byDayProject: [String: [String: [String: TokenCounts]]] = [:]
        var lastActivity: Date?
        var sawUnknownModel = false
    }

    private var cache = Cache()
    private var loaded = false

    private static var cacheURL: URL {
        HookServer.supportDir.appendingPathComponent("usage-cache.json")
    }

    private static let projectsRoot =
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude/projects")

    // Formatters are expensive to build and are not Sendable, so the actor
    // owns them: actor isolation is what makes sharing them safe.
    private let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
    private let hourFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH"
        return f
    }()
    private let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private let isoPlain = ISO8601DateFormatter()

    private func parseTimestamp(_ s: String) -> Date? {
        isoFractional.date(from: s) ?? isoPlain.date(from: s)
    }

    // MARK: Entry point

    /// Rescans what changed and returns a fresh snapshot.
    func refresh() -> AgentUsageSnapshot {
        loadCacheIfNeeded()
        scan()
        prune()
        persist()
        return buildSnapshot()
    }

    /// Drops everything and rebuilds from scratch. Used by the tests and after
    /// a cache-format change.
    func reset() {
        cache = Cache()
        loaded = true
        try? FileManager.default.removeItem(at: Self.cacheURL)
    }

    // MARK: Persistence

    private func loadCacheIfNeeded() {
        guard !loaded else { return }
        loaded = true
        guard let data = try? Data(contentsOf: Self.cacheURL),
              let decoded = try? JSONDecoder().decode(Cache.self, from: data),
              decoded.version == Cache().version
        else { return }
        cache = decoded
    }

    private func persist() {
        let dir = HookServer.supportDir
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(cache) else { return }
        try? data.write(to: Self.cacheURL, options: .atomic)
    }

    // MARK: Scanning

    private func transcriptPaths() -> [String] {
        let fm = FileManager.default
        guard let projects = try? fm.contentsOfDirectory(
            at: Self.projectsRoot, includingPropertiesForKeys: nil)
        else { return [] }
        var out: [String] = []
        for project in projects {
            guard let files = try? fm.contentsOfDirectory(
                at: project, includingPropertiesForKeys: nil) else { continue }
            for f in files where f.pathExtension == "jsonl" {
                out.append(f.path)
            }
        }
        return out
    }

    private func scan() {
        let fm = FileManager.default
        let paths = transcriptPaths()
        let live = Set(paths)
        // Forget transcripts that have been deleted.
        cache.cursors = cache.cursors.filter { live.contains($0.key) }

        for path in paths {
            guard let attrs = try? fm.attributesOfItem(atPath: path),
                  let size = (attrs[.size] as? NSNumber)?.int64Value,
                  let mtime = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970
            else { continue }

            var cursor = cache.cursors[path] ?? Cursor(size: 0, mtime: 0, offset: 0)
            if cursor.size == size && cursor.mtime == mtime { continue }   // untouched
            if size < Int64(cursor.offset) { cursor = Cursor(size: 0, mtime: 0, offset: 0) }  // rewritten

            let directory = URL(fileURLWithPath: path)
                .deletingLastPathComponent().lastPathComponent
            let consumed = ingest(path: path, from: cursor.offset, directory: directory)
            cursor.offset = consumed
            cursor.size   = size
            cursor.mtime  = mtime
            cache.cursors[path] = cursor
        }
    }

    /// Streams complete lines from `offset` and folds them in.
    /// Returns the offset just past the last *complete* line, so a transcript
    /// being appended to right now is resumed cleanly next pass.
    private func ingest(path: String, from offset: UInt64, directory: String) -> UInt64 {
        guard let handle = FileHandle(forReadingAtPath: path) else { return offset }
        defer { try? handle.close() }
        do { try handle.seek(toOffset: offset) } catch { return offset }

        var consumed = offset
        var remainder = Data()
        let newline = UInt8(ascii: "\n")

        while true {
            let chunk: Data?
            do { chunk = try handle.read(upToCount: 1 << 20) } catch { break }
            guard let chunk, !chunk.isEmpty else { break }
            remainder.append(chunk)

            var start = remainder.startIndex
            while let nl = remainder[start...].firstIndex(of: newline) {
                let line = remainder[start..<nl]
                fold(line: line, directory: directory)
                consumed += UInt64(line.count + 1)
                start = remainder.index(after: nl)
            }
            remainder = Data(remainder[start...])
        }
        return consumed
    }

    private func fold(line: Data, directory: String) {
        // Cheap reject before the JSON parser: only assistant turns carry usage.
        guard line.count > 2, Self.contains(line, pattern: Self.usageNeedle) else { return }
        guard let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let message = obj["message"] as? [String: Any],
              let usage = message["usage"] as? [String: Any],
              let model = message["model"] as? String,
              ClaudePricing.isBillable(model)
        else { return }

        guard let id = message["id"] as? String else { return }
        if cache.seenIds[id] != nil { return }          // replayed turn — already counted

        guard let stamp = obj["timestamp"] as? String,
              let date = parseTimestamp(stamp) else { return }
        guard date.timeIntervalSinceNow > -Double(Self.windowDays) * 86_400 else { return }

        let counts = TokenCounts(usage: usage)
        guard counts.total > 0 else { return }

        let project = Self.projectName(cwd: obj["cwd"] as? String,
                                       directory: directory)

        let dayKey  = dayFormatter.string(from: date)
        let hourKey = hourFormatter.string(from: date)

        cache.seenIds[id] = dayKey
        cache.byDayModel[dayKey, default: [:]][model, default: TokenCounts()].add(counts)
        cache.byHourModel[hourKey, default: [:]][model, default: TokenCounts()].add(counts)
        cache.byDayProject[dayKey, default: [:]][project, default: [:]][model, default: TokenCounts()].add(counts)
        if !ClaudePricing.price(for: model).known { cache.sawUnknownModel = true }
        if date > (cache.lastActivity ?? .distantPast) { cache.lastActivity = date }
    }

    private static let usageNeedle = Array("\"usage\"".utf8)

    /// Substring search over raw bytes — avoids building a String per line.
    private static func contains(_ data: Data, pattern: [UInt8]) -> Bool {
        guard data.count >= pattern.count else { return false }
        return data.withUnsafeBytes { raw -> Bool in
            guard let base = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return false }
            let limit = data.count - pattern.count
            if limit < 0 { return false }
            let first = pattern[0]
            var i = 0
            while i <= limit {
                if base[i] == first {
                    var j = 1
                    while j < pattern.count, base[i + j] == pattern[j] { j += 1 }
                    if j == pattern.count { return true }
                }
                i += 1
            }
            return false
        }
    }

    /// Works out which project a turn belongs to.
    ///
    /// Claude Code names a transcript's directory after the project root, with
    /// every `/` and `.` replaced by `-`. That encoding is lossy — a directory
    /// called `windows-atoll-` is indistinguishable from a path separator — so
    /// rather than decode it we re-encode each ancestor of the record's `cwd`
    /// and keep the one that matches. That recovers the exact root even when
    /// the session was started deep inside the tree.
    ///
    /// Git worktrees are then folded back into their repository: a dozen
    /// worktrees of one repo are one project to the person reading the card,
    /// not a dozen.
    private static func projectName(cwd: String?, directory: String) -> String {
        guard let cwd, !cwd.isEmpty else { return fallbackName(directory) }

        var root = cwd
        var probe = URL(fileURLWithPath: cwd)
        while probe.path != "/" {
            if encode(probe.path) == directory { root = probe.path; break }
            probe.deleteLastPathComponent()
        }

        if let marker = root.range(of: "/.claude/worktrees/") {
            root = String(root[root.startIndex..<marker.lowerBound])
        }
        let name = URL(fileURLWithPath: root).lastPathComponent
        return name.isEmpty ? fallbackName(directory) : name
    }

    /// `/Users/me/my.app` → `-Users-me-my-app`, matching Claude Code.
    private static func encode(_ path: String) -> String {
        String(path.map { ($0 == "/" || $0 == ".") ? "-" : $0 })
    }

    /// Last resort when a record carries no `cwd`.
    private static func fallbackName(_ directory: String) -> String {
        directory.split(separator: "-", omittingEmptySubsequences: true)
            .last.map(String.init) ?? directory
    }

    // MARK: Window pruning

    private func prune() {
        let cutoff = Calendar.current.date(byAdding: .day, value: -Self.windowDays, to: Date())
            ?? Date(timeIntervalSinceNow: -Double(Self.windowDays) * 86_400)
        let cutoffKey = dayFormatter.string(from: cutoff)

        cache.byDayModel   = cache.byDayModel.filter   { $0.key >= cutoffKey }
        cache.byDayProject = cache.byDayProject.filter { $0.key >= cutoffKey }
        cache.seenIds      = cache.seenIds.filter      { $0.value >= cutoffKey }
        // Hourly detail is only ever drawn for today; three days is ample.
        let hourCutoff = dayFormatter.string(
            from: Date(timeIntervalSinceNow: -3 * 86_400))
        cache.byHourModel = cache.byHourModel.filter { String($0.key.prefix(10)) >= hourCutoff }
    }

    // MARK: Snapshot

    private func spend(_ perModel: [String: TokenCounts]) -> Double {
        perModel.reduce(0) { $0 + ClaudePricing.cost(model: $1.key, counts: $1.value) }
    }

    private func buildSnapshot() -> AgentUsageSnapshot {
        var snap = AgentUsageSnapshot()
        snap.computedAt      = Date()
        snap.hasUnknownModel = cache.sawUnknownModel
        snap.lastActivity    = cache.lastActivity
        snap.isEmpty         = cache.cursors.isEmpty

        let now     = Date()
        let todayKey = dayFormatter.string(from: now)

        // Today
        let todayModels = cache.byDayModel[todayKey] ?? [:]
        snap.spendToday = spend(todayModels)
        var todayTotals = TokenCounts()
        for (_, c) in todayModels { todayTotals.add(c) }
        snap.tokensToday     = todayTotals.total
        snap.cacheShareToday = todayTotals.cacheShare

        snap.byModel = todayModels
            .map { UsageRow(name: ClaudePricing.displayName($0.key),
                            spend: ClaudePricing.cost(model: $0.key, counts: $0.value)) }
            .filter { $0.spend > 0 }
            .sorted { $0.spend > $1.spend }

        snap.byProject = (cache.byDayProject[todayKey] ?? [:])
            .map { project, perModel in
                UsageRow(name: project, spend: spend(perModel))
            }
            .filter { $0.spend > 0 }
            .sorted { $0.spend > $1.spend }

        // Trend — 24 hourly buckets for today
        var hourly = Array(repeating: 0.0, count: 24)
        for hour in 0..<24 {
            let key = String(format: "%@ %02d", todayKey, hour)
            if let models = cache.byHourModel[key] { hourly[hour] = spend(models) }
        }
        snap.hourlyToday = hourly

        // Activity — one cell per day across the window
        var days: [ActivityDay] = []
        var total = 0.0
        var active = 0
        var busiest: ActivityDay?
        let cal = Calendar.current
        for back in stride(from: Self.activityDays - 1, through: 0, by: -1) {
            guard let date = cal.date(byAdding: .day, value: -back, to: now) else { continue }
            let key = dayFormatter.string(from: date)
            let value = cache.byDayModel[key].map { spend($0) } ?? 0
            let cell = ActivityDay(day: cal.startOfDay(for: date), spend: value)
            days.append(cell)
            total += value
            if value > 0 { active += 1 }
            if value > (busiest?.spend ?? 0) { busiest = cell }
        }
        snap.activity    = days
        snap.windowSpend = total
        snap.windowWeeks = Self.activityDays / 7
        snap.activeDays  = active
        snap.busiestDay  = busiest

        return snap
    }
}

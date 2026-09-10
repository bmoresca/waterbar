import Foundation

/// Mirrors ~/.claude/water/state.json. Every field is decoded leniently so a
/// file written by an older build (or by the Python engine) still loads.
struct LedgerState: Codable {
    struct Cell: Codable, Hashable {
        var ml: Double = 0
        var requests: Int = 0

        init(ml: Double = 0, requests: Int = 0) {
            self.ml = ml
            self.requests = requests
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            ml = try c.decodeIfPresent(Double.self, forKey: .ml) ?? 0
            requests = try c.decodeIfPresent(Int.self, forKey: .requests) ?? 0
        }
    }

    struct Tokens: Codable {
        var input = 0
        var output = 0
        var cache_write = 0
        var cache_read = 0

        init() {}

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            input = try c.decodeIfPresent(Int.self, forKey: .input) ?? 0
            output = try c.decodeIfPresent(Int.self, forKey: .output) ?? 0
            cache_write = try c.decodeIfPresent(Int.self, forKey: .cache_write) ?? 0
            cache_read = try c.decodeIfPresent(Int.self, forKey: .cache_read) ?? 0
        }
    }

    var version = 1
    var total_ml: Double = 0
    var requests = 0
    var tokens = Tokens()
    var by_day: [String: Cell] = [:]
    var by_project: [String: Cell] = [:]
    var by_model: [String: Cell] = [:]
    var by_session: [String: Cell] = [:]
    var unlocked: [String] = []
    var first_seen: String?
    var last_seen: String?
    var updated_at: String?

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        total_ml = try c.decodeIfPresent(Double.self, forKey: .total_ml) ?? 0
        requests = try c.decodeIfPresent(Int.self, forKey: .requests) ?? 0
        tokens = try c.decodeIfPresent(Tokens.self, forKey: .tokens) ?? Tokens()
        by_day = try c.decodeIfPresent([String: Cell].self, forKey: .by_day) ?? [:]
        by_project = try c.decodeIfPresent([String: Cell].self, forKey: .by_project) ?? [:]
        by_model = try c.decodeIfPresent([String: Cell].self, forKey: .by_model) ?? [:]
        by_session = try c.decodeIfPresent([String: Cell].self, forKey: .by_session) ?? [:]
        unlocked = try c.decodeIfPresent([String].self, forKey: .unlocked) ?? []
        first_seen = try c.decodeIfPresent(String.self, forKey: .first_seen)
        last_seen = try c.decodeIfPresent(String.self, forKey: .last_seen)
        updated_at = try c.decodeIfPresent(String.self, forKey: .updated_at)
    }
}

/// One priced request, as written to ledger.jsonl.
struct LedgerRow {
    var timestamp: String?
    var id: String
    var session: String?
    var project: String
    var tier: String
    var ml: Double
    var input: Int
    var output: Int
    var cacheWrite: Int
    var cacheRead: Int

    var asJSONLine: String {
        let fields: [String] = [
            "\"ts\":\(timestamp.map { "\"\($0)\"" } ?? "null")",
            "\"id\":\"\(id)\"",
            "\"s\":\(session.map { "\"\($0)\"" } ?? "null")",
            "\"p\":\(Self.quote(project))",
            "\"m\":\"\(tier)\"",
            "\"ml\":\(ml)",
            "\"tok\":[\(input),\(output),\(cacheWrite),\(cacheRead)]",
        ]
        return "{" + fields.joined(separator: ",") + "}"
    }

    private static func quote(_ value: String) -> String {
        let data = try? JSONSerialization.data(withJSONObject: [value],
                                               options: [.withoutEscapingSlashes])
        guard let data, var text = String(data: data, encoding: .utf8) else { return "\"\"" }
        text.removeFirst()
        text.removeLast()
        return text
    }
}

/// Python's built-in `round()` rounds the decimal representation, not the
/// scaled binary one - `(x * 10000).rounded() / 10000` disagrees with it on
/// values that sit near a boundary. printf rounds the same way Python does, so
/// both engines can append to one ledger without the totals drifting apart.
@inline(__always)
func round4(_ value: Double) -> Double {
    Double(String(format: "%.4f", value)) ?? value
}

enum Scanner {
    private static let recentIDCap = 50_000
    private static let usageNeedle: [UInt8] = Array("\"usage\"".utf8)

    /// Read whatever is new in the transcripts, extend the ledger, update state.
    ///
    /// `onlyPath` limits the walk to a single transcript - hooks pass the
    /// session's own file so a per-request refresh stays in the single-digit
    /// milliseconds even when the full history is a gigabyte.
    @discardableResult
    static func scan(onlyPath: String? = nil, model: WaterModel? = nil) -> (LedgerState, [Milestone]) {
        let model = model ?? WaterModel.load()
        let lock = FileLock()
        defer { lock.release() }

        var cursor = JSONFile.read(Paths.cursor) ?? [:]
        var files = cursor["files"] as? [String: [String: Any]] ?? [:]
        var recent = cursor["recent_ids"] as? [String] ?? []
        var seen = Set(recent)

        var state = JSONFile.decode(LedgerState.self, from: Paths.state) ?? LedgerState()
        let before = state.total_ml
        var rows: [LedgerRow] = []

        for path in onlyPath.map({ [$0] }) ?? transcripts() {
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
                  let size = (attrs[.size] as? NSNumber)?.intValue else { continue }
            var offset = files[path]?["offset"] as? Int ?? 0
            if size < offset { offset = 0 }  // rewritten by a resume, rewind or compaction
            if size == offset { continue }

            guard let handle = FileHandle(forReadingAtPath: path) else { continue }
            defer { try? handle.close() }
            try? handle.seek(toOffset: UInt64(offset))
            guard let chunk = try? handle.readToEnd(), !chunk.isEmpty else { continue }

            // Never consume a half-written trailing line.
            guard let lastNewline = chunk.lastIndex(of: 0x0A) else {
                files[path] = ["offset": offset]
                continue
            }
            let usableCount = chunk.distance(from: chunk.startIndex, to: lastNewline) + 1
            files[path] = ["offset": offset + usableCount]

            // Walk the raw bytes: Data's generic `split` and `range(of:)` both
            // collapse under a gigabyte of transcripts. memchr finds the line
            // breaks, memmem rejects the ~95% of lines with no usage on them,
            // and only survivors get copied out for a JSON parse.
            for line in candidateLines(in: chunk, count: usableCount) {
                guard let row = price(line: line, path: path, model: model, seen: seen) else { continue }
                seen.insert(row.id)
                recent.append(row.id)
                rows.append(row)
            }
        }

        var newlyUnlocked: [Milestone] = []
        if !rows.isEmpty {
            append(rows)
            apply(rows, to: &state)
            newlyUnlocked = refreshUnlocked(&state, since: before)
        }

        if recent.count > recentIDCap {
            recent = Array(recent.suffix(recentIDCap))
        }
        state.updated_at = ISO8601DateFormatter().string(from: Date())
        cursor["files"] = files
        cursor["recent_ids"] = recent
        JSONFile.encode(state, to: Paths.state)
        JSONFile.write(Paths.cursor, cursor)
        return (state, newlyUnlocked)
    }

    // MARK: - Pieces

    /// Newline-delimited lines that mention token usage, copied out one at a
    /// time so the 95% that don't never leave the mapped buffer.
    private static func candidateLines(in chunk: Data, count: Int) -> [Data] {
        chunk.withUnsafeBytes { buffer -> [Data] in
            guard let base = buffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return [] }
            return usageNeedle.withUnsafeBufferPointer { needle -> [Data] in
                var found: [Data] = []
                var start = 0
                while start < count {
                    let remaining = count - start
                    let cursor = UnsafeRawPointer(base + start)
                    guard let breakAt = memchr(cursor, 0x0A, remaining) else { break }
                    let length = UnsafeRawPointer(breakAt) - cursor
                    if length > needle.count,
                       memmem(cursor, length, needle.baseAddress, needle.count) != nil {
                        found.append(Data(bytes: cursor, count: length))
                    }
                    start += length + 1
                }
                return found
            }
        }
    }

    private static func transcripts() -> [String] {
        guard let walker = FileManager.default.enumerator(atPath: Paths.projectsDir) else { return [] }
        var found: [String] = []
        for case let relative as String in walker where relative.hasSuffix(".jsonl") {
            found.append((Paths.projectsDir as NSString).appendingPathComponent(relative))
        }
        return found
    }

    private static func price(line: Data, path: String, model: WaterModel, seen: Set<String>) -> LedgerRow? {
        guard let record = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              record["type"] as? String == "assistant",
              let message = record["message"] as? [String: Any],
              let rawUsage = message["usage"] as? [String: Any],
              let modelID = message["model"] as? String,
              !modelID.isEmpty, modelID != "<synthetic>" else { return nil }

        guard let id = record["requestId"] as? String
                ?? message["id"] as? String
                ?? record["uuid"] as? String,
              !seen.contains(id) else { return nil }

        var usage = WaterModel.Usage()
        usage.input = rawUsage["input_tokens"] as? Int ?? 0
        usage.output = rawUsage["output_tokens"] as? Int ?? 0
        usage.cacheWrite = rawUsage["cache_creation_input_tokens"] as? Int ?? 0
        usage.cacheRead = rawUsage["cache_read_input_tokens"] as? Int ?? 0
        if let server = rawUsage["server_tool_use"] as? [String: Any] {
            usage.serverToolCalls = (server["web_search_requests"] as? Int ?? 0)
                + (server["web_fetch_requests"] as? Int ?? 0)
        }

        let tier = WaterModel.tier(for: modelID)
        return LedgerRow(
            timestamp: record["timestamp"] as? String,
            id: id,
            session: record["sessionId"] as? String,
            project: projectLabel(cwd: record["cwd"] as? String, path: path),
            tier: tier,
            // Rounded per row, exactly as plugin/engine/water.py does, so the
            // two engines can append to the same ledger without drifting.
            ml: round4(model.millilitres(usage: usage, tier: tier)),
            input: usage.input, output: usage.output,
            cacheWrite: usage.cacheWrite, cacheRead: usage.cacheRead
        )
    }

    /// Last two path components, so sibling `app` / `site` folders under
    /// different parents don't collapse into one bucket.
    private static func projectLabel(cwd: String?, path: String) -> String {
        var source = cwd ?? ""
        if source.isEmpty {
            let slug = ((path as NSString).deletingLastPathComponent as NSString).lastPathComponent
            source = slug.replacingOccurrences(of: "-", with: "/")
        }
        let parts = source.split(separator: "/").map(String.init)
        guard !parts.isEmpty else { return source }
        return parts.suffix(2).joined(separator: "/")
    }

    private static func append(_ rows: [LedgerRow]) {
        Paths.ensureWaterDir()
        let text = rows.map(\.asJSONLine).joined(separator: "\n") + "\n"
        guard let data = text.data(using: .utf8) else { return }
        if !FileManager.default.fileExists(atPath: Paths.ledger) {
            FileManager.default.createFile(atPath: Paths.ledger, contents: data)
            return
        }
        guard let handle = FileHandle(forWritingAtPath: Paths.ledger) else { return }
        defer { try? handle.close() }
        try? handle.seekToEnd()
        try? handle.write(contentsOf: data)
    }

    static func apply(_ rows: [LedgerRow], to state: inout LedgerState) {
        for row in rows {
            state.total_ml = round4(state.total_ml + row.ml)
            state.requests += 1
            state.tokens.input += row.input
            state.tokens.output += row.output
            state.tokens.cache_write += row.cacheWrite
            state.tokens.cache_read += row.cacheRead
            bump(&state.by_day, localDay(row.timestamp), row.ml)
            bump(&state.by_project, row.project, row.ml)
            bump(&state.by_model, row.tier, row.ml)
            if let session = row.session { bump(&state.by_session, session, row.ml) }
            if let ts = row.timestamp {
                if state.first_seen == nil || ts < state.first_seen! { state.first_seen = ts }
                if state.last_seen == nil || ts > state.last_seen! { state.last_seen = ts }
            }
        }

        // Keep the maps from growing without bound.
        if state.by_day.count > 400 {
            let keep = Set(state.by_day.keys.sorted().suffix(400))
            state.by_day = state.by_day.filter { keep.contains($0.key) }
        }
        if state.by_session.count > 5000 {
            let keep = Set(state.by_session.sorted { $0.value.ml > $1.value.ml }.prefix(5000).map(\.key))
            state.by_session = state.by_session.filter { keep.contains($0.key) }
        }
    }

    private static func bump(_ bucket: inout [String: LedgerState.Cell], _ key: String, _ ml: Double) {
        var cell = bucket[key] ?? LedgerState.Cell()
        cell.ml = round4(cell.ml + ml)
        cell.requests += 1
        bucket[key] = cell
    }

    static func localDay(_ timestamp: String?) -> String {
        let output = DateFormatter()
        output.dateFormat = "yyyy-MM-dd"
        guard let timestamp, let date = parseISO(timestamp) else {
            return output.string(from: Date())
        }
        return output.string(from: date)
    }

    private static func parseISO(_ text: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: text) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: text)
    }

    @discardableResult
    static func refreshUnlocked(_ state: inout LedgerState, since previousTotal: Double) -> [Milestone] {
        let unlocked = Milestones.unlocked(at: state.total_ml)
        state.unlocked = unlocked.map(\.name)
        let newly = unlocked.filter { $0.thresholdML > previousTotal }
        guard !newly.isEmpty else { return [] }

        var log = JSONFile.readArray(Paths.achievements)
        let stamp = ISO8601DateFormatter().string(from: Date())
        for milestone in newly {
            log.append(["name": milestone.name, "icon": milestone.icon,
                        "blurb": milestone.blurb, "threshold_ml": milestone.thresholdML,
                        "at": stamp])
        }
        JSONFile.write(Paths.achievements, log)
        return newly
    }

    /// Recompute state.json from the ledger - used after the model constants change.
    static func rebuild() -> LedgerState {
        var state = LedgerState()
        guard let data = FileManager.default.contents(atPath: Paths.ledger) else { return state }
        var rows: [LedgerRow] = []
        for line in data.split(separator: 0x0A, omittingEmptySubsequences: true) {
            guard let record = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  let id = record["id"] as? String,
                  let ml = record["ml"] as? Double else { continue }
            let tok = record["tok"] as? [Int] ?? [0, 0, 0, 0]
            rows.append(LedgerRow(timestamp: record["ts"] as? String, id: id,
                                  session: record["s"] as? String,
                                  project: record["p"] as? String ?? "",
                                  tier: record["m"] as? String ?? "unknown", ml: ml,
                                  input: tok.count > 0 ? tok[0] : 0,
                                  output: tok.count > 1 ? tok[1] : 0,
                                  cacheWrite: tok.count > 2 ? tok[2] : 0,
                                  cacheRead: tok.count > 3 ? tok[3] : 0))
        }
        apply(rows, to: &state)
        refreshUnlocked(&state, since: -1)
        state.updated_at = ISO8601DateFormatter().string(from: Date())
        JSONFile.encode(state, to: Paths.state)
        return state
    }
}

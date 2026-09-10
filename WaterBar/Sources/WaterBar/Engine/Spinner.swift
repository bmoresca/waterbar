import Foundation

struct SessionStats {
    var totalML: Double = 0
    var requests: Int = 0
    var lastML: Double?
    var averageML: Double? { requests > 0 ? totalML / Double(requests) : nil }
}

/// Claude Code picks a spinner verb at random from `settings.spinnerVerbs` at
/// the start of each turn, and watches its settings files for changes. So
/// rewriting that list after every request makes the spinner report live
/// numbers.
///
/// We can't know what the request about to run will cost, so the number shown
/// is the one the *previous* request actually cost, jittered a little. It is a
/// nowcast, not a prediction. That is the honest version of this joke.
enum Spinner {
    static let templates = [
        "Evaporating", "Boiling off", "Drinking", "Sipping", "Guzzling", "Slurping",
        "Chugging", "Draining", "Misting", "Vaporizing", "Sweating out",
        "Desalinating", "Condensing", "Wasting", "Steaming", "Decanting",
    ]

    static func sessionStats(_ state: LedgerState, session: String?) -> SessionStats {
        var stats = SessionStats()
        guard let session else { return stats }
        if let cell = state.by_session[session] {
            stats.totalML = cell.ml
            stats.requests = cell.requests
        }
        for line in tailLines(Paths.ledger).reversed() {
            guard let record = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  record["s"] as? String == session else { continue }
            stats.lastML = record["ml"] as? Double
            break
        }
        return stats
    }

    /// The session that most recently made a request, per the ledger tail.
    static func latestSession() -> String? {
        for line in tailLines(Paths.ledger, maxBytes: 16_384).reversed() {
            if let record = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
               let session = record["s"] as? String {
                return session
            }
        }
        return nil
    }

    static func verbs(base: Double, sessionTotal: Double, showTotal: Bool, count: Int = 12) -> [String] {
        let picked = templates.shuffled().prefix(count)
        let totalText = Format.ml(sessionTotal)
        return picked.enumerated().map { index, template in
            let jitter = base * Double.random(in: 0.85...1.15)
            var verb = "\(template) \(Format.ml(jitter))"
            if showTotal, sessionTotal > 0, index % 4 == 3 {
                verb += " · \(totalText) this session"
            }
            return verb
        }
    }

    /// Rewrite spinnerVerbs in the target settings file. Returns nil when
    /// nothing needed changing.
    @discardableResult
    static func apply(session: String?, config: WaterConfig? = nil,
                      state: LedgerState? = nil, force: Bool = false) -> [String]? {
        let config = config ?? WaterConfig.load()
        guard config.spinnerEnabled else { return nil }
        let state = state ?? JSONFile.decode(LedgerState.self, from: Paths.state) ?? LedgerState()
        let stats = sessionStats(state, session: session)

        var base = stats.lastML ?? stats.averageML ?? 0
        if base <= 0 {
            base = state.requests > 0 ? state.total_ml / Double(state.requests) : 8
        }

        // Claude Code re-reads its settings on every change, so don't rewrite
        // the file when nothing visible would move. Rounding is what the user
        // sees, so rounding is what we compare.
        let signature = "\(Format.ml(base))|\(Format.ml(stats.totalML))|\(session ?? "")"
        if !force, JSONFile.read(Paths.spinnerMemo)?["signature"] as? String == signature { return nil }

        let list = verbs(base: base, sessionTotal: stats.totalML, showTotal: config.showSessionTotal)
        let path = Paths.settingsFile(target: config.settingsTarget)

        let lock = FileLock()
        defer { lock.release() }

        var settings: [String: Any]
        if let existing = JSONFile.read(path) {
            settings = existing
        } else if FileManager.default.fileExists(atPath: path) {
            return nil  // malformed file - leave it alone
        } else {
            settings = [:]
        }

        let backup = path + ".before-water"
        if !FileManager.default.fileExists(atPath: backup),
           FileManager.default.fileExists(atPath: path) {
            JSONFile.write(backup, settings)
        }

        settings["spinnerVerbs"] = ["mode": config.spinnerMode, "verbs": list]
        JSONFile.write(path, settings)
        JSONFile.write(Paths.spinnerMemo, ["signature": signature, "at": Date().timeIntervalSince1970])
        return list
    }

    @discardableResult
    static func clear(config: WaterConfig? = nil) -> Bool {
        let config = config ?? WaterConfig.load()
        let path = Paths.settingsFile(target: config.settingsTarget)
        let lock = FileLock()
        defer { lock.release() }
        guard var settings = JSONFile.read(path), settings["spinnerVerbs"] != nil else { return false }
        settings.removeValue(forKey: "spinnerVerbs")
        JSONFile.write(path, settings)
        try? FileManager.default.removeItem(atPath: Paths.spinnerMemo)
        return true
    }

    private static func tailLines(_ path: String, maxBytes: Int = 131_072) -> [String] {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let size = (attrs[.size] as? NSNumber)?.intValue,
              let handle = FileHandle(forReadingAtPath: path) else { return [] }
        defer { try? handle.close() }
        try? handle.seek(toOffset: UInt64(max(0, size - maxBytes)))
        guard var data = try? handle.readToEnd(), !data.isEmpty else { return [] }
        // A partial first line is inevitable when we seek into the middle.
        if size > maxBytes, let firstNewline = data.firstIndex(of: 0x0A) {
            data = data[data.index(after: firstNewline)...]
        }
        return String(decoding: data, as: UTF8.self)
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
    }
}

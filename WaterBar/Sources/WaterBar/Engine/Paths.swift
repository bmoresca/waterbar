import Foundation

/// Every file the engine touches. Kept byte-compatible with the Python
/// implementation in plugin/engine/water.py so the two can share a ledger.
enum Paths {
    static var claudeDir: String {
        if let override = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"], !override.isEmpty {
            return override
        }
        return (NSHomeDirectory() as NSString).appendingPathComponent(".claude")
    }

    static var waterDir: String { (claudeDir as NSString).appendingPathComponent("water") }
    static var projectsDir: String { (claudeDir as NSString).appendingPathComponent("projects") }

    static var model: String { water("model.json") }
    static var config: String { water("config.json") }
    static var ledger: String { water("ledger.jsonl") }
    static var cursor: String { water("cursor.json") }
    static var state: String { water("state.json") }
    static var achievements: String { water("achievements.json") }
    static var spinnerMemo: String { water("spinner.json") }
    static var lock: String { water(".lock") }

    private static func water(_ name: String) -> String {
        (waterDir as NSString).appendingPathComponent(name)
    }

    static func settingsFile(target: String) -> String {
        switch target {
        case "user-local": return (claudeDir as NSString).appendingPathComponent("settings.local.json")
        default:
            if target.hasPrefix("/") { return target }
            return (claudeDir as NSString).appendingPathComponent("settings.json")
        }
    }

    static func ensureWaterDir() {
        try? FileManager.default.createDirectory(atPath: waterDir, withIntermediateDirectories: true)
    }
}

enum JSONFile {
    static func read(_ path: String) -> [String: Any]? {
        guard let data = FileManager.default.contents(atPath: path),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return object
    }

    static func readArray(_ path: String) -> [Any] {
        guard let data = FileManager.default.contents(atPath: path),
              let object = try? JSONSerialization.jsonObject(with: data) as? [Any] else { return [] }
        return object
    }

    /// Write via a temp file + rename, so a reader never sees a half-written file.
    @discardableResult
    static func write(_ path: String, _ object: Any) -> Bool {
        Paths.ensureWaterDir()
        guard let data = try? JSONSerialization.data(
            withJSONObject: object, options: [.prettyPrinted, .sortedKeys]) else { return false }
        let tmp = path + ".tmp.\(ProcessInfo.processInfo.processIdentifier)"
        guard (try? data.write(to: URL(fileURLWithPath: tmp))) != nil else { return false }
        do {
            _ = try FileManager.default.replaceItemAt(URL(fileURLWithPath: path),
                                                      withItemAt: URL(fileURLWithPath: tmp))
            return true
        } catch {
            try? FileManager.default.removeItem(atPath: path)
            try? FileManager.default.moveItem(atPath: tmp, toPath: path)
            return true
        }
    }

    static func encode<T: Encodable>(_ value: T, to path: String) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(value) else { return }
        let tmp = path + ".tmp.\(ProcessInfo.processInfo.processIdentifier)"
        Paths.ensureWaterDir()
        guard (try? data.write(to: URL(fileURLWithPath: tmp))) != nil else { return }
        if (try? FileManager.default.replaceItemAt(URL(fileURLWithPath: path),
                                                   withItemAt: URL(fileURLWithPath: tmp))) == nil {
            try? FileManager.default.removeItem(atPath: path)
            try? FileManager.default.moveItem(atPath: tmp, toPath: path)
        }
    }

    static func decode<T: Decodable>(_ type: T.Type, from path: String) -> T? {
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}

/// Best-effort exclusive lock, so two hooks firing at once can't interleave a
/// read-modify-write of the ledger or of settings.json.
struct FileLock {
    private let held: Bool

    init(timeout: TimeInterval = 5) {
        Paths.ensureWaterDir()
        let deadline = Date().addingTimeInterval(timeout)
        var acquired = false
        while !acquired {
            let fd = open(Paths.lock, O_CREAT | O_EXCL | O_WRONLY, 0o644)
            if fd >= 0 {
                close(fd)
                acquired = true
                break
            }
            // Reap a lock left behind by a process that died holding it.
            if let attrs = try? FileManager.default.attributesOfItem(atPath: Paths.lock),
               let modified = attrs[.modificationDate] as? Date,
               Date().timeIntervalSince(modified) > 30 {
                try? FileManager.default.removeItem(atPath: Paths.lock)
                continue
            }
            if Date() > deadline { break }  // proceed unlocked rather than hang a hook
            Thread.sleep(forTimeInterval: 0.05)
        }
        held = acquired
    }

    func release() {
        guard held else { return }
        try? FileManager.default.removeItem(atPath: Paths.lock)
    }
}

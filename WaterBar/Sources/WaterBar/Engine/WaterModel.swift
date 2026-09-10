import Foundation

/// The estimate model: tokens -> watt-hours -> kWh (x PUE) -> litres.
///
/// Every constant is public and editable in ~/.claude/water/model.json. The
/// defaults and the reasoning behind them are documented in the README; the
/// short version is that they were fitted between Google's 2025 Gemini
/// inference figures at the low end and Li et al. (2023) at the high end.
struct WaterModel {
    struct Rates {
        var output: Double
        var input: Double
        var cacheWrite: Double
        var cacheRead: Double
    }

    var tiers: [String: Rates]
    var pue: Double
    var onsiteLitresPerKWh: Double
    var offsiteLitresPerKWh: Double
    var webSearchWh: Double

    static let defaults = WaterModel(
        tiers: [
            "opus":    Rates(output: 3.00, input: 0.100, cacheWrite: 0.100, cacheRead: 0.015),
            "sonnet":  Rates(output: 1.10, input: 0.040, cacheWrite: 0.040, cacheRead: 0.006),
            "fable":   Rates(output: 0.60, input: 0.022, cacheWrite: 0.022, cacheRead: 0.004),
            "haiku":   Rates(output: 0.30, input: 0.012, cacheWrite: 0.012, cacheRead: 0.002),
            "unknown": Rates(output: 1.10, input: 0.040, cacheWrite: 0.040, cacheRead: 0.006),
        ],
        pue: 1.10,
        onsiteLitresPerKWh: 1.80,
        offsiteLitresPerKWh: 3.10,
        webSearchWh: 0.30
    )

    /// Order matters: "claude-opus-5" must not match on a later, looser rule.
    static func tier(for modelID: String) -> String {
        let lower = modelID.lowercased()
        for candidate in ["opus", "sonnet", "fable", "haiku"] where lower.contains(candidate) {
            return candidate
        }
        return "unknown"
    }

    func rates(for tier: String) -> Rates {
        tiers[tier] ?? tiers["unknown"] ?? WaterModel.defaults.tiers["unknown"]!
    }

    /// Millilitres of water for one API request.
    func millilitres(usage: Usage, tier: String) -> Double {
        let r = rates(for: tier)
        var wh = (Double(usage.output) * r.output
                  + Double(usage.input) * r.input
                  + Double(usage.cacheWrite) * r.cacheWrite
                  + Double(usage.cacheRead) * r.cacheRead) / 1000
        wh += Double(usage.serverToolCalls) * webSearchWh
        let kwh = (wh / 1000) * pue
        return kwh * (onsiteLitresPerKWh + offsiteLitresPerKWh) * 1000
    }

    struct Usage {
        var input = 0
        var output = 0
        var cacheWrite = 0
        var cacheRead = 0
        var serverToolCalls = 0
    }

    // MARK: - Persistence
    //
    // Written in exactly the shape plugin/engine/water.py expects, so whichever
    // side creates the file first, the other reads it.

    static func load() -> WaterModel {
        guard let raw = JSONFile.read(Paths.model) else {
            JSONFile.write(Paths.model, defaults.asJSON())
            return defaults
        }
        var model = defaults
        if let energy = raw["energy_wh_per_1k"] as? [String: [String: Any]] {
            for (tier, values) in energy {
                let fallback = model.tiers[tier] ?? defaults.tiers["unknown"]!
                model.tiers[tier] = Rates(
                    output: values["output"] as? Double ?? fallback.output,
                    input: values["input"] as? Double ?? fallback.input,
                    cacheWrite: values["cache_write"] as? Double ?? fallback.cacheWrite,
                    cacheRead: values["cache_read"] as? Double ?? fallback.cacheRead
                )
            }
        }
        model.pue = raw["pue"] as? Double ?? model.pue
        if let water = raw["water_l_per_kwh"] as? [String: Any] {
            model.onsiteLitresPerKWh = water["onsite_cooling"] as? Double ?? model.onsiteLitresPerKWh
            model.offsiteLitresPerKWh = water["offsite_electricity"] as? Double ?? model.offsiteLitresPerKWh
        }
        model.webSearchWh = raw["web_search_wh"] as? Double ?? model.webSearchWh
        return model
    }

    func asJSON() -> [String: Any] {
        var energy: [String: Any] = [:]
        for (tier, r) in tiers {
            energy[tier] = ["output": r.output, "input": r.input,
                            "cache_write": r.cacheWrite, "cache_read": r.cacheRead]
        }
        return [
            "version": 1,
            "_comment": "Watt-hours per 1,000 tokens, per model tier. Edit freely.",
            "energy_wh_per_1k": energy,
            "pue": pue,
            "water_l_per_kwh": ["onsite_cooling": onsiteLitresPerKWh,
                                "offsite_electricity": offsiteLitresPerKWh],
            "web_search_wh": webSearchWh,
        ]
    }
}

/// User-facing switches, shared with the plugin.
struct WaterConfig {
    var spinnerEnabled = true
    var settingsTarget = "user"
    var spinnerMode = "replace"
    var showSessionTotal = true
    var notifyOnMilestone = true
    var supportURL = ""

    static func load() -> WaterConfig {
        guard let raw = JSONFile.read(Paths.config) else {
            let fresh = WaterConfig()
            JSONFile.write(Paths.config, fresh.asJSON())
            return fresh
        }
        var config = WaterConfig()
        if let spinner = raw["spinner"] as? [String: Any] {
            config.spinnerEnabled = spinner["enabled"] as? Bool ?? config.spinnerEnabled
            config.settingsTarget = spinner["settings_target"] as? String ?? config.settingsTarget
            config.spinnerMode = spinner["mode"] as? String ?? config.spinnerMode
            config.showSessionTotal = spinner["show_session_total"] as? Bool ?? config.showSessionTotal
        }
        config.notifyOnMilestone = raw["notify_on_milestone"] as? Bool ?? config.notifyOnMilestone
        config.supportURL = raw["support_url"] as? String ?? config.supportURL
        return config
    }

    func asJSON() -> [String: Any] {
        ["spinner": ["enabled": spinnerEnabled,
                     "settings_target": settingsTarget,
                     "mode": spinnerMode,
                     "show_session_total": showSessionTotal],
         "notify_on_milestone": notifyOnMilestone,
         "support_url": supportURL]
    }

    func save() { JSONFile.write(Paths.config, asJSON()) }
}

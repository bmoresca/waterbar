import Foundation

enum Report {
    private static let equivalents: [(size: Double, one: String, many: String)] = [
        (500, "bottle of water", "bottles of water"),
        (250, "glass of water", "glasses of water"),
        (6_000, "toilet flush", "toilet flushes"),
        (50_000, "shower", "showers"),
        (150_000, "bathtub", "bathtubs"),
    ]

    static func comparisons(_ totalML: Double) -> [String] {
        var found: [String] = []
        for item in equivalents {
            let n = totalML / item.size
            guard n >= 0.75 else { continue }
            let label = (n < 1.5) ? item.one : item.many
            var number = String(format: "%.1f", n)
            if number.hasSuffix(".0") { number.removeLast(2) }
            found.append("\(number) \(label)")
        }
        return Array(found.suffix(3))
    }

    static func progressBar(_ fraction: Double, width: Int = 24) -> String {
        let filled = Int((max(0, min(1, fraction)) * Double(width)).rounded())
        return String(repeating: "█", count: filled) + String(repeating: "░", count: width - filled)
    }

    static func markdown(_ state: LedgerState, session: String?) -> String {
        var lines: [String] = []
        lines.append("## 💧 Water ledger")
        lines.append("")
        lines.append("**\(Format.ml(state.total_ml))** across \(Format.count(state.requests)) requests")
        let eq = comparisons(state.total_ml)
        if !eq.isEmpty { lines.append("_about \(eq.joined(separator: ", or "))_") }
        lines.append("")

        lines.append("| | water | requests |")
        lines.append("|---|---:|---:|")
        lines.append("| Today | \(Format.ml(state.todayML)) | \(Format.count(state.todayRequests)) |")
        if let session {
            let stats = Spinner.sessionStats(state, session: session)
            lines.append("| This session | \(Format.ml(stats.totalML)) | \(Format.count(stats.requests)) |")
            if let last = stats.lastML {
                lines.append("| Last request | \(Format.ml(last)) | |")
            }
        }
        lines.append("| All time | \(Format.ml(state.total_ml)) | \(Format.count(state.requests)) |")
        lines.append("")

        let unlocked = state.unlockedMilestones
        if let next = state.nextMilestone {
            lines.append("**Next milestone** \(next.icon) \(next.name) - \(Format.ml(next.thresholdML))")
            let percent = Int((state.progressToNext * 100).rounded())
            lines.append("`\(progressBar(state.progressToNext))` \(percent)%  (\(Format.ml(next.thresholdML - state.total_ml)) to go)")
        } else {
            lines.append("**Every milestone unlocked.** There is nothing left to pour.")
        }
        lines.append("")

        if !unlocked.isEmpty {
            lines.append("**Unlocked (\(unlocked.count)/\(Milestones.all.count))**")
            lines.append("")
            for milestone in unlocked.suffix(6) {
                lines.append("- \(milestone.icon) **\(milestone.name)** - \(milestone.blurb)")
            }
            if unlocked.count > 6 { lines.append("- _...and \(unlocked.count - 6) earlier_") }
            lines.append("")
        }

        let projects = state.topProjects.prefix(5)
        if !projects.isEmpty {
            lines.append("**Thirstiest projects**")
            lines.append("")
            for project in projects {
                lines.append("- `\(project.name)` - \(Format.ml(project.ml))")
            }
            lines.append("")
        }

        let models = state.by_model.sorted { $0.value.ml > $1.value.ml }
        if !models.isEmpty {
            lines.append("**By model** " + models.map { "\($0.key) \(Format.ml($0.value.ml))" }
                .joined(separator: " · "))
            lines.append("")
        }

        lines.append("_Estimated from token counts. Not measured. See `~/.claude/water/model.json`._")
        return lines.joined(separator: "\n")
    }
}

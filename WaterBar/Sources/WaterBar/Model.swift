import Foundation

/// Everything the UI needs that isn't stored in state.json, derived on demand.
extension LedgerState {
    var todayML: Double {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return by_day[formatter.string(from: Date())]?.ml ?? 0
    }

    var todayRequests: Int {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return by_day[formatter.string(from: Date())]?.requests ?? 0
    }

    var unlockedMilestones: [Milestone] { Milestones.unlocked(at: total_ml) }
    var lockedMilestones: [Milestone] { Milestones.all.filter { total_ml < $0.thresholdML } }
    var nextMilestone: Milestone? { Milestones.next(after: total_ml) }

    /// Progress reads as the distance between two rungs, not from zero.
    var progressToNext: Double {
        guard let next = nextMilestone else { return 1 }
        let previous = unlockedMilestones.last?.thresholdML ?? 0
        let span = next.thresholdML - previous
        guard span > 0 else { return 1 }
        return min(1, max(0, (total_ml - previous) / span))
    }

    func recentDays(_ days: Int) -> [(day: String, ml: Double)] {
        by_day.keys.sorted().suffix(days).map { ($0, by_day[$0]?.ml ?? 0) }
    }

    var last7Days: Double { recentDays(7).reduce(0) { $0 + $1.ml } }

    var topProjects: [(name: String, ml: Double)] {
        by_project.sorted { $0.value.ml > $1.value.ml }.map { ($0.key, $0.value.ml) }
    }
}

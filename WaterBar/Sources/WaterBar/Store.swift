import Foundation
import SwiftUI
import UserNotifications

/// Owns the polling loop. The engine runs in-process, so WaterBar has no
/// runtime dependencies at all - no Python, no helper binaries.
@MainActor
final class WaterStore: ObservableObject {
    @Published private(set) var state = LedgerState()
    @Published private(set) var isLoading = true
    @Published private(set) var errorText: String?
    @Published var showTodayInMenuBar = UserDefaults.standard.bool(forKey: "showTodayInMenuBar")

    private var timer: Timer?
    private var launchBaselineTaken = false
    private let refreshInterval: TimeInterval = 20

    init(loadSynchronously: Bool = false) {
        if loadSynchronously {
            let (state, _) = Scanner.scan()
            self.state = state
            isLoading = false
            return
        }
        requestNotificationPermission()
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    var menuBarText: String {
        if isLoading && state.requests == 0 { return "…" }
        return Format.ml(showTodayInMenuBar ? state.todayML : state.total_ml)
    }

    func toggleMenuBarMode() {
        showTodayInMenuBar.toggle()
        UserDefaults.standard.set(showTodayInMenuBar, forKey: "showTodayInMenuBar")
    }

    func refresh() {
        Task.detached(priority: .utility) {
            let (state, newly) = Scanner.scan()
            // Keep the Claude Code spinner current even when the plugin isn't
            // installed; the plugin's hooks just do it sooner.
            Spinner.apply(session: Spinner.latestSession(), state: state)
            let hasTranscripts = FileManager.default.fileExists(atPath: Paths.projectsDir)
            await MainActor.run {
                self.isLoading = false
                self.state = state
                self.errorText = hasTranscripts ? nil
                    : "No Claude Code transcripts found in \(Paths.projectsDir). Use Claude Code once and this fills in."
                self.announce(newly)
            }
        }
    }

    // MARK: - Milestone notifications

    private func requestNotificationPermission() {
        guard Bundle.main.bundleIdentifier != nil else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func announce(_ milestones: [Milestone]) {
        // The first poll of a launch establishes a baseline; it isn't news.
        defer { launchBaselineTaken = true }
        guard launchBaselineTaken, Bundle.main.bundleIdentifier != nil,
              WaterConfig.load().notifyOnMilestone else { return }

        for milestone in milestones {
            let content = UNMutableNotificationContent()
            content.title = "\(milestone.icon)  \(milestone.name)"
            content.body = "\(milestone.blurb)\nTotal: \(Format.ml(state.total_ml))"
            content.sound = .default
            UNUserNotificationCenter.current().add(
                UNNotificationRequest(identifier: "milestone-\(milestone.name)",
                                      content: content, trigger: nil))
        }
    }
}

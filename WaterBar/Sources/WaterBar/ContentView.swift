import SwiftUI

private let waterBlue = Color(red: 0.13, green: 0.55, blue: 0.86)
private let waterDeep = Color(red: 0.05, green: 0.32, blue: 0.60)

struct ContentView: View {
    @ObservedObject var store: WaterStore
    /// ImageRenderer can't draw a ScrollView or a live Button, so the offscreen
    /// screenshot path lays the same content out flat instead.
    var staticRender = false
    @State private var showAllMilestones = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            scrollingBody {
                VStack(alignment: .leading, spacing: 18) {
                    if let error = store.errorText {
                        ErrorCard(text: error)
                    }
                    totals
                    if store.state.nextMilestone != nil { nextMilestone }
                    if !store.state.by_day.isEmpty { history }
                    achievements
                    if !store.state.by_project.isEmpty { projects }
                    coffee
                    footnote
                }
                .padding(16)
            }
            Divider()
            footer
        }
        .frame(width: 380)
        .frame(maxHeight: staticRender ? .infinity : 620)
    }

    @ViewBuilder
    private func scrollingBody<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        if staticRender {
            content()
        } else {
            ScrollView { content() }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("💧")
                .font(.system(size: 30))
                .baselineOffset(-4)
            VStack(alignment: .leading, spacing: 2) {
                Text(Format.ml(store.state.total_ml))
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .foregroundColor(waterDeep)
                    .contentTransition(.numericText())
                Text("estimated across \(Format.count(store.state.requests)) requests")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            LinearGradient(colors: [waterBlue.opacity(0.16), waterBlue.opacity(0.03)],
                           startPoint: .top, endPoint: .bottom)
        )
    }

    // MARK: Totals

    private var totals: some View {
        HStack(spacing: 10) {
            StatTile(label: "Today", value: Format.ml(store.state.todayML))
            StatTile(label: "Last 7 days", value: Format.ml(store.state.last7Days))
            StatTile(label: "All time", value: Format.ml(store.state.total_ml), emphasized: true)
        }
    }

    // MARK: Next milestone

    private var nextMilestone: some View {
        let next = store.state.nextMilestone!
        let progress = store.state.progressToNext
        let remaining = max(0, next.thresholdML - store.state.total_ml)
        return VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Next milestone")
            HStack(spacing: 10) {
                Text(next.icon).font(.system(size: 24))
                VStack(alignment: .leading, spacing: 1) {
                    Text(next.name).font(.system(size: 13, weight: .semibold))
                    Text(next.blurb).font(.system(size: 11)).foregroundColor(.secondary)
                }
                Spacer()
                Text("\(Int(progress * 100))%")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(waterBlue)
            }
            Tank(progress: progress)
            Text("\(Format.ml(remaining)) to go")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
    }

    // MARK: History

    private var history: some View {
        let days = store.state.recentDays(14)
        let peak = max(days.map(\.ml).max() ?? 1, 1)
        return VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Last \(days.count) days")
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(days, id: \.day) { entry in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(waterBlue.opacity(entry.ml > 0 ? 0.85 : 0.15))
                        .frame(height: max(3, CGFloat(entry.ml / peak) * 46))
                        .help("\(entry.day) — \(Format.ml(entry.ml))")
                }
            }
            .frame(height: 46, alignment: .bottom)
        }
    }

    // MARK: Achievements

    private var achievements: some View {
        let unlocked = store.state.unlockedMilestones
        let locked = store.state.lockedMilestones
        // Newest achievements first, and only the recent few unless asked -
        // twenty-two rows of history buries everything below it.
        let shownUnlocked = showAllMilestones ? unlocked.reversed().map { $0 }
                                              : Array(unlocked.reversed().prefix(5))
        let shownLocked = showAllMilestones ? locked : Array(locked.prefix(2))
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionLabel("Milestones")
                Spacer()
                Text("\(unlocked.count) / \(Milestones.all.count)")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
            }
            VStack(spacing: 4) {
                ForEach(shownUnlocked) { MilestoneRow(milestone: $0, total: store.state.total_ml) }
                ForEach(shownLocked) { MilestoneRow(milestone: $0, total: store.state.total_ml) }
            }
            if !staticRender, showAllMilestones || shownUnlocked.count + shownLocked.count < Milestones.all.count {
                Button(showAllMilestones ? "Show fewer" : "Show all \(Milestones.all.count)") {
                    withAnimation { showAllMilestones.toggle() }
                }
                .buttonStyle(.link)
                .font(.system(size: 11))
            }
        }
    }

    // MARK: Projects

    private var projects: some View {
        let top = store.state.by_project.sorted { $0.value.ml > $1.value.ml }.prefix(5)
        let peak = top.first?.value.ml ?? 1
        return VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Thirstiest projects")
            VStack(spacing: 5) {
                ForEach(Array(top), id: \.key) { name, cell in
                    HStack(spacing: 8) {
                        Text(name)
                            .font(.system(size: 11, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.head)
                            .frame(width: 150, alignment: .leading)
                        GeometryReader { geo in
                            RoundedRectangle(cornerRadius: 3)
                                .fill(waterBlue.opacity(0.7))
                                .frame(width: max(2, geo.size.width * CGFloat(cell.ml / peak)))
                        }
                        .frame(height: 8)
                        Text(Format.ml(cell.ml))
                            .font(.system(size: 10, design: .rounded))
                            .foregroundColor(.secondary)
                            .frame(width: 58, alignment: .trailing)
                    }
                }
            }
        }
    }

    /// Hidden entirely until a support URL is configured, so a fork with no
    /// link doesn't ship a dead button.
    @ViewBuilder
    private var coffee: some View {
        if let url = SupportLink.url {
            if staticRender {
                CoffeeLabel()
            } else {
                Button { NSWorkspace.shared.open(url) } label: { CoffeeLabel() }
                    .buttonStyle(.plain)
                    .help(SupportLink.tooltip)
            }
        }
    }

    private var footnote: some View {
        Text("Estimated from token counts using published figures for inference energy and datacenter water use. Nothing here is measured. Tune the constants in ~/.claude/water/model.json.")
            .font(.system(size: 10))
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Footer

    @ViewBuilder
    private var footer: some View {
        if staticRender {
            HStack {
                Text("Menu bar: all time").foregroundColor(.secondary)
                Spacer()
                Text("Refresh   Quit").foregroundColor(.secondary)
            }
            .font(.system(size: 11))
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
        } else {
            liveFooter
        }
    }

    private var liveFooter: some View {
        HStack(spacing: 12) {
            Button(action: { store.toggleMenuBarMode() }) {
                Label(store.showTodayInMenuBar ? "Menu bar: today" : "Menu bar: all time",
                      systemImage: "arrow.left.arrow.right")
            }
            .buttonStyle(.link)
            Spacer()
            Button(action: { store.refresh() }) {
                Image(systemName: store.isLoading ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Refresh now")
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.link)
        }
        .font(.system(size: 11))
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
    }
}

// MARK: - Pieces

private struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 9, weight: .bold, design: .rounded))
            .tracking(0.8)
            .foregroundColor(.secondary)
    }
}

private struct StatTile: View {
    let label: String
    let value: String
    var emphasized = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .tracking(0.6)
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(emphasized ? waterDeep : .primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(RoundedRectangle(cornerRadius: 8).fill(waterBlue.opacity(emphasized ? 0.14 : 0.07)))
    }
}

/// A little tank that fills toward the next milestone.
private struct Tank: View {
    let progress: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 5).fill(waterBlue.opacity(0.12))
                RoundedRectangle(cornerRadius: 5)
                    .fill(LinearGradient(colors: [waterBlue, waterDeep],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(4, geo.size.width * CGFloat(progress)))
            }
        }
        .frame(height: 10)
        .animation(.easeOut(duration: 0.5), value: progress)
    }
}

private struct MilestoneRow: View {
    let milestone: Milestone
    let total: Double

    private var isUnlocked: Bool { total >= milestone.thresholdML }

    var body: some View {
        HStack(spacing: 9) {
            Text(milestone.icon)
                .font(.system(size: 15))
                .opacity(isUnlocked ? 1 : 0.28)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 0) {
                Text(milestone.name)
                    .font(.system(size: 12, weight: isUnlocked ? .medium : .regular))
                    .foregroundColor(isUnlocked ? .primary : .secondary)
                Text(milestone.blurb)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if isUnlocked {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 11))
                    .foregroundColor(waterBlue)
            } else {
                Text(Format.ml(milestone.thresholdML))
                    .font(.system(size: 10, design: .rounded))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 8)
        .background(RoundedRectangle(cornerRadius: 6)
            .fill(isUnlocked ? waterBlue.opacity(0.07) : Color.clear))
    }
}

private struct CoffeeLabel: View {
    private let warm = Color(red: 0.60, green: 0.40, blue: 0.24)

    var body: some View {
        HStack(spacing: 7) {
            Text("☕").font(.system(size: 14))
            Text("Buy me a coffee")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(warm)
            Spacer()
            Image(systemName: "arrow.up.forward")
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(warm.opacity(0.6))
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(warm.opacity(0.10))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(warm.opacity(0.22), lineWidth: 1))
        )
        .contentShape(Rectangle())
    }
}

private struct ErrorCard: View {
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
            Text(text).font(.system(size: 11)).fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.12)))
    }
}

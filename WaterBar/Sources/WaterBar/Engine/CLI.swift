import Foundation

/// WaterBar is one binary in two modes. With no recognised subcommand it opens
/// the menu bar item; with one, it behaves like a normal CLI and exits. The
/// plugin's hooks call this mode, which is why the app needs no Python.
enum CLI {
    static let commands = ["scan", "status", "report", "hook", "statusline", "spinner",
                           "spinner-on", "spinner-off", "rebuild", "reset", "paths",
                           "help", "--help", "-h", "version", "--version"]

    static func runIfRequested() {
        let args = Array(CommandLine.arguments.dropFirst())
        guard let command = args.first, commands.contains(command) else { return }
        exit(run(command, args: Array(args.dropFirst())))
    }

    private static func option(_ name: String, _ args: [String]) -> String? {
        guard let index = args.firstIndex(of: name), index + 1 < args.count else { return nil }
        return args[index + 1]
    }

    private static func run(_ command: String, args: [String]) -> Int32 {
        switch command {
        case "scan":
            let (state, newly) = Scanner.scan()
            emit(["total_ml": state.total_ml, "requests": state.requests,
                  "unlocked": newly.map(\.name)])

        case "status":
            let (state, _) = Scanner.scan(onlyPath: option("--transcript", args))
            if args.contains("--refresh-spinner") {
                Spinner.apply(session: option("--session", args) ?? Spinner.latestSession(), state: state)
            }
            emit(statusPayload(state, session: option("--session", args)))

        case "report":
            let (state, _) = Scanner.scan()
            print(Report.markdown(state, session: option("--session", args)))

        case "hook":
            return hook()

        case "statusline":
            return statusline()

        case "spinner":
            let (state, _) = Scanner.scan()
            let verbs = Spinner.apply(session: option("--session", args) ?? Spinner.latestSession(),
                                      state: state, force: true)
            emit(["verbs": verbs ?? []])

        case "spinner-on":
            var config = WaterConfig.load()
            config.spinnerEnabled = true
            config.save()
            let (state, _) = Scanner.scan()
            Spinner.apply(session: option("--session", args) ?? Spinner.latestSession(),
                          config: config, state: state, force: true)
            print("spinner verbs enabled")

        case "spinner-off":
            var config = WaterConfig.load()
            config.spinnerEnabled = false
            config.save()
            print(Spinner.clear(config: config) ? "removed" : "nothing to remove")

        case "rebuild":
            emit(["total_ml": Scanner.rebuild().total_ml])

        case "reset":
            for path in [Paths.ledger, Paths.cursor, Paths.state, Paths.achievements, Paths.spinnerMemo] {
                try? FileManager.default.removeItem(atPath: path)
            }
            print("ledger reset - back to zero")

        case "paths":
            emit(["water_dir": Paths.waterDir, "ledger": Paths.ledger, "state": Paths.state,
                  "model": Paths.model, "config": Paths.config, "projects": Paths.projectsDir])

        case "version", "--version":
            print("WaterBar \(AppVersion.current)")

        default:
            print("""
            WaterBar - how much water Claude Code is drinking.

            Usage: WaterBar <command> [options]

              scan                    read new transcripts into the ledger
              status [--session ID]   everything, as JSON
              report [--session ID]   the markdown report
              spinner [--session ID]  rewrite the Claude Code spinner verbs now
              spinner-on / -off       enable or restore Claude's normal verbs
              hook                    hook entry point (reads hook JSON on stdin)
              statusline              statusLine entry point (JSON on stdin)
              rebuild                 recompute totals from the ledger
              reset                   wipe the ledger and milestones
              paths                   where everything lives

            With no command, WaterBar opens in the menu bar.
            """)
        }
        return 0
    }

    // MARK: - Hook entry points
    //
    // Never allowed to fail loudly - a broken hook is worse than a missing joke.

    private static func hook() -> Int32 {
        let payload = stdinJSON()
        let session = payload["session_id"] as? String
        var transcript = payload["transcript_path"] as? String
        if let path = transcript, !FileManager.default.fileExists(atPath: path) { transcript = nil }

        let config = WaterConfig.load()
        let (state, newly) = Scanner.scan(onlyPath: transcript)
        Spinner.apply(session: session, config: config, state: state)

        var output: [String: Any] = ["suppressOutput": true]
        if let milestone = newly.last, config.notifyOnMilestone {
            output["systemMessage"] = "\(milestone.icon)  Milestone unlocked: \(milestone.name) - "
                + "\(milestone.blurb) (total: \(Format.ml(state.total_ml)))"
        }
        emit(output)
        return 0
    }

    private static func statusline() -> Int32 {
        let payload = stdinJSON()
        let (state, _) = Scanner.scan()
        let stats = Spinner.sessionStats(state, session: payload["session_id"] as? String)
        var parts = ["💧 \(Format.ml(stats.totalML)) session",
                     "\(Format.ml(state.todayML)) today",
                     "\(Format.ml(state.total_ml)) all time"]
        if let next = state.nextMilestone { parts.append("next: \(next.icon) \(next.name)") }
        print(parts.joined(separator: "  "))
        return 0
    }

    // MARK: - Plumbing

    private static func statusPayload(_ state: LedgerState, session: String?) -> [String: Any] {
        var payload: [String: Any] = [
            "total_ml": state.total_ml,
            "requests": state.requests,
            "today_ml": state.todayML,
            "unlocked": state.unlocked,
            "by_day": state.by_day.mapValues { ["ml": $0.ml, "requests": $0.requests] },
            "by_project": state.by_project.mapValues { ["ml": $0.ml, "requests": $0.requests] },
            "by_model": state.by_model.mapValues { ["ml": $0.ml, "requests": $0.requests] },
            "milestones": Milestones.all.map {
                ["threshold_ml": $0.thresholdML, "icon": $0.icon, "name": $0.name,
                 "blurb": $0.blurb, "unlocked": state.total_ml >= $0.thresholdML]
            },
        ]
        if let next = state.nextMilestone {
            payload["next_milestone"] = ["threshold_ml": next.thresholdML, "icon": next.icon,
                                         "name": next.name, "blurb": next.blurb]
        }
        if let session {
            let stats = Spinner.sessionStats(state, session: session)
            payload["session"] = ["total_ml": stats.totalML, "requests": stats.requests,
                                  "last_ml": stats.lastML as Any]
        }
        return payload
    }

    private static func stdinJSON() -> [String: Any] {
        guard let data = try? FileHandle.standardInput.readToEnd(), !data.isEmpty,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return object
    }

    private static func emit(_ object: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: object,
                                                     options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: data, encoding: .utf8) else { return }
        print(text)
    }
}

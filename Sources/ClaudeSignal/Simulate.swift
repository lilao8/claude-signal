import Foundation
import ClaudeSignalCore

/// Headless light-resolution check through the REAL Coordinator pipeline (permission and
/// idle detection, seen/acknowledgment, fresh-done flash, network override), so what it
/// prints is exactly what the app would show. No AppKit, no Claude.
///
/// Usage: claude-signal --simulate <session>[,<session>...] <presence> [networkDown]
///   session  := state[@event][:age]   state ∈ working|permission|done|error
///               event = last hook event (e.g. PreToolUse), age = seconds since it was
///               written (default 60, i.e. not "just finished").
///   presence := present | away | idle=<seconds since last keyboard/mouse input>
///               (present = idle 0, away = idle 3600)
/// Examples:
///   claude-signal --simulate working,done away
///   claude-signal --simulate working@PreToolUse:15 present      # stuck prompt -> permission
///   claude-signal --simulate working@SubagentStop:30 idle=100   # idle session, unseen -> done
///   claude-signal --simulate done:2 present                     # just finished -> green flash
enum Simulate {
    private struct FixedIdle: IdleTimeProviding {
        let seconds: TimeInterval
        func idleSeconds() -> TimeInterval { seconds }
    }
    private struct FixedReach: ReachabilityChecking {
        let up: Bool
        func isReachable() -> Bool { up }
    }
    private struct AlwaysAlive: ProcessLivenessChecking {
        func isAlive(_ pid: Int32) -> Bool { true }
    }

    static func run(_ args: [String]) -> Int32 {
        guard args.count >= 2 else { return usage() }
        let now: TimeInterval = 1_000_000

        var sessions: [SessionState] = []
        for (i, spec) in args[0].split(separator: ",").enumerated() {
            guard let s = parse(String(spec), id: "s\(i)", now: now) else { return usage() }
            sessions.append(s)
        }
        guard let idle = parseIdle(args[1]) else { return usage() }
        let networkDown = args.count >= 3 && args[2] == "networkDown"

        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("claude-signal-sim-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            for s in sessions {
                try JSONEncoder().encode(s).write(to: dir.appendingPathComponent("\(s.sessionId).json"))
            }
        } catch {
            FileHandle.standardError.write(Data("simulate: \(error)\n".utf8))
            return 1
        }

        let coordinator = Coordinator(
            store: StateStore(directory: dir, staleThreshold: 300, liveness: AlwaysAlive()),
            presence: PresenceMonitor(threshold: 30, provider: FixedIdle(seconds: idle)),
            reachability: FixedReach(up: !networkDown),
            rateLimitStore: RateLimitStore(fileURL: dir.appendingPathComponent("ratelimit.json"))
        )
        let display = coordinator.computeDisplayState(now: now)
        let desc = sessions.map { s in
            "\(s.status.rawValue)\(s.event.map { "@\($0)" } ?? ""):\(Int(now - s.updatedAt))s"
        }.joined(separator: ",")
        print("sessions=[\(desc)] idle=\(Int(idle))s\(networkDown ? " networkDown" : "") -> display=\(display)")
        return 0
    }

    /// state[@event][:age]
    private static func parse(_ spec: String, id: String, now: TimeInterval) -> SessionState? {
        var rest = Substring(spec)
        var age: TimeInterval = 60
        if let colon = rest.lastIndex(of: ":") {
            guard let a = TimeInterval(rest[rest.index(after: colon)...]) else { return nil }
            age = a
            rest = rest[..<colon]
        }
        var event: String?
        if let at = rest.firstIndex(of: "@") {
            event = String(rest[rest.index(after: at)...])
            rest = rest[..<at]
        }
        guard let status = SessionStatus(rawValue: String(rest)) else { return nil }
        return SessionState(sessionId: id, status: status, updatedAt: now - age, event: event, pid: 1)
    }

    private static func parseIdle(_ s: String) -> TimeInterval? {
        switch s {
        case "present": return 0
        case "away": return 3600
        default:
            guard s.hasPrefix("idle=") else { return nil }
            return TimeInterval(s.dropFirst(5))
        }
    }

    private static func usage() -> Int32 {
        FileHandle.standardError.write(Data(
            "usage: --simulate state[@event][:age][,...] <present|away|idle=N> [networkDown]\n".utf8))
        return 2
    }
}

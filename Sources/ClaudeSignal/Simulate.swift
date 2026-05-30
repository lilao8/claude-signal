import Foundation
import ClaudeSignalCore

/// Usage: claude-signal --simulate <state>[,<state>...] <present|away> [networkDown]
/// Example: claude-signal --simulate working,done away
/// Prints the resolved DisplayState. No AppKit; pure logic check.
enum Simulate {
    static func run(_ args: [String]) -> Int32 {
        guard args.count >= 2 else {
            FileHandle.standardError.write(Data("usage: --simulate <states> <present|away> [networkDown]\n".utf8))
            return 2
        }
        let statuses: [SessionStatus] = args[0].split(separator: ",").compactMap {
            SessionStatus(rawValue: String($0))
        }
        let sessions = statuses.enumerated().map {
            SessionState(sessionId: "s\($0.offset)", status: $0.element, updatedAt: 0)
        }
        let presence: Presence = (args[1] == "away") ? .away : .present
        let networkDown = args.count >= 3 && args[2] == "networkDown"

        var aggregate = Aggregator.aggregate(sessions)
        aggregate = applyNetworkOverride(aggregate, networkDown: networkDown)
        let display = SignalResolver.resolve(aggregate, presence: presence)
        print("aggregate=\(aggregate) presence=\(presence) -> display=\(display)")
        return 0
    }
}

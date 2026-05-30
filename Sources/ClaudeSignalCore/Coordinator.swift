import Foundation

public struct Coordinator: Sendable {
    let store: StateStore
    let presence: PresenceMonitor
    let reachability: ReachabilityChecking

    public init(store: StateStore, presence: PresenceMonitor, reachability: ReachabilityChecking) {
        self.store = store
        self.presence = presence
        self.reachability = reachability
    }

    public func computeDisplayState(now: TimeInterval) -> DisplayState {
        let sessions = store.loadLiveSessions(now: now)
        var aggregate = Aggregator.aggregate(sessions)
        aggregate = applyNetworkOverride(aggregate, networkDown: !reachability.isReachable())
        return SignalResolver.resolve(aggregate, presence: presence.current())
    }
}

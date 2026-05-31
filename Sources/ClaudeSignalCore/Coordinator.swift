import Foundation

public struct Coordinator: Sendable {
    let store: StateStore
    let presence: PresenceMonitor
    let reachability: ReachabilityChecking
    let rateLimitStore: RateLimitStore

    public init(store: StateStore,
                presence: PresenceMonitor,
                reachability: ReachabilityChecking,
                rateLimitStore: RateLimitStore) {
        self.store = store
        self.presence = presence
        self.reachability = reachability
        self.rateLimitStore = rateLimitStore
    }

    public func computeDisplayState(now: TimeInterval) -> DisplayState {
        let sessions = store.loadLiveSessions(now: now)
        var aggregate = Aggregator.aggregate(sessions)
        aggregate = applyNetworkOverride(aggregate, networkDown: !reachability.isReachable())
        aggregate = applyRateLimitOverride(aggregate, rateLimit: rateLimitStore.read(now: now), now: now)
        return SignalResolver.resolve(aggregate, presence: presence.current())
    }
}

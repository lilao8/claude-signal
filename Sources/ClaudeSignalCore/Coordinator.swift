import Foundation

public struct Coordinator: Sendable {
    let store: StateStore
    let presence: PresenceMonitor
    let reachability: ReachabilityChecking
    let rateLimitStore: RateLimitStore
    let permissionThreshold: TimeInterval

    public init(store: StateStore,
                presence: PresenceMonitor,
                reachability: ReachabilityChecking,
                rateLimitStore: RateLimitStore,
                permissionThreshold: TimeInterval = PermissionDetection.defaultThreshold) {
        self.store = store
        self.presence = presence
        self.reachability = reachability
        self.rateLimitStore = rateLimitStore
        self.permissionThreshold = permissionThreshold
    }

    public func computeDisplayState(now: TimeInterval) -> DisplayState {
        var sessions = store.loadLiveSessions(now: now)
        // Promote sessions blocked on an inline permission prompt (stuck at PreToolUse) to
        // .permission so the light goes yellow even when Claude Code fires no Notification.
        sessions = PermissionDetection.promote(sessions, now: now, threshold: permissionThreshold)
        var aggregate = Aggregator.aggregate(sessions)
        aggregate = applyNetworkOverride(aggregate, networkDown: !reachability.isReachable())
        aggregate = applyRateLimitOverride(aggregate, rateLimit: rateLimitStore.read(now: now), now: now)
        return SignalResolver.resolve(aggregate, presence: presence.current())
    }
}

import Foundation

public struct Coordinator: Sendable {
    let store: StateStore
    let presence: PresenceMonitor
    let reachability: ReachabilityChecking
    let rateLimitStore: RateLimitStore
    let permissionThreshold: TimeInterval
    let idleThreshold: TimeInterval

    public init(store: StateStore,
                presence: PresenceMonitor,
                reachability: ReachabilityChecking,
                rateLimitStore: RateLimitStore,
                permissionThreshold: TimeInterval = PermissionDetection.defaultThreshold,
                idleThreshold: TimeInterval = IdleDetection.defaultThreshold) {
        self.store = store
        self.presence = presence
        self.reachability = reachability
        self.rateLimitStore = rateLimitStore
        self.permissionThreshold = permissionThreshold
        self.idleThreshold = idleThreshold
    }

    public func computeDisplayState(now: TimeInterval) -> DisplayState {
        let idle = presence.idleSeconds()   // sample once; drives both presence and "seen"
        var sessions = store.loadLiveSessions(now: now)
        // Promote sessions blocked on an inline permission prompt (stuck at PreToolUse) to
        // .permission so the light goes yellow even when Claude Code fires no Notification.
        sessions = PermissionDetection.promote(sessions, now: now, threshold: permissionThreshold)
        // Demote step-boundary sessions that went silent (no Stop fired) to .done so the
        // light turns off instead of staying stuck blue. Disjoint event set from above.
        sessions = IdleDetection.demote(sessions, now: now, threshold: idleThreshold)
        // A just-finished session flashes green even while you're present (checked before
        // dropSeen, which would hide it the moment you touch the keyboard).
        let freshDone = Acknowledgment.hasFreshDone(sessions, now: now)
        // Drop done/error sessions you've already seen (input since they finished).
        sessions = Acknowledgment.dropSeen(sessions, lastInputAt: now - idle)
        var aggregate = Aggregator.aggregate(sessions)
        aggregate = applyNetworkOverride(aggregate, networkDown: !reachability.isReachable())
        aggregate = applyRateLimitOverride(aggregate, rateLimit: rateLimitStore.read(now: now), now: now)
        let display = SignalResolver.resolve(aggregate, presence: presence.presence(forIdle: idle))
        return (display == .off && freshDone) ? .done : display
    }
}

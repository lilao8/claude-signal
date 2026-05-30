public protocol ReachabilityChecking: Sendable {
    func isReachable() -> Bool
}

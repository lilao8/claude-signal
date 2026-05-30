public enum Aggregator {
    /// Highest-priority state across all live sessions.
    /// Priority: error > permission > working > done > (none -> idle).
    public static func aggregate(_ sessions: [SessionState]) -> AggregateState {
        if sessions.isEmpty { return .idle }
        if sessions.contains(where: { $0.status == .error }) { return .error }
        if sessions.contains(where: { $0.status == .permission }) { return .permission }
        if sessions.contains(where: { $0.status == .working }) { return .working }
        return .done
    }
}

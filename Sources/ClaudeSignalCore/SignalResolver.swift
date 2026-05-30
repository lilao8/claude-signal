public enum SignalResolver {
    public static func resolve(_ aggregate: AggregateState, presence: Presence) -> DisplayState {
        switch aggregate {
        case .error:      return .error
        case .permission: return .permission
        case .working:    return .working
        case .done:       return presence == .away ? .done : .off
        case .idle:       return .off
        }
    }
}

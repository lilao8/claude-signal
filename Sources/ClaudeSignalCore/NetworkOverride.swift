/// Network-down only escalates to error while Claude is actively working.
/// (Conservative red, per spec §8.)
public func applyNetworkOverride(_ aggregate: AggregateState, networkDown: Bool) -> AggregateState {
    if networkDown && aggregate == .working { return .error }
    return aggregate
}

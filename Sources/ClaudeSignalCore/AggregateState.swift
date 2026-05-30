public enum AggregateState: Equatable, Sendable {
    case idle, done, working, permission, error
}

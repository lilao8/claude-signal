import Foundation

/// While an account-level usage limit is active (now < resetAt), force the light to error
/// (red). Symmetric with `applyNetworkOverride`. Expired or absent limits pass through.
public func applyRateLimitOverride(_ aggregate: AggregateState,
                                   rateLimit: RateLimitState?,
                                   now: TimeInterval) -> AggregateState {
    if let rl = rateLimit, now < rl.resetAt { return .error }
    return aggregate
}

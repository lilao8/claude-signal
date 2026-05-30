import Foundation
import CoreGraphics

public protocol IdleTimeProviding: Sendable {
    func idleSeconds() -> TimeInterval
}

/// Real provider: seconds since last keyboard/mouse/HID event.
public struct SystemIdleTimeProvider: IdleTimeProviding {
    public init() {}
    public func idleSeconds() -> TimeInterval {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .null)
    }
}

public struct PresenceMonitor: Sendable {
    public let threshold: TimeInterval
    public let provider: IdleTimeProviding

    public init(threshold: TimeInterval, provider: IdleTimeProviding) {
        self.threshold = threshold
        self.provider = provider
    }

    public func current() -> Presence {
        provider.idleSeconds() >= threshold ? .away : .present
    }
}

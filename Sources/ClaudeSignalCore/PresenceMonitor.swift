import Foundation
import CoreGraphics

public protocol IdleTimeProviding: Sendable {
    func idleSeconds() -> TimeInterval
}

/// Real provider: seconds since last keyboard/mouse/HID event.
public struct SystemIdleTimeProvider: IdleTimeProviding {
    public init() {}
    public func idleSeconds() -> TimeInterval {
        // kCGAnyInputEventType (~0) = seconds since ANY keyboard/mouse/HID input.
        // NOT .null (rawValue 0), which means "since last null-type event" — those
        // essentially never fire, so .null returns a huge constant and breaks presence.
        let anyInput = CGEventType(rawValue: ~0)!
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
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
        presence(forIdle: idleSeconds())
    }

    /// Seconds since the last keyboard/mouse input (sample once per tick and reuse).
    public func idleSeconds() -> TimeInterval {
        provider.idleSeconds()
    }

    public func presence(forIdle idle: TimeInterval) -> Presence {
        idle >= threshold ? .away : .present
    }
}

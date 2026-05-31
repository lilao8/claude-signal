import AppKit
import Foundation
import ClaudeSignalCore

/// Owns the surfaces + coordinator, polls state on a timer, renders to every surface.
@MainActor
final class AppController: NSObject, NSApplicationDelegate {
    private let surfaces: [any SignalSurface]
    private let coordinator: Coordinator
    private var pollTimer: Timer?

    override init() {
        let base = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude-signal/sessions")
        coordinator = Coordinator(
            store: StateStore(directory: base, staleThreshold: 300),
            presence: PresenceMonitor(threshold: 30, provider: SystemIdleTimeProvider()),
            reachability: SystemReachability(),
            rateLimitStore: RateLimitStore(fileURL: FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".claude-signal/ratelimit.json"))
        )
        // Menu bar (universal) + Touch Bar (no-ops gracefully if unavailable).
        surfaces = [MenuBarSurface(), TouchBarSurface()]
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Render the initial state immediately rather than waiting one full interval.
        tick()
        // pollTimer runs for the whole process lifetime and is intentionally never
        // invalidated; the OS reclaims it at exit. [weak self] keeps it a safe no-op
        // if the controller is ever torn down early.
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            // The timer fires on the main run loop, so we are already on the main actor.
            // assumeIsolated lets us call the @MainActor tick() without a Sendable crossing.
            MainActor.assumeIsolated {
                self?.tick()
            }
        }
    }

    private func tick() {
        let state = coordinator.computeDisplayState(now: Date().timeIntervalSince1970)
        for surface in surfaces {
            surface.render(state)
        }
    }
}

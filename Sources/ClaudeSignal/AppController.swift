import AppKit
import Foundation
import ClaudeSignalCore

/// Owns the surface + coordinator, polls state on a timer, renders.
@MainActor
final class AppController: NSObject, NSApplicationDelegate {
    private let surface = MenuBarSurface()
    private let coordinator: Coordinator
    private var pollTimer: Timer?

    override init() {
        let base = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude-signal/sessions")
        coordinator = Coordinator(
            store: StateStore(directory: base, staleThreshold: 300),
            presence: PresenceMonitor(threshold: 30, provider: SystemIdleTimeProvider()),
            reachability: SystemReachability()
        )
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        tick()
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
        surface.render(state)
    }
}

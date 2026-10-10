import AppKit
import QuartzCore
import ClaudeSignalCore

/// Drives a light's brightness with Core Animation on its layer's opacity, instead of each
/// surface redrawing at 30fps from a Timer (~5% CPU for a status light, plus the notch's
/// two blurred shadow passes every frame). Surfaces now draw once per state change at full
/// brightness; the breathe/flash curve runs on the render server. Timing and levels come
/// from `LightAnimation` so all surfaces stay in sync with the spec.
@MainActor
enum LightLayerAnimator {
    private static let key = "claude-signal.light"

    static func apply(_ state: DisplayState, to layer: CALayer?) {
        guard let layer else { return }
        layer.removeAnimation(forKey: key)
        guard let config = LightAnimation.config(for: state) else { return }   // steady

        let anim: CAAnimation
        if config.ease {
            // Breathe: dim → bright → dim over one period (sine-like ease, matches the
            // cosine in LightAnimation.alpha).
            let a = CABasicAnimation(keyPath: "opacity")
            a.fromValue = LightAnimation.breatheMin
            a.toValue = 1.0
            a.duration = config.period / 2
            a.autoreverses = true
            a.timingFunction = CAMediaTimingFunction(controlPoints: 0.37, 0, 0.63, 1)
            anim = a
        } else {
            // Flash: on for the first half of the period, low for the second.
            let a = CAKeyframeAnimation(keyPath: "opacity")
            a.values = [1.0, LightAnimation.flashLow]
            a.keyTimes = [0, 0.5, 1]
            a.calculationMode = .discrete
            a.duration = config.period
            anim = a
        }
        anim.repeatCount = .infinity
        anim.isRemovedOnCompletion = false
        layer.add(anim, forKey: key)
    }
}

import CoreGraphics

/// Inputs needed to locate the notch, captured from NSScreen at the call site so this
/// stays pure and unit-testable without real hardware.
public struct NotchInsetInput: Equatable, Sendable {
    public let screenFrame: CGRect
    public let safeAreaTop: CGFloat
    public let auxLeft: CGRect?
    public let auxRight: CGRect?

    public init(screenFrame: CGRect, safeAreaTop: CGFloat, auxLeft: CGRect?, auxRight: CGRect?) {
        self.screenFrame = screenFrame
        self.safeAreaTop = safeAreaTop
        self.auxLeft = auxLeft
        self.auxRight = auxRight
    }
}

/// Pure geometry: NSScreen notch insets -> the overlay-window frame that traces the
/// notch's bottom + left + right (no top — that's the physical screen edge).
/// Returns nil when there is no usable notch. AppKit coords (origin bottom-left).
public enum NotchGeometry {
    public static func outlineFrame(_ input: NotchInsetInput, margin: CGFloat = 2) -> CGRect? {
        guard input.safeAreaTop > 0,
              let auxLeft = input.auxLeft,
              let auxRight = input.auxRight else { return nil }

        let notchLeftX = auxLeft.maxX
        let notchRightX = auxRight.minX
        let notchWidth = notchRightX - notchLeftX
        guard notchWidth > 0 else { return nil }

        let topY = input.screenFrame.maxY
        return CGRect(
            x: notchLeftX - margin,
            y: topY - input.safeAreaTop - margin,
            width: notchWidth + 2 * margin,
            height: input.safeAreaTop + margin
        )
    }
}

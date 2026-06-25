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

/// Pure geometry: NSScreen notch insets -> the overlay-window frame for the U-shaped
/// light that hugs the notch's bottom edge. Returns nil when there is no usable notch.
/// AppKit coords (origin bottom-left).
///
/// The window's TOP runs flush with the screen top, so the bracket's two arms span the
/// whole notch band (those pixels sit behind the physical camera housing — hidden, fine).
/// Its BOTTOM extends `depth` pt past the notch's bottom edge into the visible content
/// area. The visible part of the bracket therefore emerges right at the physical occlusion
/// edge and hugs the notch as tightly as the hardware allows — important because the camera
/// housing + bezel + viewing angle occlude noticeably more than the logical `safeAreaTop`.
/// `depth` tunes how far the visible curve drops below the notch.
///
/// (The earliest version placed the frame ENTIRELY within the notch band with no depth —
/// so the whole outline was behind the camera housing and invisible on real hardware, even
/// though it showed up in screenshots of the logical framebuffer.)
public enum NotchGeometry {
    public static func outlineFrame(_ input: NotchInsetInput,
                                    margin: CGFloat = 12,
                                    depth: CGFloat = 11) -> CGRect? {
        guard input.safeAreaTop > 0,
              let auxLeft = input.auxLeft,
              let auxRight = input.auxRight else { return nil }

        let notchLeftX = auxLeft.maxX
        let notchRightX = auxRight.minX
        let notchWidth = notchRightX - notchLeftX
        guard notchWidth > 0 else { return nil }

        let notchBottomY = input.screenFrame.maxY - input.safeAreaTop
        return CGRect(
            x: notchLeftX - margin,
            y: notchBottomY - depth,
            width: notchWidth + 2 * margin,
            height: input.safeAreaTop + depth
        )
    }
}

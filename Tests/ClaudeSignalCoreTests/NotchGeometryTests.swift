import XCTest
import CoreGraphics
@testable import ClaudeSignalCore

final class NotchGeometryTests: XCTestCase {
    // Realistic-ish 16" MacBook Pro: 1728×1117 points, notch ~32pt tall, ~200pt wide centered.
    private func sixteenInch() -> NotchInsetInput {
        let screen = CGRect(x: 0, y: 0, width: 1728, height: 1117)
        let notchWidth: CGFloat = 200
        let notchLeftX = (1728 - notchWidth) / 2      // 764
        let notchRightX = notchLeftX + notchWidth     // 964
        let menuTop: CGFloat = 1117 - 32
        let auxLeft = CGRect(x: 0, y: menuTop, width: notchLeftX, height: 32)
        let auxRight = CGRect(x: notchRightX, y: menuTop, width: 1728 - notchRightX, height: 32)
        return NotchInsetInput(screenFrame: screen, safeAreaTop: 32, auxLeft: auxLeft, auxRight: auxRight)
    }

    func testNoNotchWhenSafeAreaZero() {
        let input = NotchInsetInput(screenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
                                    safeAreaTop: 0, auxLeft: nil, auxRight: nil)
        XCTAssertNil(NotchGeometry.outlineFrame(input))
    }

    func testNoNotchWhenAuxMissing() {
        let input = NotchInsetInput(screenFrame: CGRect(x: 0, y: 0, width: 1728, height: 1117),
                                    safeAreaTop: 32, auxLeft: nil, auxRight: nil)
        XCTAssertNil(NotchGeometry.outlineFrame(input))
    }

    func testOutlineFrameForSixteenInch() {
        // notchBottomY = 1117 - 32 = 1085; margin 2, depth 20.
        let frame = NotchGeometry.outlineFrame(sixteenInch(), margin: 2, depth: 20)
        let f = try! XCTUnwrap(frame)
        XCTAssertEqual(f.minX, 762, accuracy: 0.001)    // 764 - 2
        XCTAssertEqual(f.width, 204, accuracy: 0.001)   // 200 + 4
        XCTAssertEqual(f.minY, 1065, accuracy: 0.001)   // 1085 - 20
        XCTAssertEqual(f.height, 52, accuracy: 0.001)   // safeAreaTop 32 + depth 20
        // Arms run flush with the screen top; bottom drops `depth` below the notch.
        XCTAssertEqual(f.maxY, 1117, accuracy: 0.001)   // flush with screen top
    }

    func testDegenerateWidthReturnsNil() {
        let screen = CGRect(x: 0, y: 0, width: 1728, height: 1117)
        let auxLeft = CGRect(x: 0, y: 1085, width: 900, height: 32)    // maxX 900
        let auxRight = CGRect(x: 850, y: 1085, width: 878, height: 32)  // minX 850 < 900
        let input = NotchInsetInput(screenFrame: screen, safeAreaTop: 32, auxLeft: auxLeft, auxRight: auxRight)
        XCTAssertNil(NotchGeometry.outlineFrame(input))
    }

    func testMarginZero() {
        let frame = NotchGeometry.outlineFrame(sixteenInch(), margin: 0, depth: 20)
        let f = try! XCTUnwrap(frame)
        XCTAssertEqual(f.minX, 764, accuracy: 0.001)
        XCTAssertEqual(f.width, 200, accuracy: 0.001)
        XCTAssertEqual(f.minY, 1065, accuracy: 0.001)  // 1085 - 20
        XCTAssertEqual(f.height, 52, accuracy: 0.001)  // 32 + 20
    }
}

import XCTest
@testable import ClaudeSignalCore

final class LightAnimationTests: XCTestCase {
    func testKindForEachState() {
        XCTAssertEqual(LightAnimation.kind(for: .off), .steady)
        XCTAssertEqual(LightAnimation.kind(for: .done), .steady)
        XCTAssertEqual(LightAnimation.kind(for: .working), .breathe)
        XCTAssertEqual(LightAnimation.kind(for: .permission), .flash)
        XCTAssertEqual(LightAnimation.kind(for: .error), .flash)
    }

    func testPeriodForEachState() {
        XCTAssertNil(LightAnimation.period(for: .off))
        XCTAssertNil(LightAnimation.period(for: .done))
        XCTAssertEqual(LightAnimation.period(for: .working), 1.8)
        XCTAssertEqual(LightAnimation.period(for: .permission), 1.0)
        XCTAssertEqual(LightAnimation.period(for: .error), 0.6)
    }

    func testBreatheAlphaDimAtStartBrightAtHalf() {
        XCTAssertEqual(LightAnimation.alpha(elapsed: 0.0, period: 1.8, ease: true), 0.35, accuracy: 0.0001)
        XCTAssertEqual(LightAnimation.alpha(elapsed: 0.9, period: 1.8, ease: true), 1.0, accuracy: 0.0001)
        XCTAssertEqual(LightAnimation.alpha(elapsed: 1.8, period: 1.8, ease: true), 0.35, accuracy: 0.0001)
    }

    func testFlashAlphaOnFirstHalfOffSecondHalf() {
        XCTAssertEqual(LightAnimation.alpha(elapsed: 0.0, period: 1.0, ease: false), 1.0, accuracy: 0.0001)
        XCTAssertEqual(LightAnimation.alpha(elapsed: 0.25, period: 1.0, ease: false), 1.0, accuracy: 0.0001)
        XCTAssertEqual(LightAnimation.alpha(elapsed: 0.5, period: 1.0, ease: false), 0.15, accuracy: 0.0001)
        XCTAssertEqual(LightAnimation.alpha(elapsed: 0.75, period: 1.0, ease: false), 0.15, accuracy: 0.0001)
    }
}

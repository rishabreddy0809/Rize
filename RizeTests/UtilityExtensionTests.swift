import XCTest
import SwiftUI
@testable import Rize

final class UtilityExtensionTests: XCTestCase {

    // MARK: - Color(hex:)

    private func components(_ color: Color) -> (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        return (r, g, b, a)
    }

    func testSixDigitHexParsesRGBWithFullAlpha() {
        let c = components(Color(hex: "FF0000"))
        XCTAssertEqual(c.r, 1.0, accuracy: 0.01)
        XCTAssertEqual(c.g, 0.0, accuracy: 0.01)
        XCTAssertEqual(c.b, 0.0, accuracy: 0.01)
        XCTAssertEqual(c.a, 1.0, accuracy: 0.01)
    }

    func testThreeDigitHexExpandsEachNibble() {
        // "F00" should read the same as "FF0000".
        let short = components(Color(hex: "F00"))
        let long = components(Color(hex: "FF0000"))
        XCTAssertEqual(short.r, long.r, accuracy: 0.01)
        XCTAssertEqual(short.g, long.g, accuracy: 0.01)
        XCTAssertEqual(short.b, long.b, accuracy: 0.01)
    }

    func testEightDigitHexIncludesAlpha() {
        let c = components(Color(hex: "80FF0000")) // ~50% alpha red
        XCTAssertEqual(c.a, 0x80 / 255.0, accuracy: 0.01)
        XCTAssertEqual(c.r, 1.0, accuracy: 0.01)
    }

    func testHexStringToleratesLeadingHash() {
        let withHash = components(Color(hex: "#0A84FF"))
        let withoutHash = components(Color(hex: "0A84FF"))
        XCTAssertEqual(withHash.r, withoutHash.r, accuracy: 0.01)
        XCTAssertEqual(withHash.g, withoutHash.g, accuracy: 0.01)
        XCTAssertEqual(withHash.b, withoutHash.b, accuracy: 0.01)
    }

    // MARK: - Color.darker / .lighter

    func testDarkerMovesTowardBlack() {
        let base = components(Color(hex: "FF0000"))
        let darkened = components(Color(hex: "FF0000").darker(0.5))
        XCTAssertLessThan(darkened.r, base.r)
    }

    func testLighterMovesTowardWhite() {
        let base = components(Color(hex: "FF0000"))
        let lightened = components(Color(hex: "FF0000").lighter(0.5))
        XCTAssertGreaterThan(lightened.g, base.g, "blending red toward white should raise the green channel")
    }

    // MARK: - Collection safe subscript

    func testSafeSubscriptReturnsElementInBounds() {
        let array = ["a", "b", "c"]
        XCTAssertEqual(array[safe: 1], "b")
    }

    func testSafeSubscriptReturnsNilOutOfBounds() {
        let array = ["a", "b", "c"]
        XCTAssertNil(array[safe: 3])
        XCTAssertNil(array[safe: -1])
    }

    func testSafeSubscriptOnEmptyArrayIsNil() {
        let array: [Int] = []
        XCTAssertNil(array[safe: 0])
    }
}

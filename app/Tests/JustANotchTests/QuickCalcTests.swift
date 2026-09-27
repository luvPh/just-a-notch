import XCTest
@testable import JustANotch

final class QuickCalcTests: XCTestCase {
    let rates: [String: Double] = ["USD": 1, "VND": 26_000, "EUR": 0.9, "JPY": 150]

    private func value(_ s: String, rates r: [String: Double]? = nil) -> QuickCalc.Value? {
        try? QuickCalc.evaluate(s, rates: r ?? rates).get().value
    }
    private func amount(_ s: String) -> Double? { value(s)?.amount }

    // MARK: Numbers

    func testVietnameseThousands() {
        XCTAssertEqual(QuickCalc.parseNumber("1.000.000"), 1_000_000)
        XCTAssertEqual(QuickCalc.parseNumber("1,000,000"), 1_000_000)
        XCTAssertEqual(QuickCalc.parseNumber("1.500"), 1_500)
        XCTAssertEqual(QuickCalc.parseNumber("1.234.567,89"), 1_234_567.89, accuracy: 1e-6)
        XCTAssertEqual(QuickCalc.parseNumber("1,234,567.89"), 1_234_567.89, accuracy: 1e-6)
    }

    func testDecimals() {
        XCTAssertEqual(QuickCalc.parseNumber("2,5"), 2.5)
        XCTAssertEqual(QuickCalc.parseNumber("3.14"), 3.14)
        XCTAssertEqual(QuickCalc.parseNumber("0.125"), 0.125)
    }

    // MARK: Arithmetic

    func testPrecedence() {
        XCTAssertEqual(amount("2+3*4"), 14)
        XCTAssertEqual(amount("(2+3)*4"), 20)
        XCTAssertEqual(amount("2^3^2"), 512)
        XCTAssertEqual(amount("-3+5"), 2)
        XCTAssertEqual(amount("10/4"), 2.5)
        XCTAssertEqual(amount("3x4"), 12)
        XCTAssertEqual(amount("3 × 4 ÷ 2"), 6)
        XCTAssertEqual(amount("50%"), 0.5)
        XCTAssertEqual(amount("200 * 10%"), 20)
    }

    func testSuffixes() {
        XCTAssertEqual(amount("150k"), 150_000)
        XCTAssertEqual(amount("2.5tr"), 2_500_000)
        XCTAssertEqual(amount("2tr5"), 2_500_000)
        XCTAssertEqual(amount("1ty"), 1_000_000_000)
        XCTAssertEqual(amount("150k * 3"), 450_000)
    }

    func testTrailingEqualsIsIgnored() {
        XCTAssertEqual(amount("2+2="), 4)
    }

    func testIncompleteInputFailsWithoutCrashing() {
        XCTAssertThrowsError(try QuickCalc.evaluate("2+", rates: rates).get())
        XCTAssertThrowsError(try QuickCalc.evaluate("(2+3", rates: rates).get())
        XCTAssertThrowsError(try QuickCalc.evaluate("abc", rates: rates).get())
        XCTAssertEqual(try? QuickCalc.evaluate("", rates: rates).get(), nil)
    }

    func testDivideByZero() {
        guard case .failure(.divideByZero) = QuickCalc.evaluate("5/0", rates: rates) else {
            return XCTFail("expected divideByZero")
        }
    }

    // MARK: Currency

    func testForeignDefaultsToVND() {
        let v = value("100usd")
        XCTAssertEqual(v?.currency, "VND")
        XCTAssertEqual(v?.amount, 2_600_000)
    }

    func testVNDDefaultsToUSD() {
        let v = value("5tr đ")
        XCTAssertEqual(v?.currency, "USD")
        XCTAssertEqual(v!.amount, 5_000_000 / 26_000, accuracy: 1e-9)
    }

    func testExplicitTarget() {
        let v = value("100 usd to eur")
        XCTAssertEqual(v?.currency, "EUR")
        XCTAssertEqual(v!.amount, 90, accuracy: 1e-9)
        XCTAssertEqual(value("5tr vnd sang usd")?.currency, "USD")
        XCTAssertEqual(value("$20 -> vnd")?.amount, 520_000)
    }

    func testSymbols() {
        XCTAssertEqual(value("$100")?.amount, 2_600_000)
        XCTAssertEqual(value("€9")?.amount, 260_000)
    }

    func testMixedCurrencyAddition() {
        // 1 USD + 26.000 ₫ = 2 USD → 52.000 ₫
        XCTAssertEqual(value("1usd + 26000vnd")?.amount, 52_000)
    }

    func testUnknownCurrency() {
        guard case .failure(.unknownCurrency("XYZ")) = QuickCalc.evaluate("10xyz", rates: rates) else {
            return XCTFail("expected unknownCurrency")
        }
    }

    func testNoRates() {
        guard case .failure(.noRates) = QuickCalc.evaluate("10usd", rates: nil) else {
            return XCTFail("expected noRates")
        }
        XCTAssertEqual(try? QuickCalc.evaluate("1+1", rates: nil).get().value.amount, 2)
    }

    // MARK: Formatting

    func testFormat() {
        XCTAssertEqual(QuickCalc.format(.init(amount: 2_634_000, currency: "VND")), "2.634.000 ₫")
        XCTAssertEqual(QuickCalc.format(.init(amount: 1234.5, currency: "USD")), "1.234,5 USD")
        XCTAssertEqual(QuickCalc.format(.init(amount: 0.1 + 0.2, currency: nil)), "0,3")
        XCTAssertEqual(QuickCalc.copyString(.init(amount: 2_634_000.4, currency: "VND")), "2.634.000")
    }
}

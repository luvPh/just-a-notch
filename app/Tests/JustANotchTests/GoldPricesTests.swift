import XCTest
@testable import JustANotch

final class GoldPricesTests: XCTestCase {
    func testParseBTMHPicksWantedCodesAndHandlesNoSell() {
        let json = #"""
        {"data":{"goldRates":{"items":[
          {"code":"NL9999","name":"Vàng nguyên liệu","buy_price":13600000,"sell_price":1,"trend_value":"0","last_updated":"2026-09-26 17:21:25.0"},
          {"code":"SJC9999","name":"Vàng miếng SJC","buy_price":14140000,"sell_price":1,"trend_value":"0","last_updated":"2026-09-24 10:37:36.0"},
          {"code":"KGB","name":"Kim Gia Bảo 24K","buy_price":14140000,"sell_price":14540000,"trend_value":"-10.000","last_updated":"2026-09-26 16:55:15.0"}
        ]}}}
        """#
        let items = GoldPrices.parseBTMH(Data(json.utf8))!
        XCTAssertEqual(items.map(\.code), ["KGB", "SJC9999"])   // theo thứ tự hiển thị
        XCTAssertEqual(items[0].sell, 14_540_000)
        XCTAssertEqual(items[0].trend, -10_000)
        XCTAssertNotNil(items[0].at)
        XCTAssertNil(items[1].sell)       // sell_price = 1 → không bán ra
        XCTAssertNil(items[1].trend)
    }

    func testParseGoldAPI() {
        XCTAssertEqual(GoldPrices.parseGoldAPI(Data(#"{"currency":"USD","price":4286.2,"symbol":"XAU"}"#.utf8)), 4286.2)
    }

    func testParseYahoo() {
        let json = #"{"chart":{"result":[{"meta":{"regularMarketPrice":4300.5,"chartPreviousClose":4250.0}}]}}"#
        let r = GoldPrices.parseYahoo(Data(json.utf8))!
        XCTAssertEqual(r.price, 4300.5)
        XCTAssertEqual(r.prevClose, 4250.0)
        XCTAssertNil(GoldPrices.parseYahoo(Data(#"{"chart":{"result":null}}"#.utf8)))
    }
}

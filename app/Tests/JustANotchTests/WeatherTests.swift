import XCTest
@testable import JustANotch

final class WeatherTests: XCTestCase {
    func testWMOMapping() {
        XCTAssertEqual(WeatherKind.from(wmo: 0), .clear)
        XCTAssertEqual(WeatherKind.from(wmo: 2), .partly)
        XCTAssertEqual(WeatherKind.from(wmo: 63), .rain)
        XCTAssertEqual(WeatherKind.from(wmo: 81), .rain)
        XCTAssertEqual(WeatherKind.from(wmo: 95), .thunder)
        XCTAssertEqual(WeatherKind.from(wmo: 73), .snow)
    }

    func testParseForecast() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let json = """
        {"current":{"temperature_2m":28.4,"apparent_temperature":31.2,"weather_code":61,"is_day":1},
         "hourly":{"time":[996400,1000000,1003600,1007200],"temperature_2m":[27,28,29,30],
                   "weather_code":[0,61,3,95],"is_day":[1,1,1,0]},
         "daily":{"temperature_2m_max":[32.1],"temperature_2m_min":[24.6],"precipitation_probability_max":[80]}}
        """
        let w = WeatherParser.forecast(Data(json.utf8), city: "Hà Nội", now: now)
        XCTAssertEqual(w?.kind, .rain)
        XCTAssertEqual(w?.hi, 32.1)
        XCTAssertEqual(w?.rainChance, 80)
        XCTAssertEqual(w?.hourly.count, 3)          // bỏ giờ đã qua quá 30′
        XCTAssertEqual(w?.hourly.last?.kind, .thunder)
    }
}

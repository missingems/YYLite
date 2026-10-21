import XCTest
import Foundation
import Codable50
import Models50
import Compare50

final class Bench50Tests: XCTestCase {
    func testDecodeEqualsFoundation() throws {
        let data = try Fixture.load("models50.json")
        XCTAssertEqual(diff50(try Foundation50.decode(data), try Root50(data: data)), [])
    }
    func testRoundTripAndCrossCheck() throws {
        let data = try Fixture.load("models50.json")
        let s = try Foundation50.decode(data)
        let c = try Root50(data: data)
        let enc = try c.jsonData()
        XCTAssertEqual(diff50(s, try Root50(data: enc)), [])                       // decode → encode → decode
        XCTAssertEqual(diff50(try Foundation50.decode(enc), c), [])                // Foundation reads our output
        XCTAssertEqual(diff50(s, try Root50(data: try Foundation50.encode(s))), []) // we read Foundation's output
        let pretty = try c.jsonData(pretty: true)
        XCTAssertEqual(diff50(s, try Root50(data: pretty)), [])
        XCTAssertNoThrow(try JSONSerialization.jsonObject(with: pretty))
    }
    func testMeasureDecode() throws {
        let data = try Fixture.load("models50.json")
        measure { _ = try? Root50(data: data) }
    }
    func testMeasureEncode() throws {
        let c = try Root50(data: try Fixture.load("models50.json"))
        measure { _ = try? c.jsonData() }
    }
}

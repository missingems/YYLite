import XCTest
import Codable50
import Models50S
import Compare50   // Fixture
import Compare50S

/// The `--kind struct` variant: equal to Foundation field by field, round-trips, reads Foundation's output.
final class StructVariantTests: XCTestCase {
    func testStructsEqualFoundationAndRoundTrip() throws {
        let data = try Fixture.load("models50.json")
        let s = try Foundation50.decode(data)
        let t = try Root50(data: data)
        XCTAssertEqual(diffS50(s, t), [])
        let enc = try t.jsonData()
        XCTAssertEqual(diffS50(s, try Root50(data: enc)), [])
        XCTAssertEqual(diffS50(s, try Root50(data: try Foundation50.encode(s))), [])
        XCTAssertEqual(diffS50(try Foundation50.decode(enc), t), [])
    }
}

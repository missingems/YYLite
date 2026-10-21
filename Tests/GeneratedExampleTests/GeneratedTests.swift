import XCTest
import Foundation
import YYLite

final class GeneratedTests: XCTestCase {
    func testGeneratedRoundTrip() throws {
        let src = #"{"id":1,"name":"Bolt","mana_cost":"{R}","cmc":1,"colors":["R"],"set":{"code":"LEA","name":"Alpha"},"printings":[{"year":1993}],"default":true}"#
        let c = try Card(data: Data(src.utf8))
        XCTAssertEqual(c.printings[0].foil, false); XCTAssertNil(c.altSet); XCTAssertNil(c.reprints); XCTAssertEqual(c.default, true)
        let out = String(decoding: try c.jsonData(), as: UTF8.self)
        XCTAssertEqual(out, #"{"id":1,"name":"Bolt","mana_cost":"{R}","cmc":1.0,"colors":["R"],"set":{"code":"LEA","name":"Alpha"},"printings":[{"year":1993,"foil":false}],"default":true}"#)
        XCTAssertEqual(String(decoding: try Card(data: Data(out.utf8)).jsonData(), as: UTF8.self), out)
        XCTAssertThrowsError(try Card(data: Data(#"{"id":1}"#.utf8))) { XCTAssertEqual(($0 as? JSONError)?.path, "$.name") }
    }
}

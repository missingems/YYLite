import XCTest
import YYLite
import Foundation

extension SetInfo { func encode(_ w: JSONWriter) { w.object { w.string("code", code); w.string("name", name) } } }
extension Printing { func encode(_ w: JSONWriter) { w.object { w.int("year", year); w.bool("foil", foil) } } }
extension Card {
    func encode(_ w: JSONWriter) {
        w.object {
            w.int("id", id); w.string("name", name); w.optionalString("mana_cost", manaCost); w.double("cmc", cmc)
            w.strings("colors", colors); w.key("set"); set.encode(w)
            w.array("printings") { for p in printings { p.encode(w) } }
            w.optionalInt("power", power)
        }
    }
}

final class EncodeTests: XCTestCase {
    func str(_ pretty: Bool = false, nil n: JSONWriter.NilStrategy = .omit, _ body: (JSONWriter) -> Void) throws -> String {
        String(decoding: try JSONWriter.encode(pretty: pretty, nilStrategy: n, body), as: UTF8.self)
    }

    func testModelRoundTrip() throws {
        let c = try Card(JSON.parse(cardJSON))
        let out = try str { c.encode($0) }
        XCTAssertEqual(out, #"{"id":7,"name":"Æther Ōni ✓","cmc":3.0,"colors":["U","R"],"set":{"code":"NEO","name":"Kamigawa"},"printings":[{"year":2022,"foil":true},{"year":2023,"foil":false}]}"#)
        let c2 = try Card(JSON.parse(out))
        XCTAssertEqual(try str { c2.encode($0) }, out)
        XCTAssertEqual(try str(nil: .null) { c.encode($0) }.contains(#""mana_cost":null"#), true)
        XCTAssertEqual(try str(nil: .null) { c.encode($0) }.contains(#""power":null"#), true)
    }

    func testPrettyIsValidAndSame() throws {
        let c = try Card(JSON.parse(cardJSON))
        let p = try str(true) { c.encode($0) }
        XCTAssertTrue(p.contains("\n  \"id\": 7,\n"))
        XCTAssertTrue(p.hasSuffix("\n}"))
        let compact = try str { c.encode($0) }
        XCTAssertEqual(try str { try! Card(JSON.parse(p)).encode($0) }, compact)
        XCTAssertEqual(try str(true) { w in w.object { w.array("e") {}; w.object("o") {} } }, "{\n  \"e\": [],\n  \"o\": {}\n}")
        // Foundation must accept it
        XCTAssertNoThrow(try JSONSerialization.jsonObject(with: Data(p.utf8)))
    }

    func testEscaping() throws {
        let nasty = "q\"b\\s/ \u{0}\u{1}\u{8}\u{9}\u{A}\u{C}\u{D}\u{1F}\u{7F} é 東京 😀 \u{2028}"
        let out = try str { w in w.array { w.string(nasty) } }
        XCTAssertEqual(out, #"["q\"b\\s/ \u0000\u0001\b\t\n\f\r\u001f"# + "\u{7F} é 東京 😀 \u{2028}\"]")
        XCTAssertEqual(try JSON.parse(out)[0]!.string(), nasty)
        let f = try JSONSerialization.jsonObject(with: Data(out.utf8)) as! [String]
        XCTAssertEqual(f[0], nasty)
        // keys are escaped too
        XCTAssertEqual(try str { w in w.object { w.key("a\"b"); w.int(1) } }, #"{"a\"b":1}"#)
        XCTAssertEqual(try str { w in w.array { w.string("") } }, #"[""]"#)
    }

    func testNumbers() throws {
        let ints = [Int.min, Int.max, 0, -1, 1, 9, 10, 99, 100, -1_000_000_007]
        let out = try str { w in w.object { w.ints("i", ints); w.uint("u", UInt.max); w.int64("i64", Int64.min) } }
        let j = try JSON.parse(out)
        XCTAssertEqual(try j.ints("i"), ints); XCTAssertEqual(try j.uint("u"), UInt.max); XCTAssertEqual(try j.int64("i64"), Int64.min)
        XCTAssertTrue(out.contains("18446744073709551615") && out.contains("-9223372036854775808"))

        let ds: [Double] = [0, -0.0, 0.1, 1e308, 5e-324, 2.2250738585072014e-308, 1.7976931348623157e308, -1.5,
                            123456789.123456789, 1e-7, 1e21, 0.3, 2.0 / 3.0, 9007199254740993, 100]
        let dout = try str { w in w.doubles("d", ds) ; } // keyed outside object is allowed syntactically
        _ = dout
        let arr = try str { w in w.array { for d in ds { w.double(d) } } }
        let back = try JSON.parse(arr).elements().map { try $0.double() }
        XCTAssertEqual(back.map(\.bitPattern), ds.map(\.bitPattern), arr)           // exact, incl. -0.0
        let fb = (try JSONSerialization.jsonObject(with: Data(arr.utf8)) as! [NSNumber]).map(\.doubleValue)
        XCTAssertEqual(fb.dropFirst(2).map(\.bitPattern), ds.dropFirst(2).map(\.bitPattern))  // Foundation agrees
        let floats: [Float] = [0.1, 3.4028235e38, 1e-45, -2.5]
        let fo = try str { w in w.array { for f in floats { w.float(f) } } }
        XCTAssertEqual(try JSON.parse(fo).elements().map { try $0.float() }, floats)
    }

    func testNonFinite() throws {
        XCTAssertThrowsError(try JSONWriter.encode { w in w.object { w.double("x", .nan) } }) { e in
            XCTAssertEqual((e as? JSONError)?.found, "NaN"); XCTAssertEqual((e as? JSONError)?.path, "$….x")
        }
        XCTAssertThrowsError(try JSONWriter.encode { w in w.array { w.double(.infinity) } })
        XCTAssertThrowsError(try JSONWriter.encode { w in w.array { w.float(-.infinity) } })
        let d = try JSONWriter.encode(nonFinite: .null) { w in w.array { w.double(.nan); w.double(-.infinity) } }
        XCTAssertEqual(String(decoding: d, as: UTF8.self), "[null,null]")
    }

    func testStructureAndGrowth() throws {
        let out = try str { w in
            w.array {
                w.null(); w.bool(true); w.int(1); w.object {}; w.array {}
                w.object { w.null("n"); w.object("o") { w.array("a") { w.int(1); w.int(2) } }; w.key("k"); w.string("v") }
            }
        }
        XCTAssertEqual(out, #"[null,true,1,{},[],{"n":null,"o":{"a":[1,2]},"k":"v"}]"#)
        let big = String(repeating: "x\"", count: 100_000)
        let b = try str { w in w.array { for _ in 0..<5 { w.string(big) } } }
        XCTAssertEqual(try JSON.parse(b).elements().map { try $0.string() }, Array(repeating: big, count: 5))
    }
}

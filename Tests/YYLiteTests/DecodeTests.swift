import XCTest
import YYLite
#if canImport(FoundationEssentials)
import FoundationEssentials
#endif
import Foundation

final class SetInfo {
    let code: String; let name: String
    init(_ j: JSON) throws { code = try j.string("code"); name = try j.string("name") }
}
final class Printing {
    let year: Int; let foil: Bool
    init(_ j: JSON) throws { year = try j.int("year"); foil = try j.bool("foil", default: false) }
}
final class Card {
    let id: Int; let name: String; let manaCost: String?; let cmc: Double; let colors: [String]
    let set: SetInfo; let printings: [Printing]; let power: Int?
    init(_ j: JSON) throws {
        id = try j.int("id"); name = try j.string("name"); manaCost = try j.optionalString("mana_cost")
        cmc = try j.double("cmc"); colors = try j.strings("colors"); set = try SetInfo(j.object("set"))
        printings = try j.objects("printings").map(Printing.init); power = try j.optionalInt("power")
    }
}

let cardJSON = """
{"id":7,"name":"Æther Ōni ✓","mana_cost":null,"cmc":3,"colors":["U","R"],"set":{"code":"NEO","name":"Kamigawa"},
 "printings":[{"year":2022,"foil":true},{"year":2023}],"extra":{"a":[1,2,{"b":null}]}}
"""

func expectError(_ s: String, _ path: String, _ expected: String, _ found: String,
                 file: StaticString = #filePath, line: UInt = #line, _ body: (JSON) throws -> Void) {
    do {
        try body(JSON.parse(s))
        XCTFail("no error", file: file, line: line)
    } catch let e as JSONError {
        XCTAssertEqual(e.path, path, "\(e)", file: file, line: line)
        XCTAssertEqual(e.expected, expected, "\(e)", file: file, line: line)
        XCTAssertEqual(e.found, found, "\(e)", file: file, line: line)
    } catch { XCTFail("\(error)", file: file, line: line) }
}

final class DecodeTests: XCTestCase {
    func testModel() throws {
        let c = try Card(JSON.parse(cardJSON))
        XCTAssertEqual(c.id, 7); XCTAssertEqual(c.name, "Æther Ōni ✓"); XCTAssertNil(c.manaCost)
        XCTAssertEqual(c.cmc, 3.0); XCTAssertEqual(c.colors, ["U", "R"]); XCTAssertEqual(c.set.code, "NEO")
        XCTAssertEqual(c.printings.map(\.year), [2022, 2023]); XCTAssertEqual(c.printings.map(\.foil), [true, false])
        XCTAssertNil(c.power)
    }

    func testAllScalarGetters() throws {
        let j = try JSON.parse(#"{"i":-5,"big":18446744073709551615,"d":1.5,"f":0.25,"b":true,"s":"x","n":null,"a":"single-letter"}"#)
        XCTAssertEqual(try j.int("i"), -5); XCTAssertEqual(try j.int64("i"), -5)
        XCTAssertEqual(try j.uint("big"), UInt.max); XCTAssertEqual(try j.double("d"), 1.5)
        XCTAssertEqual(try j.float("f"), 0.25); XCTAssertEqual(try j.bool("b"), true); XCTAssertEqual(try j.string("s"), "x")
        XCTAssertEqual(try j.double("i"), -5.0)                         // ints accepted as double
        XCTAssertEqual(try j.string("a"), "single-letter")               // 1-char StaticString key
        // optional + default
        XCTAssertNil(try j.optionalInt("n")); XCTAssertNil(try j.optionalInt("missing"))
        XCTAssertEqual(try j.optionalInt("i"), -5)
        XCTAssertEqual(try j.int("n", default: 9), 9); XCTAssertEqual(try j.int("missing", default: 9), 9)
        XCTAssertEqual(try j.string("missing", default: "d"), "d"); XCTAssertEqual(try j.bool("missing", default: true), true)
        XCTAssertEqual(try j.double("missing", default: 2), 2); XCTAssertEqual(try j.uint("missing", default: 3), 3)
        XCTAssertEqual(try j.float("missing", default: 1), 1); XCTAssertEqual(try j.int64("missing", default: 4), 4)
        XCTAssertNil(try j.optionalString("n")); XCTAssertNil(try j.optionalBool("n")); XCTAssertNil(try j.optionalDouble("n"))
        XCTAssertNil(try j.optionalFloat("n")); XCTAssertNil(try j.optionalUInt("n")); XCTAssertNil(try j.optionalInt64("n"))
        XCTAssertNil(try j.optionalObject("n")); XCTAssertNil(try j.optionalObjects("n")); XCTAssertNil(try j.optionalStrings("n"))
        // value-level
        XCTAssertEqual(try j["i"]!.int(), -5); XCTAssertEqual(try j["s"]!.string(), "x")
        XCTAssertEqual(try j["b"]!.bool(), true); XCTAssertEqual(try j["d"]!.double(), 1.5)
        XCTAssertEqual(try j["f"]!.float(), 0.25); XCTAssertEqual(try j["big"]!.uint(), UInt.max); XCTAssertEqual(try j["i"]!.int64(), -5)
    }

    func testArrays() throws {
        let j = try JSON.parse(#"{"s":["a","b"],"i":[1,-2],"d":[1,2.5],"b":[true,false],"o":[{"x":1},{"x":2}],"e":[]}"#)
        XCTAssertEqual(try j.strings("s"), ["a", "b"]); XCTAssertEqual(try j.ints("i"), [1, -2])
        XCTAssertEqual(try j.doubles("d"), [1, 2.5]); XCTAssertEqual(try j.bools("b"), [true, false])
        XCTAssertEqual(try j.objects("o").map { try $0.int("x") }, [1, 2]); XCTAssertEqual(try j.objects("e").count, 0)
        var xs: [Int] = []
        try j.forEachObject("o") { xs.append(try $0.int("x")) }
        XCTAssertEqual(xs, [1, 2])
        XCTAssertEqual(try j.optionalInts("i"), [1, -2]); XCTAssertNil(try j.optionalDoubles("zz")); XCTAssertNil(try j.optionalBools("zz"))
        XCTAssertEqual(try j["o"]!.elements().count, 2)
    }

    func testRawAccess() throws {
        let j = try JSON.parse(cardJSON)
        XCTAssertEqual(j.type, .object); XCTAssertTrue(j.contains("extra")); XCTAssertFalse(j.contains("nope"))
        XCTAssertEqual(j.keys, ["id", "name", "mana_cost", "cmc", "colors", "set", "printings", "extra"])
        XCTAssertTrue(j["mana_cost"]!.isNull); XCTAssertEqual(j["colors"]!.count, 2); XCTAssertEqual(j.count, 8)
        XCTAssertEqual(try j["colors"]?[1]?.string(), "R"); XCTAssertNil(j["colors"]?[2]); XCTAssertNil(j["colors"]?[-1])
        var n = 0; j.forEachMember { _, _ in n += 1 }; XCTAssertEqual(n, 8)
        var types: [JSONType] = []; j["extra"]!["a"]!.forEachElement { types.append($0.type) }
        XCTAssertEqual(types, [.number, .number, .object])
        XCTAssertEqual(j["name"]!.type, .string); XCTAssertEqual(j["mana_cost"]!.type, .null)
        XCTAssertEqual(j["printings"]!.type, .array); XCTAssertEqual(j["printings"]![0]!["foil"]!.type, .bool)
    }

    func testErrorPaths() {
        expectError(cardJSON, "$.missing", "Int", "missing") { _ = try $0.int("missing") }
        expectError(cardJSON, "$.name", "Int", "string") { _ = try $0.int("name") }
        expectError(cardJSON, "$.mana_cost", "String", "null") { _ = try $0.string("mana_cost") }
        expectError(cardJSON, "$.cmc", "String", "number") { _ = try $0.optionalString("cmc") }
        expectError(cardJSON, "$.set.code", "Int", "string") { _ = try SetInfo($0.object("set")); _ = try $0.object("set").int("code") }
        expectError(cardJSON, "$.printings[1].year", "Bool", "number") { j in _ = try j.objects("printings")[1].bool("year") }
        expectError(cardJSON, "$.printings[1].foil", "Int", "missing") { j in _ = try j.objects("printings")[1].int("foil") }
        expectError(cardJSON, "$.extra.a[2]", "Int", "object") { j in _ = try j.object("extra").ints("a") }
        expectError(cardJSON, "$.colors", "object", "array") { j in _ = try j.object("colors") }
        expectError(cardJSON, "$.colors", "object", "array") { j in _ = try j["colors"]!.int("x") }   // getter on non-object
        expectError(cardJSON, "$.colors[0]", "Int", "string") { j in _ = try j.ints("colors") }
        expectError(cardJSON, "$.cmc", "Bool", "number") { j in _ = try j.bool("cmc", default: false) }
        expectError(#"{"x":1.5}"#, "$.x", "Int", "non-integer number") { _ = try $0.int("x") }
        expectError(#"{"x":-1}"#, "$.x", "UInt", "out-of-range number") { _ = try $0.uint("x") }
        expectError(#"{"x":18446744073709551615}"#, "$.x", "Int", "out-of-range number") { _ = try $0.int("x") }
        expectError(#"[{"a":1},2]"#, "$[1]", "object", "number") { _ = try $0[1]!.int("a") }
    }

    func testDescription() {
        XCTAssertEqual(JSONError(path: "$.a", expected: "Int", found: "string").description, "$.a: expected Int, found string")
    }

    func testInvalidJSON() {
        for bad in ["", "{", #"{"a":}"#, "[1,]", "nul", #"{"a":1}x"#, "\u{FEFF}{}", #"{"a":NaN}"#, "\"\\x\"", "[1e999]", "{'a':1}"] {
            do { _ = try JSON.parse(bad); XCTFail("accepted: \(bad)") }
            catch let e as JSONError { XCTAssertTrue(e.isParseError, bad); XCTAssertEqual(e.path, "$") }
            catch { XCTFail("\(error)") }
        }
        let bytes: [UInt8] = [0x22, 0xFF, 0x22]                    // invalid UTF-8
        XCTAssertThrowsError(try bytes.withUnsafeBytes { try JSONDocument(bytes: $0) })
        do { _ = try JSON.parse(#"{"a":1,}"#) } catch let e as JSONError { XCTAssertEqual(e.parsePosition, 6); XCTAssertTrue("\(e)".contains("at byte 6")) } catch {}
    }

    /// JSON values keep their document alive (run with --sanitize=address to check).
    func testLifetime() throws {
        func make() throws -> [JSON] {
            var data = Data(cardJSON.utf8)
            let docObjects = try JSONDocument(data: data).root.objects("printings")   // doc only referenced by values
            data.resetBytes(in: 0..<data.count)                                      // input not needed after parse
            return docObjects
        }
        let ps = try make()
        weak var weakDoc: JSONDocument?
        weakDoc = ps[0].document
        XCTAssertNotNil(weakDoc)
        XCTAssertEqual(try ps.map { try $0.int("year") }, [2022, 2023])
        let card = try Card(JSONDocument(data: Data(cardJSON.utf8)).root)          // temporary document
        XCTAssertEqual(card.set.name, "Kamigawa")
        var w2: JSONDocument?
        do { let d = try JSONDocument(string: "[1]"); w2 = d }
        XCTAssertEqual(try w2?.root[0]?.int(), 1)
        weak var gone: JSONDocument?
        do { let d = try JSONDocument(string: "{}"); gone = d; _ = d.byteCount }
        XCTAssertNil(gone)                                                          // freed when last ref drops
    }
}

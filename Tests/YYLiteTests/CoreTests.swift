import XCTest
import YYLite
import CYYJSON
import Foundation

/// Tests of the shared C writer core paths that the ObjC wrapper uses (C double/float formatting),
/// plus lookup-cursor behaviour of the reader.
final class CoreTests: XCTestCase {
    private func cWrite(_ body: (UnsafeMutablePointer<yylite_writer>) -> Void) -> String {
        let w = UnsafeMutablePointer<yylite_writer>.allocate(capacity: 1)
        defer { yylite_w_free(w); w.deallocate() }
        _ = yylite_w_init(w, 16, false)
        body(w)
        return String(decoding: UnsafeBufferPointer(start: w.pointee.buf, count: w.pointee.len), as: UTF8.self)
    }

    func testCDoubleFormattingRoundTrips() throws {
        var ds: [Double] = [0, -0.0, 0.1, 0.3, 1e308, 5e-324, 2.2250738585072014e-308, 1.7976931348623157e308, -1.5,
                            123456789.123456789, 1e-7, 1e21, 2.0 / 3.0, 9007199254740993, 100, 1e16, 123e-300]
        var g = SystemRandomNumberGenerator()
        for _ in 0..<20_000 { ds.append(Double(bitPattern: g.next() & 0x7FEF_FFFF_FFFF_FFFF | (g.next() & (1 << 63)))) }
        let out = cWrite { w in yylite_w_begin(w, 0x5B); for d in ds { XCTAssertTrue(yylite_w_double(w, d)) }; yylite_w_end(w, 0x5D) }
        let back = try JSON.parse(out).elements().map { try $0.double() }
        XCTAssertEqual(back.map(\.bitPattern), ds.map(\.bitPattern))
        XCTAssertTrue(out.hasPrefix("[0.0,-0.0,0.1,0.3,1e+308,4.94065645841247e-324,"), String(out.prefix(80)))
        XCTAssertEqual(cWrite { w in _ = yylite_w_double(w, 100) }, "100.0")
        XCTAssertEqual(cWrite { w in XCTAssertFalse(yylite_w_double(w, .nan)) }, "null")
        let fs: [Float] = [0.1, 3.4028235e38, 1e-45, -2.5, 16777217]
        let fo = cWrite { w in yylite_w_begin(w, 0x5B); for f in fs { _ = yylite_w_float(w, f) }; yylite_w_end(w, 0x5D) }
        XCTAssertEqual(try JSON.parse(fo).elements().map { try $0.float() }, fs)
        XCTAssertTrue(fo.hasPrefix("[0.1,3.4028235e+38,1.4013e-45,-2.5,"), fo)
    }

    func testCStringEscapesAndInts() throws {
        let out = cWrite { w in
            yylite_w_begin(w, 0x7B)
            yylite_w_key(w, "a\"", 2); yylite_w_string(w, "x\u{1}\n\\/é", 7)
            yylite_w_key(w, "i", 1); yylite_w_int(w, Int64.min)
            yylite_w_key(w, "u", 1); yylite_w_uint(w, UInt64.max)
            yylite_w_end(w, 0x7D)
        }
        XCTAssertEqual(out, #"{"a\"":"x\u0001\n\\/é","i":-9223372036854775808,"u":18446744073709551615}"#)
    }

    /// Random strings (plain runs of every length, control chars, quotes, backslashes, multi-byte)
    /// through the block-wise escaper, re-parsed and compared; also checked against Foundation.
    func testEscapeFuzz() throws {
        var g = SystemRandomNumberGenerator()
        let alphabet: [Character] = ["a", "b", "Z", "0", " ", "\"", "\\", "\n", "\t", "\u{0}", "\u{1}", "\u{1F}",
                                     "\u{7F}", "/", "é", "✓", "😀", "\u{2028}"]
        var strings: [String] = []
        for len in 0..<40 { for _ in 0..<25 {
            let plain = Int.random(in: 0..<4, using: &g) == 0
            strings.append(String((0..<len).map { _ in plain ? "x" : alphabet.randomElement(using: &g)! }))
        } }
        strings.append(String(repeating: "abcdefgh", count: 5000) + "\"" + String(repeating: "\u{1}", count: 3000))
        let data = try JSONWriter.encode { w in w.array { for s in strings { w.string(s) } } }
        XCTAssertEqual(try JSON.parse(data).elements().map { try $0.string() }, strings)
        XCTAssertEqual(try JSONSerialization.jsonObject(with: data) as? [String], strings)
        let keyed = try JSONWriter.encode { w in w.object { for (i, s) in strings.prefix(300).enumerated() { w.key(s + "\(i)"); w.int(i) } } }
        let back = try JSON.parse(keyed)
        for (i, s) in strings.prefix(300).enumerated() { XCTAssertEqual(try back[s + "\(i)"]?.int(), i) }
    }

    /// The key cursor must give the same answers for any read order, across nested objects.
    func testLookupOrderIndependence() throws {
        let j = try JSON.parse(#"{"a":1,"b":{"x":1,"y":2,"z":3},"c":3,"d":{"x":4},"e":5,"f":null}"#)
        XCTAssertEqual(try j.int("e"), 5); XCTAssertEqual(try j.int("a"), 1)
        let b = try j.object("b"), d = try j.object("d")
        XCTAssertEqual(try b.int("z"), 3); XCTAssertEqual(try d.int("x"), 4); XCTAssertEqual(try b.int("x"), 1)
        XCTAssertEqual(try j.int("c"), 3); XCTAssertEqual(try b.int("y"), 2); XCTAssertNil(try j.optionalInt("f"))
        XCTAssertNil(try j.optionalInt("zz")); XCTAssertEqual(try j.int("a"), 1); XCTAssertEqual(try j.int("c"), 3)
        // more live objects than cursor slots
        let many = try JSON.parse("[" + (0..<10).map { #"{"k":\#($0),"v":"\#($0)"}"# }.joined(separator: ",") + "]").elements()
        for _ in 0..<3 { for (i, o) in many.enumerated().reversed() { XCTAssertEqual(try o.string("v"), "\(i)"); XCTAssertEqual(try o.int("k"), i) } }
    }
}

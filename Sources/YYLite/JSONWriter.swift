#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import CYYJSON

/// Streaming JSON writer. A thin Swift layer over the shared C core (`yylite_writer.c`,
/// also used by YYLiteObjC): bytes go straight into a buffer, with no intermediate tree.
///
/// Models write themselves with a non-generic `func encode(_ w: JSONWriter)`:
/// ```swift
/// func encode(_ w: JSONWriter) {
///     w.object {
///         w.int("id", id); w.string("name", name); w.optionalString("mana_cost", manaCost)
///         w.key("set"); set.encode(w)
///         w.array("printings") { for p in printings { p.encode(w) } }
///     }
/// }
/// let data = try JSONWriter.encode { deck.encode($0) }
/// ```
/// Keyed calls (`int("id", 1)`) go inside `object {}`. Unkeyed calls (`int(1)`) go inside
/// `array {}` or after `key(_:)`. Nesting is not checked; generated code always gets it right.
public final class JSONWriter {
    /// What `optional…` writers do with `nil`. Default `.omit` (like Foundation's synthesized Codable).
    public enum NilStrategy: Sendable { case omit, null }
    /// What to do with NaN / ±Infinity. Default `.throw` (like Foundation's JSONEncoder).
    public enum NonFiniteStrategy: Sendable { case `throw`, null }

    public let nilStrategy: NilStrategy
    public let nonFinite: NonFiniteStrategy
    private let w: UnsafeMutablePointer<yylite_writer>
    private var error: JSONError?

    public init(pretty: Bool = false, nilStrategy: NilStrategy = .omit,
                nonFinite: NonFiniteStrategy = .throw, capacity: Int = 4096) {
        self.nilStrategy = nilStrategy; self.nonFinite = nonFinite
        w = .allocate(capacity: 1)
        _ = yylite_w_init(w, capacity, pretty)
    }
    deinit { yylite_w_free(w); w.deallocate() }

    /// Runs `body` with a fresh writer and returns the UTF-8 JSON.
    /// Throws if a non-finite number was written with `nonFinite: .throw`.
    public static func encode(pretty: Bool = false, nilStrategy: NilStrategy = .omit,
                              nonFinite: NonFiniteStrategy = .throw,
                              _ body: (JSONWriter) -> Void) throws -> Data {
        let wr = JSONWriter(pretty: pretty, nilStrategy: nilStrategy, nonFinite: nonFinite)
        body(wr)
        return try wr.take()
    }

    /// Takes the bytes written (no copy) and resets the writer.
    public func take() throws -> Data {
        if let error { throw error }
        if w.pointee.failed { throw JSONError(path: "$", expected: "memory", found: "allocation failure") }
        var len = 0
        guard let p = yylite_w_take(w, &len) else { return Data() }
        return Data(bytesNoCopy: p, count: len, deallocator: .free)
    }
    /// The JSON written so far, as a String (copy).
    public func string() throws -> String {
        if let error { throw error }
        return String(decoding: UnsafeBufferPointer(start: w.pointee.buf, count: w.pointee.len), as: UTF8.self)
    }

    // MARK: structure

    /// Writes `"key":` (inside an object). The next unkeyed write is its value.
    public func key(_ key: StaticString) {
        if key.hasPointerRepresentation {
            yylite_w_key(w, UnsafeRawPointer(key.utf8Start).assumingMemoryBound(to: CChar.self), key.utf8CodeUnitCount)
        } else {
            key.withUTF8Buffer { b in yylite_w_key(w, UnsafeRawPointer(b.baseAddress!).assumingMemoryBound(to: CChar.self), b.count) }
        }
    }
    /// Runtime-key variant of `key(_:)`.
    public func key(_ key: String) {
        var k = key
        k.withUTF8 { b in yylite_w_key(w, UnsafeRawPointer(b.baseAddress)?.assumingMemoryBound(to: CChar.self), b.count) }
    }

    /// `{ … }`: an object as an array element or after `key(_:)`.
    public func object(_ body: () -> Void) { yylite_w_begin(w, 0x7B); body(); yylite_w_end(w, 0x7D) }
    /// `"key": { … }`
    public func object(_ k: StaticString, _ body: () -> Void) { key(k); object(body) }
    /// `[ … ]`: an array as an array element or after `key(_:)`.
    public func array(_ body: () -> Void) { yylite_w_begin(w, 0x5B); body(); yylite_w_end(w, 0x5D) }
    /// `"key": [ … ]`
    public func array(_ k: StaticString, _ body: () -> Void) { key(k); array(body) }

    // MARK: unkeyed values (array elements, or after key())

    public func null() { yylite_w_null(w) }
    public func bool(_ v: Bool) { yylite_w_bool(w, v) }
    public func int(_ v: Int) { yylite_w_int(w, Int64(v)) }
    public func int64(_ v: Int64) { yylite_w_int(w, v) }
    public func uint(_ v: UInt) { yylite_w_uint(w, UInt64(v)) }
    public func double(_ v: Double) { writeDouble(v, nil) }
    public func float(_ v: Float) {
        guard v.isFinite else { return nonFiniteValue(v.isNaN ? "NaN" : "Infinity", nil) }
        writeNumberText(v.description)
    }
    public func string(_ v: String) {
        var s = v
        s.withUTF8 { b in yylite_w_string(w, UnsafeRawPointer(b.baseAddress)?.assumingMemoryBound(to: CChar.self), b.count) }
    }

    // MARK: keyed values (inside an object)

    public func null(_ k: StaticString) { key(k); null() }
    public func bool(_ k: StaticString, _ v: Bool) { key(k); bool(v) }
    public func int(_ k: StaticString, _ v: Int) { key(k); int(v) }
    public func int64(_ k: StaticString, _ v: Int64) { key(k); int64(v) }
    public func uint(_ k: StaticString, _ v: UInt) { key(k); uint(v) }
    public func double(_ k: StaticString, _ v: Double) { key(k); writeDouble(v, k) }
    public func float(_ k: StaticString, _ v: Float) { key(k); float(v) }
    public func string(_ k: StaticString, _ v: String) { key(k); string(v) }

    /// For a nil optional (nested model etc.): writes `"key": null` with `.null`, nothing with `.omit`.
    public func nilValue(_ k: StaticString) { if nilStrategy == .null { null(k) } }

    public func optionalBool(_ k: StaticString, _ v: Bool?) { if let v { bool(k, v) } else { nilValue(k) } }
    public func optionalInt(_ k: StaticString, _ v: Int?) { if let v { int(k, v) } else { nilValue(k) } }
    public func optionalInt64(_ k: StaticString, _ v: Int64?) { if let v { int64(k, v) } else { nilValue(k) } }
    public func optionalUInt(_ k: StaticString, _ v: UInt?) { if let v { uint(k, v) } else { nilValue(k) } }
    public func optionalDouble(_ k: StaticString, _ v: Double?) { if let v { double(k, v) } else { nilValue(k) } }
    public func optionalFloat(_ k: StaticString, _ v: Float?) { if let v { float(k, v) } else { nilValue(k) } }
    public func optionalString(_ k: StaticString, _ v: String?) { if let v { string(k, v) } else { nilValue(k) } }

    // Arrays of primitives
    public func strings(_ k: StaticString, _ v: [String]) { array(k) { for x in v { string(x) } } }
    public func ints(_ k: StaticString, _ v: [Int]) { array(k) { for x in v { int(x) } } }
    public func doubles(_ k: StaticString, _ v: [Double]) { array(k) { for x in v { double(x) } } }
    public func bools(_ k: StaticString, _ v: [Bool]) { array(k) { for x in v { bool(x) } } }
    public func optionalStrings(_ k: StaticString, _ v: [String]?) { if let v { strings(k, v) } else { nilValue(k) } }
    public func optionalInts(_ k: StaticString, _ v: [Int]?) { if let v { ints(k, v) } else { nilValue(k) } }
    public func optionalDoubles(_ k: StaticString, _ v: [Double]?) { if let v { doubles(k, v) } else { nilValue(k) } }
    public func optionalBools(_ k: StaticString, _ v: [Bool]?) { if let v { bools(k, v) } else { nilValue(k) } }

    // MARK: numbers

    /// Swift's `description` is the shortest text that round-trips. It is stdlib code, which ships
    /// in the OS on Apple platforms, so it adds no app bytes. Faster than the C core's printf path.
    /// Integral values print as "2.0", and -0.0 as "-0.0".
    @inline(never) private func writeDouble(_ v: Double, _ k: StaticString?) {
        guard v.isFinite else { return nonFiniteValue(v.isNaN ? "NaN" : "Infinity", k) }
        writeNumberText(v.description)
    }
    @inline(never) private func writeNumberText(_ s: String) {
        var s = s
        s.withUTF8 { b in yylite_w_number_text(w, UnsafeRawPointer(b.baseAddress)?.assumingMemoryBound(to: CChar.self), b.count) }
    }
    @inline(never) private func nonFiniteValue(_ what: String, _ k: StaticString?) {
        yylite_w_null(w)
        if nonFinite == .throw && error == nil {
            error = JSONError(path: k.map { "$…." + $0.description } ?? "$…", expected: "finite number", found: what)
        }
    }
}

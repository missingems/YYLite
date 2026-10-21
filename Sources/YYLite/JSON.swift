#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import CYYJSON

typealias YYVal = UnsafeMutablePointer<yyjson_val>

/// The kind of a JSON value.
public enum JSONType: Sendable { case null, bool, number, string, array, object }

/// A read-only view of one value inside a `JSONDocument`.
///
/// Small (pointer + document reference) and cheap to copy. It holds a strong reference to
/// its document, so it stays valid as long as you keep it. Like its document, use it from one
/// thread at a time. Getters take literal keys
/// (`StaticString`); use `j["key"]` for keys built at runtime.
///
/// Optional getters: missing or `null` → `nil`; present with the wrong type → throws.
/// `default:` getters: missing or `null` → the default; wrong type → throws.
public struct JSON {
    let val: YYVal
    let doc: JSONDocument

    init(_ val: YYVal, _ doc: JSONDocument) { self.val = val; self.doc = doc }

    /// Parses `data` and returns its root value (which keeps the document alive).
    public static func parse(_ data: Data) throws -> JSON { try JSONDocument(data: data).root }
    /// Parses a JSON string and returns its root value.
    public static func parse(_ string: String) throws -> JSON { try JSONDocument(string: string).root }

    /// The document that owns this value.
    public var document: JSONDocument { doc }
}

// MARK: - Internal, non-generic conversions

@inline(__always) func stringValue(_ v: YYVal) -> String? {
    guard yyjson_is_str(v), let p = yyjson_get_str(v) else { return nil }
    // UnsafeBufferPointer<UInt8> hits String's contiguous-UTF-8 fast path (a raw buffer does not).
    return String(decoding: UnsafeBufferPointer(start: UnsafeRawPointer(p).assumingMemoryBound(to: UInt8.self),
                                                count: yyjson_get_len(v)), as: UTF8.self)
}
@inline(__always) func intValue(_ v: YYVal) -> Int? {
    if yyjson_is_sint(v) { return Int(truncatingIfNeeded: yyjson_get_sint(v)) }   // 64-bit Int
    if yyjson_is_uint(v) { return Int(exactly: yyjson_get_uint(v)) }
    return nil
}
@inline(__always) func uintValue(_ v: YYVal) -> UInt? {
    if yyjson_is_uint(v) { return UInt(exactly: yyjson_get_uint(v)) }
    if yyjson_is_sint(v) { return UInt(exactly: yyjson_get_sint(v)) }
    return nil
}
@inline(__always) func doubleValue(_ v: YYVal) -> Double? {
    yyjson_is_num(v) ? yyjson_get_num(v) : nil      // integers are accepted as doubles
}
@inline(__always) func boolValue(_ v: YYVal) -> Bool? {
    yyjson_is_bool(v) ? yyjson_get_bool(v) : nil
}
func typeName(_ v: YYVal) -> String {
    switch JSON.kind(v) {
    case .null: return "null"; case .bool: return "bool"; case .number: return "number"
    case .string: return "string"; case .array: return "array"; case .object: return "object"
    }
}

// MARK: - Lookup and errors

extension JSON {
    @inline(__always) func lookup(_ key: StaticString) -> YYVal? {
        if key.hasPointerRepresentation {
            return doc.find(val, UnsafeRawPointer(key.utf8Start), key.utf8CodeUnitCount)
        }
        return lookupScalarKey(key)
    }
    /// A one-character literal may be stored as a Unicode scalar instead of a pointer.
    @inline(never) func lookupScalarKey(_ key: StaticString) -> YYVal? {
        key.withUTF8Buffer { b in
            doc.find(val, UnsafeRawPointer(b.baseAddress!), b.count)
        }
    }

    @inline(never) func missing(_ key: StaticString, _ expected: String) -> JSONError {
        let here = doc.path(to: val)
        if !yyjson_is_obj(val) { return JSONError(path: here, expected: "object", found: typeName(val)) }
        return JSONError(path: here + "." + key.description, expected: expected, found: "missing")
    }

    @inline(never) func mismatch(_ v: YYVal, _ expected: String) -> JSONError {
        var found = typeName(v)
        if yyjson_is_num(v) && (expected == "Int" || expected == "Int64" || expected == "UInt") {
            found = yyjson_is_real(v) ? "non-integer number" : "out-of-range number"
        }
        return JSONError(path: doc.path(to: v), expected: expected, found: found)
    }

    static func kind(_ v: YYVal) -> JSONType {
        if yyjson_is_obj(v) { return .object }
        if yyjson_is_arr(v) { return .array }
        if yyjson_is_str(v) { return .string }
        if yyjson_is_num(v) { return .number }
        if yyjson_is_bool(v) { return .bool }
        return .null
    }
}

// MARK: - Scalars: required / optional / default / value itself

extension JSON {
    // Int
    public func int(_ key: StaticString) throws -> Int {
        guard let v = lookup(key) else { throw missing(key, "Int") }
        guard let x = intValue(v) else { throw mismatch(v, "Int") }
        return x
    }
    public func optionalInt(_ key: StaticString) throws -> Int? {
        guard let v = lookup(key), !yyjson_is_null(v) else { return nil }
        guard let x = intValue(v) else { throw mismatch(v, "Int") }
        return x
    }
    public func int(_ key: StaticString, default d: Int) throws -> Int { try optionalInt(key) ?? d }
    public func int() throws -> Int {
        guard let x = intValue(val) else { throw mismatch(val, "Int") }
        return x
    }

    // Int64
    public func int64(_ key: StaticString) throws -> Int64 {
        guard let v = lookup(key) else { throw missing(key, "Int64") }
        guard let x = intValue(v) else { throw mismatch(v, "Int64") }
        return Int64(x)
    }
    public func optionalInt64(_ key: StaticString) throws -> Int64? {
        guard let v = lookup(key), !yyjson_is_null(v) else { return nil }
        guard let x = intValue(v) else { throw mismatch(v, "Int64") }
        return Int64(x)
    }
    public func int64(_ key: StaticString, default d: Int64) throws -> Int64 { try optionalInt64(key) ?? d }
    public func int64() throws -> Int64 {
        guard let x = intValue(val) else { throw mismatch(val, "Int64") }
        return Int64(x)
    }

    // UInt
    public func uint(_ key: StaticString) throws -> UInt {
        guard let v = lookup(key) else { throw missing(key, "UInt") }
        guard let x = uintValue(v) else { throw mismatch(v, "UInt") }
        return x
    }
    public func optionalUInt(_ key: StaticString) throws -> UInt? {
        guard let v = lookup(key), !yyjson_is_null(v) else { return nil }
        guard let x = uintValue(v) else { throw mismatch(v, "UInt") }
        return x
    }
    public func uint(_ key: StaticString, default d: UInt) throws -> UInt { try optionalUInt(key) ?? d }
    public func uint() throws -> UInt {
        guard let x = uintValue(val) else { throw mismatch(val, "UInt") }
        return x
    }

    // Double
    public func double(_ key: StaticString) throws -> Double {
        guard let v = lookup(key) else { throw missing(key, "Double") }
        guard let x = doubleValue(v) else { throw mismatch(v, "Double") }
        return x
    }
    public func optionalDouble(_ key: StaticString) throws -> Double? {
        guard let v = lookup(key), !yyjson_is_null(v) else { return nil }
        guard let x = doubleValue(v) else { throw mismatch(v, "Double") }
        return x
    }
    public func double(_ key: StaticString, default d: Double) throws -> Double { try optionalDouble(key) ?? d }
    public func double() throws -> Double {
        guard let x = doubleValue(val) else { throw mismatch(val, "Double") }
        return x
    }

    // Float (from the double value)
    public func float(_ key: StaticString) throws -> Float {
        guard let v = lookup(key) else { throw missing(key, "Float") }
        guard let x = doubleValue(v) else { throw mismatch(v, "Float") }
        return Float(x)
    }
    public func optionalFloat(_ key: StaticString) throws -> Float? {
        guard let v = lookup(key), !yyjson_is_null(v) else { return nil }
        guard let x = doubleValue(v) else { throw mismatch(v, "Float") }
        return Float(x)
    }
    public func float(_ key: StaticString, default d: Float) throws -> Float { try optionalFloat(key) ?? d }
    public func float() throws -> Float {
        guard let x = doubleValue(val) else { throw mismatch(val, "Float") }
        return Float(x)
    }

    // Bool
    public func bool(_ key: StaticString) throws -> Bool {
        guard let v = lookup(key) else { throw missing(key, "Bool") }
        guard let x = boolValue(v) else { throw mismatch(v, "Bool") }
        return x
    }
    public func optionalBool(_ key: StaticString) throws -> Bool? {
        guard let v = lookup(key), !yyjson_is_null(v) else { return nil }
        guard let x = boolValue(v) else { throw mismatch(v, "Bool") }
        return x
    }
    public func bool(_ key: StaticString, default d: Bool) throws -> Bool { try optionalBool(key) ?? d }
    public func bool() throws -> Bool {
        guard let x = boolValue(val) else { throw mismatch(val, "Bool") }
        return x
    }

    // String
    public func string(_ key: StaticString) throws -> String {
        guard let v = lookup(key) else { throw missing(key, "String") }
        guard let x = stringValue(v) else { throw mismatch(v, "String") }
        return x
    }
    public func optionalString(_ key: StaticString) throws -> String? {
        guard let v = lookup(key), !yyjson_is_null(v) else { return nil }
        guard let x = stringValue(v) else { throw mismatch(v, "String") }
        return x
    }
    public func string(_ key: StaticString, default d: String) throws -> String { try optionalString(key) ?? d }
    public func string() throws -> String {
        guard let x = stringValue(val) else { throw mismatch(val, "String") }
        return x
    }
}

// MARK: - Arrays of primitives

extension JSON {
    @inline(__always) func arrayValue(_ key: StaticString, _ expected: String) throws -> YYVal {
        guard let v = lookup(key) else { throw missing(key, expected) }
        guard yyjson_is_arr(v) else { throw mismatch(v, expected) }
        return v
    }
    @inline(__always) func optionalArrayValue(_ key: StaticString, _ expected: String) throws -> YYVal? {
        guard let v = lookup(key), !yyjson_is_null(v) else { return nil }
        guard yyjson_is_arr(v) else { throw mismatch(v, expected) }
        return v
    }

    func stringArray(_ a: YYVal) throws -> [String] {
        var out: [String] = []; out.reserveCapacity(yyjson_arr_size(a))
        var it = yyjson_arr_iter(); _ = yyjson_arr_iter_init(a, &it)
        while let e = yyjson_arr_iter_next(&it) {
            guard let x = stringValue(e) else { throw mismatch(e, "String") }
            out.append(x)
        }
        return out
    }
    func intArray(_ a: YYVal) throws -> [Int] {
        var out: [Int] = []; out.reserveCapacity(yyjson_arr_size(a))
        var it = yyjson_arr_iter(); _ = yyjson_arr_iter_init(a, &it)
        while let e = yyjson_arr_iter_next(&it) {
            guard let x = intValue(e) else { throw mismatch(e, "Int") }
            out.append(x)
        }
        return out
    }
    func doubleArray(_ a: YYVal) throws -> [Double] {
        var out: [Double] = []; out.reserveCapacity(yyjson_arr_size(a))
        var it = yyjson_arr_iter(); _ = yyjson_arr_iter_init(a, &it)
        while let e = yyjson_arr_iter_next(&it) {
            guard let x = doubleValue(e) else { throw mismatch(e, "Double") }
            out.append(x)
        }
        return out
    }
    func boolArray(_ a: YYVal) throws -> [Bool] {
        var out: [Bool] = []; out.reserveCapacity(yyjson_arr_size(a))
        var it = yyjson_arr_iter(); _ = yyjson_arr_iter_init(a, &it)
        while let e = yyjson_arr_iter_next(&it) {
            guard let x = boolValue(e) else { throw mismatch(e, "Bool") }
            out.append(x)
        }
        return out
    }

    public func strings(_ key: StaticString) throws -> [String] { try stringArray(arrayValue(key, "[String]")) }
    public func optionalStrings(_ key: StaticString) throws -> [String]? {
        guard let a = try optionalArrayValue(key, "[String]") else { return nil }
        return try stringArray(a)
    }
    public func ints(_ key: StaticString) throws -> [Int] { try intArray(arrayValue(key, "[Int]")) }
    public func optionalInts(_ key: StaticString) throws -> [Int]? {
        guard let a = try optionalArrayValue(key, "[Int]") else { return nil }
        return try intArray(a)
    }
    public func doubles(_ key: StaticString) throws -> [Double] { try doubleArray(arrayValue(key, "[Double]")) }
    public func optionalDoubles(_ key: StaticString) throws -> [Double]? {
        guard let a = try optionalArrayValue(key, "[Double]") else { return nil }
        return try doubleArray(a)
    }
    public func bools(_ key: StaticString) throws -> [Bool] { try boolArray(arrayValue(key, "[Bool]")) }
    public func optionalBools(_ key: StaticString) throws -> [Bool]? {
        guard let a = try optionalArrayValue(key, "[Bool]") else { return nil }
        return try boolArray(a)
    }
}

// MARK: - Nested objects and arrays of objects

extension JSON {
    /// Nested object at `key`.
    public func object(_ key: StaticString) throws -> JSON {
        guard let v = lookup(key) else { throw missing(key, "object") }
        guard yyjson_is_obj(v) else { throw mismatch(v, "object") }
        return JSON(v, doc)
    }
    public func optionalObject(_ key: StaticString) throws -> JSON? {
        guard let v = lookup(key), !yyjson_is_null(v) else { return nil }
        guard yyjson_is_obj(v) else { throw mismatch(v, "object") }
        return JSON(v, doc)
    }

    func objectArray(_ a: YYVal) throws -> [JSON] {
        var out: [JSON] = []; out.reserveCapacity(yyjson_arr_size(a))
        var it = yyjson_arr_iter(); _ = yyjson_arr_iter_init(a, &it)
        while let e = yyjson_arr_iter_next(&it) {
            guard yyjson_is_obj(e) else { throw mismatch(e, "object") }
            out.append(JSON(e, doc))
        }
        return out
    }

    /// Array of objects at `key`. Map each to your model: `try j.objects("cards").map(Card.init)`.
    public func objects(_ key: StaticString) throws -> [JSON] { try objectArray(arrayValue(key, "[object]")) }
    public func optionalObjects(_ key: StaticString) throws -> [JSON]? {
        guard let a = try optionalArrayValue(key, "[object]") else { return nil }
        return try objectArray(a)
    }

    /// Calls `body` for each object in the array at `key` without building an intermediate array.
    public func forEachObject(_ key: StaticString, _ body: (JSON) throws -> Void) throws {
        let a = try arrayValue(key, "[object]")
        var it = yyjson_arr_iter(); _ = yyjson_arr_iter_init(a, &it)
        while let e = yyjson_arr_iter_next(&it) {
            guard yyjson_is_obj(e) else { throw mismatch(e, "object") }
            try body(JSON(e, doc))
        }
    }
}

// MARK: - Raw access

extension JSON {
    public var type: JSONType { JSON.kind(val) }
    public var isNull: Bool { yyjson_is_null(val) }
    /// Number of elements (array) or members (object); 0 for scalars.
    public var count: Int {
        yyjson_is_arr(val) ? yyjson_arr_size(val) : (yyjson_is_obj(val) ? yyjson_obj_size(val) : 0)
    }

    /// Member for a runtime key, or nil if missing / not an object. (`null` gives a JSON whose `isNull` is true.)
    public subscript(key: String) -> JSON? {
        var k = key
        let v = k.withUTF8 { b in
            yyjson_obj_getn(val, UnsafeRawPointer(b.baseAddress)?.assumingMemoryBound(to: CChar.self), b.count)
        }
        return v.map { JSON($0, doc) }
    }
    /// Element at `index`, or nil if out of range / not an array.
    public subscript(index: Int) -> JSON? {
        guard index >= 0, let v = yyjson_arr_get(val, index) else { return nil }
        return JSON(v, doc)
    }
    public func contains(_ key: String) -> Bool { self[key] != nil }

    /// Object keys in document order (empty for non-objects).
    public var keys: [String] {
        var out: [String] = []
        forEachMember { k, _ in out.append(k) }
        return out
    }
    /// Iterates object members in document order (nothing for non-objects).
    public func forEachMember(_ body: (String, JSON) throws -> Void) rethrows {
        var it = yyjson_obj_iter()
        guard yyjson_obj_iter_init(val, &it) else { return }
        while let k = yyjson_obj_iter_next(&it) {
            try body(stringValue(k) ?? "", JSON(yyjson_obj_iter_get_val(k), doc))
        }
    }
    /// Iterates array elements (nothing for non-arrays).
    public func forEachElement(_ body: (JSON) throws -> Void) rethrows {
        var it = yyjson_arr_iter()
        guard yyjson_arr_iter_init(val, &it) else { return }
        while let e = yyjson_arr_iter_next(&it) { try body(JSON(e, doc)) }
    }
    /// All elements of this array; throws if this is not an array.
    public func elements() throws -> [JSON] {
        guard yyjson_is_arr(val) else { throw mismatch(val, "array") }
        var out: [JSON] = []; out.reserveCapacity(yyjson_arr_size(val))
        forEachElement { out.append($0) }
        return out
    }
}

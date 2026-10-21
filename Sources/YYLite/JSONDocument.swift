#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import CYYJSON

/// Owns a parsed, immutable yyjson document. Freed when the last reference goes away.
///
/// Every `JSON` value keeps a strong reference to its document, so values may be stored,
/// passed around or outlive the `JSONDocument` variable; the memory stays valid.
/// Not thread-safe: read a document (and its `JSON` values) from one thread at a time.
/// It keeps a small key-lookup cursor cache that makes in-order key reads O(1).
public final class JSONDocument {
    @usableFromInline let doc: UnsafeMutablePointer<yyjson_doc>

    /// Parses UTF-8 JSON. The input is copied into the document; `bytes` need not stay alive.
    public convenience init(bytes: UnsafeRawBufferPointer) throws {
        self.init(doc: try JSONDocument.read(bytes))
    }

    public convenience init(data: Data) throws {
        self.init(doc: try data.withUnsafeBytes { try JSONDocument.read($0) })
    }

    public convenience init(string: String) throws {
        var s = string
        self.init(doc: try s.withUTF8 { try JSONDocument.read(UnsafeRawBufferPointer($0)) })
    }

    private init(doc: UnsafeMutablePointer<yyjson_doc>) {
        self.doc = doc
        iters = .allocate(capacity: 4)
        iters.initialize(repeating: yyjson_obj_iter(), count: 4)
    }

    // Key-lookup cursors for the 4 most recently read objects. each cursor continues
    // from the previous match, so reading keys in document order costs O(1) per key instead of
    // a scan from the first key. Out-of-order keys still work (it wraps around).
    // This mutable cache is why a document must not be read from several threads at once.
    private let iters: UnsafeMutablePointer<yyjson_obj_iter>
    private var slot = 0

    /// Finds `key` in `obj`, continuing from where the previous lookup in `obj` matched.
    @inline(__always)
    func find(_ obj: UnsafeMutablePointer<yyjson_val>, _ key: UnsafeRawPointer, _ len: Int) -> UnsafeMutablePointer<yyjson_val>? {
        let cur = iters + slot                       // most recently used cursor first
        if cur.pointee.obj == obj { return scan(cur, key, len) }
        return findOther(obj, key, len)
    }
    @inline(never)
    func findOther(_ obj: UnsafeMutablePointer<yyjson_val>, _ key: UnsafeRawPointer, _ len: Int) -> UnsafeMutablePointer<yyjson_val>? {
        for i in 0..<4 where iters[i].obj == obj { slot = i; return scan(iters + i, key, len) }
        return findMiss(obj, key, len)
    }
    @inline(never)
    func findMiss(_ obj: UnsafeMutablePointer<yyjson_val>, _ key: UnsafeRawPointer, _ len: Int) -> UnsafeMutablePointer<yyjson_val>? {
        guard yyjson_is_obj(obj) else { return nil }
        slot = (slot + 1) & 3
        let it = iters + slot
        _ = yyjson_obj_iter_init(obj, it)
        return scan(it, key, len)
    }
    /// Like yyjson_obj_iter_getn, but with an inline key compare (no memcmp call for short keys).
    @inline(__always)
    private func scan(_ it: UnsafeMutablePointer<yyjson_obj_iter>, _ key: UnsafeRawPointer, _ len: Int) -> UnsafeMutablePointer<yyjson_val>? {
        let max = it.pointee.max
        var idx = it.pointee.idx
        var k = it.pointee.cur
        var n = max
        while n > 0 {
            if idx == max { idx = 0; k = unsafe_yyjson_get_first(it.pointee.obj) }
            let kv = k!
            let next = unsafe_yyjson_get_next(kv + 1)
            idx += 1
            if unsafe_yyjson_get_len(kv) == len && keyEquals(UnsafeRawPointer(unsafe_yyjson_get_str(kv)!), key, len) {
                it.pointee.idx = idx; it.pointee.cur = next
                return kv + 1
            }
            k = next; n -= 1
        }
        return nil
    }

    private static func read(_ bytes: UnsafeRawBufferPointer) throws -> UnsafeMutablePointer<yyjson_doc> {
        var err = yyjson_read_err()
        // yyjson writes to the input only with YYJSON_READ_INSITU, which is never used here.
        let p = UnsafeMutablePointer(mutating: bytes.baseAddress?.assumingMemoryBound(to: CChar.self))
        guard let d = yylite_yyjson_read_opts(p, bytes.count, 0, nil, &err) else {
            throw JSONError(path: "$", expected: "valid JSON", found: "parse error",
                            parseCode: err.code, parsePosition: err.pos)
        }
        return d
    }

    deinit { yyjson_doc_free(doc); iters.deallocate() }

    /// The root value.
    public var root: JSON { JSON(yyjson_doc_get_root(doc)!, self) }

    /// Number of JSON bytes read.
    public var byteCount: Int { yyjson_doc_get_read_size(doc) }

    // MARK: error paths (slow path only)

    /// JSONPath-like location of `target`, e.g. `$.cards[3].set.code`. O(document) — errors only.
    @inline(never)
    func path(to target: UnsafeMutablePointer<yyjson_val>) -> String {
        var comps: [String] = []
        func walk(_ v: UnsafeMutablePointer<yyjson_val>) -> Bool {
            if v == target { return true }
            if yyjson_is_obj(v) {
                var it = yyjson_obj_iter()
                _ = yyjson_obj_iter_init(v, &it)
                while let k = yyjson_obj_iter_next(&it) {
                    comps.append("." + (stringValue(k) ?? "?"))
                    if walk(yyjson_obj_iter_get_val(k)) { return true }
                    comps.removeLast()
                }
            } else if yyjson_is_arr(v) {
                var it = yyjson_arr_iter()
                _ = yyjson_arr_iter_init(v, &it)
                var i = 0
                while let e = yyjson_arr_iter_next(&it) {
                    comps.append("[\(i)]")
                    if walk(e) { return true }
                    comps.removeLast(); i += 1
                }
            }
            return false
        }
        return walk(yyjson_doc_get_root(doc)!) ? "$" + comps.joined() : "$?"
    }
}

@inline(__always)
func keyEquals(_ a: UnsafeRawPointer, _ b: UnsafeRawPointer, _ len: Int) -> Bool {
    // Overlapping fixed-size loads: no byte loop for keys up to 16 bytes.
    if len >= 8 {
        var i = 0
        while i &+ 8 < len {
            if a.loadUnaligned(fromByteOffset: i, as: UInt64.self) != b.loadUnaligned(fromByteOffset: i, as: UInt64.self) { return false }
            i &+= 8
        }
        return a.loadUnaligned(fromByteOffset: len &- 8, as: UInt64.self) == b.loadUnaligned(fromByteOffset: len &- 8, as: UInt64.self)
    }
    if len >= 4 {
        return a.loadUnaligned(as: UInt32.self) == b.loadUnaligned(as: UInt32.self)
            && a.loadUnaligned(fromByteOffset: len &- 4, as: UInt32.self) == b.loadUnaligned(fromByteOffset: len &- 4, as: UInt32.self)
    }
    if len >= 2 {
        return a.loadUnaligned(as: UInt16.self) == b.loadUnaligned(as: UInt16.self)
            && a.loadUnaligned(fromByteOffset: len &- 2, as: UInt16.self) == b.loadUnaligned(fromByteOffset: len &- 2, as: UInt16.self)
    }
    return len == 0 || a.load(as: UInt8.self) == b.load(as: UInt8.self)
}

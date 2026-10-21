// Counts heap allocations per operation. Run with LD_PRELOAD=malloccount/libmalloccount.so.
import Foundation
import Codable50
import Models50
import Models50S
import Compare50

typealias GetFn = @convention(c) (UnsafeMutablePointer<UInt64>) -> Void
guard let sym = dlsym(dlopen(nil, RTLD_NOW), "mcount_get") else {
    print("run with LD_PRELOAD=malloccount/libmalloccount.so"); exit(1)
}
let get = unsafeBitCast(sym, to: GetFn.self)
func snap() -> (UInt64, UInt64, UInt64) { var a = [UInt64](repeating: 0, count: 3); a.withUnsafeMutableBufferPointer { get($0.baseAddress!) }; return (a[0], a[1], a[2]) }

let data = try Fixture.load("models50.json")
var keep: [Any] = []
func measure(_ label: String, keepResult: Bool = true, _ body: () throws -> Any) rethrows {
    for _ in 0..<3 { _ = try body() }                       // warm caches / lazy metadata
    let a = snap()
    let r = try body()
    let b = snap()
    let allocs = b.0 - a.0, frees = b.1 - a.1, bytes = b.2 - a.2
    keep.append(r)                                         // still alive: live = allocs - frees
    print("  " + label.padding(toLength: 34, withPad: " ", startingAt: 0)
          + String(format: "allocs %8llu   live after %8llu   requested %6.2f MB", allocs, allocs - frees, Double(bytes) / 1e6))
}
print("per operation on models50.json (live after = still allocated while the result is held)")
try measure("Foundation decode → structs") { try Foundation50.decode(data) }
try measure("YYLite decode → classes") { try Models50.Root50(data: data) }
try measure("YYLite decode → structs") { try Models50S.Root50(data: data) }
let s = try Foundation50.decode(data), c = try Models50.Root50(data: data), t = try Models50S.Root50(data: data)
try measure("Foundation encode ← structs") { try Foundation50.encode(s) }
try measure("YYLite encode ← classes") { try c.jsonData() }
try measure("YYLite encode ← structs") { try t.jsonData() }

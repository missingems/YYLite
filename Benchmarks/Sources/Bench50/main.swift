import Foundation
import Codable50
import Models50
import Models50Loop
import Compare50
import YYLite

let iters = CommandLine.arguments.count > 1 ? Int(CommandLine.arguments[1]) ?? 51 : 51
#if os(Linux)
print("Platform: Linux — Foundation = swift-corelibs-foundation (JSONDecoder/JSONEncoder from swift-foundation); NOT Apple's iOS build.")
#endif

func nowNs() -> UInt64 { DispatchTime.now().uptimeNanoseconds }
@discardableResult
func bench(_ label: String, bytes: Int, _ body: () -> Void) -> Double {
    for _ in 0..<max(3, iters / 10) { body() }
    var t = [Double](); t.reserveCapacity(iters)
    for _ in 0..<iters { let s = nowNs(); body(); t.append(Double(nowNs() - s) / 1e6) }
    t.sort(); let med = t[t.count / 2]
    print("  " + label.padding(toLength: 36, withPad: " ", startingAt: 0)
          + String(format: "median %8.3f ms  %7.1f MB/s  %8.1f ops/s", med, Double(bytes) / (med / 1e3) / 1e6, 1e3 / med))
    return med
}

let data = try Fixture.load("models50.json")
print("== models50.json (\(data.count) bytes)")
let s = try Foundation50.decode(data)
let c = try Models50.Root50(data: data)
let cl = try Models50Loop.Root50(data: data)
precondition(diff50(s, c).isEmpty, "YYLite decode != Foundation decode")
// round trip + cross-checks
let enc = try c.jsonData()
let rt = try Models50.Root50(data: enc)
precondition(diff50(s, rt).isEmpty, "decode->encode->decode mismatch")
let fdec = try Foundation50.decode(enc)
precondition(diff50(fdec, c).isEmpty, "Foundation decode of YYLite output mismatch")
let fenc = try Foundation50.encode(s)
let ydec = try Models50.Root50(data: fenc)
precondition(diff50(s, ydec).isEmpty, "YYLite decode of Foundation output mismatch")
print("  verify: decode equal; round-trip equal; cross-decoded both ways equal (\(count50(s)) objects)")
print("  output size: YYLite \(enc.count) B, Foundation \(fenc.count) B")

print("decode")
let fd = bench("Foundation JSONDecoder → structs", bytes: data.count) { _ = try! Foundation50.decode(data) }
let yd = bench("YYLite → classes (objects().map)", bytes: data.count) { _ = try! Models50.Root50(data: data) }
bench("YYLite → classes (forEachObject)", bytes: data.count) { _ = try! Models50Loop.Root50(data: data) }
print(String(format: "  speedup: %.1fx", fd / yd))
print("encode (MB/s of YYLite output size)")
let fe = bench("Foundation JSONEncoder ← structs", bytes: enc.count) { _ = try! Foundation50.encode(s) }
let ye = bench("YYLite JSONWriter ← classes", bytes: enc.count) { _ = try! c.jsonData() }
print(String(format: "  speedup: %.1fx", fe / ye))
withExtendedLifetime(cl) {}
print("breakdown")
bench("YYLite parse only (JSONDocument)", bytes: data.count) { _ = try! JSONDocument(data: data) }
let pre = try JSONDocument(data: data)
bench("YYLite map only (Root50(root))", bytes: data.count) { _ = try! Models50.Root50(pre.root) }

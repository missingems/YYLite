import Foundation
import Codable50
import Models50
import Models50Loop
import Compare50
import Compare50S
import Models50S
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
// struct variant: field-by-field equal to Foundation, identical bytes out, round trips
let st = try Models50S.Root50(data: data)
precondition(diffS50(s, st).isEmpty, "struct decode != Foundation decode")
let encS = try st.jsonData()
precondition(encS == enc, "struct encode bytes != class encode bytes")
let rtS = try Models50S.Root50(data: encS), fS = try Models50S.Root50(data: fenc)
precondition(diffS50(s, rtS).isEmpty && diffS50(s, fS).isEmpty, "struct round trip")
print("  verify (structs): decode equal to Foundation; encode byte-identical to classes; round-trip + Foundation output equal")
print("  verify: decode equal; round-trip equal; cross-decoded both ways equal (\(count50(s)) objects)")
print("  output size: YYLite \(enc.count) B, Foundation \(fenc.count) B")

print("decode")
let fd = bench("Foundation JSONDecoder → structs", bytes: data.count) { _ = try! Foundation50.decode(data) }
let yd = bench("YYLite → classes (objects().map)", bytes: data.count) { _ = try! Models50.Root50(data: data) }
bench("YYLite → classes (forEachObject)", bytes: data.count) { _ = try! Models50Loop.Root50(data: data) }
let ydS = bench("YYLite → structs (objects().map)", bytes: data.count) { _ = try! Models50S.Root50(data: data) }
print(String(format: "  struct/class decode time: %.2f", ydS / yd))
print(String(format: "  speedup: %.1fx", fd / yd))
print("encode (MB/s of YYLite output size)")
let fe = bench("Foundation JSONEncoder ← structs", bytes: enc.count) { _ = try! Foundation50.encode(s) }
let ye = bench("YYLite JSONWriter ← classes", bytes: enc.count) { _ = try! c.jsonData() }
let yeS = bench("YYLite JSONWriter ← structs", bytes: enc.count) { _ = try! st.jsonData() }
print(String(format: "  struct/class encode time: %.2f", yeS / ye))
print(String(format: "  speedup: %.1fx", fe / ye))
withExtendedLifetime(cl) {}
print("breakdown")
bench("YYLite parse only (JSONDocument)", bytes: data.count) { _ = try! JSONDocument(data: data) }
let pre = try JSONDocument(data: data)
bench("YYLite map only (Root50(root))", bytes: data.count) { _ = try! Models50.Root50(pre.root) }
bench("YYLite map only, structs", bytes: data.count) { _ = try! Models50S.Root50(pre.root) }

// Copy cost: one copy of every element of the largest model arrays (what `let x = a[i]`, `a.map { $0 }`,
// storing into another collection, or passing into an escaping closure does).
print("copy cost (copy every element once into a new array)")
print("  layout: class ref = \(MemoryLayout<Models50.Event>.size) B;  struct Event = \(MemoryLayout<Models50S.Event>.size) B, Employee = \(MemoryLayout<Models50S.Employee>.size) B, Order = \(MemoryLayout<Models50S.Order>.size) B, Product = \(MemoryLayout<Models50S.Product>.size) B, Root50 = \(MemoryLayout<Models50S.Root50>.size) B")
@inline(never) func copyC(_ a: [Models50.Event]) -> [Models50.Event] { var o = [Models50.Event](); o.reserveCapacity(a.count); for x in a { o.append(x) }; return o }
@inline(never) func copyS(_ a: [Models50S.Event]) -> [Models50S.Event] { var o = [Models50S.Event](); o.reserveCapacity(a.count); for x in a { o.append(x) }; return o }
@inline(never) func copyCE(_ a: [Models50.Employee]) -> [Models50.Employee] { var o = [Models50.Employee](); o.reserveCapacity(a.count); for x in a { o.append(x) }; return o }
@inline(never) func copySE(_ a: [Models50S.Employee]) -> [Models50S.Employee] { var o = [Models50S.Employee](); o.reserveCapacity(a.count); for x in a { o.append(x) }; return o }
let reps = 1000
func perElem(_ label: String, _ n: Int, _ body: () -> Int) {
    var t = [Double]()
    for _ in 0..<21 { let s0 = nowNs(); var k = 0; for _ in 0..<reps { k &+= body() }; t.append(Double(nowNs() - s0) / Double(reps * n)); precondition(k > 0) }
    t.sort(); print("  " + label.padding(toLength: 36, withPad: " ", startingAt: 0) + String(format: "%7.1f ns / element", t[10]))
}
perElem("[Event] classes (\(c.eventList.count))", c.eventList.count) { copyC(c.eventList).count }
perElem("[Event] structs", st.eventList.count) { copyS(st.eventList).count }
perElem("[Employee] classes (\(c.employeeList.count))", c.employeeList.count) { copyCE(c.employeeList).count }
perElem("[Employee] structs", st.employeeList.count) { copySE(st.employeeList).count }

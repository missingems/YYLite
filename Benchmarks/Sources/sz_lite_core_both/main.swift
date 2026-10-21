// Library core only: parse + a few getters + writer (one model by hand), to size the core.
import Foundation
import YYLite
final class P { let a: Int; let b: String?; let c: [String]; let d: Double; let e: Bool
    init(_ j: JSON) throws { a = try j.int("a"); b = try j.optionalString("b"); c = try j.strings("c"); d = try j.double("d"); e = try j.bool("e") }
    func encode(_ w: JSONWriter) { w.object { w.int("a", a); w.optionalString("b", b); w.strings("c", c); w.double("d", d); w.bool("e", e) } } }
if let j = try? JSON.parse(Data(CommandLine.arguments.last!.utf8)), let ps = try? j.objects("p").map(P.init),
   let d = try? JSONWriter.encode({ w in w.array { for p in ps { p.encode(w) } } }) { print(d.count) }

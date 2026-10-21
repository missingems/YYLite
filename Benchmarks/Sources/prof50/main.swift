import Foundation
import YYLite
import Models50
import Compare50
let data = try Fixture.load("models50.json")
let doc = try JSONDocument(data: data)
let root = try Root50(doc.root)
if CommandLine.arguments.contains("encode") {
    for _ in 0..<20 { _ = try JSONWriter.encode { root.encode($0) } }
} else {
    for _ in 0..<20 { _ = try Root50(doc.root) }
}

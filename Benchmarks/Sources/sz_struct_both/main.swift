import Foundation
import Models50S
if let r = try? Root50(data: Data(CommandLine.arguments.last!.utf8)), let d = try? r.jsonData() { print(d.count) }

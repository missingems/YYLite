import Foundation
import Codable50
if let r = try? Foundation50.decode(Data(CommandLine.arguments.last!.utf8)), let d = try? Foundation50.encode(r) { print(d.count) }

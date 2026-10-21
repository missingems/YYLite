import Foundation
import Codable50
if let r = try? Foundation50.decode(Data(CommandLine.arguments.last!.utf8)) { print(r.userList.count) }

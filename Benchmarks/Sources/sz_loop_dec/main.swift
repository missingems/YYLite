import Foundation
import Models50Loop
if let r = try? Root50(data: Data(CommandLine.arguments.last!.utf8)) { print(r.userList.count) }

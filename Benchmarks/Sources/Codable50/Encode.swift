import Foundation
extension Foundation50 {
    public static func encode(_ r: Root50S) throws -> Data {
        let e = JSONEncoder(); e.keyEncodingStrategy = .convertToSnakeCase
        return try e.encode(r)
    }
}

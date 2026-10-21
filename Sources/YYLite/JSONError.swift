/// The one error type thrown by YYLite.
///
/// `description` reads like: `$.cards[3].set.code: expected String, found number`
/// or for parse errors: `$: invalid JSON (yyjson error 6 at byte 120)`.
public struct JSONError: Error, CustomStringConvertible, Sendable {
    /// Location of the problem, e.g. `$.cards[3].mana_cost`. `$` is the root.
    public let path: String
    /// What the getter wanted: "Int", "String", "object", "array", "valid JSON", ...
    public let expected: String
    /// What was there: "missing", "null", "string", "number", "out-of-range number", "parse error", ...
    public let found: String
    /// yyjson read error code (`YYJSON_READ_ERROR_*`), 0 when this is not a parse error.
    public let parseCode: UInt32
    /// Byte offset of a parse error in the input, 0 otherwise.
    public let parsePosition: Int

    public init(path: String, expected: String, found: String, parseCode: UInt32 = 0, parsePosition: Int = 0) {
        self.path = path; self.expected = expected; self.found = found
        self.parseCode = parseCode; self.parsePosition = parsePosition
    }

    public var isParseError: Bool { parseCode != 0 }

    public var description: String {
        if parseCode != 0 { return "\(path): invalid JSON (yyjson error \(parseCode) at byte \(parsePosition))" }
        return "\(path): expected \(expected), found \(found)"
    }
}

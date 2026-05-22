import Foundation

public enum TOMLValue: Equatable, Sendable {
    case string(String)
    case bool(Bool)
    case int(Int)
    case stringArray([String])

    public var stringValue: String? {
        switch self {
        case .string(let value): value
        case .bool(let value): value ? "true" : "false"
        case .int(let value): String(value)
        case .stringArray: nil
        }
    }

    public var boolValue: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }

    public var intValue: Int? {
        if case .int(let value) = self { return value }
        return nil
    }

    public var stringArrayValue: [String]? {
        if case .stringArray(let value) = self { return value }
        return nil
    }
}

public enum SimpleTOMLError: Error, LocalizedError, Equatable {
    case invalidLine(line: Int, text: String)
    case invalidString(line: Int, value: String)
    case invalidArray(line: Int, value: String)

    public var errorDescription: String? {
        switch self {
        case .invalidLine(let line, let text):
            return "Line \(line) is not valid TOML for AnySee: \(text)"
        case .invalidString(let line, let value):
            return "Line \(line) has an invalid string value: \(value)"
        case .invalidArray(let line, let value):
            return "Line \(line) has an invalid array value: \(value)"
        }
    }
}

public enum SimpleTOML {
    public static func stripComment(from line: String) -> String {
        var output = ""
        var isInString = false
        var escaped = false

        for character in line {
            if character == "\\" && isInString {
                escaped.toggle()
                output.append(character)
                continue
            }
            if character == "\"" && !escaped {
                isInString.toggle()
            }
            if character == "#" && !isInString {
                break
            }
            escaped = false
            output.append(character)
        }

        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func parseAssignment(_ line: String, lineNumber: Int) throws -> (String, TOMLValue) {
        var isInString = false
        var escaped = false
        var splitIndex: String.Index?

        for index in line.indices {
            let character = line[index]
            if character == "\\" && isInString {
                escaped.toggle()
                continue
            }
            if character == "\"" && !escaped {
                isInString.toggle()
            }
            if character == "=" && !isInString {
                splitIndex = index
                break
            }
            escaped = false
        }

        guard let splitIndex else {
            throw SimpleTOMLError.invalidLine(line: lineNumber, text: line)
        }

        let key = line[..<splitIndex].trimmingCharacters(in: .whitespacesAndNewlines)
        let valueStart = line.index(after: splitIndex)
        let rawValue = line[valueStart...].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            throw SimpleTOMLError.invalidLine(line: lineNumber, text: line)
        }

        return (String(key), try parseValue(String(rawValue), lineNumber: lineNumber))
    }

    public static func parseValue(_ rawValue: String, lineNumber: Int) throws -> TOMLValue {
        if rawValue == "true" { return .bool(true) }
        if rawValue == "false" { return .bool(false) }
        if let intValue = Int(rawValue) { return .int(intValue) }
        if rawValue.hasPrefix("[") {
            return .stringArray(try parseStringArray(rawValue, lineNumber: lineNumber))
        }
        if rawValue.hasPrefix("\"") {
            return .string(try parseString(rawValue, lineNumber: lineNumber))
        }
        return .string(rawValue)
    }

    private static func parseString(_ rawValue: String, lineNumber: Int) throws -> String {
        guard rawValue.hasPrefix("\""), rawValue.hasSuffix("\"") else {
            throw SimpleTOMLError.invalidString(line: lineNumber, value: rawValue)
        }
        guard let data = rawValue.data(using: .utf8) else {
            throw SimpleTOMLError.invalidString(line: lineNumber, value: rawValue)
        }
        do {
            return try JSONDecoder().decode(String.self, from: data)
        } catch {
            throw SimpleTOMLError.invalidString(line: lineNumber, value: rawValue)
        }
    }

    private static func parseStringArray(_ rawValue: String, lineNumber: Int) throws -> [String] {
        guard rawValue.hasPrefix("["), rawValue.hasSuffix("]") else {
            throw SimpleTOMLError.invalidArray(line: lineNumber, value: rawValue)
        }
        let inner = rawValue.dropFirst().dropLast()
        var values: [String] = []
        var current = ""
        var isInString = false
        var escaped = false

        func flush() throws {
            let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
            current = ""
            guard !trimmed.isEmpty else { return }
            values.append(try parseString(trimmed, lineNumber: lineNumber))
        }

        for character in inner {
            if character == "\\" && isInString {
                escaped.toggle()
                current.append(character)
                continue
            }
            if character == "\"" && !escaped {
                isInString.toggle()
            }
            if character == "," && !isInString {
                try flush()
                escaped = false
                continue
            }
            escaped = false
            current.append(character)
        }
        try flush()

        if isInString {
            throw SimpleTOMLError.invalidArray(line: lineNumber, value: rawValue)
        }

        return values
    }
}

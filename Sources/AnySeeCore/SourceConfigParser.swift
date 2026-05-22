import Foundation

public enum SourceConfigParserError: Error, LocalizedError, Equatable {
    case unknownTable(line: Int, table: String)
    case missingRequiredField(String)
    case invalidEnum(field: String, value: String)
    case nestedActionWithoutSignal(line: Int)

    public var errorDescription: String? {
        switch self {
        case .unknownTable(let line, let table):
            return "Line \(line) uses an unsupported table: \(table)"
        case .missingRequiredField(let field):
            return "Missing required field: \(field)"
        case .invalidEnum(let field, let value):
            return "Invalid value for \(field): \(value)"
        case .nestedActionWithoutSignal(let line):
            return "Line \(line) defines a signal action before a signal item."
        }
    }
}

public enum SourceConfigParser {
    private enum Context {
        case root
        case refresh
        case http
        case script
        case signal
        case action
    }

    private struct ParsedSignal {
        var fields: [String: TOMLValue] = [:]
        var actions: [[String: TOMLValue]] = []
    }

    public static func parseSourceConfig(_ contents: String, sourceFilePath: String? = nil) throws -> SignalSource {
        var root: [String: TOMLValue] = [:]
        var refresh: [String: TOMLValue] = [:]
        var http: [String: TOMLValue] = [:]
        var script: [String: TOMLValue] = [:]
        var signals: [ParsedSignal] = []
        var currentSignal: ParsedSignal?
        var currentAction: [String: TOMLValue]?
        var context: Context = .root

        func flushAction() {
            guard let action = currentAction else { return }
            if currentSignal == nil { currentSignal = ParsedSignal() }
            currentSignal?.actions.append(action)
            currentAction = nil
        }

        func flushSignal() {
            flushAction()
            guard let signal = currentSignal else { return }
            signals.append(signal)
            currentSignal = nil
        }

        for (offset, rawLine) in contents.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let lineNumber = offset + 1
            let line = SimpleTOML.stripComment(from: String(rawLine))
            guard !line.isEmpty else { continue }

            if line.hasPrefix("[[") && line.hasSuffix("]]") {
                let table = line.dropFirst(2).dropLast(2).trimmingCharacters(in: .whitespacesAndNewlines)
                switch table {
                case "signal":
                    flushSignal()
                    currentSignal = ParsedSignal()
                    context = .signal
                case "signal.action":
                    guard currentSignal != nil else {
                        throw SourceConfigParserError.nestedActionWithoutSignal(line: lineNumber)
                    }
                    flushAction()
                    currentAction = [:]
                    context = .action
                default:
                    throw SourceConfigParserError.unknownTable(line: lineNumber, table: table)
                }
                continue
            }

            if line.hasPrefix("[") && line.hasSuffix("]") {
                flushAction()
                let table = line.dropFirst().dropLast().trimmingCharacters(in: .whitespacesAndNewlines)
                switch table {
                case "refresh": context = .refresh
                case "http": context = .http
                case "script": context = .script
                default: throw SourceConfigParserError.unknownTable(line: lineNumber, table: table)
                }
                continue
            }

            let (key, value) = try SimpleTOML.parseAssignment(line, lineNumber: lineNumber)
            switch context {
            case .root:
                root[key] = value
            case .refresh:
                refresh[key] = value
            case .http:
                http[key] = value
            case .script:
                script[key] = value
            case .signal:
                if currentSignal == nil { currentSignal = ParsedSignal() }
                currentSignal?.fields[key] = value
            case .action:
                currentAction?[key] = value
            }
        }

        flushSignal()

        let id = try requiredString("id", in: root)
        let kindString = string("kind", in: root, default: "manual")
        guard let kind = SignalSourceKind(rawValue: kindString) else {
            throw SourceConfigParserError.invalidEnum(field: "kind", value: kindString)
        }

        let name = string("name", in: root, default: id)
        let enabled = bool("enabled", in: root, default: true)
        let refreshPolicy = try parseRefreshPolicy(refresh)
        let manualSignals = try signals.map { try parseSignal($0, defaultSourceID: id) }

        var httpOptions: HTTPSourceOptions?
        if kind == .http {
            httpOptions = try parseHTTPOptions(http, sourceID: id)
        }

        var scriptOptions: ScriptSourceOptions?
        if kind == .script {
            scriptOptions = try parseScriptOptions(script)
        }

        return SignalSource(
            id: id,
            name: name,
            kind: kind,
            enabled: enabled,
            refreshPolicy: refreshPolicy,
            manualSignals: manualSignals,
            http: httpOptions,
            script: scriptOptions,
            sourceFilePath: sourceFilePath
        )
    }

    public static func parseSettings(_ contents: String) throws -> AnySeeSettings {
        var root: [String: TOMLValue] = [:]

        for (offset, rawLine) in contents.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let lineNumber = offset + 1
            let line = SimpleTOML.stripComment(from: String(rawLine))
            guard !line.isEmpty else { continue }
            if line.hasPrefix("[") {
                throw SourceConfigParserError.unknownTable(line: lineNumber, table: line)
            }
            let (key, value) = try SimpleTOML.parseAssignment(line, lineNumber: lineNumber)
            root[key] = value
        }

        return AnySeeSettings(
            appName: string("app_name", in: root, default: "AnySee"),
            quietByDefault: bool("quiet_by_default", in: root, default: true),
            maxSignalsInPopover: int("max_signals_in_popover", in: root, default: 30)
        )
    }

    private static func parseRefreshPolicy(_ values: [String: TOMLValue]) throws -> RefreshPolicy {
        guard !values.isEmpty else { return .manual }
        let kindString = string("kind", in: values, default: "manual")
        guard let kind = RefreshPolicyKind(rawValue: kindString) else {
            throw SourceConfigParserError.invalidEnum(field: "refresh.kind", value: kindString)
        }
        return RefreshPolicy(
            kind: kind,
            intervalSeconds: int("interval_seconds", in: values, default: 0) > 0 ? int("interval_seconds", in: values, default: 0) : nil,
            schedule: optionalString("schedule", in: values)
        )
    }

    private static func parseHTTPOptions(_ values: [String: TOMLValue], sourceID: String) throws -> HTTPSourceOptions {
        let url = try requiredString("http.url", in: values, actualKey: "url")
        return HTTPSourceOptions(
            url: url,
            method: string("method", in: values, default: "GET"),
            timeoutSeconds: int("timeout_seconds", in: values, default: 10),
            expectedStatus: int("expected_status", in: values, default: 200),
            signalOnStatusMismatch: bool("signal_on_status_mismatch", in: values, default: true),
            jsonPath: optionalString("json_path", in: values),
            equals: optionalString("equals", in: values),
            notEquals: optionalString("not_equals", in: values),
            title: string("title", in: values, default: "\(sourceID) needs attention"),
            body: string("body", in: values, default: "HTTP source matched its attention condition."),
            priority: try priority("priority", in: values, default: .high),
            state: try state("state", in: values, default: .needsAttention)
        )
    }

    private static func parseScriptOptions(_ values: [String: TOMLValue]) throws -> ScriptSourceOptions {
        ScriptSourceOptions(
            path: try requiredString("script.path", in: values, actualKey: "path"),
            timeoutSeconds: int("timeout_seconds", in: values, default: 15),
            workingDirectory: optionalString("working_directory", in: values)
        )
    }

    private static func parseSignal(_ parsed: ParsedSignal, defaultSourceID: String) throws -> SignalItem {
        let fields = parsed.fields
        let actions = try parsed.actions.map(parseAction)
        return SignalItem(
            id: try requiredString("signal.id", in: fields, actualKey: "id"),
            title: try requiredString("signal.title", in: fields, actualKey: "title"),
            body: string("body", in: fields, default: ""),
            priority: try priority("priority", in: fields, default: .normal),
            state: try state("state", in: fields, default: .needsAttention),
            source: string("source", in: fields, default: defaultSourceID),
            url: optionalString("url", in: fields),
            actions: actions
        )
    }

    private static func parseAction(_ values: [String: TOMLValue]) throws -> SignalAction {
        let typeString = try requiredString("signal.action.type", in: values, actualKey: "type")
        guard let type = SignalActionType(rawValue: typeString) else {
            throw SourceConfigParserError.invalidEnum(field: "signal.action.type", value: typeString)
        }
        return SignalAction(
            label: try requiredString("signal.action.label", in: values, actualKey: "label"),
            type: type,
            url: optionalString("url", in: values),
            text: optionalString("text", in: values),
            command: optionalString("command", in: values),
            arguments: values["arguments"]?.stringArrayValue ?? [],
            durationMinutes: optionalInt("duration_minutes", in: values)
        )
    }

    private static func requiredString(_ displayKey: String, in values: [String: TOMLValue], actualKey: String? = nil) throws -> String {
        let key = actualKey ?? displayKey
        guard let value = optionalString(key, in: values), !value.isEmpty else {
            throw SourceConfigParserError.missingRequiredField(displayKey)
        }
        return value
    }

    private static func string(_ key: String, in values: [String: TOMLValue], default defaultValue: String) -> String {
        optionalString(key, in: values) ?? defaultValue
    }

    private static func optionalString(_ key: String, in values: [String: TOMLValue]) -> String? {
        values[key]?.stringValue
    }

    private static func bool(_ key: String, in values: [String: TOMLValue], default defaultValue: Bool) -> Bool {
        values[key]?.boolValue ?? defaultValue
    }

    private static func int(_ key: String, in values: [String: TOMLValue], default defaultValue: Int) -> Int {
        values[key]?.intValue ?? defaultValue
    }

    private static func optionalInt(_ key: String, in values: [String: TOMLValue]) -> Int? {
        values[key]?.intValue
    }

    private static func priority(_ key: String, in values: [String: TOMLValue], default defaultValue: SignalPriority) throws -> SignalPriority {
        guard let value = optionalString(key, in: values) else { return defaultValue }
        guard let priority = SignalPriority(rawValue: value) else {
            throw SourceConfigParserError.invalidEnum(field: key, value: value)
        }
        return priority
    }

    private static func state(_ key: String, in values: [String: TOMLValue], default defaultValue: SignalState) throws -> SignalState {
        guard let value = optionalString(key, in: values) else { return defaultValue }
        guard let state = SignalState(rawValue: value) else {
            throw SourceConfigParserError.invalidEnum(field: key, value: value)
        }
        return state
    }
}

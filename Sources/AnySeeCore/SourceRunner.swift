import Foundation

public struct SourceRunner: Sendable {
    public init() {}

    public func run(_ source: SignalSource, paths: AnySeeConfigPaths = .defaults()) -> SourceRunResult {
        guard source.enabled else {
            return SourceRunResult(sourceID: source.id)
        }

        switch source.kind {
        case .manual:
            return runManual(source)
        case .http:
            return runHTTP(source)
        case .script:
            return runScript(source, paths: paths)
        }
    }

    public static func resolveScriptURL(_ path: String, paths: AnySeeConfigPaths) -> URL {
        if path.hasPrefix("/") {
            return URL(fileURLWithPath: path)
        }
        return paths.scriptsDirectory.appendingPathComponent(path)
    }

    private func runManual(_ source: SignalSource) -> SourceRunResult {
        let items = source.manualSignals.map { item in
            var copy = item
            if copy.source.isEmpty {
                copy.source = source.id
            }
            return copy
        }
        return SourceRunResult(sourceID: source.id, items: items)
    }

    private func runHTTP(_ source: SignalSource) -> SourceRunResult {
        guard let options = source.http else {
            return SourceRunResult(
                sourceID: source.id,
                issues: [.init(severity: .error, sourceID: source.id, message: "HTTP source is missing [http] configuration.")]
            )
        }
        guard let url = URL(string: options.url) else {
            return SourceRunResult(
                sourceID: source.id,
                issues: [.init(severity: .error, sourceID: source.id, message: "Invalid URL: \(options.url)")]
            )
        }

        var request = URLRequest(url: url, timeoutInterval: TimeInterval(options.timeoutSeconds))
        request.httpMethod = options.method

        let box = HTTPResponseBox()
        let semaphore = DispatchSemaphore(value: 0)
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            box.data = data
            box.response = response as? HTTPURLResponse
            box.error = error
            semaphore.signal()
        }
        task.resume()

        if semaphore.wait(timeout: .now() + .seconds(options.timeoutSeconds)) == .timedOut {
            task.cancel()
            return attentionResult(
                sourceID: source.id,
                options: options,
                bodyOverride: "HTTP request timed out after \(options.timeoutSeconds)s."
            )
        }

        if let error = box.error {
            return attentionResult(sourceID: source.id, options: options, bodyOverride: error.localizedDescription)
        }

        guard let response = box.response else {
            return attentionResult(sourceID: source.id, options: options, bodyOverride: "No HTTP response was received.")
        }

        if response.statusCode != options.expectedStatus && options.signalOnStatusMismatch {
            return attentionResult(
                sourceID: source.id,
                options: options,
                bodyOverride: "Expected HTTP \(options.expectedStatus), got HTTP \(response.statusCode)."
            )
        }

        if let jsonPath = options.jsonPath {
            guard let data = box.data else {
                return attentionResult(sourceID: source.id, options: options, bodyOverride: "No response body was received.")
            }
            do {
                let value = try JSONPathReader.value(in: data, path: jsonPath)
                let valueString = JSONPathReader.stringValue(value)
                if shouldSignal(valueString: valueString, options: options) {
                    let body = options.body.replacingOccurrences(of: "{value}", with: valueString ?? "nil")
                    return attentionResult(sourceID: source.id, options: options, bodyOverride: body)
                }
            } catch {
                return attentionResult(sourceID: source.id, options: options, bodyOverride: "Could not read JSON path `\(jsonPath)`: \(error.localizedDescription)")
            }
        }

        return SourceRunResult(sourceID: source.id)
    }

    private func runScript(_ source: SignalSource, paths: AnySeeConfigPaths) -> SourceRunResult {
        guard let options = source.script else {
            return SourceRunResult(
                sourceID: source.id,
                issues: [.init(severity: .error, sourceID: source.id, message: "Script source is missing [script] configuration.")]
            )
        }

        let scriptURL = Self.resolveScriptURL(options.path, paths: paths)
        guard FileManager.default.fileExists(atPath: scriptURL.path) else {
            return SourceRunResult(
                sourceID: source.id,
                issues: [.init(severity: .error, sourceID: source.id, message: "Script does not exist: \(scriptURL.path)")]
            )
        }

        let process = Process()
        process.executableURL = scriptURL
        if let workingDirectory = options.workingDirectory {
            process.currentDirectoryURL = workingDirectory.hasPrefix("/")
                ? URL(fileURLWithPath: workingDirectory)
                : paths.rootDirectory.appendingPathComponent(workingDirectory, isDirectory: true)
        } else {
            process.currentDirectoryURL = paths.rootDirectory
        }

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
        } catch {
            return SourceRunResult(
                sourceID: source.id,
                issues: [.init(severity: .error, sourceID: source.id, message: "Could not run script: \(error.localizedDescription)")]
            )
        }

        let deadline = Date().addingTimeInterval(TimeInterval(options.timeoutSeconds))
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }

        if process.isRunning {
            process.terminate()
            process.waitUntilExit()
            return SourceRunResult(
                sourceID: source.id,
                issues: [.init(severity: .error, sourceID: source.id, message: "Script timed out after \(options.timeoutSeconds)s.")]
            )
        }

        let stdoutData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            let message = stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "Script exited with code \(process.terminationStatus)."
                : stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return SourceRunResult(
                sourceID: source.id,
                issues: [.init(severity: .error, sourceID: source.id, message: message)],
                rawOutput: stdout
            )
        }

        do {
            let items = try decodeSignalOutput(stdoutData, defaultSourceID: source.id)
            let issues = items.flatMap { ConfigStore(paths: paths).validate(signal: $0, sourceID: source.id) }
            return SourceRunResult(sourceID: source.id, items: items, issues: issues, rawOutput: stdout)
        } catch {
            return SourceRunResult(
                sourceID: source.id,
                issues: [.init(severity: .error, sourceID: source.id, message: "Script stdout was not valid Signal JSON: \(error.localizedDescription)")],
                rawOutput: stdout
            )
        }
    }

    private func decodeSignalOutput(_ data: Data, defaultSourceID: String) throws -> [SignalItem] {
        let decoder = JSONDecoder()
        if let array = try? decoder.decode([SignalItem].self, from: data) {
            return array.map { filledSource($0, defaultSourceID: defaultSourceID) }
        }
        let item = try decoder.decode(SignalItem.self, from: data)
        return [filledSource(item, defaultSourceID: defaultSourceID)]
    }

    private func filledSource(_ item: SignalItem, defaultSourceID: String) -> SignalItem {
        var copy = item
        if copy.source.isEmpty {
            copy.source = defaultSourceID
        }
        return copy
    }

    private func attentionResult(sourceID: String, options: HTTPSourceOptions, bodyOverride: String? = nil) -> SourceRunResult {
        let item = SignalItem(
            id: "\(sourceID)-http",
            title: options.title,
            body: bodyOverride ?? options.body,
            priority: options.priority,
            state: options.state,
            source: sourceID,
            url: options.url,
            actions: [
                SignalAction(label: "Open URL", type: .openURL, url: options.url),
                SignalAction(label: "Dismiss", type: .dismiss)
            ]
        )
        return SourceRunResult(sourceID: sourceID, items: [item])
    }

    private func shouldSignal(valueString: String?, options: HTTPSourceOptions) -> Bool {
        if let expected = options.equals {
            return valueString == expected
        }
        if let rejected = options.notEquals {
            return valueString != rejected
        }
        return valueString == "true"
    }
}

private final class HTTPResponseBox: @unchecked Sendable {
    var data: Data?
    var response: HTTPURLResponse?
    var error: Error?
}

public enum JSONPathReader {
    public enum Error: Swift.Error, LocalizedError, Equatable {
        case invalidJSON
        case missingKey(String)
        case invalidArrayIndex(String)

        public var errorDescription: String? {
            switch self {
            case .invalidJSON:
                return "Response body is not JSON."
            case .missingKey(let key):
                return "Missing key \(key)."
            case .invalidArrayIndex(let index):
                return "Invalid array index \(index)."
            }
        }
    }

    public static func value(in data: Data, path: String) throws -> Any? {
        let object = try JSONSerialization.jsonObject(with: data)
        return try value(in: object, components: path.split(separator: ".").map(String.init))
    }

    public static func stringValue(_ value: Any?) -> String? {
        switch value {
        case let value as String:
            return value
        case let value as Bool:
            return value ? "true" : "false"
        case let value as NSNumber:
            return value.stringValue
        case Optional<Any>.none:
            return nil
        default:
            return String(describing: value!)
        }
    }

    private static func value(in object: Any, components: [String]) throws -> Any? {
        guard let first = components.first else { return object }
        let rest = Array(components.dropFirst())

        if let dictionary = object as? [String: Any] {
            guard let nestedValue = dictionary[first] else {
                throw Error.missingKey(first)
            }
            return try value(in: nestedValue, components: rest)
        }

        if let array = object as? [Any] {
            guard let index = Int(first), array.indices.contains(index) else {
                throw Error.invalidArrayIndex(first)
            }
            return try value(in: array[index], components: rest)
        }

        throw Error.missingKey(first)
    }
}

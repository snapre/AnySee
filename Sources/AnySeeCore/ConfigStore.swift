import Foundation

public struct AnySeeConfigPaths: Equatable, Sendable {
    public var rootDirectory: URL
    public var mainConfigFile: URL
    public var sourcesDirectory: URL
    public var scriptsDirectory: URL
    public var schemasDirectory: URL
    public var examplesDirectory: URL
    public var agentsGuideFile: URL

    public init(rootDirectory: URL) {
        self.rootDirectory = rootDirectory
        mainConfigFile = rootDirectory.appendingPathComponent("anysee.toml")
        sourcesDirectory = rootDirectory.appendingPathComponent("sources", isDirectory: true)
        scriptsDirectory = rootDirectory.appendingPathComponent("scripts", isDirectory: true)
        schemasDirectory = rootDirectory.appendingPathComponent("schemas", isDirectory: true)
        examplesDirectory = rootDirectory.appendingPathComponent("examples", isDirectory: true)
        agentsGuideFile = rootDirectory.appendingPathComponent("AGENTS.md")
    }

    public static func defaults(fileManager: FileManager = .default) -> AnySeeConfigPaths {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
        return AnySeeConfigPaths(rootDirectory: appSupport.appendingPathComponent("AnySee", isDirectory: true))
    }
}

public struct ConfigStore: Sendable {
    public var paths: AnySeeConfigPaths

    public init(paths: AnySeeConfigPaths = .defaults()) {
        self.paths = paths
    }

    public func ensureBootstrapped(fileManager: FileManager = .default) throws {
        try fileManager.createDirectory(at: paths.rootDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: paths.sourcesDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: paths.scriptsDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: paths.schemasDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: paths.examplesDirectory, withIntermediateDirectories: true)

        try writeIfMissing(DefaultConfigTemplates.mainConfig, to: paths.mainConfigFile, fileManager: fileManager)
        try writeIfMissing(DefaultConfigTemplates.manualSource, to: paths.sourcesDirectory.appendingPathComponent("manual.toml"), fileManager: fileManager)
        try writeIfMissing(DefaultConfigTemplates.httpSource, to: paths.examplesDirectory.appendingPathComponent("http-source.toml"), fileManager: fileManager)
        try writeIfMissing(DefaultConfigTemplates.scriptSource, to: paths.examplesDirectory.appendingPathComponent("script-source.toml"), fileManager: fileManager)
        try writeIfMissing(DefaultConfigTemplates.manualSource, to: paths.examplesDirectory.appendingPathComponent("manual-source.toml"), fileManager: fileManager)
        try writeIfMissing(DefaultConfigTemplates.sampleSignalJSON, to: paths.examplesDirectory.appendingPathComponent("signal.json"), fileManager: fileManager)
        try writeIfMissing(DefaultConfigTemplates.signalSchema, to: paths.schemasDirectory.appendingPathComponent("signal.schema.json"), fileManager: fileManager)
        try writeIfMissing(DefaultConfigTemplates.agentsGuide, to: paths.agentsGuideFile, fileManager: fileManager)
        try writeIfMissing(DefaultConfigTemplates.sampleScript, to: paths.scriptsDirectory.appendingPathComponent("sample-signal.sh"), fileManager: fileManager)

        let sampleScriptURL = paths.scriptsDirectory.appendingPathComponent("sample-signal.sh")
        try? fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: sampleScriptURL.path)
    }

    public func load(fileManager: FileManager = .default) throws -> AnySeeConfiguration {
        let settings = try loadSettings(fileManager: fileManager)
        let sources = try loadSources(fileManager: fileManager)
        return AnySeeConfiguration(settings: settings, sources: sources)
    }

    public func loadSettings(fileManager: FileManager = .default) throws -> AnySeeSettings {
        guard fileManager.fileExists(atPath: paths.mainConfigFile.path) else {
            return AnySeeSettings()
        }
        let contents = try String(contentsOf: paths.mainConfigFile, encoding: .utf8)
        return try SourceConfigParser.parseSettings(contents)
    }

    public func loadSources(fileManager: FileManager = .default) throws -> [SignalSource] {
        guard fileManager.fileExists(atPath: paths.sourcesDirectory.path) else {
            return []
        }

        let fileURLs = try fileManager.contentsOfDirectory(
            at: paths.sourcesDirectory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        .filter { $0.pathExtension == "toml" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }

        return try fileURLs.map { fileURL in
            let contents = try String(contentsOf: fileURL, encoding: .utf8)
            return try SourceConfigParser.parseSourceConfig(contents, sourceFilePath: fileURL.path)
        }
    }

    public func source(named query: String, in configuration: AnySeeConfiguration) -> SignalSource? {
        configuration.sources.first { source in
            if source.id == query { return true }
            guard let sourceFilePath = source.sourceFilePath else { return false }
            let fileURL = URL(fileURLWithPath: sourceFilePath)
            return fileURL.deletingPathExtension().lastPathComponent == query || fileURL.lastPathComponent == query
        }
    }

    public func validate(_ configuration: AnySeeConfiguration, fileManager: FileManager = .default) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        var seenIDs: Set<String> = []

        if !fileManager.fileExists(atPath: paths.rootDirectory.path) {
            issues.append(.init(severity: .error, message: "Config directory does not exist. Run `anysee doctor` to create it."))
        }

        if !fileManager.fileExists(atPath: paths.mainConfigFile.path) {
            issues.append(.init(severity: .warning, message: "Missing anysee.toml; defaults will be used."))
        }

        for source in configuration.sources {
            if !seenIDs.insert(source.id).inserted {
                issues.append(.init(severity: .error, sourceID: source.id, message: "Duplicate source id."))
            }
            if source.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                issues.append(.init(severity: .error, sourceID: source.id, message: "Source id cannot be empty."))
            }
            if source.kind == .manual && source.manualSignals.isEmpty {
                issues.append(.init(severity: .warning, sourceID: source.id, message: "Manual source has no signal items."))
            }
            if source.kind == .http && source.http == nil {
                issues.append(.init(severity: .error, sourceID: source.id, message: "HTTP source is missing [http] configuration."))
            }
            if source.kind == .script {
                if let script = source.script {
                    let scriptURL = SourceRunner.resolveScriptURL(script.path, paths: paths)
                    if !fileManager.fileExists(atPath: scriptURL.path) {
                        issues.append(.init(severity: .error, sourceID: source.id, message: "Script does not exist: \(scriptURL.path)"))
                    }
                    if script.path.hasPrefix("/") {
                        issues.append(.init(severity: .warning, sourceID: source.id, message: "Script path is absolute; relative paths under scripts/ are easier for AI agents to review."))
                    }
                } else {
                    issues.append(.init(severity: .error, sourceID: source.id, message: "Script source is missing [script] configuration."))
                }
            }

            for signal in source.manualSignals {
                issues.append(contentsOf: validate(signal: signal, sourceID: source.id))
            }
        }

        return issues
    }

    public func validate(signal: SignalItem, sourceID: String) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        if signal.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(.init(severity: .error, sourceID: sourceID, message: "Signal id cannot be empty."))
        }
        if signal.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(.init(severity: .error, sourceID: sourceID, message: "Signal title cannot be empty."))
        }
        for action in signal.actions {
            switch action.type {
            case .openURL:
                if action.url?.isEmpty ?? true {
                    issues.append(.init(severity: .error, sourceID: sourceID, message: "Action `\(action.label)` requires url."))
                }
            case .copyText:
                if action.text?.isEmpty ?? true {
                    issues.append(.init(severity: .error, sourceID: sourceID, message: "Action `\(action.label)` requires text."))
                }
            case .runCommand:
                if action.command?.isEmpty ?? true {
                    issues.append(.init(severity: .error, sourceID: sourceID, message: "Action `\(action.label)` requires command."))
                }
            case .dismiss, .snooze:
                break
            }
        }
        return issues
    }

    private func writeIfMissing(_ contents: String, to url: URL, fileManager: FileManager) throws {
        guard !fileManager.fileExists(atPath: url.path) else { return }
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }
}

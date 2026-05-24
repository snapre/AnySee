import Foundation

public enum RunCommandResolutionError: Error, LocalizedError, Equatable {
    case missingCommand
    case unsafeRelativePath(String)
    case relativePathEscapesScripts(String)

    public var errorDescription: String? {
        switch self {
        case .missingCommand:
            return "Command is required."
        case .unsafeRelativePath(let command):
            return "Relative command path is not safe: \(command)"
        case .relativePathEscapesScripts(let command):
            return "Relative command must resolve inside scripts/: \(command)"
        }
    }
}

public enum RunCommandResolver {
    public static func resolveExecutableURL(command: String?, paths: AnySeeConfigPaths) throws -> URL {
        guard let command = command?.trimmingCharacters(in: .whitespacesAndNewlines), !command.isEmpty else {
            throw RunCommandResolutionError.missingCommand
        }

        if command.hasPrefix("/") {
            return URL(fileURLWithPath: command).standardizedFileURL.resolvingSymlinksInPath()
        }

        try validateRelativePath(command)

        let scriptsDirectory = paths.scriptsDirectory.standardizedFileURL.resolvingSymlinksInPath()
        let candidatePath = (scriptsDirectory.path as NSString).appendingPathComponent(command)
        let candidateURL = URL(fileURLWithPath: candidatePath).standardizedFileURL.resolvingSymlinksInPath()

        guard isContained(candidateURL, in: scriptsDirectory) else {
            throw RunCommandResolutionError.relativePathEscapesScripts(command)
        }

        return candidateURL
    }

    private static func validateRelativePath(_ command: String) throws {
        let components = command.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard !components.isEmpty else {
            throw RunCommandResolutionError.unsafeRelativePath(command)
        }

        for component in components where component.isEmpty || component == "." || component == ".." {
            throw RunCommandResolutionError.unsafeRelativePath(command)
        }
    }

    private static func isContained(_ url: URL, in directory: URL) -> Bool {
        let path = url.standardizedFileURL.path
        let directoryPath = directory.standardizedFileURL.path
        return path == directoryPath || path.hasPrefix(directoryPath + "/")
    }
}

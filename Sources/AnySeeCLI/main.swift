import AnySeeCore
import Foundation

@main
struct AnySeeCLI {
    static func main() {
        let exitCode = run(arguments: Array(CommandLine.arguments.dropFirst()))
        Foundation.exit(Int32(exitCode))
    }

    static func run(arguments: [String]) -> Int {
        guard let command = arguments.first else {
            printHelp()
            return 0
        }

        let paths = AnySeeConfigPaths.defaults()
        let store = ConfigStore(paths: paths)

        do {
            switch command {
            case "help", "--help", "-h":
                printHelp()
                return 0
            case "doctor":
                try store.ensureBootstrapped()
                let configuration = try store.load()
                let issues = store.validate(configuration)
                print("Config: \(paths.rootDirectory.path)")
                print("Sources: \(configuration.sources.count)")
                printIssues(issues)
                return issues.contains(where: { $0.severity == .error }) ? 1 : 0
            case "validate":
                let configuration = try store.load()
                let issues = store.validate(configuration)
                printIssues(issues)
                return issues.contains(where: { $0.severity == .error }) ? 1 : 0
            case "preview":
                guard arguments.count >= 2 else {
                    print("Missing source id.")
                    return 2
                }
                let configuration = try store.load()
                guard let source = store.source(named: arguments[1], in: configuration) else {
                    print("Source not found: \(arguments[1])")
                    return 2
                }
                let result = SourceRunner().run(source, paths: paths)
                printPreview(result)
                return result.issues.contains(where: { $0.severity == .error }) ? 1 : 0
            case "run":
                guard arguments.count >= 2 else {
                    print("Missing source id.")
                    return 2
                }
                let configuration = try store.load()
                guard let source = store.source(named: arguments[1], in: configuration) else {
                    print("Source not found: \(arguments[1])")
                    return 2
                }
                let result = SourceRunner().run(source, paths: paths)
                if !result.issues.isEmpty {
                    printIssues(result.issues)
                    return result.issues.contains(where: { $0.severity == .error }) ? 1 : 0
                }
                printJSON(result.items)
                return 0
            case "prompt":
                let configuration = try? store.load()
                print(AIConfigurationPrompt.build(paths: paths, configuration: configuration))
                return 0
            default:
                print("Unknown command: \(command)")
                printHelp()
                return 2
            }
        } catch {
            print("Error: \(error.localizedDescription)")
            return 1
        }
    }

    private static func printHelp() {
        print("""
        anysee - local AnySee configuration tools

        Commands:
          anysee doctor              Create/check local config directory
          anysee validate            Validate anysee.toml and sources/*.toml
          anysee preview <source>    Run a source and print a human summary
          anysee run <source>        Run a source and print Signal JSON
          anysee prompt              Print the Configure with AI prompt
        """)
    }

    private static func printIssues(_ issues: [ValidationIssue]) {
        guard !issues.isEmpty else {
            print("OK")
            return
        }
        for issue in issues {
            let prefix = issue.sourceID.map { "[\($0)] " } ?? ""
            print("\(issue.severity.rawValue.uppercased()): \(prefix)\(issue.message)")
        }
    }

    private static func printPreview(_ result: SourceRunResult) {
        print("Source: \(result.sourceID)")
        print("Signals: \(result.items.count)")
        printIssues(result.issues)
        for item in SignalFeed.focused(result.items) {
            print("- [\(item.priority.rawValue)/\(item.state.rawValue)] \(item.title)")
            if !item.body.isEmpty {
                print("  \(item.body)")
            }
        }
    }

    private static func printJSON(_ items: [SignalItem]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        do {
            let data = try encoder.encode(items)
            print(String(data: data, encoding: .utf8) ?? "[]")
        } catch {
            print("[]")
        }
    }
}

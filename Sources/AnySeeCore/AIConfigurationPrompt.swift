import Foundation

public enum AIConfigurationPrompt {
    public static func build(paths: AnySeeConfigPaths = .defaults(), configuration: AnySeeConfiguration? = nil) -> String {
        let sourcesSummary: String
        if let configuration {
            sourcesSummary = configuration.sources.map { source in
                "- \(source.id) (\(source.kind.rawValue), enabled: \(source.enabled), refresh: \(source.refreshPolicy.kind.rawValue))"
            }.joined(separator: "\n")
        } else {
            sourcesSummary = "- No configuration loaded."
        }

        return """
        You are helping me configure AnySee, a local-first macOS menu bar attention center.

        Product rules:
        - Show only signals that deserve attention.
        - Keep configuration local and auditable.
        - Do not add Gmail, Slack, GitHub, OAuth, cloud sync, or plugin marketplace behavior.
        - Do not write credentials, tokens, cookies, passwords, or secrets into config files.
        - Prefer relative script paths under scripts/.
        - Prefer relative run_command commands under scripts/; they are resolved there and must not traverse outside it.
        - Script stdout must be one Signal JSON object or an array of Signal JSON objects.

        Local config directory:
        \(paths.rootDirectory.path)

        Current sources:
        \(sourcesSummary)

        Source types:
        - manual: static [[signal]] entries in TOML.
        - http: request a URL, compare status code or a JSON field, produce a signal only when attention is needed.
        - script: run a local executable from scripts/ and parse stdout as Signal JSON.

        Signal JSON example:
        \(DefaultConfigTemplates.sampleSignalJSON)

        Please produce only the files or patches needed under:
        - anysee.toml
        - sources/*.toml
        - scripts/*

        Validate with:
        swift run anysee validate
        swift run anysee preview <source-id>
        swift run anysee run <source-id>
        """
    }
}

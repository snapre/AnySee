import XCTest
@testable import AnySeeCore

final class ConfigStoreTests: XCTestCase {
    func testBootstrapCreatesExpectedFilesAndLoadsDefaultSource() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("AnySeeConfig-\(UUID().uuidString)", isDirectory: true)
        let paths = AnySeeConfigPaths(rootDirectory: tempRoot)
        let store = ConfigStore(paths: paths)

        try store.ensureBootstrapped()
        let configuration = try store.load()
        let issues = store.validate(configuration)

        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.mainConfigFile.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.agentsGuideFile.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.schemasDirectory.appendingPathComponent("signal.schema.json").path))
        XCTAssertEqual(configuration.sources.map(\.id), ["welcome"])
        XCTAssertFalse(issues.contains(where: { $0.severity == .error }))

        try? FileManager.default.removeItem(at: tempRoot)
    }

    func testAIPromptMentionsCurrentSourcesAndSecurity() {
        let configuration = AnySeeConfiguration(
            sources: [
                SignalSource(id: "sample", name: "Sample", kind: .manual)
            ]
        )

        let prompt = AIConfigurationPrompt.build(
            paths: AnySeeConfigPaths(rootDirectory: URL(fileURLWithPath: "/tmp/AnySee")),
            configuration: configuration
        )

        XCTAssertTrue(prompt.contains("sample (manual"))
        XCTAssertTrue(prompt.contains("Do not write credentials"))
        XCTAssertTrue(prompt.contains("swift run anysee validate"))
    }
}

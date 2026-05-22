import XCTest
@testable import AnySeeCore

final class SourceRunnerTests: XCTestCase {
    func testManualRunnerReturnsAttentionSignals() {
        let source = SignalSource(
            id: "manual",
            name: "Manual",
            kind: .manual,
            manualSignals: [
                SignalItem(id: "ok", title: "OK", priority: .low, state: .ok, source: "manual"),
                SignalItem(id: "bad", title: "Bad", priority: .high, state: .needsAttention, source: "manual")
            ]
        )

        let result = SourceRunner().run(source)

        XCTAssertEqual(result.items.count, 2)
        XCTAssertEqual(SignalFeed.focused(result.items).map(\.id), ["bad"])
    }

    func testScriptRunnerDecodesSingleSignal() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("AnySeeTests-\(UUID().uuidString)", isDirectory: true)
        let paths = AnySeeConfigPaths(rootDirectory: tempRoot)
        try FileManager.default.createDirectory(at: paths.scriptsDirectory, withIntermediateDirectories: true)
        let scriptURL = paths.scriptsDirectory.appendingPathComponent("signal.sh")
        try """
        #!/bin/sh
        printf '%s\\n' '{"id":"from-script","title":"From script","priority":"high","state":"needs_attention","source":"script"}'
        """.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        let source = SignalSource(
            id: "script",
            name: "Script",
            kind: .script,
            script: ScriptSourceOptions(path: "signal.sh", timeoutSeconds: 5)
        )

        let result = SourceRunner().run(source, paths: paths)

        XCTAssertTrue(result.issues.isEmpty)
        XCTAssertEqual(result.items.map(\.id), ["from-script"])
        XCTAssertEqual(result.items.first?.priority, .high)

        try? FileManager.default.removeItem(at: tempRoot)
    }

    func testJSONPathReaderReadsNestedValues() throws {
        let data = #"{"status":"degraded","checks":[{"name":"db","ok":false}]}"#.data(using: .utf8)!

        XCTAssertEqual(try JSONPathReader.stringValue(JSONPathReader.value(in: data, path: "status")), "degraded")
        XCTAssertEqual(try JSONPathReader.stringValue(JSONPathReader.value(in: data, path: "checks.0.ok")), "false")
    }
}

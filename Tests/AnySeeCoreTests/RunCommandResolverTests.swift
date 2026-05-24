import XCTest
@testable import AnySeeCore

final class RunCommandResolverTests: XCTestCase {
    func testResolvesRelativeExecutableInsideScriptsDirectory() throws {
        let paths = try makePaths()
        defer { try? FileManager.default.removeItem(at: paths.rootDirectory) }

        let executableURL = paths.scriptsDirectory.appendingPathComponent("tools/fix.sh")
        try FileManager.default.createDirectory(at: executableURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try writeExecutable(at: executableURL)

        let resolvedURL = try RunCommandResolver.resolveExecutableURL(command: "tools/fix.sh", paths: paths)

        XCTAssertEqual(resolvedURL.path, executableURL.resolvingSymlinksInPath().path)
    }

    func testValidationAcceptsRelativeAndAbsoluteRunCommands() throws {
        let paths = try makePaths()
        defer { try? FileManager.default.removeItem(at: paths.rootDirectory) }

        let relativeExecutable = paths.scriptsDirectory.appendingPathComponent("fix.sh")
        try writeExecutable(at: relativeExecutable)

        let source = SignalSource(
            id: "manual",
            name: "Manual",
            kind: .manual,
            manualSignals: [
                SignalItem(
                    id: "needs-fix",
                    title: "Needs fix",
                    actions: [
                        SignalAction(label: "Run fix", type: .runCommand, command: "fix.sh"),
                        SignalAction(label: "Echo", type: .runCommand, command: "/bin/echo", arguments: ["ok"])
                    ]
                )
            ]
        )

        let issues = ConfigStore(paths: paths).validate(AnySeeConfiguration(sources: [source]))

        XCTAssertFalse(issues.contains(where: { $0.severity == .error }), issues.map(\.message).joined(separator: "\n"))
    }

    func testValidationRejectsRelativeTraversalOutsideScriptsDirectory() throws {
        let paths = try makePaths()
        defer { try? FileManager.default.removeItem(at: paths.rootDirectory) }

        let source = SignalSource(
            id: "manual",
            name: "Manual",
            kind: .manual,
            manualSignals: [
                SignalItem(
                    id: "unsafe",
                    title: "Unsafe",
                    actions: [
                        SignalAction(label: "Run unsafe", type: .runCommand, command: "../outside.sh")
                    ]
                )
            ]
        )

        let issues = ConfigStore(paths: paths).validate(AnySeeConfiguration(sources: [source]))

        XCTAssertTrue(issues.contains { issue in
            issue.severity == .error && issue.message.contains("Relative command path is not safe")
        }, issues.map(\.message).joined(separator: "\n"))
    }

    func testResolverRejectsSymlinkEscapeFromScriptsDirectory() throws {
        let paths = try makePaths()
        defer { try? FileManager.default.removeItem(at: paths.rootDirectory) }

        let outsideExecutable = paths.rootDirectory.appendingPathComponent("outside.sh")
        try writeExecutable(at: outsideExecutable)
        let linkURL = paths.scriptsDirectory.appendingPathComponent("outside-link.sh")
        try FileManager.default.createSymbolicLink(at: linkURL, withDestinationURL: outsideExecutable)

        XCTAssertThrowsError(try RunCommandResolver.resolveExecutableURL(command: "outside-link.sh", paths: paths)) { error in
            XCTAssertEqual(error as? RunCommandResolutionError, .relativePathEscapesScripts("outside-link.sh"))
        }
    }

    private func makePaths() throws -> AnySeeConfigPaths {
        let rootDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AnySeeRunCommand-\(UUID().uuidString)", isDirectory: true)
        let paths = AnySeeConfigPaths(rootDirectory: rootDirectory)
        try FileManager.default.createDirectory(at: paths.scriptsDirectory, withIntermediateDirectories: true)
        return paths
    }

    private func writeExecutable(at url: URL) throws {
        try """
        #!/bin/sh
        exit 0
        """.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }
}

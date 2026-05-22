import XCTest
@testable import AnySeeCore

final class SourceConfigParserTests: XCTestCase {
    func testParsesManualSourceWithActions() throws {
        let source = try SourceConfigParser.parseSourceConfig("""
        id = "backup"
        name = "Backup"
        kind = "manual"
        enabled = true

        [refresh]
        kind = "manual"

        [[signal]]
        id = "backup-failed"
        title = "Backup failed"
        body = "Last backup exited with code 1"
        priority = "high"
        state = "needs_attention"
        source = "backup"
        url = "file:///tmp/backup.log"

        [[signal.action]]
        label = "Open log"
        type = "open_url"
        url = "file:///tmp/backup.log"

        [[signal.action]]
        label = "Later"
        type = "snooze"
        duration_minutes = 45
        """)

        XCTAssertEqual(source.id, "backup")
        XCTAssertEqual(source.kind, .manual)
        XCTAssertEqual(source.refreshPolicy.kind, .manual)
        XCTAssertEqual(source.manualSignals.count, 1)
        XCTAssertEqual(source.manualSignals[0].priority, .high)
        XCTAssertEqual(source.manualSignals[0].actions.count, 2)
        XCTAssertEqual(source.manualSignals[0].actions[1].durationMinutes, 45)
    }

    func testParsesHTTPSourceCondition() throws {
        let source = try SourceConfigParser.parseSourceConfig("""
        id = "health"
        name = "Health"
        kind = "http"

        [refresh]
        kind = "interval"
        interval_seconds = 60

        [http]
        url = "https://example.com/health"
        expected_status = 200
        json_path = "status"
        not_equals = "ok"
        priority = "critical"
        """)

        XCTAssertEqual(source.kind, .http)
        XCTAssertEqual(source.refreshPolicy.intervalSeconds, 60)
        XCTAssertEqual(source.http?.url, "https://example.com/health")
        XCTAssertEqual(source.http?.notEquals, "ok")
        XCTAssertEqual(source.http?.priority, .critical)
    }

    func testRejectsUnknownPriority() {
        XCTAssertThrowsError(try SourceConfigParser.parseSourceConfig("""
        id = "bad"
        kind = "manual"

        [[signal]]
        id = "bad-signal"
        title = "Bad"
        priority = "urgent"
        """))
    }
}

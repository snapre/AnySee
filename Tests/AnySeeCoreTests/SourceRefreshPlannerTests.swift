import XCTest
@testable import AnySeeCore

final class SourceRefreshPlannerTests: XCTestCase {
    func testScheduledRefreshesKeepPerSourceIntervals() {
        let sources = [
            SignalSource(id: "manual", name: "Manual", kind: .manual),
            SignalSource(
                id: "fast",
                name: "Fast",
                kind: .script,
                refreshPolicy: RefreshPolicy(kind: .interval, intervalSeconds: 60)
            ),
            SignalSource(
                id: "slow",
                name: "Slow",
                kind: .http,
                refreshPolicy: RefreshPolicy(kind: .interval, intervalSeconds: 300)
            ),
            SignalSource(
                id: "disabled",
                name: "Disabled",
                kind: .script,
                enabled: false,
                refreshPolicy: RefreshPolicy(kind: .interval, intervalSeconds: 15)
            ),
            SignalSource(
                id: "missing-interval",
                name: "Missing Interval",
                kind: .script,
                refreshPolicy: RefreshPolicy(kind: .interval)
            )
        ]

        let refreshes = SourceRefreshPlanner.scheduledRefreshes(for: sources)

        XCTAssertEqual(
            refreshes,
            [
                ScheduledSourceRefresh(sourceID: "fast", intervalSeconds: 60),
                ScheduledSourceRefresh(sourceID: "slow", intervalSeconds: 300)
            ]
        )
    }

    func testManualRefreshRunsAllEnabledSources() {
        let sources = [
            SignalSource(id: "manual", name: "Manual", kind: .manual),
            SignalSource(
                id: "interval",
                name: "Interval",
                kind: .script,
                refreshPolicy: RefreshPolicy(kind: .interval, intervalSeconds: 60)
            ),
            SignalSource(
                id: "disabled",
                name: "Disabled",
                kind: .manual,
                enabled: false
            )
        ]

        let sourceIDs = SourceRefreshPlanner
            .sourcesToRun(for: .manual, in: sources)
            .map(\.id)

        XCTAssertEqual(sourceIDs, ["manual", "interval"])
    }

    func testScheduledRefreshRunsOnlyRequestedIntervalSources() {
        let sources = [
            SignalSource(id: "manual", name: "Manual", kind: .manual),
            SignalSource(
                id: "fast",
                name: "Fast",
                kind: .script,
                refreshPolicy: RefreshPolicy(kind: .interval, intervalSeconds: 60)
            ),
            SignalSource(
                id: "disabled",
                name: "Disabled",
                kind: .script,
                enabled: false,
                refreshPolicy: RefreshPolicy(kind: .interval, intervalSeconds: 15)
            ),
            SignalSource(
                id: "missing-interval",
                name: "Missing Interval",
                kind: .script,
                refreshPolicy: RefreshPolicy(kind: .interval)
            )
        ]

        let sourceIDs = SourceRefreshPlanner
            .sourcesToRun(
                for: .scheduled(sourceIDs: ["manual", "fast", "disabled", "missing-interval"]),
                in: sources
            )
            .map(\.id)

        XCTAssertEqual(sourceIDs, ["fast"])
    }
}

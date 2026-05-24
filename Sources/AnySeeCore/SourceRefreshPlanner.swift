import Foundation

public enum SourceRefreshRequest: Equatable, Sendable {
    case manual
    case scheduled(sourceIDs: Set<String>)
}

public struct ScheduledSourceRefresh: Equatable, Sendable {
    public var sourceID: String
    public var intervalSeconds: Int

    public init(sourceID: String, intervalSeconds: Int) {
        self.sourceID = sourceID
        self.intervalSeconds = intervalSeconds
    }
}

public enum SourceRefreshPlanner {
    public static func sourcesToRun(for request: SourceRefreshRequest, in sources: [SignalSource]) -> [SignalSource] {
        switch request {
        case .manual:
            return sources.filter(\.enabled)
        case .scheduled(let sourceIDs):
            return sources.filter { source in
                sourceIDs.contains(source.id) && isScheduledIntervalSource(source)
            }
        }
    }

    public static func scheduledRefreshes(for sources: [SignalSource]) -> [ScheduledSourceRefresh] {
        sources.compactMap { source in
            guard isScheduledIntervalSource(source), let intervalSeconds = source.refreshPolicy.intervalSeconds else {
                return nil
            }
            return ScheduledSourceRefresh(sourceID: source.id, intervalSeconds: intervalSeconds)
        }
    }

    private static func isScheduledIntervalSource(_ source: SignalSource) -> Bool {
        source.enabled
            && source.refreshPolicy.kind == .interval
            && (source.refreshPolicy.intervalSeconds ?? 0) > 0
    }
}

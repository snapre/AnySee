import AnySeeCore
import AppKit
import Combine
import Foundation

@MainActor
final class SignalStore: ObservableObject {
    @Published private(set) var items: [SignalItem] = []
    @Published private(set) var issues: [ValidationIssue] = []
    @Published private(set) var sources: [SignalSource] = []
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastRefreshAt: Date?
    @Published private(set) var lastCopiedPromptAt: Date?

    let paths: AnySeeConfigPaths
    private let configStore: ConfigStore
    private var refreshTask: Task<Void, Never>?
    private var schedulerTasks: [String: Task<Void, Never>] = [:]
    private var scheduledIntervals: [String: Int] = [:]
    private var pendingScheduledSourceIDs: Set<String> = []
    private var itemsBySourceID: [String: [SignalItem]] = [:]
    private var runIssuesBySourceID: [String: [ValidationIssue]] = [:]
    private var validationIssues: [ValidationIssue] = []
    private var dismissedIDs: Set<String> = []
    private var snoozedUntil: [String: Date] = [:]

    init(paths: AnySeeConfigPaths = .defaults()) {
        self.paths = paths
        self.configStore = ConfigStore(paths: paths)
    }

    var visibleItems: [SignalItem] {
        let now = Date()
        return SignalFeed.focused(items).filter { item in
            if dismissedIDs.contains(item.id) { return false }
            if let until = snoozedUntil[item.id], until > now { return false }
            return true
        }
    }

    var globalPriority: SignalPriority {
        SignalFeed.globalPriority(for: visibleItems, issues: issues)
    }

    var globalState: SignalState {
        SignalFeed.globalState(for: visibleItems, issues: issues, isRefreshing: isRefreshing)
    }

    func start() {
        do {
            try configStore.ensureBootstrapped()
        } catch {
            issues = [.init(severity: .error, message: "Could not create config directory: \(error.localizedDescription)")]
        }
        refresh()
    }

    func refresh() {
        refresh(request: .manual)
    }

    private func refresh(request: SourceRefreshRequest) {
        guard refreshTask == nil else {
            if case .scheduled(let sourceIDs) = request {
                pendingScheduledSourceIDs.formUnion(sourceIDs)
            }
            return
        }

        isRefreshing = true
        let paths = paths
        let configStore = configStore

        refreshTask = Task { [weak self] in
            let snapshot = await Task.detached(priority: .userInitiated) {
                Self.loadAndRun(configStore: configStore, paths: paths, request: request)
            }.value

            guard let self else { return }
            self.apply(snapshot)
            self.sources = snapshot.sources
            self.lastRefreshAt = Date()
            self.isRefreshing = false
            self.refreshTask = nil
            self.updateSchedulers(for: snapshot.sources, resetExisting: request == .manual)
            if request == .manual {
                self.pendingScheduledSourceIDs.removeAll()
            }
            self.startPendingScheduledRefreshIfNeeded()
        }
    }

    func dismiss(_ item: SignalItem) {
        dismissedIDs.insert(item.id)
        objectWillChange.send()
    }

    func snooze(_ item: SignalItem, minutes: Int = 30) {
        snoozedUntil[item.id] = Date().addingTimeInterval(TimeInterval(minutes * 60))
        objectWillChange.send()
    }

    func copyAIPromptToClipboard() {
        let configuration = try? configStore.load()
        let prompt = AIConfigurationPrompt.build(paths: paths, configuration: configuration)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(prompt, forType: .string)
        lastCopiedPromptAt = Date()
    }

    func openConfigDirectory() {
        NSWorkspace.shared.open(paths.rootDirectory)
    }

    func runCommandAction(_ action: SignalAction) {
        guard let executableURL = try? RunCommandResolver.resolveExecutableURL(command: action.command, paths: paths) else { return }
        guard FileManager.default.isExecutableFile(atPath: executableURL.path) else { return }
        let process = Process()
        process.executableURL = executableURL
        process.arguments = action.arguments
        try? process.run()
    }

    private func apply(_ snapshot: RefreshSnapshot) {
        validationIssues = snapshot.validationIssues
        if snapshot.replacesAllSourceResults {
            itemsBySourceID = [:]
            runIssuesBySourceID = [:]
        }

        let enabledSourceIDs = Set(snapshot.sources.filter(\.enabled).map(\.id))
        itemsBySourceID = itemsBySourceID.filter { enabledSourceIDs.contains($0.key) }
        runIssuesBySourceID = runIssuesBySourceID.filter { enabledSourceIDs.contains($0.key) }

        for result in snapshot.results {
            itemsBySourceID[result.sourceID] = result.items
            runIssuesBySourceID[result.sourceID] = result.issues
        }

        items = Self.orderedItems(from: itemsBySourceID, sources: snapshot.sources)
        issues = Self.orderedIssues(
            validationIssues: validationIssues,
            runIssuesBySourceID: runIssuesBySourceID,
            sources: snapshot.sources
        )
    }

    private func updateSchedulers(for sources: [SignalSource], resetExisting: Bool) {
        var intervals: [String: Int] = [:]
        for scheduledRefresh in SourceRefreshPlanner.scheduledRefreshes(for: sources) where intervals[scheduledRefresh.sourceID] == nil {
            intervals[scheduledRefresh.sourceID] = scheduledRefresh.intervalSeconds
        }

        let staleSourceIDs = schedulerTasks.keys.filter { sourceID in
            resetExisting || intervals[sourceID] != scheduledIntervals[sourceID]
        }

        for sourceID in staleSourceIDs {
            schedulerTasks[sourceID]?.cancel()
            schedulerTasks[sourceID] = nil
        }

        for (sourceID, intervalSeconds) in intervals where schedulerTasks[sourceID] == nil {
            schedulerTasks[sourceID] = Task { [weak self] in
                while !Task.isCancelled {
                    do {
                        try await Task.sleep(for: .seconds(intervalSeconds))
                    } catch {
                        break
                    }
                    guard !Task.isCancelled else { break }
                    await MainActor.run {
                        self?.enqueueScheduledRefresh(sourceID: sourceID)
                    }
                }
            }
        }

        scheduledIntervals = intervals
        pendingScheduledSourceIDs.formIntersection(Set(intervals.keys))
    }

    private func enqueueScheduledRefresh(sourceID: String) {
        pendingScheduledSourceIDs.insert(sourceID)
        startPendingScheduledRefreshIfNeeded()
    }

    private func startPendingScheduledRefreshIfNeeded() {
        guard refreshTask == nil, !pendingScheduledSourceIDs.isEmpty else { return }
        let sourceIDs = pendingScheduledSourceIDs
        pendingScheduledSourceIDs.removeAll()
        refresh(request: .scheduled(sourceIDs: sourceIDs))
    }

    nonisolated private static func loadAndRun(configStore: ConfigStore, paths: AnySeeConfigPaths, request: SourceRefreshRequest) -> RefreshSnapshot {
        do {
            let configuration = try configStore.load()
            let validationIssues = configStore.validate(configuration)
            let runner = SourceRunner()
            let results = SourceRefreshPlanner
                .sourcesToRun(for: request, in: configuration.sources)
                .map { runner.run($0, paths: paths) }

            return RefreshSnapshot(
                validationIssues: validationIssues,
                results: results,
                sources: configuration.sources,
                replacesAllSourceResults: request == .manual
            )
        } catch {
            return RefreshSnapshot(
                validationIssues: [.init(severity: .error, message: error.localizedDescription)],
                results: [],
                sources: [],
                replacesAllSourceResults: true
            )
        }
    }

    nonisolated private static func orderedItems(from itemsBySourceID: [String: [SignalItem]], sources: [SignalSource]) -> [SignalItem] {
        sources
            .filter(\.enabled)
            .flatMap { itemsBySourceID[$0.id] ?? [] }
    }

    nonisolated private static func orderedIssues(
        validationIssues: [ValidationIssue],
        runIssuesBySourceID: [String: [ValidationIssue]],
        sources: [SignalSource]
    ) -> [ValidationIssue] {
        validationIssues + sources
            .filter(\.enabled)
            .flatMap { runIssuesBySourceID[$0.id] ?? [] }
    }
}

private struct RefreshSnapshot: Sendable {
    var validationIssues: [ValidationIssue]
    var results: [SourceRunResult]
    var sources: [SignalSource]
    var replacesAllSourceResults: Bool
}

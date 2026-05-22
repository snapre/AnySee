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
    private var schedulerTask: Task<Void, Never>?
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
        guard refreshTask == nil else { return }
        isRefreshing = true
        let paths = paths
        let configStore = configStore

        refreshTask = Task { [weak self] in
            let snapshot = await Task.detached(priority: .userInitiated) {
                Self.loadAndRun(configStore: configStore, paths: paths)
            }.value

            guard let self else { return }
            self.items = snapshot.items
            self.issues = snapshot.issues
            self.sources = snapshot.sources
            self.lastRefreshAt = Date()
            self.isRefreshing = false
            self.refreshTask = nil
            self.restartScheduler(intervalSeconds: snapshot.nextIntervalSeconds)
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
        guard let command = action.command, command.hasPrefix("/") else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = action.arguments
        try? process.run()
    }

    private func restartScheduler(intervalSeconds: Int?) {
        schedulerTask?.cancel()
        guard let intervalSeconds, intervalSeconds > 0 else { return }

        schedulerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(intervalSeconds))
                await MainActor.run {
                    self?.refresh()
                }
            }
        }
    }

    nonisolated private static func loadAndRun(configStore: ConfigStore, paths: AnySeeConfigPaths) -> RefreshSnapshot {
        do {
            let configuration = try configStore.load()
            var allIssues = configStore.validate(configuration)
            var allItems: [SignalItem] = []
            let runner = SourceRunner()

            for source in configuration.sources where source.enabled {
                let result = runner.run(source, paths: paths)
                allItems.append(contentsOf: result.items)
                allIssues.append(contentsOf: result.issues)
            }

            let interval = configuration.sources
                .filter(\.enabled)
                .compactMap { source -> Int? in
                    guard source.refreshPolicy.kind == .interval else { return nil }
                    return source.refreshPolicy.intervalSeconds
                }
                .min()

            return RefreshSnapshot(items: allItems, issues: allIssues, sources: configuration.sources, nextIntervalSeconds: interval)
        } catch {
            return RefreshSnapshot(
                items: [],
                issues: [.init(severity: .error, message: error.localizedDescription)],
                sources: [],
                nextIntervalSeconds: nil
            )
        }
    }
}

private struct RefreshSnapshot: Sendable {
    var items: [SignalItem]
    var issues: [ValidationIssue]
    var sources: [SignalSource]
    var nextIntervalSeconds: Int?
}

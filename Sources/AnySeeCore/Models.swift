import Foundation

public enum SignalPriority: String, Codable, CaseIterable, Comparable, Sendable {
    case none
    case low
    case normal
    case high
    case critical

    public var rank: Int {
        switch self {
        case .none: 0
        case .low: 1
        case .normal: 2
        case .high: 3
        case .critical: 4
        }
    }

    public static func < (lhs: SignalPriority, rhs: SignalPriority) -> Bool {
        lhs.rank < rhs.rank
    }
}

public enum SignalState: String, Codable, CaseIterable, Sendable {
    case ok
    case needsAttention = "needs_attention"
    case running
    case paused
    case unknown

    public var attentionRank: Int {
        switch self {
        case .ok: 0
        case .paused: 1
        case .unknown: 2
        case .running: 3
        case .needsAttention: 4
        }
    }
}

public enum SignalActionType: String, Codable, CaseIterable, Sendable {
    case openURL = "open_url"
    case copyText = "copy_text"
    case runCommand = "run_command"
    case dismiss
    case snooze
}

public struct SignalAction: Codable, Equatable, Identifiable, Sendable {
    public var id: String { "\(label):\(type.rawValue)" }
    public var label: String
    public var type: SignalActionType
    public var url: String?
    public var text: String?
    public var command: String?
    public var arguments: [String]
    public var durationMinutes: Int?

    public init(
        label: String,
        type: SignalActionType,
        url: String? = nil,
        text: String? = nil,
        command: String? = nil,
        arguments: [String] = [],
        durationMinutes: Int? = nil
    ) {
        self.label = label
        self.type = type
        self.url = url
        self.text = text
        self.command = command
        self.arguments = arguments
        self.durationMinutes = durationMinutes
    }

    private enum CodingKeys: String, CodingKey {
        case label
        case type
        case url
        case text
        case command
        case arguments
        case durationMinutes = "duration_minutes"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        label = try container.decode(String.self, forKey: .label)
        type = try container.decode(SignalActionType.self, forKey: .type)
        url = try container.decodeIfPresent(String.self, forKey: .url)
        text = try container.decodeIfPresent(String.self, forKey: .text)
        command = try container.decodeIfPresent(String.self, forKey: .command)
        arguments = try container.decodeIfPresent([String].self, forKey: .arguments) ?? []
        durationMinutes = try container.decodeIfPresent(Int.self, forKey: .durationMinutes)
    }
}

public struct SignalItem: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var body: String
    public var priority: SignalPriority
    public var state: SignalState
    public var source: String
    public var url: String?
    public var actions: [SignalAction]

    public init(
        id: String,
        title: String,
        body: String = "",
        priority: SignalPriority = .normal,
        state: SignalState = .needsAttention,
        source: String = "",
        url: String? = nil,
        actions: [SignalAction] = []
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.priority = priority
        self.state = state
        self.source = source
        self.url = url
        self.actions = actions
    }

    public var isAttentionWorthy: Bool {
        if priority >= .normal { return true }
        switch state {
        case .needsAttention, .running, .unknown:
            return true
        case .ok, .paused:
            return false
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case body
        case priority
        case state
        case source
        case url
        case actions
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        body = try container.decodeIfPresent(String.self, forKey: .body) ?? ""
        priority = try container.decodeIfPresent(SignalPriority.self, forKey: .priority) ?? .normal
        state = try container.decodeIfPresent(SignalState.self, forKey: .state) ?? .needsAttention
        source = try container.decodeIfPresent(String.self, forKey: .source) ?? ""
        url = try container.decodeIfPresent(String.self, forKey: .url)
        actions = try container.decodeIfPresent([SignalAction].self, forKey: .actions) ?? []
    }
}

public enum SignalSourceKind: String, Codable, CaseIterable, Sendable {
    case manual
    case http
    case script
}

public enum RefreshPolicyKind: String, Codable, CaseIterable, Sendable {
    case manual
    case interval
    case schedule
}

public struct RefreshPolicy: Codable, Equatable, Sendable {
    public var kind: RefreshPolicyKind
    public var intervalSeconds: Int?
    public var schedule: String?

    public init(kind: RefreshPolicyKind, intervalSeconds: Int? = nil, schedule: String? = nil) {
        self.kind = kind
        self.intervalSeconds = intervalSeconds
        self.schedule = schedule
    }

    public static let manual = RefreshPolicy(kind: .manual)
}

public struct HTTPSourceOptions: Equatable, Sendable {
    public var url: String
    public var method: String
    public var timeoutSeconds: Int
    public var expectedStatus: Int
    public var signalOnStatusMismatch: Bool
    public var jsonPath: String?
    public var equals: String?
    public var notEquals: String?
    public var title: String
    public var body: String
    public var priority: SignalPriority
    public var state: SignalState

    public init(
        url: String,
        method: String = "GET",
        timeoutSeconds: Int = 10,
        expectedStatus: Int = 200,
        signalOnStatusMismatch: Bool = true,
        jsonPath: String? = nil,
        equals: String? = nil,
        notEquals: String? = nil,
        title: String = "HTTP signal",
        body: String = "HTTP source matched its attention condition.",
        priority: SignalPriority = .high,
        state: SignalState = .needsAttention
    ) {
        self.url = url
        self.method = method
        self.timeoutSeconds = timeoutSeconds
        self.expectedStatus = expectedStatus
        self.signalOnStatusMismatch = signalOnStatusMismatch
        self.jsonPath = jsonPath
        self.equals = equals
        self.notEquals = notEquals
        self.title = title
        self.body = body
        self.priority = priority
        self.state = state
    }
}

public struct ScriptSourceOptions: Equatable, Sendable {
    public var path: String
    public var timeoutSeconds: Int
    public var workingDirectory: String?

    public init(path: String, timeoutSeconds: Int = 15, workingDirectory: String? = nil) {
        self.path = path
        self.timeoutSeconds = timeoutSeconds
        self.workingDirectory = workingDirectory
    }
}

public struct SignalSource: Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var kind: SignalSourceKind
    public var enabled: Bool
    public var refreshPolicy: RefreshPolicy
    public var manualSignals: [SignalItem]
    public var http: HTTPSourceOptions?
    public var script: ScriptSourceOptions?
    public var sourceFilePath: String?

    public init(
        id: String,
        name: String,
        kind: SignalSourceKind,
        enabled: Bool = true,
        refreshPolicy: RefreshPolicy = .manual,
        manualSignals: [SignalItem] = [],
        http: HTTPSourceOptions? = nil,
        script: ScriptSourceOptions? = nil,
        sourceFilePath: String? = nil
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.enabled = enabled
        self.refreshPolicy = refreshPolicy
        self.manualSignals = manualSignals
        self.http = http
        self.script = script
        self.sourceFilePath = sourceFilePath
    }
}

public struct AnySeeSettings: Equatable, Sendable {
    public var appName: String
    public var quietByDefault: Bool
    public var maxSignalsInPopover: Int

    public init(appName: String = "AnySee", quietByDefault: Bool = true, maxSignalsInPopover: Int = 30) {
        self.appName = appName
        self.quietByDefault = quietByDefault
        self.maxSignalsInPopover = maxSignalsInPopover
    }
}

public struct AnySeeConfiguration: Equatable, Sendable {
    public var settings: AnySeeSettings
    public var sources: [SignalSource]

    public init(settings: AnySeeSettings = AnySeeSettings(), sources: [SignalSource] = []) {
        self.settings = settings
        self.sources = sources
    }
}

public enum ValidationSeverity: String, Equatable, Sendable {
    case warning
    case error
}

public struct ValidationIssue: Identifiable, Equatable, Sendable {
    public var id: String { "\(severity.rawValue):\(sourceID ?? "global"):\(message)" }
    public var severity: ValidationSeverity
    public var sourceID: String?
    public var message: String

    public init(severity: ValidationSeverity, sourceID: String? = nil, message: String) {
        self.severity = severity
        self.sourceID = sourceID
        self.message = message
    }
}

public struct SourceRunResult: Equatable, Sendable {
    public var sourceID: String
    public var items: [SignalItem]
    public var issues: [ValidationIssue]
    public var rawOutput: String?
    public var ranAt: Date

    public init(
        sourceID: String,
        items: [SignalItem] = [],
        issues: [ValidationIssue] = [],
        rawOutput: String? = nil,
        ranAt: Date = Date()
    ) {
        self.sourceID = sourceID
        self.items = items
        self.issues = issues
        self.rawOutput = rawOutput
        self.ranAt = ranAt
    }
}

public enum SignalFeed {
    public static func focused(_ items: [SignalItem]) -> [SignalItem] {
        items
            .filter(\.isAttentionWorthy)
            .sorted { lhs, rhs in
                if lhs.priority != rhs.priority { return lhs.priority > rhs.priority }
                if lhs.state != rhs.state { return lhs.state.attentionRank > rhs.state.attentionRank }
                if lhs.source != rhs.source { return lhs.source < rhs.source }
                return lhs.title < rhs.title
            }
    }

    public static func globalPriority(for items: [SignalItem], issues: [ValidationIssue] = []) -> SignalPriority {
        if issues.contains(where: { $0.severity == .error }) { return .critical }
        if issues.contains(where: { $0.severity == .warning }) { return .high }
        return focused(items).map(\.priority).max() ?? .none
    }

    public static func globalState(for items: [SignalItem], issues: [ValidationIssue] = [], isRefreshing: Bool = false) -> SignalState {
        if isRefreshing { return .running }
        if !issues.isEmpty { return .unknown }
        let focusedItems = focused(items)
        if focusedItems.contains(where: { $0.state == .needsAttention }) { return .needsAttention }
        if focusedItems.contains(where: { $0.state == .running }) { return .running }
        if focusedItems.contains(where: { $0.state == .unknown }) { return .unknown }
        return .ok
    }
}

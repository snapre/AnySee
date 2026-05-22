import AnySeeCore
import AppKit
import SwiftUI

struct AttentionPopoverView: View {
    @ObservedObject var store: SignalStore
    var onOpenSettings: @MainActor () -> Void
    var onQuit: @MainActor () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 420, height: 560)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: iconName)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(priorityColor)
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text("AnySee")
                    .font(.headline)
                Text(statusLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button {
                store.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Refresh")
        }
        .padding(14)
    }

    @ViewBuilder
    private var content: some View {
        if store.visibleItems.isEmpty && store.issues.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 34))
                    .foregroundStyle(.green)
                Text("Nothing needs attention")
                    .font(.headline)
                Text("Sources are quiet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if !store.issues.isEmpty {
                        SectionLabel(title: "Diagnostics")
                        ForEach(store.issues) { issue in
                            DiagnosticRow(issue: issue)
                        }
                    }

                    let critical = store.visibleItems.filter { $0.priority == .critical }
                    if !critical.isEmpty {
                        SectionLabel(title: "Critical")
                        ForEach(critical) { item in
                            SignalRow(item: item, store: store)
                        }
                    }

                    let attention = store.visibleItems.filter { $0.priority == .high || ($0.priority == .normal && $0.state == .needsAttention) }
                    if !attention.isEmpty {
                        SectionLabel(title: "Attention")
                        ForEach(attention) { item in
                            SignalRow(item: item, store: store)
                        }
                    }

                    let running = store.visibleItems.filter { $0.state == .running && $0.priority < .high }
                    if !running.isEmpty {
                        SectionLabel(title: "Running")
                        ForEach(running) { item in
                            SignalRow(item: item, store: store)
                        }
                    }

                    let other = store.visibleItems.filter { item in
                        !critical.contains(where: { $0.id == item.id })
                            && !attention.contains(where: { $0.id == item.id })
                            && !running.contains(where: { $0.id == item.id })
                    }
                    if !other.isEmpty {
                        SectionLabel(title: "Other")
                        ForEach(other) { item in
                            SignalRow(item: item, store: store)
                        }
                    }
                }
                .padding(12)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button {
                store.copyAIPromptToClipboard()
            } label: {
                Label("Configure with AI", systemImage: "sparkles")
            }
            Button {
                onOpenSettings()
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
            Spacer()
            Button {
                onQuit()
            } label: {
                Image(systemName: "power")
            }
            .help("Quit")
        }
        .buttonStyle(.borderless)
        .padding(12)
    }

    private var iconName: String {
        if store.isRefreshing { return "arrow.triangle.2.circlepath.circle" }
        switch store.globalPriority {
        case .critical: return "exclamationmark.triangle.fill"
        case .high, .normal: return "exclamationmark.circle.fill"
        case .low: return "circle.lefthalf.filled"
        case .none: return "circle"
        }
    }

    private var priorityColor: Color {
        switch store.globalPriority {
        case .critical: .red
        case .high: .orange
        case .normal: .yellow
        case .low: .blue
        case .none: .green
        }
    }

    private var statusLine: String {
        if store.isRefreshing { return "Refreshing" }
        if !store.issues.isEmpty { return "\(store.issues.count) diagnostic item(s)" }
        if store.visibleItems.isEmpty { return "Quiet" }
        return "\(store.visibleItems.count) signal(s)"
    }
}

private struct SectionLabel: View {
    var title: String

    var body: some View {
        Text(title.uppercased())
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.top, 4)
    }
}

private struct DiagnosticRow: View {
    var issue: ValidationIssue

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: issue.severity == .error ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(issue.severity == .error ? .red : .orange)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 3) {
                if let sourceID = issue.sourceID {
                    Text(sourceID)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Text(issue.message)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct SignalRow: View {
    var item: SignalItem
    @ObservedObject var store: SignalStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: symbolName)
                    .foregroundStyle(priorityColor)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title)
                        .font(.callout.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    if !item.body.isEmpty {
                        Text(item.body)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text(item.source)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                ForEach(actionList) { action in
                    Button {
                        perform(action)
                    } label: {
                        actionLabel(action)
                    }
                    .buttonStyle(.borderless)
                    .help(action.label)
                }
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var actionList: [SignalAction] {
        var actions = item.actions
        if let url = item.url, !actions.contains(where: { $0.type == .openURL }) {
            actions.insert(SignalAction(label: "Open", type: .openURL, url: url), at: 0)
        }
        if !actions.contains(where: { $0.type == .snooze }) {
            actions.append(SignalAction(label: "Snooze", type: .snooze, durationMinutes: 30))
        }
        if !actions.contains(where: { $0.type == .dismiss }) {
            actions.append(SignalAction(label: "Dismiss", type: .dismiss))
        }
        return actions
    }

    private var symbolName: String {
        switch item.priority {
        case .critical: return "exclamationmark.triangle.fill"
        case .high: return "exclamationmark.circle.fill"
        case .normal: return "circle.lefthalf.filled"
        case .low: return "smallcircle.filled.circle"
        case .none: return "circle"
        }
    }

    private var priorityColor: Color {
        switch item.priority {
        case .critical: .red
        case .high: .orange
        case .normal: .yellow
        case .low: .blue
        case .none: .secondary
        }
    }

    @ViewBuilder
    private func actionLabel(_ action: SignalAction) -> some View {
        switch action.type {
        case .openURL:
            Label(action.label, systemImage: "arrow.up.right.square")
        case .copyText:
            Label(action.label, systemImage: "doc.on.doc")
        case .runCommand:
            Label(action.label, systemImage: "terminal")
        case .dismiss:
            Label(action.label, systemImage: "xmark")
        case .snooze:
            Label(action.label, systemImage: "clock")
        }
    }

    private func perform(_ action: SignalAction) {
        switch action.type {
        case .openURL:
            guard let value = action.url, let url = URL(string: value) else { return }
            NSWorkspace.shared.open(url)
        case .copyText:
            guard let text = action.text else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        case .runCommand:
            store.runCommandAction(action)
        case .dismiss:
            store.dismiss(item)
        case .snooze:
            store.snooze(item, minutes: action.durationMinutes ?? 30)
        }
    }
}

struct SettingsView: View {
    @ObservedObject var store: SignalStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "circle.grid.2x2")
                    .font(.system(size: 24, weight: .semibold))
                VStack(alignment: .leading, spacing: 2) {
                    Text("AnySee")
                        .font(.title3.weight(.semibold))
                    Text(store.paths.rootDirectory.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                Button {
                    store.openConfigDirectory()
                } label: {
                    Label("Open Config", systemImage: "folder")
                }
            }
            .padding(18)

            Divider()

            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Sources")
                        .font(.headline)
                    if store.sources.isEmpty {
                        Text("No sources loaded")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(store.sources) { source in
                            SourceSettingsRow(source: source)
                        }
                    }
                    Spacer()
                }
                .frame(width: 320)

                VStack(alignment: .leading, spacing: 12) {
                    Text("Tools")
                        .font(.headline)
                    Button {
                        store.copyAIPromptToClipboard()
                    } label: {
                        Label("Copy AI Prompt", systemImage: "sparkles")
                    }
                    Button {
                        store.refresh()
                    } label: {
                        Label("Refresh Now", systemImage: "arrow.clockwise")
                    }
                    if let copiedAt = store.lastCopiedPromptAt {
                        Text("Prompt copied \(copiedAt.formatted(date: .omitted, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Divider()

                    Text("Diagnostics")
                        .font(.headline)
                    if store.issues.isEmpty {
                        Label("OK", systemImage: "checkmark.circle")
                            .foregroundStyle(.green)
                    } else {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(store.issues) { issue in
                                    DiagnosticRow(issue: issue)
                                }
                            }
                        }
                    }
                    Spacer()
                }
            }
            .padding(18)
        }
    }
}

private struct SourceSettingsRow: View {
    var source: SignalSource

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: iconName)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(source.name)
                    .font(.callout.weight(.semibold))
                Text("\(source.id) - \(source.kind.rawValue) - \(source.enabled ? "enabled" : "disabled")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var iconName: String {
        switch source.kind {
        case .manual: "hand.point.up.left"
        case .http: "network"
        case .script: "terminal"
        }
    }
}

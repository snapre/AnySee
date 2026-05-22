import AnySeeCore
import AppKit

@MainActor
enum StatusIconRenderer {
    static func image(priority: SignalPriority, state: SignalState, isRefreshing: Bool) -> NSImage? {
        let symbolName: String
        if isRefreshing {
            symbolName = "arrow.triangle.2.circlepath.circle"
        } else {
            switch (priority, state) {
            case (.critical, _):
                symbolName = "exclamationmark.triangle.fill"
            case (.high, _), (.normal, .needsAttention):
                symbolName = "exclamationmark.circle.fill"
            case (_, .running):
                symbolName = "arrow.triangle.2.circlepath.circle"
            case (_, .paused):
                symbolName = "pause.circle"
            case (_, .unknown):
                symbolName = "questionmark.circle"
            default:
                symbolName = "circle"
            }
        }

        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "AnySee status")
        image?.isTemplate = true
        return image
    }
}

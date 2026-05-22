import AnySeeCore
import AppKit
import Combine
import SwiftUI

@MainActor
final class MenuBarController {
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private let store: SignalStore
    private var cancellable: AnyCancellable?

    init(store: SignalStore, onOpenSettings: @escaping @MainActor () -> Void, onQuit: @escaping @MainActor () -> Void) {
        self.store = store
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        popover.behavior = .transient
        popover.contentSize = NSSize(width: 420, height: 560)
        popover.contentViewController = NSHostingController(
            rootView: AttentionPopoverView(
                store: store,
                onOpenSettings: onOpenSettings,
                onQuit: onQuit
            )
        )

        configureButton()
        cancellable = store.objectWillChange.sink { [weak self] _ in
            Task { @MainActor in
                self?.updateIcon()
            }
        }
        updateIcon()
    }

    private func configureButton() {
        guard let button = statusItem.button else { return }
        button.action = #selector(togglePopover(_:))
        button.target = self
        button.imagePosition = .imageLeading
    }

    private func updateIcon() {
        guard let button = statusItem.button else { return }
        button.image = StatusIconRenderer.image(priority: store.globalPriority, state: store.globalState, isRefreshing: store.isRefreshing)
        button.toolTip = "AnySee - \(store.globalPriority.rawValue)"
    }

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

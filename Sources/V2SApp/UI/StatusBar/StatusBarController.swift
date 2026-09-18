import AppKit
import Combine
import SwiftUI

@MainActor
final class StatusBarController: NSObject, NSPopoverDelegate {
    private let model: AppModel
    private let openAdvancedSettings: () -> Void
    private let showTranscript: () -> Void
    private let quitApp: () -> Void
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private let outsideClickMonitor = PopoverOutsideClickMonitor()
    private var cancellables = Set<AnyCancellable>()

    init(
        model: AppModel,
        openAdvancedSettings: @escaping () -> Void,
        showTranscript: @escaping () -> Void,
        quitApp: @escaping () -> Void
    ) {
        self.model = model
        self.openAdvancedSettings = openAdvancedSettings
        self.showTranscript = showTranscript
        self.quitApp = quitApp
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        configureStatusItem()
        configurePopover()
        bindModel()
        updateStatusIcon()
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else {
            return
        }

        button.action = #selector(togglePopover(_:))
        button.target = self
        button.imagePosition = .imageOnly
        button.toolTip = "v2s"
    }

    private func configurePopover() {
        popover.delegate = self
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 340, height: 500)
        applySystemAppearance()
    }

    /// Pins the popover to the system light/dark appearance.
    ///
    /// Left unset, the popover's glass backdrop derives its appearance from
    /// whatever sits behind it, so a bright wallpaper makes the content draw in
    /// light mode while the system is in dark mode.
    private func applySystemAppearance() {
        popover.appearance = NSApp.effectiveAppearance
    }

    private func bindModel() {
        // .receive(on:) で「値が格納された後」に配信させる（@Published は willSet で発火するため、
        // sink 内で model を読むと更新前の値になる）。
        model.$sessionState
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateStatusIcon() }
            .store(in: &cancellables)
        model.$isReconnecting
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateStatusIcon() }
            .store(in: &cancellables)
    }

    private func updateStatusIcon() {
        let symbolName: String

        if model.isReconnecting {
            // 詰まりを検出して自動再接続している最中であることを見せる。
            symbolName = "arrow.triangle.2.circlepath"
        } else {
            switch model.sessionState {
            case .idle:
                symbolName = "captions.bubble"
            case .running:
                symbolName = "captions.bubble.fill"
            case .error:
                symbolName = "exclamationmark.bubble"
            }
        }

        let image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: "v2s status icon"
        )
        image?.isTemplate = true
        statusItem.button?.image = image
    }

    /// Screen rect of the status bar button, for animation targeting.
    var statusItemScreenRect: NSRect? {
        guard let button = statusItem.button,
              let window = button.window else { return nil }
        let rect = button.convert(button.bounds, to: nil)
        return window.convertToScreen(rect)
    }

    @objc
    private func togglePopover(_ sender: Any?) {
        guard let button = statusItem.button else {
            return
        }

        if popover.isShown {
            popover.performClose(sender)
        } else {
            model.refreshSources()
            applySystemAppearance()
            popover.contentViewController = NSHostingController(
                rootView: StatusBarPopoverView(
                    model: model,
                    closePopover: { [weak self] in
                        self?.popover.performClose(nil)
                    },
                    openAdvancedSettings: { [weak self] in
                        self?.popover.performClose(nil)
                        self?.openAdvancedSettings()
                    },
                    showTranscript: { [weak self] in
                        self?.popover.performClose(nil)
                        self?.showTranscript()
                    },
                    quitApp: { [weak self] in
                        self?.popover.performClose(nil)
                        self?.quitApp()
                    }
                )
            )
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    func popoverWillShow(_ notification: Notification) {
        outsideClickMonitor.start(
            shouldIgnoreClick: { [weak self] screenPoint in
                self?.clickShouldKeepPopoverOpen(at: screenPoint) ?? true
            },
            onOutsideClick: { [weak self] in
                guard let self, self.popover.isShown else {
                    return
                }

                self.popover.performClose(nil)
            }
        )
    }

    func popoverDidClose(_ notification: Notification) {
        outsideClickMonitor.stop()
        popover.contentViewController = nil
    }

    private func clickShouldKeepPopoverOpen(at screenPoint: NSPoint) -> Bool {
        statusItemScreenRect?.contains(screenPoint) == true
            || popover.contentViewController?.view.window?.frame.contains(screenPoint) == true
    }
}

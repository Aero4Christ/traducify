import AppKit
import Combine
import SwiftUI

/// Borderless floating panel pinned top-center, hugging the notch on notched
/// Macs and sitting just under the menu bar on everything else.
final class NotchPanel: NSPanel {
    static let panelWidth: CGFloat = 720

    private let state: AppState
    private var subscriptions = Set<AnyCancellable>()

    init(state: AppState) {
        self.state = state
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: NotchPanel.panelWidth, height: 380),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)

        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isMovable = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false

        let host = NSHostingView(rootView: PanelView(state: state, notchInset: NotchPanel.notchInset))
        host.frame = contentRect(forFrameRect: frame)
        contentView = host

        // height follows the UI phase and the collapse toggle
        state.$collapsed.combineLatest(state.$phase)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] collapsed, phase in
                self?.layout(collapsed: collapsed, phase: phase)
            }
            .store(in: &subscriptions)

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in
                guard let self else { return }
                self.layout(collapsed: self.state.collapsed, phase: self.state.phase)
            }
    }

    override var canBecomeKey: Bool { true }  // the chat field needs key status

    private static var targetScreen: NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main
    }

    /// Height of the camera-housing area on the target screen (0 on non-notched Macs).
    private static var notchInset: CGFloat {
        targetScreen?.safeAreaInsets.top ?? 0
    }

    func show() {
        layout(collapsed: state.collapsed, phase: state.phase)
        orderFrontRegardless()
    }

    private func layout(collapsed: Bool, phase: AppState.Phase) {
        guard let screen = NotchPanel.targetScreen else { return }
        let notch = screen.safeAreaInsets.top

        let height: CGFloat
        if collapsed {
            height = max(notch, 30) + 8
        } else {
            switch phase {
            case .setup: height = 370
            case .downloading, .loading, .failed: height = 170
            case .running: height = 320
            }
        }

        // Notched Macs: flush with the physical top so the panel extends the notch.
        // Others: tucked under the menu bar.
        let top = notch > 0 ? screen.frame.maxY : screen.visibleFrame.maxY
        let frame = NSRect(
            x: (screen.frame.midX - NotchPanel.panelWidth / 2).rounded(),
            y: top - height,
            width: NotchPanel.panelWidth,
            height: height)
        setFrame(frame, display: true, animate: isVisible)
    }
}

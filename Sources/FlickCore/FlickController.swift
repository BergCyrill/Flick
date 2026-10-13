/// Reads and moves windows.
@MainActor
public protocol WindowAccess: AnyObject {
    func frame(of window: WindowHandle) -> GlobalRect?
    /// Returns `false` if the window could not be moved at all.
    func setFrame(_ frame: GlobalRect, of window: WindowHandle) -> Bool
}

/// Knows the screens.
@MainActor
public protocol ScreenProvider: AnyObject {
    /// Visible frame (no menu bar, no Dock) of the screen containing `point`.
    func visibleFrame(containing point: GlobalPoint) -> GlobalRect?
}

/// Shows the target frame while a gesture is in progress.
@MainActor
public protocol PreviewPresenter: AnyObject {
    func show(_ frame: GlobalRect)
    func hide()
}

/// Turns gesture updates into previews and window moves.
@MainActor
public final class FlickController {
    private let windows: WindowAccess
    private let screens: ScreenProvider
    private let preview: PreviewPresenter
    private let gap: Double
    private var history = FrameHistory()

    public init(
        windows: WindowAccess,
        screens: ScreenProvider,
        preview: PreviewPresenter,
        gap: Double = LayoutEngine.defaultGap
    ) {
        self.windows = windows
        self.screens = screens
        self.preview = preview
        self.gap = gap
    }

    public func handle(_ update: GestureUpdate) {
        switch update {
        case let .preview(context, target):
            if let target, let frame = frame(for: target, context: context) {
                preview.show(frame)
            } else {
                preview.hide()
            }
        case let .commit(context, target):
            preview.hide()
            commit(target, context: context)
        case .cancel:
            preview.hide()
        }
    }

    private func frame(for target: Target, context: GestureContext) -> GlobalRect? {
        switch target {
        case let .slot(slot):
            guard let visible = screens.visibleFrame(containing: context.pointer) else { return nil }
            return LayoutEngine.frame(for: slot, in: visible, gap: gap)
        case .restore:
            return history.peek(for: context.window)
        }
    }

    private func commit(_ target: Target, context: GestureContext) {
        let window = context.window
        switch target {
        case .slot:
            guard let current = windows.frame(of: window),
                let next = frame(for: target, context: context),
                windows.setFrame(next, of: window)
            else { return }
            history.record(current, for: window)
        case .restore:
            guard let previous = history.take(for: window) else { return }
            _ = windows.setFrame(previous, of: window)
        }
    }
}

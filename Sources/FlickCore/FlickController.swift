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
    private let gap: @MainActor () -> Double
    private let settings: @MainActor () -> FlickSettings
    private var history = FrameHistory()
    /// The frame the preview shows right now, so an unchanged preview isn't redrawn.
    private var shownFrame: GlobalRect?

    public init(
        windows: WindowAccess,
        screens: ScreenProvider,
        preview: PreviewPresenter,
        gap: @escaping @MainActor () -> Double = { LayoutEngine.defaultGap },
        settings: @escaping @MainActor () -> FlickSettings = { FlickSettings() }
    ) {
        self.windows = windows
        self.screens = screens
        self.preview = preview
        self.gap = gap
        self.settings = settings
    }

    public func handle(_ update: GestureUpdate) {
        switch update {
        case let .preview(context, target):
            if settings().livePreview, let target, let frame = frame(for: target, context: context) {
                showPreview(frame)
            } else {
                hidePreview()
            }
        case let .commit(context, target):
            hidePreview()
            commit(target, context: context)
        case .cancel:
            hidePreview()
        }
    }

    private func showPreview(_ frame: GlobalRect) {
        guard frame != shownFrame else { return }
        shownFrame = frame
        preview.show(frame)
    }

    private func hidePreview() {
        shownFrame = nil
        preview.hide()
    }

    private func frame(for target: Target, context: GestureContext) -> GlobalRect? {
        switch target {
        case let .slot(slot):
            guard let visible = screens.visibleFrame(containing: context.pointer) else { return nil }
            return LayoutEngine.frame(for: slot, in: visible, gap: gap())
        case .restore:
            guard let original = history.peek(for: context.window) else { return nil }
            guard let drag = context.drag else { return original }
            // During a drag the window comes back at its restore size, under the pointer.
            guard let visible = screens.visibleFrame(containing: context.pointer) else { return nil }
            return DragRestore.frame(restoring: original, drag: drag, pointer: context.pointer, visible: visible)
        }
    }

    private func commit(_ target: Target, context: GestureContext) {
        let window = context.window
        switch target {
        case .slot:
            guard let actual = windows.frame(of: window),
                let next = frame(for: target, context: context),
                windows.setFrame(next, of: window)
            else { return }
            // A dragged window counts as still being where it was when the button went down, so
            // dragging a snapped window out and filling it continues the run.
            let current = context.drag?.frameAtPress ?? actual
            // Read back where the window actually ended up: apps may adjust the requested frame.
            let placed = windows.frame(of: window) ?? next
            history.recordMove(from: current, to: placed, for: window)
        case .restore:
            guard let next = frame(for: target, context: context) else { return }
            _ = history.take(for: window)
            _ = windows.setFrame(next, of: window)
        }
    }
}

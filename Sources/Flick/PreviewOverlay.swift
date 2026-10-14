import AppKit
import FlickCore

/// Click-through panel that draws the target slot while a gesture is in progress.
@MainActor
final class PreviewOverlay: PreviewPresenter {
    /// #2F6BFF, the accent from the design drawing.
    private static let accent = NSColor(srgbRed: 0x2F / 255, green: 0x6B / 255, blue: 0xFF / 255, alpha: 1)

    private let panel: NSPanel

    init() {
        panel = NSPanel(
            contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle, .fullScreenAuxiliary]

        let box = NSView()
        box.wantsLayer = true
        box.layer?.cornerRadius = 12
        box.layer?.borderWidth = 2
        box.layer?.borderColor = Self.accent.cgColor
        box.layer?.backgroundColor = Self.accent.withAlphaComponent(0.2).cgColor
        panel.contentView = box
    }

    func show(_ frame: GlobalRect) {
        let target = frame.flipped(primaryHeight: ScreenAdapter.primaryHeight).nsRect
        // Animate a change of slot; a preview that only moves (following the pointer during a
        // drag) jumps, so it doesn't trail behind.
        if panel.isVisible, panel.frame.size != target.size {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                panel.animator().setFrame(target, display: true)
            }
        } else {
            panel.setFrame(target, display: true)
            panel.orderFrontRegardless()
        }
    }

    func hide() {
        panel.orderOut(nil)
    }
}

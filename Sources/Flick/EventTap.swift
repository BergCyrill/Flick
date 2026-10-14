import AppKit
import FlickCore
import os

/// Session event tap for scroll and trackpad gesture events, plus left-mouse events for drag +
/// scroll. Hands every event to the router and drops the ones it claims (never mouse events).
@MainActor
final class EventTap {
    private static let logger = Logger(subsystem: "local.personal.flick", category: "EventTap")
    /// CGEventType raw values for gesture events, which have no named case in the SDK.
    private static let gestureTypes: [UInt32] = [29, 30]
    private static let mouseTypes: [CGEventType] = [.leftMouseDown, .leftMouseDragged, .leftMouseUp]

    private let router: InputRouter
    private var port: CFMachPort?
    private var source: CFRunLoopSource?

    init(router: InputRouter) {
        self.router = router
    }

    var isRunning: Bool { port != nil }

    /// Returns `false` if the tap could not be created (usually: no Accessibility access).
    func start() -> Bool {
        guard port == nil else { return true }
        var mask = CGEventMask(1) << CGEventType.scrollWheel.rawValue
        for type in Self.gestureTypes {
            mask |= CGEventMask(1) << type
        }
        for type in Self.mouseTypes {
            mask |= CGEventMask(1) << type.rawValue
        }
        guard
            let port = CGEvent.tapCreate(
                tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                eventsOfInterest: mask, callback: eventTapCallback,
                userInfo: Unmanaged.passUnretained(self).toOpaque())
        else {
            Self.logger.error("CGEvent.tapCreate failed")
            return false
        }
        let source = CFMachPortCreateRunLoopSource(nil, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        self.port = port
        self.source = source
        return true
    }

    /// Returns `true` if the event should be swallowed.
    fileprivate func handle(type: CGEventType, input: InputEvent?) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            Self.logger.warning("Event tap disabled by the system (type \(type.rawValue)), re-enabling")
            if let port { CGEvent.tapEnable(tap: port, enable: true) }
            // Events were lost while disabled; don't wait for an `ended` that may never come.
            router.reset()
            return false
        }
        guard let input else { return false }
        return router.handle(input) == .swallow
    }
}

private let eventTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let tap = Unmanaged<EventTap>.fromOpaque(userInfo).takeUnretainedValue()
    // Translate before hopping onto the main actor: CGEvent is not Sendable, InputEvent is.
    let input = EventTranslator.input(from: event)
    // The tap's run-loop source is on the main run loop, so this runs on the main thread.
    let swallow = MainActor.assumeIsolated { tap.handle(type: type, input: input) }
    return swallow ? nil : Unmanaged.passUnretained(event)
}

/// Converts CGEvents into FlickCore's InputEvent. Returns `nil` for anything Flick ignores
/// (mouse wheels without a held button, other gesture kinds).
enum EventTranslator {
    static func input(from cgEvent: CGEvent) -> InputEvent? {
        guard let event = NSEvent(cgEvent: cgEvent) else { return nil }
        let location = GlobalPoint(x: cgEvent.location.x, y: cgEvent.location.y)
        switch event.type {
        case .leftMouseDown:
            return .mouseDown(location: location)
        case .leftMouseDragged:
            return .mouseDragged(location: location)
        case .leftMouseUp:
            return .mouseUp(location: location)
        case .scrollWheel:
            return scroll(event, location: location)
        case .magnify:
            guard let phase = phase(event.phase) else { return nil }
            return .magnify(phase: phase, magnification: event.magnification, location: location)
        default:
            return nil
        }
    }

    private static func scroll(_ event: NSEvent, location: GlobalPoint) -> InputEvent? {
        let momentum = phase(event.momentumPhase)
        // Left button held: a candidate for drag + scroll, mouse wheel and trackpad alike. Asking
        // the event source (not our own mouse-down tracking) means a lost mouse-up can't fool it.
        if momentum == nil, CGEventSource.buttonState(.combinedSessionState, button: .left) {
            return .dragScroll(
                deltaY: event.scrollingDeltaY, precise: event.hasPreciseScrollingDeltas,
                invertedFromDevice: event.isDirectionInvertedFromDevice, location: location)
        }
        guard event.hasPreciseScrollingDeltas else { return nil }
        if let momentum {
            return .momentum(phase: momentum)
        }
        guard let phase = phase(event.phase) else { return nil }
        return .scroll(
            phase: phase, deltaX: event.scrollingDeltaX, deltaY: event.scrollingDeltaY,
            invertedFromDevice: event.isDirectionInvertedFromDevice, location: location)
    }

    private static func phase(_ phase: NSEvent.Phase) -> GesturePhase? {
        if phase.contains(.began) { return .began }
        if phase.contains(.changed) { return .changed }
        if phase.contains(.ended) { return .ended }
        if phase.contains(.cancelled) { return .cancelled }
        if phase.contains(.mayBegin) { return .mayBegin }
        return nil
    }
}

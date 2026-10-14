import AppKit
import FlickCore
import os

/// Marks the right-clicks Flick replays itself, so none of its taps claims them again.
private let replayMarker: Int64 = 0x464C_4B52  // "FLKR"

/// The right press Flick swallowed last, kept until its release decides whether to replay it.
/// Only touched by tap callbacks, which all run on the main run loop.
nonisolated(unsafe) private var heldPress: CGEvent?

/// Session event taps:
/// - an active one for scroll and trackpad gesture events;
/// - a listen-only one for left-mouse events (drag + scroll), so left clicks never wait for Flick;
/// - an active one for right-mouse events (hold + scroll), which swallows titlebar presses and is
///   enabled only while the setting includes the right button.
/// Hands every event to the router and acts on its decision.
@MainActor
final class EventTap {
    private static let logger = Logger(subsystem: "local.personal.flick", category: "EventTap")
    /// CGEventType raw values for gesture events, which have no named case in the SDK.
    private static let gestureTypes: [UInt32] = [29, 30]
    private static let mouseTypes: [CGEventType] = [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
    private static let rightMouseTypes: [CGEventType] = [.rightMouseDown, .rightMouseDragged, .rightMouseUp]

    private let router: InputRouter
    private var port: CFMachPort?
    private var mousePort: CFMachPort?
    private var rightPort: CFMachPort?
    private var sources: [CFRunLoopSource] = []

    /// Whether right-mouse events reach Flick at all. Off: right-clicks never wait for it.
    var isRightButtonEnabled = false {
        didSet { enableTaps() }
    }

    init(router: InputRouter) {
        self.router = router
    }

    var isRunning: Bool { port != nil }

    /// Returns `false` if the taps could not be created (usually: no Accessibility access).
    func start() -> Bool {
        guard port == nil else { return true }
        var mask = CGEventMask(1) << CGEventType.scrollWheel.rawValue
        for type in Self.gestureTypes {
            mask |= CGEventMask(1) << type
        }
        let port = makeTap(mask, options: .defaultTap)
        let mousePort = makeTap(Self.mask(Self.mouseTypes), options: .listenOnly)
        let rightPort = makeTap(Self.mask(Self.rightMouseTypes), options: .defaultTap)
        guard let port, let mousePort, let rightPort else {
            Self.logger.error("CGEvent.tapCreate failed")
            // Don't leave a tap enabled without a run loop to serve it.
            for created in [port, mousePort, rightPort].compactMap({ $0 }) {
                CFMachPortInvalidate(created)
            }
            return false
        }
        for created in [port, mousePort, rightPort] {
            let source = CFMachPortCreateRunLoopSource(nil, created, 0)
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            if let source { sources.append(source) }
        }
        self.port = port
        self.mousePort = mousePort
        self.rightPort = rightPort
        enableTaps()
        return true
    }

    private static func mask(_ types: [CGEventType]) -> CGEventMask {
        types.reduce(CGEventMask(0)) { $0 | CGEventMask(1) << $1.rawValue }
    }

    private func makeTap(_ mask: CGEventMask, options: CGEventTapOptions) -> CFMachPort? {
        CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: options,
            eventsOfInterest: mask, callback: eventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque())
    }

    /// Enables the scroll and left-mouse taps, and the right-mouse tap only while it is wanted.
    /// Disabling a tap ourselves can come back as `tapDisabledByUserInput`; this keeps it off.
    private func enableTaps() {
        for tap in [port, mousePort].compactMap({ $0 }) {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
        if let rightPort {
            CGEvent.tapEnable(tap: rightPort, enable: isRightButtonEnabled)
        }
    }

    fileprivate func handle(type: CGEventType, input: InputEvent?) -> EventDecision {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            Self.logger.warning("Event tap disabled (type \(type.rawValue)), re-enabling")
            enableTaps()
            // Events were lost while disabled; don't wait for an `ended` that may never come.
            router.reset()
            return .passThrough
        }
        guard let input else { return .passThrough }
        return router.handle(input)
    }
}

private let eventTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
    let pass = Unmanaged.passUnretained(event)
    // Clicks Flick replays itself pass untouched.
    guard let userInfo, event.getIntegerValueField(.eventSourceUserData) != replayMarker else { return pass }
    let tap = Unmanaged<EventTap>.fromOpaque(userInfo).takeUnretainedValue()
    // Translate before hopping onto the main actor: CGEvent is not Sendable, InputEvent is.
    let input = EventTranslator.input(from: event)
    // The taps' run-loop sources are on the main run loop, so this runs on the main thread.
    let decision = MainActor.assumeIsolated { tap.handle(type: type, input: input) }
    switch decision {
    case .passThrough:
        return pass
    case .swallow:
        if type == .rightMouseDown {
            heldPress = event.copy()
        }
        return nil
    case .replayPress:
        replay(press: heldPress, release: event)
        heldPress = nil
        return nil
    }
}

/// Posts the swallowed right press and its release again, in that order, marked so Flick's taps
/// let them through: the app gets its right-click after all, on release.
private func replay(press: CGEvent?, release: CGEvent) {
    guard let press, let release = release.copy() else {
        Logger(subsystem: "local.personal.flick", category: "EventTap").error("No right press to replay")
        return
    }
    for event in [press, release] {
        event.setIntegerValueField(.eventSourceUserData, value: replayMarker)
        event.post(tap: .cgSessionEventTap)
    }
}

/// Converts CGEvents into FlickCore's InputEvent. Returns `nil` for anything Flick ignores
/// (mouse wheels without a held button, other gesture kinds).
enum EventTranslator {
    static func input(from cgEvent: CGEvent) -> InputEvent? {
        guard let event = NSEvent(cgEvent: cgEvent) else { return nil }
        let location = GlobalPoint(x: cgEvent.location.x, y: cgEvent.location.y)
        switch event.type {
        case .leftMouseDown, .leftMouseDragged, .leftMouseUp, .rightMouseDown, .rightMouseDragged, .rightMouseUp:
            return mouse(event.type, location: location)
        case .scrollWheel:
            return scroll(event, location: location)
        case .magnify:
            guard let phase = phase(event.phase) else { return nil }
            return .magnify(phase: phase, magnification: event.magnification, location: location)
        default:
            return nil
        }
    }

    private static func mouse(_ type: NSEvent.EventType, location: GlobalPoint) -> InputEvent? {
        switch type {
        case .leftMouseDown: .mouseDown(location: location)
        case .leftMouseDragged: .mouseDragged(location: location)
        case .leftMouseUp: .mouseUp(location: location)
        case .rightMouseDown: .rightMouseDown(location: location)
        case .rightMouseDragged: .rightMouseDragged(location: location)
        case .rightMouseUp: .rightMouseUp(location: location)
        default: nil
        }
    }

    private static func scroll(_ event: NSEvent, location: GlobalPoint) -> InputEvent? {
        let momentum = phase(event.momentumPhase)
        // A held button makes a scroll a candidate for drag + scroll (left) or hold + scroll
        // (right), mouse wheel and trackpad alike. Asking the event source (not our own press
        // tracking) means a lost release can't fool it.
        if momentum == nil, CGEventSource.buttonState(.combinedSessionState, button: .left) {
            return .dragScroll(
                deltaY: event.scrollingDeltaY, precise: event.hasPreciseScrollingDeltas,
                invertedFromDevice: event.isDirectionInvertedFromDevice, location: location)
        }
        // Flick may have swallowed the right press before the session saw it, so the session's
        // state says "up": ask the hardware about the right button instead.
        if momentum == nil, CGEventSource.buttonState(.hidSystemState, button: .right) {
            return .holdScroll(
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

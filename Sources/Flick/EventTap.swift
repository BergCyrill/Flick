import AppKit
import FlickCore
import os

/// Session event tap for trackpad scroll and gesture events. Hands every event to the
/// recognizer and drops the ones it claims.
@MainActor
final class EventTap {
    private static let logger = Logger(subsystem: "local.personal.flick", category: "EventTap")
    /// CGEventType raw values for gesture events, which have no named case in the SDK.
    private static let gestureTypes: [UInt32] = [29, 30]

    private let recognizer: GestureRecognizer
    private var port: CFMachPort?
    private var source: CFRunLoopSource?

    init(recognizer: GestureRecognizer) {
        self.recognizer = recognizer
    }

    var isRunning: Bool { port != nil }

    /// Returns `false` if the tap could not be created (usually: no Accessibility access).
    func start() -> Bool {
        guard port == nil else { return true }
        var mask = CGEventMask(1) << CGEventType.scrollWheel.rawValue
        for type in Self.gestureTypes {
            mask |= CGEventMask(1) << type
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
            recognizer.reset()
            return false
        }
        guard let input else { return false }
        return recognizer.handle(input) == .swallow
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
/// (mouse wheels, other gesture kinds).
enum EventTranslator {
    static func input(from cgEvent: CGEvent) -> InputEvent? {
        guard let event = NSEvent(cgEvent: cgEvent) else { return nil }
        let location = GlobalPoint(x: cgEvent.location.x, y: cgEvent.location.y)
        switch event.type {
        case .scrollWheel:
            guard event.hasPreciseScrollingDeltas else { return nil }
            if let momentum = phase(event.momentumPhase) {
                return .momentum(phase: momentum)
            }
            guard let phase = phase(event.phase) else { return nil }
            return .scroll(
                phase: phase, deltaX: event.scrollingDeltaX, deltaY: event.scrollingDeltaY,
                invertedFromDevice: event.isDirectionInvertedFromDevice, location: location)
        case .magnify:
            guard let phase = phase(event.phase) else { return nil }
            return .magnify(phase: phase, magnification: event.magnification, location: location)
        default:
            return nil
        }
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

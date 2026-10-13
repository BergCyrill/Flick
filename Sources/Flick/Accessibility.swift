import ApplicationServices
import FlickCore

/// Small typed wrappers around the Accessibility C API.
enum Accessibility {
    static func isTrusted(prompt: Bool) -> Bool {
        // String literal instead of kAXTrustedCheckOptionPrompt: the global is not
        // concurrency-safe under Swift 6 strict checking.
        let options = ["AXTrustedCheckOptionPrompt": prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        copy(element, attribute) as? String
    }

    static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let value = copy(element, attribute), CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        return (value as! AXUIElement)  // swiftlint:disable:this force_cast
    }

    static func frame(of element: AXUIElement) -> GlobalRect? {
        var position = CGPoint.zero
        var size = CGSize.zero
        guard let positionValue = axValue(element, kAXPositionAttribute),
            let sizeValue = axValue(element, kAXSizeAttribute),
            AXValueGetValue(positionValue, .cgPoint, &position),
            AXValueGetValue(sizeValue, .cgSize, &size)
        else { return nil }
        return GlobalRect(x: position.x, y: position.y, width: size.width, height: size.height)
    }

    @discardableResult
    static func setPosition(_ element: AXUIElement, x: Double, y: Double) -> Bool {
        var point = CGPoint(x: x, y: y)
        guard let value = AXValueCreate(.cgPoint, &point) else { return false }
        return AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, value) == .success
    }

    @discardableResult
    static func setSize(_ element: AXUIElement, width: Double, height: Double) -> Bool {
        var size = CGSize(width: width, height: height)
        guard let value = AXValueCreate(.cgSize, &size) else { return false }
        return AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, value) == .success
    }

    private static func copy(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value
    }

    private static func axValue(_ element: AXUIElement, _ attribute: String) -> AXValue? {
        guard let value = copy(element, attribute), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        return (value as! AXValue)  // swiftlint:disable:this force_cast
    }
}

extension WindowHandle {
    init(_ element: AXUIElement) {
        self.init(AnyHashable(element))
    }

    /// Only the adapters create WindowHandles, always from an AXUIElement.
    var element: AXUIElement {
        id.base as! AXUIElement  // swiftlint:disable:this force_cast
    }
}

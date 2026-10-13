/// An opaque handle for a window. Only the macOS adapters create and unwrap it;
/// FlickCore just compares and hashes it.
public struct WindowHandle: Hashable {
    public let id: AnyHashable

    public init(_ id: AnyHashable) {
        self.id = id
    }
}

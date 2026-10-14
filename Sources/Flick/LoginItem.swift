import ServiceManagement

/// Launch at login through `SMAppService`. macOS owns the state; Flick only asks for changes
/// and reads the result back.
@MainActor
enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Why launch at login isn't active although it was asked for, or `nil`.
    static var problem: String? {
        SMAppService.mainApp.status == .requiresApproval
            ? "Requires approval in System Settings → Login Items." : nil
    }

    /// Registers or unregisters Flick. Returns the text to show under the switch if it didn't
    /// work out, or `nil`.
    static func set(enabled: Bool) -> String? {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return problem
        } catch {
            return error.localizedDescription
        }
    }

    static func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

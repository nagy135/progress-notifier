import AppKit
import ProgressCore

struct T3ThreadOpener {
    // Beta and Nightly share a bundle ID and URL scheme. Choose the exact app.
    static let applicationURL = URL(fileURLWithPath: "/Applications/T3 Code (Beta).app", isDirectory: true)
    var openURLs: ([URL], URL, NSWorkspace.OpenConfiguration) -> Void = { urls, application, configuration in
        NSWorkspace.shared.open(urls, withApplicationAt: application, configuration: configuration) { _, error in
            if let error { NSLog("Could not open T3 thread: %@", error.localizedDescription) }
        }
    }

    @discardableResult
    func open(_ reference: T3ThreadReference?) -> Bool {
        guard let url = reference?.url else { return false }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        openURLs([url], Self.applicationURL, configuration)
        return true
    }
}

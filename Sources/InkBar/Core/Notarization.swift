import Foundation
import Security

/// While the allowlist is active, macOS 27 hid every listed app that wasn't notarized in testing
/// (Developer ID only, ad-hoc), and kept every notarized or Apple-signed one. Knowing which apps
/// are affected lets the UI explain why they vanish.
enum Notarization {
    private static var cache: [URL: Bool] = [:]
    private static let lock = NSLock()
    // Apple's own apps and Mac App Store apps are signed by Apple instead of notarized.
    private static let requirementText = "anchor apple or notarized or (anchor apple generic and certificate leaf[field.1.2.840.113635.100.6.1.9])"

    static func isTrusted(_ url: URL?) -> Bool {
        guard let url else { return true }
        lock.lock(); defer { lock.unlock() }
        if let known = cache[url] { return known }
        var code: SecStaticCode?
        var requirement: SecRequirement?
        let ok = SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess
            && SecRequirementCreateWithString(requirementText as CFString, [], &requirement) == errSecSuccess
            && SecStaticCodeCheckValidity(code!, [], requirement) == errSecSuccess
        cache[url] = ok
        return ok
    }
}

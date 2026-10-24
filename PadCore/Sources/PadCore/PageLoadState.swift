import Foundation

/// Keeps a failed provisional address visible when WebKit returns to the previous document.
public struct PageLoadState: Sendable {
    public private(set) var attempted: URL?
    public private(set) var failed: URL?
    public init() {}
    public mutating func begin(_ url: URL?) { attempted = url; failed = nil }
    public mutating func commit() { attempted = nil; failed = nil }
    public mutating func fail(_ url: URL?) { failed = url ?? attempted }
    public func displayURL(current: URL?) -> URL? { failed ?? current ?? attempted }
}

public enum PageLoadFailure {
    public static func message(domain: String, code: Int) -> String {
        guard domain == NSURLErrorDomain else {
            return BrowserText.localized("This page could not load. Reload to try again, or check the address.")
        }
        switch code {
        case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost, NSURLErrorDataNotAllowed:
            return BrowserText.localized("The internet connection is unavailable. Check your connection, then reload.")
        case NSURLErrorCannotFindHost, NSURLErrorDNSLookupFailed:
            return BrowserText.localized("This website could not be found. Check the address or try again later.")
        case NSURLErrorSecureConnectionFailed, NSURLErrorServerCertificateHasBadDate,
             NSURLErrorServerCertificateUntrusted, NSURLErrorServerCertificateHasUnknownRoot,
             NSURLErrorServerCertificateNotYetValid, NSURLErrorClientCertificateRejected,
             NSURLErrorClientCertificateRequired:
            return BrowserText.localized("A secure connection could not be verified. Check the address and your device’s date. Try again later or contact the website.")
        case NSURLErrorTimedOut, NSURLErrorCannotConnectToHost:
            return BrowserText.localized("This website did not respond. Reload to try again, or try again later.")
        case NSURLErrorUserAuthenticationRequired, NSURLErrorUserCancelledAuthentication:
            return BrowserText.localized("The website could not sign you in. Reload to try again with another name or password.")
        default:
            return BrowserText.localized("This page could not load. Reload to try again, or check the address.")
        }
    }
}

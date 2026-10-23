import AppKit
import WebKit

enum Metrics { static let card: CGFloat = 12 }

@MainActor
final class Load: NSObject, WKNavigationDelegate {
    var done: (() -> Void)?
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { done?(); done = nil }
}

@main
struct MacViewportValidation {
    @MainActor static func main() {
        let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
Task { @MainActor in
    do {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let web = WKWebView(frame: .zero, configuration: configuration)
        let holder = PageHolder()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = holder
        holder.show(web)
        let loader = Load(); web.navigationDelegate = loader
        await withCheckedContinuation { continuation in
            loader.done = { continuation.resume() }
            web.loadHTMLString("<meta name='viewport' content='width=device-width'><style>body{margin:0}#page{width:100vw;height:100vh}</style><div id='page'>Viewport fixture</div>", baseURL: nil)
        }
        let sizes: [(CGFloat, CGFloat)] = [(944, 720), (824, 720), (1184, 720), (500, 720), (250, 720), (1072, 640)]
        for (index, size) in sizes.enumerated() {
            holder.frame.size = NSSize(width: size.0, height: size.1)
            holder.bounds = NSRect(x: 0, y: 0, width: size.0 - 8, height: size.1 - 8)
            holder.layoutSubtreeIfNeeded()
            guard web.frame == holder.bounds else { fatalError("WebKit frame does not match its visible host after resize") }
            var width = 0
            for _ in 0..<100 {
                width = (try await web.evaluateJavaScript("window.innerWidth") as? NSNumber)?.intValue ?? -1
                if width == Int(holder.bounds.width) { break }
                try await Task.sleep(for: .milliseconds(20))
            }
            guard width == Int(holder.bounds.width) else { fatalError("CSS viewport \(width) differs from visible width \(holder.bounds.width)") }
            print("PASS viewport \(index + 1): \(width) CSS px matches visible host")
        }
        holder.show(nil)
        guard web.superview == nil else { fatalError("Detached page remains attached") }
        print("PASS detach; 7 native viewport checks")
        exit(0)
    } catch { print(error); exit(1) }
}
app.run()

    }
}

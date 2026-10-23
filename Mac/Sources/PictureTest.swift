#if DEBUG
import AppKit
import PadCore
import WebKit

extension Page {
    /// A test build's run of Tests/picture.html, with no one at the keys:
    /// `-pictureHosts 127.0.0.1 -pictureTest /path/report.txt`. Once the page
    /// has loaded it presses the page's buttons from the app (WebKit counts
    /// the app's call as a click), closes the window each way it can go, and
    /// writes what the page's title said after each step.
    private static let pictureReport = UserDefaults.standard.string(forKey: "pictureTest")

    /// The pages already run, each once.
    private static let pictureTested = NSHashTable<Page>.weakObjects()

    func testPictureIfAsked() {
        guard let report = Self.pictureReport, !Self.pictureTested.contains(self), Self.offersPicture(committed ?? view.url),
              !HandsOff.covers(view.url), !HandsOff.covers(committed) else { return }
        Self.pictureTested.add(self)
        Task { @MainActor [weak self] in
            var lines: [String] = []
            @MainActor func note(_ step: String) async {
                guard let self else { return }
                let title = (try? await self.view.callAsyncJavaScript("return document.title", in: nil, contentWorld: .page)) as? String
                let frame = self.picture.map { "\(Int($0.view.frame.width))x\(Int($0.view.frame.height))" } ?? "none"
                lines.append("\(step): title=\(title ?? "?") window=\(frame) automatic=\(self.picture?.automatic ?? false)")
                try? lines.joined(separator: "\n").write(toFile: report, atomically: true, encoding: .utf8)
            }
            @MainActor func press(_ id: String) async {
                _ = try? await self?.view.callAsyncJavaScript("document.getElementById(id).click()", arguments: ["id": id],
                                                              in: nil, contentWorld: .page)
            }
            await note("loaded")
            await press("open")
            try? await Task.sleep(for: .seconds(2.5))
            await note("opened by its button")
            _ = try? await self?.view.callAsyncJavaScript("documentPictureInPicture.window?.close()", in: nil, contentWorld: .page)
            try? await Task.sleep(for: .seconds(1.5))
            await note("closed by the site")
            await press("openSmall")
            try? await Task.sleep(for: .seconds(2.5))
            await note("opened without Back to Tab")
            self?.picture?.close()
            try? await Task.sleep(for: .seconds(1.5))
            await note("closed by the app")
            // Off screen, as a tab switch leaves it: its window lets go of it.
            let window = self?.host
            self?.host = nil
            self?.enterPicture()
            try? await Task.sleep(for: .seconds(2.5))
            await note("opened on leaving the tab")
            self?.host = window
            self?.cameOnScreen()
            try? await Task.sleep(for: .seconds(1.5))
            await note("back on the tab")
            await press("open")
            try? await Task.sleep(for: .seconds(2.5))
            await press("open")
            try? await Task.sleep(for: .seconds(2.5))
            await note("opened again while open")
            _ = try? await self?.view.callAsyncJavaScript("documentPictureInPicture.window?.close()", in: nil, contentWorld: .page)
            try? await Task.sleep(for: .seconds(1.5))
            await note("closed by the site again")
            // Safience behind another app, with a film playing: macOS's picture in picture, and back.
            await press("playFilm")
            try? await Task.sleep(for: .seconds(1.5))
            @MainActor func floating() async -> String {
                let id = try? await self?.view.callAsyncJavaScript("return document.pictureInPictureElement?.id ?? 'none'", in: nil,
                                                                   contentWorld: .page) as? String
                return id ?? "?"
            }
            self?.appWentBehind()
            try? await Task.sleep(for: .seconds(2))
            lines.append("behind another app: in picture in picture \(await floating())")
            self?.appCameBack()
            try? await Task.sleep(for: .seconds(1.5))
            lines.append("back in front: in picture in picture \(await floating())")
            let log = try? await self?.view.callAsyncJavaScript("return document.getElementById('log').textContent", in: nil,
                                                                 contentWorld: .page) as? String
            lines.append("page log:\n" + (log ?? "?"))
            await note("done")
        }
    }
}
#endif

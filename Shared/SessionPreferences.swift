import Foundation
import PadCore

extension Session {
    /// What both apps do after a change to the settings: saved, every page
    /// told, and the history, the blocking and iCloud brought in line. Each
    /// app's Session answers the changes only it has a use for.
    @discardableResult
    func preferencesChanged(from old: Preferences) -> Preferences.Changes {
        preferences.store(in: .standard, key: Session.preferencesKey)
        for page in pages.live.values { page.settingsChanged() }
        let changes = preferences.changes(from: old)
        if changes.contains(.historyRetention) { HistoryRecorder.shared.prune(always: true) }
        if changes.contains(.historySync) {
            if preferences.historySync { HistoryCloud.shared.started(backfill: true) } else { HistoryCloud.shared.switchedOff() }
        }
        if changes.contains(.contentBlocking) { ContentBlocker.shared.preferencesChanged() }
        if changes.contains(.iCloudSync), Session.canSync {
            if preferences.iCloudSync { Sync.shared.start(join: true) } else { Sync.shared.stop() }
        }
        WritingChecker.shared.preferencesChanged(preferences)
        #if os(macOS)
        ElsewhereChecker.shared.preferencesChanged()
        // While Harper checks the writing, WebKit's own spell checking is
        // off: a word would carry two underlines otherwise. What it was
        // comes back once Harper's is off (Decided 15).
        let spellingKey = "WebContinuousSpellCheckingEnabled"
        let spellingWasKey = "egluSpellingBeforeWriting"
        if preferences.writing {
            if UserDefaults.standard.object(forKey: spellingWasKey) == nil {
                // Never set is WebKit's default: on.
                UserDefaults.standard.set(UserDefaults.standard.object(forKey: spellingKey) ?? true,
                                          forKey: spellingWasKey)
            }
            UserDefaults.standard.set(false, forKey: spellingKey)
        } else if let was = UserDefaults.standard.object(forKey: spellingWasKey) {
            UserDefaults.standard.set(was, forKey: spellingKey)
            UserDefaults.standard.removeObject(forKey: spellingWasKey)
        }
        #endif
        return changes
    }
}

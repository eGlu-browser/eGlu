import Foundation

/// Which of the two once-only asks about grammar checking a launch shows
/// (Decided 3-5): the first launch's welcome has the Writing step, a
/// workspace whose welcome is over gets the small sheet once.
public enum WritingOnboarding {
    /// The small sheet asks when the welcome is over and no build has
    /// asked yet (WritingAsked.wasAsked).
    public static func asksSheet(welcomeDone: Bool, wasAsked: Bool) -> Bool {
        welcomeDone && !wasAsked
    }
}

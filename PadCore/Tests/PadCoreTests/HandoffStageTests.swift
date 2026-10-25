import Testing
@testable import PadCore

/// How far a handoff is, and what the sheet shown meanwhile makes of it.
struct HandoffStageTests {
    private static let stages: [Handoff.Stage] = [.reading, .wordsOnly, .stopped]
        + PageKind.allCases.flatMap { [.organising(counted: $0), .ready($0)] }

    @Test("Each step is as far as the stage says", arguments: [
        (Handoff.Stage.reading, [Handoff.Progress.working, .waiting, .waiting]),
        (.organising(counted: .landing), [.done, .working, .waiting]),
        (.ready(.landing), [.done, .done, .working]),
        (.wordsOnly, [.done, .done, .working]),
        (.stopped, [.waiting, .waiting, .waiting]),
    ])
    func steps(at stage: Handoff.Stage, are expected: [Handoff.Progress]) {
        #expect(Handoff.Step.allCases.map(stage.progress(of:)) == expected)
    }

    @Test("One step at the most is at work, with those before it done and those after it waiting", arguments: stages)
    func order(at stage: Handoff.Stage) {
        let steps = Handoff.Step.allCases.map(stage.progress(of:))
        #expect(steps.filter { $0 == .working }.count <= 1)
        // Done, then at work, then waiting: never a step done after one that is not.
        #expect(steps == steps.sorted { rank($0) < rank($1) })
    }

    @Test("A stage has a file only once the page is read, and is settled only once nothing is asked", arguments: stages)
    func flags(of stage: Handoff.Stage) {
        if stage.isOrganising {
            #expect(stage.hasFile)
            #expect(!stage.isSettled)
        }
        if stage == .reading {
            #expect(!stage.hasFile)
            #expect(!stage.isSettled)
        }
        if case .ready = stage {
            #expect(stage.hasFile)
            #expect(stage.isSettled)
        }
    }

    @Test("What the sheet says of a stage is two lines of one line each on the narrowest iPhone", arguments: stages)
    func lines(for stage: Handoff.Stage) {
        // The sheet is as high as it was measured with the first pair: a
        // longer line would wrap and push the button out of it. These are
        // what the card's column holds on a 375-point screen, at its sizes.
        #expect(stage.headline.count <= 24, "\(stage.headline)")
        #expect(stage.detail.count <= 32, "\(stage.detail)")
        #expect(!stage.headline.isEmpty && !stage.detail.isEmpty)
        // Said to a person: a sentence about what they share, or how long they wait.
        #expect(stage.detail.hasSuffix("."))
        // A file's words too, with its address or, on the device, its name.
        for named in [false, true] {
            let headline = stage.headline(ofFile: true, named: named)
            let detail = stage.detail(selected: false, ofFile: true, named: named)
            #expect(headline.count <= 24, "\(headline)")
            #expect(detail.count <= 32 && detail.hasSuffix("."), "\(detail)")
        }
    }

    @Test("A file's words fit as a page's do where it goes without its content, and say its name where it has no address")
    func fileLines() {
        for named in [false, true] {
            #expect(Handoff.Stage.addressOnly.headline(ofFile: true, named: named).count <= 24)
            #expect(Handoff.Stage.addressOnly.detail(selected: false, ofFile: true, named: named).count <= 32)
            #expect(Handoff.Stage.failed(.reading).detail(selected: false, ofFile: true, named: named).count <= 32)
        }
        #expect(Handoff.Stage.failed(.reading).detail(selected: false, ofFile: true, named: true) == "Try again or share its name.")
        #expect(Handoff.Stage.addressOnly.headline(ofFile: true, named: true) == "Share the file's name")
        #expect(Handoff.Stage.addressOnly.headline(ofFile: true) == "Share the file's address")
        #expect(Handoff.Stage.wordsOnly.detail(selected: false, ofFile: true, named: true) == "You'll share the file's name.")
    }

    @Test("A page that is ready says what it is, and one still read says so")
    func words() {
        #expect(Handoff.Stage.organising(counted: .article).headline == Handoff.Stage.reading.headline)
        #expect(Handoff.Stage.organising(counted: .article).detail == Handoff.Stage.reading.detail)
        let ready = PageKind.allCases.map { Handoff.Stage.ready($0).headline }
        #expect(Set(ready).count == PageKind.allCases.count)
        #expect(!ready.contains(Handoff.Stage.reading.headline))
        // What is shared is said of every page that is ready, and never as a wait.
        for kind in PageKind.allCases {
            #expect(Handoff.Stage.ready(kind).detail.hasPrefix("You'll share"))
        }
    }

    @Test("With something selected on the page, a page that is ready says that it goes first", arguments: stages)
    func selection(at stage: Handoff.Stage) {
        let line = stage.detail(selected: true)
        if case .ready = stage {
            #expect(line == "Your selection goes first.")
        } else {
            // Nothing is ready to be said of: the wait, or that there is nothing to read.
            #expect(line == stage.detail)
        }
        #expect(line.count <= 32 && line.hasSuffix("."))
        #expect(stage.detail(selected: false) == stage.detail)
        // A transcript got from the site is said where the page is ready, the selection before it, and in a line as short as the rest.
        let spoken = stage.detail(selected: false, transcribed: true)
        if case .ready = stage {
            #expect(spoken == "You'll share its transcript too." && spoken.count <= 32)
            #expect(stage.detail(selected: true, transcribed: true) == "Your selection goes first.")
        } else {
            #expect(spoken == stage.detail)
        }
    }

    private func rank(_ progress: Handoff.Progress) -> Int {
        switch progress {
        case .done: return 0
        case .working: return 1
        case .waiting: return 2
        }
    }
}

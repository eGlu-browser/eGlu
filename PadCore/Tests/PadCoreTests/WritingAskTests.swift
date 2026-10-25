import XCTest
@testable import PadCore

final class WritingAskTests: XCTestCase {
    /// The table from the task: a welcome in progress asks on its own step,
    /// a done welcome leaves the small sheet to ask, and once the flag is
    /// set nothing ever asks again.
    func testTheDecisionFollowsTheWelcomeAndTheFlag() {
        XCTAssertEqual(WritingAsk.decision(welcomePending: true, asked: false), .welcomeStep)
        XCTAssertEqual(WritingAsk.decision(welcomePending: false, asked: false), .sheet)
        XCTAssertEqual(WritingAsk.decision(welcomePending: false, asked: true), .nothing)
        XCTAssertEqual(WritingAsk.decision(welcomePending: true, asked: true), .nothing)
    }
}

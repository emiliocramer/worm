import XCTest
@testable import Worm

final class ProgressionTests: XCTestCase {
    func test_stepReward_defaults_growthAndInsightOn_recommendationDormant() {
        let r = StepReward()
        XCTAssertTrue(r.growth)
        XCTAssertTrue(r.insight)
        XCTAssertNil(r.cosmetic)
        XCTAssertFalse(r.recommendation)
    }

    func test_progressionState_roundTripsThroughJSON() throws {
        var state = ProgressionState()
        state.cursor = 3
        state.mode = .cooldown
        state.completedEntryIDs = ["apple-music", "fit-photo"]
        state.earnedCosmetics = [.midnight]
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(ProgressionState.self, from: data)
        XCTAssertEqual(decoded.cursor, 3)
        XCTAssertEqual(decoded.mode, .cooldown)
        XCTAssertEqual(decoded.completedEntryIDs, ["apple-music", "fit-photo"])
        XCTAssertEqual(decoded.earnedCosmetics, [.midnight])
    }
}

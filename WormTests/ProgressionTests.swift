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

    func test_everyScheduleStep_referencesARealCatalogEntry() {
        let ids = Set(NodeCatalog.all.map(\.id))
        for step in NodeCatalog.firstRunSchedule {
            XCTAssertTrue(ids.contains(step.entryID), "schedule step \(step.entryID) has no catalog entry")
        }
    }

    func test_catalogEntryIDs_areUnique() {
        let ids = NodeCatalog.all.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count)
    }

    func test_sourceEntries_haveRoute_promptEntries_haveSpec() {
        for e in NodeCatalog.all {
            switch e.captureKind {
            case .source:
                XCTAssertNotNil(e.sourceRoute, "\(e.id) is .source but has no route")
            case .photo, .text, .choice:
                XCTAssertNotNil(e.prompt, "\(e.id) is a prompt kind but has no PromptSpec")
            }
        }
    }

    func test_cooldownPool_isEveryUnscheduledEntry_promptsFirst() {
        let scheduled = Set(NodeCatalog.firstRunSchedule.map(\.entryID))
        let expected = Set(NodeCatalog.all.map(\.id)).subtracting(scheduled)
        XCTAssertEqual(Set(NodeCatalog.cooldownPool.map(\.id)), expected)
        for e in NodeCatalog.cooldownPool {
            XCTAssertFalse(scheduled.contains(e.id), "\(e.id) is scheduled but also in cooldown")
        }
        // Prompts are offered before any source node.
        if let firstSource = NodeCatalog.cooldownPool.firstIndex(where: { $0.captureKind == .source }),
           let lastPrompt = NodeCatalog.cooldownPool.lastIndex(where: { $0.captureKind != .source }) {
            XCTAssertLessThan(lastPrompt, firstSource)
        }
    }

    func test_promptEntries_mapToPromptsBrainNode() {
        for e in NodeCatalog.prompts { XCTAssertEqual(e.brainNodeID, .prompts) }
        for e in NodeCatalog.source { XCTAssertNotEqual(e.brainNodeID, .prompts) }
    }
}

import XCTest
@testable import SprintPulseCore

/// The pure Cap seam, both halves of the Cap table in `docs/agents/glossary.md`: which Caps fire
/// (`Cap.fired`), and what a fired Cap does to a state (`ConfidenceState.demotedOneBand`).
///
/// `ForecastTests` covers the same rules end to end through fixtures; this seam carries the
/// arithmetic the corpus has no reason to occupy — a Waiting share of exactly 40%, which is a
/// number rather than a scenario.
final class CapTests: XCTestCase {

    // MARK: - The Unestimated Cap (`U > 0`)

    func test_fired_oneUnsizedIssueInActionableOrWaiting_firesTheUnestimatedCap() {
        XCTAssertEqual(
            Cap.fired(unestimatedCount: 1, actionablePoints: 4, waitingPoints: 0),
            [.unestimated]
        )
    }

    func test_fired_noUnsizedIssue_firesNothing() {
        XCTAssertEqual(
            Cap.fired(unestimatedCount: 0, actionablePoints: 4, waitingPoints: 0),
            []
        )
    }

    // MARK: - The Waiting-heavy Cap (`W ÷ (A + W) > 0.40`)

    func test_fired_waitingShareAboveFortyPercent_firesTheWaitingHeavyCap() {
        // W = 8 of A + W = 12 → 0.667.
        XCTAssertEqual(
            Cap.fired(unestimatedCount: 0, actionablePoints: 4, waitingPoints: 8),
            [.waitingHeavy]
        )
    }

    /// The glossary's inequality is strict, so a share of exactly 40% is not heavy.
    func test_fired_waitingShareExactlyAtTheBoundary_firesNothing() {
        // W = 8 of A + W = 20 → exactly 0.40.
        XCTAssertEqual(
            Cap.fired(unestimatedCount: 0, actionablePoints: 12, waitingPoints: 8),
            []
        )
    }

    /// `A + W = 0` is `Finished` by rule 2 and no Cap can demote that; the share is undefined
    /// arithmetic, not zero.
    func test_fired_noRemainingPoints_firesNothing() {
        XCTAssertEqual(
            Cap.fired(unestimatedCount: 0, actionablePoints: 0, waitingPoints: 0),
            []
        )
    }

    func test_fired_bothConditionsHold_firesBothInDeclarationOrder() {
        XCTAssertEqual(
            Cap.fired(unestimatedCount: 3, actionablePoints: 4, waitingPoints: 8),
            [.unestimated, .waitingHeavy]
        )
    }

    // MARK: - What a fired Cap does (the demotion scale)

    func test_demotedOneBand_stepsDownTheScaleByExactlyOneBand() {
        XCTAssertEqual(ConfidenceState.noSweat.demotedOneBand, .onTrack)
        XCTAssertEqual(ConfidenceState.onTrack.demotedOneBand, .tight)
        XCTAssertEqual(ConfidenceState.tight.demotedOneBand, .offTrack)
    }

    /// The bottom of the scale: fired Caps have nowhere left to take a Reading that is already
    /// `Off Track`, and a Cap must never promote, so there is no step back up either.
    func test_demotedOneBand_offTrackCannotDemoteFurther() {
        XCTAssertNil(ConfidenceState.offTrack.demotedOneBand)
    }

    /// `Unknown`, `Hands Off` and `Finished` are named answers, not points on the band scale.
    func test_demotedOneBand_statesThatAreNotOnTheScaleAreNeverDemoted() {
        for state in [ConfidenceState.unknown, .handsOff, .finished] {
            XCTAssertNil(state.demotedOneBand, "\(state) is not a point on the band scale")
        }
    }

    // MARK: - Firing, then walking the scale

    /// The clamp: two Caps fired, one band available. The Reading reports both — they hold — but
    /// lost only one band, which is the difference between an honest `Off Track` and a sentence
    /// claiming a demotion that never happened.
    func test_state_bottomOfTheScaleReachedMidWalk_clampsRatherThanOverreporting() {
        let reading = ConfidenceReading(rule: .ratioTight, caps: [.unestimated, .waitingHeavy])

        XCTAssertEqual(reading.uncappedState, .tight)
        XCTAssertEqual(reading.state, .offTrack)
        XCTAssertEqual(reading.demotions, 1)
    }

    func test_state_noCapFired_leavesTheTablesAnswerUntouched() {
        let reading = ConfidenceReading(rule: .ratioNoSweat, caps: [])

        XCTAssertEqual(reading.state, .noSweat)
        XCTAssertEqual(reading.demotions, 0)
    }
}

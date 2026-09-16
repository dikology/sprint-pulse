import XCTest
@testable import SprintPulseCore

final class ForecastTests: XCTestCase {
    /// The Operator, whose `key` matches the fixture assignees and whose `name` differs from
    /// their `key` so key-vs-name matching is actually exercised.
    let operatorIdentity = OperatorIdentity(key: "JIRAUSER10500", name: "dgimaletdinov")

    /// A pinned "today" inside the fixtures' sprint window.
    let now = isoDate("2026-09-08T12:00:00Z")

    /// Monday–Friday, pinned to UTC so `workingDaysRemaining` is deterministic regardless of the
    /// machine running the tests.
    let workingCalendar = WorkingCalendar(timeZone: TimeZone(identifier: "UTC")!)

    private func snapshot(_ fixture: String) async throws -> SprintSnapshot {
        let gateway = try FixtureJiraGateway.bundled(named: fixture)
        let sprint = try SprintSnapshot.selectActiveSprint(from: try await gateway.activeSprints())
        let issues = try await gateway.issues(inSprint: sprint.id)
        return SprintSnapshot(sprint: sprint, issues: issues.issues)
    }

    /// The stored-Baseline half of a Scope Delta scenario, bundled beside the Jira-shaped
    /// responses. Deliberately not a gateway concern: the Baseline is Sprint Pulse's own
    /// persisted value, not something Jira returns. `nil` for fixtures without one — those
    /// are first-observation scenarios.
    private func bundledBaseline(_ fixture: String) throws -> SprintBaseline? {
        let url = try FixtureJiraGateway.bundledDirectory(named: fixture)
            .appendingPathComponent("baseline.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(SprintBaseline.self, from: data)
    }

    private func evaluate(_ fixture: String, baseline: SprintBaseline? = nil) async throws -> (instrument: Instrument, baseline: SprintBaseline) {
        let stored = try bundledBaseline(fixture)
        return Forecast.evaluate(
            snapshot: try await snapshot(fixture),
            identity: operatorIdentity,
            statusMap: .default,
            workingCalendar: workingCalendar,
            baseline: baseline ?? stored,
            now: now
        )
    }

    /// For the Confidence fixtures, each of which is pinned against its own "now" rather than
    /// the shared one above. Resolves the bundled Baseline the same way the primary helper
    /// does, so one fixture name means one scenario in this file.
    private func evaluate(_ fixture: String, now: Date) async throws -> Instrument {
        Forecast.evaluate(
            snapshot: try await snapshot(fixture),
            identity: operatorIdentity,
            statusMap: .default,
            workingCalendar: workingCalendar,
            baseline: try bundledBaseline(fixture),
            now: now
        ).instrument
    }

    // MARK: - The whole Instrument

    /// The acceptance test: construct the domain from a fixture and a fixed date, then assert
    /// on the whole `Instrument` in a single comparison.
    func test_evaluate_fromWalkingSkeletonFixture_producesTheWholeInstrument() async throws {
        let result = try await evaluate("walking-skeleton")

        XCTAssertEqual(
            result.instrument,
            Instrument(
                sprintName: "Mobile Platform Sprint 34",
                // MOB-1201 In Progress (5); MOB-1202, -1203 Open (8, unestimated).
                pointsByFlowState: [
                    .toDo: 8, .inProgress: 5, .inReview: 0, .onHold: 0, .done: 0, .dropped: 0,
                ],
                unestimatedCount: 1,
                unmappedStatuses: [],
                // Tue 09-08 (now) through Sat 09-12 (sprint end): Tue–Fri are Working Days,
                // Saturday is not.
                workingDaysRemaining: 4,
                // Tue 09-01 (sprint start) through Tue 09-08 (now): six weekdays.
                workingDaysElapsed: 6,
                // A = 13, WDR = 4.
                requiredRate: 3.25,
                // C = 0 — the walking skeleton has nothing Done yet, so D is undefined and
                // Confidence withdraws to `Unknown` (rule 4) rather than guessing.
                demonstratedRate: nil,
                // MOB-1203 is unsized, so the Unestimated Cap fires — but `Unknown` is not a band
                // on the scale, so there is nothing for it to demote.
                reading: ConfidenceReading(rule: .insufficientHistory, caps: [.unestimated]),
                // #8: the whole sprint's task-level Points — 5 + 8 + 13 + 2; MOB-1203 is
                // Unestimated and contributes nothing, MOB-1204 is a sub-task and is not an Issue.
                liveSprintPoints: 28,
                // First observation: the Baseline is captured from these same Points, so the
                // sprint has not moved from anything.
                baselinePoints: 28
            )
        )
        XCTAssertEqual(result.instrument.scopeDelta, 0)
    }

    func test_evaluate_excludesSubTasksAndOtherPeoplesWork() async throws {
        // MOB-1201 (5) + MOB-1202 (8) = 13 Actionable. MOB-1203 is unestimated.
        // MOB-1204 is a sub-task, MOB-1205 belongs to another assignee, MOB-1207 is
        // unassigned — none contribute.
        let result = try await evaluate("walking-skeleton")

        XCTAssertEqual(result.instrument.actionablePoints, 13)
        XCTAssertEqual(result.instrument.pointsRemaining, 13)
    }

    func test_evaluate_matchesTheOperatorByNameWhenKeyDiffers() async throws {
        let byName = OperatorIdentity(key: "JIRAUSER99999", name: "dgimaletdinov")
        let result = Forecast.evaluate(
            snapshot: try await snapshot("walking-skeleton"),
            identity: byName, statusMap: .default, workingCalendar: workingCalendar,
            baseline: nil, now: now
        )

        XCTAssertEqual(result.instrument.actionablePoints, 13)
    }

    // MARK: - Points per Flow State (all six)

    func test_evaluate_partitionsMyWorkAcrossAllSixFlowStates() async throws {
        let i = try await evaluate("all-flow-states").instrument

        XCTAssertEqual(i.points(.toDo), 5)        // AFS-1201 Open (3) + AFS-1202 Backlog (2)
        XCTAssertEqual(i.points(.inProgress), 5)  // AFS-1203 In Progress
        XCTAssertEqual(i.points(.inReview), 8)    // AFS-1204 In Review
        XCTAssertEqual(i.points(.onHold), 1)      // AFS-1205 Need Info
        XCTAssertEqual(i.points(.done), 13)       // AFS-1206 Done
        XCTAssertEqual(i.points(.dropped), 21)    // AFS-1207 Cancelled
    }

    func test_evaluate_showsActionableAndWaitingAsSeparateTotals() async throws {
        let i = try await evaluate("all-flow-states").instrument

        XCTAssertEqual(i.actionablePoints, 10)  // 5 + 5
        XCTAssertEqual(i.waitingPoints, 9)      // 8 + 1
    }

    func test_evaluate_droppedIsItsOwnFigureExcludedFromEveryRemainingTotalAndNeverCompleted() async throws {
        let i = try await evaluate("all-flow-states").instrument

        XCTAssertEqual(i.droppedPoints, 21)
        XCTAssertEqual(i.completedPoints, 13, "Dropped Points are never added to Completed")
        XCTAssertEqual(i.pointsRemaining, 19, "Dropped and Done are excluded from the remaining total")
        XCTAssertFalse(FlowState.actionable.contains(.dropped))
        XCTAssertFalse(FlowState.waiting.contains(.dropped))
    }

    // MARK: - Unmapped Status

    func test_evaluate_surfacesUnmappedStatusesEachNamedOnceAndExcludesTheirIssues() async throws {
        let i = try await evaluate("unmapped-status").instrument

        // "Blocked" (UMS-1303, -1306) and "Escalated" (UMS-1305) are absent from the map.
        XCTAssertEqual(i.unmappedStatuses, ["Blocked", "Escalated"])
        // Their Issues are in no set: only UMS-1301 (5) and UMS-1302 (3) reach Actionable,
        // only UMS-1304 (2) reaches Waiting. The 8 + 1 behind "Blocked" is nowhere.
        XCTAssertEqual(i.actionablePoints, 8)
        XCTAssertEqual(i.waitingPoints, 2)
        XCTAssertEqual(i.pointsRemaining, 10)
    }

    func test_evaluate_noUnmappedStatusesForAWorkflowThatFitsTheDefaultMap() async throws {
        let i = try await evaluate("all-flow-states").instrument
        XCTAssertEqual(i.unmappedStatuses, [])
    }

    // MARK: - Unestimated Issues

    func test_evaluate_countsUnestimatedIssuesOnlyInActionableOrWaitingAndNeverAsPoints() async throws {
        let i = try await evaluate("unestimated-across-states").instrument

        // UNE-1401 ToDo, UNE-1402 InProgress, UNE-1403 InReview — three unsized Issues in
        // Actionable ∪ Waiting.
        XCTAssertEqual(i.unestimatedCount, 3)
        // UNE-1405 Done and UNE-1406 Dropped are also unsized but are not counted.
        // The unsized Issues add nothing: only UNE-1407 (5) and UNE-1404 (3) are Points.
        XCTAssertEqual(i.points(.toDo), 5)
        XCTAssertEqual(i.points(.inProgress), 0)
        XCTAssertEqual(i.points(.inReview), 0)
        XCTAssertEqual(i.points(.onHold), 3)
        XCTAssertEqual(i.points(.done), 0)
        XCTAssertEqual(i.points(.dropped), 0)
    }

    // MARK: - Sub-task estimates

    func test_evaluate_ignoresSubTaskEstimatesEntirelyRatherThanRollingThemUp() async throws {
        let i = try await evaluate("subtasks-with-estimates").instrument

        // Only the two task-level Issues count: SUB-1504 Open (2), SUB-1501 In Progress (5).
        // The sub-tasks carry 8 + 13 + 3 that must appear nowhere.
        XCTAssertEqual(i.points(.toDo), 2)
        XCTAssertEqual(i.points(.inProgress), 5)
        XCTAssertEqual(i.points(.inReview), 0)
        XCTAssertEqual(i.actionablePoints, 7)
        XCTAssertEqual(i.waitingPoints, 0)
        XCTAssertEqual(i.unestimatedCount, 0)
    }

    // MARK: - Sprint Baseline

    func test_evaluate_capturesTheBaselineOnFirstObservation() async throws {
        let result = try await evaluate("walking-skeleton")

        XCTAssertEqual(result.baseline.sprintID, 5281)
        XCTAssertEqual(result.baseline.capturedAt, now)
        // Whole sprint, task-level only: MOB-1201, -1202, -1203, -1205, -1207. Not the sub-task.
        XCTAssertEqual(
            result.baseline.entries.sorted { $0.key < $1.key },
            [
                .init(key: "MOB-1201", estimate: 5),
                .init(key: "MOB-1202", estimate: 8),
                .init(key: "MOB-1203", estimate: nil),
                .init(key: "MOB-1205", estimate: 13),
                .init(key: "MOB-1207", estimate: 2),
            ]
        )
    }

    func test_evaluate_keepsAnExistingBaselineForTheSameSprint() async throws {
        let existing = SprintBaseline(
            sprintID: 5281,
            capturedAt: isoDate("2026-09-01T09:03:11Z"),
            entries: [.init(key: "MOB-1201", estimate: 3)]
        )

        let result = try await evaluate("walking-skeleton", baseline: existing)

        XCTAssertEqual(result.baseline, existing)
    }

    func test_evaluate_recapturesTheBaselineWhenTheSprintChanges() async throws {
        let staleFromAnotherSprint = SprintBaseline(
            sprintID: 4999,
            capturedAt: isoDate("2026-08-01T09:00:00Z"),
            entries: []
        )

        let result = try await evaluate("walking-skeleton", baseline: staleFromAnotherSprint)

        XCTAssertEqual(result.baseline.sprintID, 5281)
        XCTAssertEqual(result.baseline.capturedAt, now)
    }

    // MARK: - Scope Delta (#8)

    /// The sprint grew underneath the Operator: two Issues (34 Points) entered after the
    /// Baseline was taken on day one. Added scope reads positive.
    func test_evaluate_scopeGrowthFixture_reportsLargePositiveScopeDelta() async throws {
        let result = try await evaluate("scope-growth")
        let i = result.instrument

        // 8 + 5 + 13 + 21; SGR-1805's 99 is a sub-task and SGR-1806 is unsized — an Unestimated
        // Issue contributes nothing, never a coerced zero (invariant 2).
        XCTAssertEqual(i.liveSprintPoints, 47)
        // Day one was SGR-1801 (8) + SGR-1802 (5). Their later Done and In Progress statuses
        // move Points between Flow States, not this figure.
        XCTAssertEqual(i.baselinePoints, 13)
        XCTAssertEqual(i.scopeDelta, 34)
        // The forecast runs on live Points (invariant 9): A = 5 + 13 over WDR = 4 — nothing
        // here reads the Baseline.
        XCTAssertEqual(i.requiredRate, 4.5)
        // The fixed Baseline leaves core as the value that entered it.
        XCTAssertEqual(result.baseline, try bundledBaseline("scope-growth"))
    }

    /// Scope counts the sprint's shape, not the flow within it: Unmapped Status Issues are
    /// excluded from the forecast's totals, but a status nobody has mapped has not left the
    /// sprint either. Both sides of the Delta read the same Issue set, so an unmapped status
    /// moves nothing here — were it excluded, merely transitioning an Issue would read as work
    /// removed, the very unattributable movement #8 exists to remove.
    func test_evaluate_unmappedStatusIssues_stayInSprintShapeAndLeaveTheForecast() async throws {
        let i = try await evaluate("unmapped-status").instrument

        XCTAssertEqual(i.liveSprintPoints, 19, "5 + 3 + 8 + 2 + 1; UMS-1305 is Unestimated")
        XCTAssertEqual(i.baselinePoints, 19, "first observation: this shape is what was captured")
        XCTAssertEqual(i.scopeDelta, 0)
        XCTAssertEqual(i.pointsRemaining, 10, "the forecast still sees only mapped Issues")
    }

    func test_evaluate_confidenceIsComputedFromLivePointsNotTheBaseline() async throws {
        // The same sprint read two ways: fresh (Baseline captured now, Delta 0) and against its
        // day-one Baseline. Every forecast figure is identical between them — only the Scope
        // numbers differ, because only they compare against the Baseline.
        let fresh = Forecast.evaluate(
            snapshot: try await snapshot("scope-growth"), identity: operatorIdentity,
            statusMap: .default, workingCalendar: workingCalendar, baseline: nil, now: now
        ).instrument
        let grown = try await evaluate("scope-growth").instrument

        XCTAssertEqual(fresh.requiredRate, grown.requiredRate)
        XCTAssertEqual(fresh.demonstratedRate, grown.demonstratedRate)
        XCTAssertEqual(fresh.reading, grown.reading)
        XCTAssertEqual(fresh.confidenceState, grown.confidenceState)
        XCTAssertEqual(fresh.scopeDelta, 0, "first observation has witnessed no movement")
        XCTAssertNotEqual(fresh.baselinePoints, grown.baselinePoints)
    }

    /// Work removed from the sprint — Dropped out, not `Dropped` in status: the Issues are no
    /// longer in it at all. Removed work reads negative, differently from added scope.
    func test_evaluate_scopeShrinkFixture_reportsNegativeScopeDeltaFromRemovedWork() async throws {
        let i = try await evaluate("scope-shrink").instrument

        XCTAssertEqual(i.liveSprintPoints, 21)
        XCTAssertEqual(i.baselinePoints, 29, "SSK-1903 (5) and SSK-1904 (3) left the sprint")
        XCTAssertEqual(i.scopeDelta, -8)
        // Removed work is not Completed work either: C counts only the Done Issue.
        XCTAssertEqual(i.completedPoints, 8)
    }

    /// The app installed on day six: the Baseline is captured from the moment of first
    /// observation, not reconstructed from day one, and nothing has moved since it was seen.
    func test_evaluate_coldStartMidSprint_capturesBaselineFromNowAndReadsZeroDelta() async throws {
        XCTAssertEqual(
            workingCalendar.workingDaysElapsed(now: now, sprintStart: isoDate("2026-09-01T09:00:00Z")),
            6, "the shared `now` is the sixth Working Day of this sprint — a true cold start"
        )

        let result = try await evaluate("baseline-cold-start")

        XCTAssertEqual(result.baseline.capturedAt, now, "first observation is not day one")
        XCTAssertEqual(result.instrument.baselinePoints, result.instrument.liveSprintPoints)
        XCTAssertEqual(result.instrument.scopeDelta, 0)
        XCTAssertEqual(
            result.baseline.entries.map(\.key).sorted(),
            ["BCS-2001", "BCS-2002", "BCS-2003"]
        )

        // Re-observing with the just-captured Baseline: it is fixed, and the reading holds.
        let again = Forecast.evaluate(
            snapshot: try await snapshot("baseline-cold-start"), identity: operatorIdentity,
            statusMap: .default, workingCalendar: workingCalendar,
            baseline: result.baseline, now: now
        )
        XCTAssertEqual(again.baseline, result.baseline)
        XCTAssertEqual(again.instrument, result.instrument)
    }

    /// A sprint entirely `Dropped`: every Issue was cancelled where it sat. That is flow leaving
    /// the remaining total — the Dropped figure — not the sprint changing shape: Scope Delta
    /// stays 0, and the two figures read differently on the panel.
    func test_evaluate_allDroppedFixture_showsCancelledWorkAsDroppedNotScopeMovement() async throws {
        let i = try await evaluate("all-dropped").instrument

        XCTAssertEqual(i.droppedPoints, 13, "the Operator's two Cancelled Issues")
        XCTAssertEqual(i.liveSprintPoints, 26, "the sprint still carries every Issue")
        XCTAssertEqual(i.baselinePoints, 26, "same Issues, same Estimates as day one")
        XCTAssertEqual(i.scopeDelta, 0, "cancelling in place is not scope movement")
        XCTAssertEqual(i.completedPoints, 0, "Dropped Points are never credited as Completed")
        XCTAssertEqual(i.pointsRemaining, 0)
        XCTAssertEqual(i.confidenceState, .finished, "nothing Actionable or Waiting survives")
    }

    // MARK: - Confidence State: the rate-based bands (rules 6–9)

    /// A = 4, WDR = 4 ⇒ R = 1.0. C = 2, WDE = 4 ⇒ D = 0.5. ratio 0.5 < 0.75.
    func test_evaluate_ratioBelowSevenFive_isOffTrack() async throws {
        let i = try await evaluate("confidence-off-track", now: isoDate("2026-09-17T12:00:00Z"))

        XCTAssertEqual(i.requiredRate, 1.0)
        XCTAssertEqual(i.demonstratedRate, 0.5)
        XCTAssertEqual(i.confidenceState, .offTrack)
    }

    /// A = 4, C = 3, WDR = WDE = 4 ⇒ ratio exactly 0.75, the `Tight` boundary.
    func test_evaluate_ratioAtSevenFive_isTight() async throws {
        let i = try await evaluate("confidence-tight", now: isoDate("2026-09-17T12:00:00Z"))

        XCTAssertEqual(i.requiredRate, 1.0)
        XCTAssertEqual(i.demonstratedRate, 0.75)
        XCTAssertEqual(i.confidenceState, .tight)
    }

    /// A = 4, C = 4, WDR = WDE = 4 ⇒ ratio exactly 1.00, the `On Track` boundary.
    func test_evaluate_ratioAtOne_isOnTrack() async throws {
        let i = try await evaluate("confidence-on-track", now: isoDate("2026-09-17T12:00:00Z"))

        XCTAssertEqual(i.requiredRate, 1.0)
        XCTAssertEqual(i.demonstratedRate, 1.0)
        XCTAssertEqual(i.confidenceState, .onTrack)
    }

    /// A = 4, C = 5, WDR = WDE = 4 ⇒ ratio exactly 1.25, the `No Sweat` boundary.
    func test_evaluate_ratioAtOnePointTwoFive_isNoSweat() async throws {
        let i = try await evaluate("confidence-no-sweat", now: isoDate("2026-09-17T12:00:00Z"))

        XCTAssertEqual(i.requiredRate, 1.0)
        XCTAssertEqual(i.demonstratedRate, 1.25)
        XCTAssertEqual(i.confidenceState, .noSweat)
    }

    // MARK: - Confidence State: `Unknown` (rules 1 and 4)

    /// Day one of the sprint: only one Working Day has elapsed. Confidence withdraws even
    /// though there is Actionable work and Working Days remain to burn it against.
    func test_evaluate_fewerThanTwoWorkingDaysElapsed_isUnknown() async throws {
        let i = try await evaluate("confidence-cold-start", now: isoDate("2026-09-14T09:00:00Z"))

        XCTAssertEqual(i.workingDaysElapsed, 1)
        XCTAssertEqual(i.confidenceState, .unknown)
        XCTAssertNotNil(i.requiredRate, "Required Rate stays visible while Confidence is Unknown")
        XCTAssertNil(i.demonstratedRate)
    }

    /// Enough elapsed history (`WDE ≥ 2`), but nothing Done yet: Demonstrated Rate is
    /// unmeasurable, not zero, so Confidence withdraws rather than guessing.
    func test_evaluate_zeroCompletedPoints_isUnknown() async throws {
        let i = try await evaluate("confidence-zero-completed", now: isoDate("2026-09-17T12:00:00Z"))

        XCTAssertEqual(i.workingDaysElapsed, 4)
        XCTAssertEqual(i.confidenceState, .unknown)
        XCTAssertNotNil(i.requiredRate, "Required Rate stays visible while Confidence is Unknown")
        XCTAssertNil(i.demonstratedRate)
    }

    /// An Unmapped Status forces `Unknown` (rule 1) ahead of every other rule, and the Required
    /// Rate stays visible even so.
    func test_evaluate_unmappedStatus_isUnknownButKeepsRequiredRateVisible() async throws {
        let i = try await evaluate("unmapped-status").instrument

        XCTAssertEqual(i.confidenceState, .unknown)
        XCTAssertEqual(i.requiredRate, 2.0, "8 Actionable Points over 4 Working Days Remaining")
    }

    // MARK: - Confidence State: `Hands Off` and `Finished` (rules 2–3)

    func test_evaluate_noActionableButWaitingRemains_isHandsOff() async throws {
        let i = try await evaluate("confidence-hands-off", now: isoDate("2026-09-17T12:00:00Z"))

        XCTAssertEqual(i.actionablePoints, 0)
        XCTAssertEqual(i.waitingPoints, 5)
        XCTAssertEqual(i.confidenceState, .handsOff)
    }

    func test_evaluate_neitherActionableNorWaitingRemains_isFinished() async throws {
        let i = try await evaluate("confidence-finished", now: isoDate("2026-09-17T12:00:00Z"))

        XCTAssertEqual(i.actionablePoints, 0)
        XCTAssertEqual(i.waitingPoints, 0)
        XCTAssertEqual(i.confidenceState, .finished)
    }

    // MARK: - Confidence State: days exhausted with work remaining (rule 5)

    /// The sprint's end date has passed (`WDR = 0`) while Actionable Points remain — `Off
    /// Track` by rule 5, distinct from the ratio-based rule 9 exercised above.
    func test_evaluate_workingDaysExhaustedWithActionableRemaining_isOffTrack() async throws {
        let i = try await evaluate("confidence-days-exhausted", now: isoDate("2026-09-21T12:00:00Z"))

        XCTAssertEqual(i.workingDaysRemaining, 0)
        XCTAssertGreaterThan(i.actionablePoints, 0)
        XCTAssertNil(i.requiredRate, "R = A / WDR is undefined once WDR = 0")
        XCTAssertEqual(i.confidenceState, .offTrack)
    }

    // MARK: - Caps: the band rules first, then one demotion each

    /// The Unestimated Cap firing alone. `A = 4` over `WDR = 4` ⇒ R = 1.0; `C = 5` over
    /// `WDE = 4` ⇒ D = 1.25; the ratio 1.25 clears the `No Sweat` boundary — until one unsized
    /// Issue in Actionable, which the band rules never looked at, demotes it one band.
    func test_evaluate_unestimatedCapAlone_demotesNoSweatOneBand() async throws {
        let i = try await evaluate("cap-unestimated", now: isoDate("2026-09-17T12:00:00Z"))

        XCTAssertEqual(i.unestimatedCount, 1)
        XCTAssertEqual(i.reading.rule, .ratioNoSweat, "Caps are evaluated after the band rules")
        XCTAssertEqual(i.reading.uncappedState, .noSweat)
        XCTAssertEqual(i.reading.caps, [.unestimated])
        XCTAssertEqual(i.confidenceState, .onTrack)
    }

    /// The Waiting-heavy Cap firing alone: every Issue is sized, but 8 of the 12 remaining Points
    /// are in somebody else's queue — 0.667 against the 0.40 boundary. The same `No Sweat` ratio,
    /// demoted the same one band, on different evidence.
    func test_evaluate_waitingHeavyCapAlone_demotesNoSweatOneBand() async throws {
        let i = try await evaluate("cap-waiting-heavy", now: isoDate("2026-09-17T12:00:00Z"))

        XCTAssertEqual(i.actionablePoints, 4)
        XCTAssertEqual(i.waitingPoints, 8)
        XCTAssertEqual(i.unestimatedCount, 0)
        XCTAssertEqual(i.reading.caps, [.waitingHeavy])
        XCTAssertEqual(i.confidenceState, .onTrack)
    }

    /// Both Caps firing together, each taking one band: `No Sweat → On Track → Tight`. The Cap
    /// conditions are independent of the ratio that produced `No Sweat` — unsized work and a
    /// review queue are both invisible to rules 6–9, which is why they can contradict it.
    func test_evaluate_bothCapsFire_demotingTwoBands() async throws {
        let i = try await evaluate("cap-both", now: isoDate("2026-09-17T12:00:00Z"))

        XCTAssertEqual(i.reading.uncappedState, .noSweat)
        XCTAssertEqual(i.reading.caps, [.unestimated, .waitingHeavy])
        XCTAssertEqual(i.reading.demotions, 2)
        XCTAssertEqual(i.confidenceState, .tight)
    }

    /// Both Cap conditions hold — `A = 0` makes the Waiting share 1.0 — and neither demotes
    /// anything. `Hands Off` is a named answer, not a band on the scale, so the Explanation must
    /// name the rule that matched rather than a demotion that cannot happen.
    func test_evaluate_capsAgainstHandsOff_demoteNothing() async throws {
        let i = try await evaluate("cap-hands-off", now: isoDate("2026-09-17T12:00:00Z"))

        XCTAssertEqual(i.actionablePoints, 0)
        XCTAssertEqual(i.reading.rule, .nothingActionableRemaining)
        XCTAssertEqual(i.reading.caps, [.unestimated, .waitingHeavy])
        XCTAssertEqual(i.reading.demotions, 0)
        XCTAssertEqual(i.confidenceState, .handsOff)
    }

    /// Rule 4 withdraws the answer before any ratio is taken. The Caps are true of the data and
    /// demote nothing: withdrawing is not a band to fall from.
    func test_evaluate_capsAgainstUnknown_demoteNothing() async throws {
        let i = try await evaluate("cap-unknown", now: isoDate("2026-09-17T12:00:00Z"))

        XCTAssertEqual(i.completedPoints, 0)
        XCTAssertEqual(i.reading.rule, .insufficientHistory)
        XCTAssertEqual(i.reading.caps, [.unestimated, .waitingHeavy])
        XCTAssertEqual(i.confidenceState, .unknown)
    }

    /// `Off Track` is the bottom of the scale: two Caps fired and there is nowhere left to walk.
    /// The Reading keeps both — they hold — without claiming a demotion it did not perform.
    func test_evaluate_capsAtTheBottomOfTheScale_demoteNothingFurther() async throws {
        let i = try await evaluate("cap-at-bottom", now: isoDate("2026-09-17T12:00:00Z"))

        XCTAssertEqual(i.requiredRate, 2.0)
        XCTAssertEqual(i.demonstratedRate, 0.5)
        XCTAssertEqual(i.reading.uncappedState, .offTrack)
        XCTAssertEqual(i.reading.caps, [.unestimated, .waitingHeavy])
        XCTAssertEqual(i.reading.demotions, 0)
        XCTAssertEqual(i.confidenceState, .offTrack)
    }

    /// #7 changed a displayed state in the existing corpus, so it is pinned here rather than left
    /// to a suite that only checks this fixture's Points rows: #4's all-flow-states sprint is a
    /// Waiting-heavy one, and the Cap now takes its `Tight` down a band.
    func test_evaluate_allFlowStatesFixture_isWaitingHeavySoItsTightIsCapped() async throws {
        let i = try await evaluate("all-flow-states").instrument

        XCTAssertEqual(i.actionablePoints, 10)
        XCTAssertEqual(i.waitingPoints, 9, "9 of 19 remaining Points — 0.474, over the 40% line")
        XCTAssertEqual(i.reading.uncappedState, .tight, "D 13÷6 against R 10÷4 is a ratio of 0.867")
        XCTAssertEqual(i.reading.caps, [.waitingHeavy])
        XCTAssertEqual(i.confidenceState, .offTrack)
    }
}

/// A calendar date from an ISO-8601 string, for pinning "today" and baseline timestamps.
func isoDate(_ iso: String) -> Date {
    ISO8601DateFormatter().date(from: iso)!
}

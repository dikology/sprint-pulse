import XCTest
@testable import SprintPulseCore

/// The corpus audit (#9): the scenario list in #1, transcribed, and pinned to what actually
/// ships. Each listed scenario must have a fixture (it does — it is a directory), a test
/// (named beside it, and checked to still exist), and a Confidence State (asserted here at
/// the moment the scenario itself pins — the same observation the panel produces when the
/// Operator clicks, so a picker entry that renders a different state than its name promises
/// fails the suite rather than lying in the menu bar).
///
/// The mechanism against drift is the bundle itself: this file enumerates the corpus from
/// `FixtureJiraGateway.corpusScenarioNames()` rather than from a list someone has to
/// remember to update — the previous audit test named nine of twenty-four fixtures and
/// passed.
final class FixtureCorpusTests: XCTestCase {
    let operatorIdentity = OperatorIdentity(key: "JIRAUSER10500", name: "dgimaletdinov")

    /// Monday–Friday, UTC — the calendar every fixture window was written against.
    let workingCalendar = WorkingCalendar(timeZone: TimeZone(identifier: "UTC")!)

    /// One corpus row: the scenario, the `ForecastTests` method that owns its detailed
    /// assertions, and the Confidence State it must produce at its pinned moment — which is
    /// also what its picker title (`PanelView.title(for:)`) promises in prose.
    private typealias Row = (scenario: FixtureScenario, test: String, state: ConfidenceState)

    /// The Operator's answer to the prompt, for the one scenario whose Board reports two active
    /// sprints (#11). Beside the audit rather than a fourth tuple column: two rows of
    /// twenty-seven need it, and a table with three unset columns in every other row reads as
    /// though the corpus had questions it does not ask.
    private let chosenSprintIDs: [FixtureScenario: Int] = [.twoActiveSprints: 5311]

    /// The rows whose My Work is empty on purpose (#11), asserting the size of the population the
    /// forecast summed over, independently of the state that sum produced. `Instrument` carries no
    /// such field by design — the panel asks `SprintSnapshot.myWork`, so the audit asks it too.
    private let emptyMyWork: Set<FixtureScenario> = [.noWorkAssigned]

    /// #1's scenario list, one row per bullet.
    private let scenariosFromIssueOne: [Row] = [
        (.confidenceOffTrack, "test_evaluate_ratioBelowSevenFive_isOffTrack", .offTrack),
        (.confidenceTight, "test_evaluate_ratioAtSevenFive_isTight", .tight),
        (.confidenceOnTrack, "test_evaluate_ratioAtOne_isOnTrack", .onTrack),
        (.confidenceNoSweat, "test_evaluate_ratioAtOnePointTwoFive_isNoSweat", .noSweat),
        (.confidenceColdStart, "test_evaluate_fewerThanTwoWorkingDaysElapsed_isUnknown", .unknown),
        (.confidenceZeroCompleted, "test_evaluate_zeroCompletedPoints_isUnknown", .unknown),
        (.unmappedStatus, "test_evaluate_unmappedStatus_isUnknownButKeepsRequiredRateVisible", .unknown),
        (.confidenceHandsOff, "test_evaluate_noActionableButWaitingRemains_isHandsOff", .handsOff),
        (.confidenceFinished, "test_evaluate_neitherActionableNorWaitingRemains_isFinished", .finished),
        (.confidenceDaysExhausted, "test_evaluate_workingDaysExhaustedWithActionableRemaining_isOffTrack", .offTrack),
        (.capUnestimated, "test_evaluate_unestimatedCapAlone_demotesNoSweatOneBand", .onTrack),
        (.capWaitingHeavy, "test_evaluate_waitingHeavyCapAlone_demotesNoSweatOneBand", .onTrack),
        (.capBoth, "test_evaluate_bothCapsFire_demotingTwoBands", .tight),
        (.scopeGrowth, "test_evaluate_scopeGrowthFixture_reportsLargePositiveScopeDelta", .offTrack),
        (.scopeShrink, "test_evaluate_scopeShrinkFixture_reportsNegativeScopeDeltaFromRemovedWork", .offTrack),
        (.baselineColdStart, "test_evaluate_coldStartMidSprint_capturesBaselineFromNowAndReadsZeroDelta", .onTrack),
        (.allDropped, "test_evaluate_allDroppedFixture_showsCancelledWorkAsDroppedNotScopeMovement", .finished),
        (.subtasksWithEstimates, "test_evaluate_ignoresSubTaskEstimatesEntirelyRatherThanRollingThemUp", .unknown),
    ]

    /// Corpus members beyond #1's list — whole-`Instrument` pinning, the Flow-State
    /// partition, the Unestimated count across sets, and the three Cap edges that demote
    /// nothing. The Scope rows' states (an added or removed sprint still burning at 0.30 and
    /// 0.41 of Required) are derived from the glossary and pinned here as regression, not
    /// recomputed from whatever the model happens to say.
    private let scenariosBeyondIssueOne: [Row] = [
        (.walkingSkeleton, "test_evaluate_fromWalkingSkeletonFixture_producesTheWholeInstrument", .unknown),
        (.allFlowStates, "test_evaluate_partitionsMyWorkAcrossAllSixFlowStates", .offTrack),
        (.unestimatedAcrossStates, "test_evaluate_countsUnestimatedIssuesOnlyInActionableOrWaitingAndNeverAsPoints", .unknown),
        (.capAtBottom, "test_evaluate_capsAtTheBottomOfTheScale_demoteNothingFurther", .offTrack),
        (.capHandsOff, "test_evaluate_capsAgainstHandsOff_demoteNothing", .handsOff),
        (.capUnknown, "test_evaluate_capsAgainstUnknown_demoteNothing", .unknown),
    ]

    /// #11's live-read scenarios: what a real Board reports that no M0 fixture did — two active
    /// sprints at once, a sprint shared with other people, and a sprint holding nothing that
    /// belongs to the Operator.
    private let scenariosFromIssueEleven: [Row] = [
        (.twoActiveSprints, "test_evaluate_twoActiveSprints_forecastsTheSprintTheOperatorNamed", .onTrack),
        (.severalAssignees, "test_evaluate_severalAssignees_forecastsMyWorkAndTotalsTheRestAsTeamScope", .noSweat),
        // `Finished` is what the table computes for an empty My Work, and exactly what the panel
        // must never show: `emptyMyWork` is the population it checks first (#11).
        (.noWorkAssigned, "test_evaluate_identityMatchingNoIssues_isItsOwnStateNotAConfidentZero", .finished),
    ]

    /// #12's cached-read scenarios: one sprint at two read moments. The corpus's only pair whose
    /// two directories hold the same Board and the same Issues, because the thing under test is not
    /// the sprint at all — it is how old the data behind a reading was.
    private let scenariosFromIssueTwelve: [Row] = [
        (.cacheWithinWorkingDay, "test_evaluate_dataReadEarlierInTheSameWorkingDay_stillForecasts", .noSweat),
        (.cachePredatesWorkingDay, "test_evaluate_dataFromAnEarlierWorkingDay_isUnknownWithPointsStillVisible", .unknown),
    ]

    private var allRows: [Row] {
        scenariosFromIssueOne + scenariosBeyondIssueOne + scenariosFromIssueEleven + scenariosFromIssueTwelve
    }

    func test_audit_theTablesCoverThePickerAndTheCorpusExactly() throws {
        let audited = Set(allRows.map(\.scenario))
        XCTAssertEqual(audited, Set(FixtureScenario.allCases), "the audit table and the picker's scenario list disagree")

        let onDisk = try FixtureJiraGateway.corpusScenarioNames()
        XCTAssertEqual(
            Set(allRows.map(\.scenario.rawValue)), onDisk,
            "the audited scenarios and the fixture directories disagree, in either direction"
        )
        XCTAssertEqual(Set(FixtureScenario.allCases.map(\.rawValue)), onDisk)

        // Every scenario is a frozen observation: no row may load at the wall clock.
        for row in allRows {
            XCTAssertNotNil(
                try FixtureJiraGateway.pinnedNow(named: row.scenario.rawValue),
                "\(row.scenario.rawValue): a scenario without a pinned moment drifts out of the state its title promises"
            )
        }
    }

    /// The "and a test" half of #9's audit criterion, checked mechanically: the named
    /// methods must still exist in `ForecastTests.swift`. A string table pointing at deleted
    /// tests is the same rot this file exists to prevent — it named fixtures whose tests had
    /// drifted out of sync and stayed green.
    func test_audit_everyNamedTestStillExistsInForecastTests() throws {
        let testsFile = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("ForecastTests.swift")
        let source = try String(contentsOf: testsFile, encoding: .utf8)
        for row in allRows {
            XCTAssertTrue(
                source.contains("func \(row.test)()"),
                "\(row.scenario.rawValue): the audit points at \(row.test)(), which no longer exists in ForecastTests.swift"
            )
        }
    }

    /// The picker's honesty check: every scenario is loaded the way the panel loads it —
    /// through the gateway in Jira shape, at its own pinned moment and the moment its own data
    /// claims to have been read at, with its bundled Baseline — and must produce the Confidence
    /// State its row promises.
    ///
    /// The Active Sprint is resolved through `resolveTrackedSprint`, which is how the panel
    /// resolves it since #11: the scenario whose Board reports two active sprints is read at the
    /// sprint its row records the Operator naming. Every other row is unaffected — a Board with
    /// one active sprint is never a question.
    func test_everyScenario_loadsAtItsPinnedMoment_andProducesItsPromisedState() async throws {
        for row in allRows {
            let gateway = try FixtureJiraGateway.bundled(named: row.scenario.rawValue)
            let choice = SprintSnapshot.resolveTrackedSprint(
                in: try await gateway.activeSprints(),
                chosenSprintID: chosenSprintIDs[row.scenario]
            )
            let sprint = try XCTUnwrap(
                choice.sprint,
                "\(row.scenario.rawValue): the audit names no sprint, so the panel could only prompt"
            )
            let issues = try await gateway.issues(inSprint: sprint.id)
            XCTAssertEqual(issues.issues.count, issues.total, "\(row.scenario.rawValue): issue count matches total")
            XCTAssertFalse(issues.issues.isEmpty, "\(row.scenario.rawValue): has issues")

            let moment = try XCTUnwrap(
                FixtureJiraGateway.pinnedNow(row.scenario),
                "\(row.scenario.rawValue): no pinned moment"
            )
            // A scenario that is about the cache carries a `read-at.json` too; every other
            // scenario's data was read at the moment it was observed, which is what the panel
            // passes when it has just fetched (#12).
            let readAt = try FixtureJiraGateway.bundledReadAt(row.scenario) ?? moment
            let snapshot = SprintSnapshot(sprint: sprint, issues: issues.issues)
            let instrument = Forecast.evaluate(
                snapshot: snapshot,
                identity: operatorIdentity,
                statusMap: .default,
                workingCalendar: workingCalendar,
                baseline: try FixtureJiraGateway.bundledBaseline(row.scenario),
                readAt: readAt,
                now: moment
            ).instrument
            XCTAssertEqual(instrument.sprintName, sprint.name, "\(row.scenario.rawValue)")
            XCTAssertEqual(
                instrument.confidenceState, row.state,
                "\(row.scenario.rawValue): clicking this picker entry must show the state its name promises"
            )
            XCTAssertEqual(
                instrument.predatesCurrentWorkingDay,
                workingCalendar.predatesCurrentWorkingDay(readAt: readAt, now: moment),
                "\(row.scenario.rawValue): the reading carries the same verdict on its data's age"
            )
            if emptyMyWork.contains(row.scenario) {
                XCTAssertEqual(
                    snapshot.myWork(assignedTo: operatorIdentity), [],
                    "\(row.scenario.rawValue): the reading has no subject, which is the state the panel shows"
                )
            }
        }
    }

    /// The two cache scenarios are a controlled comparison or they are nothing: same Board, same
    /// Issues, same moment of observation, one column of the pair differing. If they drifted apart
    /// in the sprint data as well, the picker would be showing two different sprints and calling
    /// the difference staleness (#12).
    func test_cacheScenarios_differOnlyInTheMomentTheirDataWasRead() async throws {
        var envelopes: [String: (sprints: JiraSprintsResponse, issues: JiraSprintIssuesResponse, now: Date, readAt: Date)] = [:]
        for scenario in [FixtureScenario.cacheWithinWorkingDay, .cachePredatesWorkingDay] {
            let gateway = try FixtureJiraGateway.bundled(scenario)
            let sprints = try await gateway.activeSprints()
            let sprint = try XCTUnwrap(SprintSnapshot.resolveTrackedSprint(in: sprints, chosenSprintID: nil).sprint)
            envelopes[scenario.rawValue] = (
                sprints,
                try await gateway.issues(inSprint: sprint.id),
                try XCTUnwrap(FixtureJiraGateway.pinnedNow(scenario)),
                try XCTUnwrap(FixtureJiraGateway.bundledReadAt(scenario))
            )
        }
        let fresh = try XCTUnwrap(envelopes[FixtureScenario.cacheWithinWorkingDay.rawValue])
        let stale = try XCTUnwrap(envelopes[FixtureScenario.cachePredatesWorkingDay.rawValue])

        XCTAssertEqual(fresh.sprints.values, stale.sprints.values, "the same Board")
        XCTAssertEqual(fresh.issues.issues, stale.issues.issues, "the same Issues")
        XCTAssertEqual(fresh.now, stale.now, "observed at the same moment")
        XCTAssertNotEqual(fresh.readAt, stale.readAt, "…except that one of them is older")
        XCTAssertFalse(
            workingCalendar.predatesCurrentWorkingDay(readAt: fresh.readAt, now: fresh.now),
            "the within-day one is inside its Working Day"
        )
        XCTAssertTrue(
            workingCalendar.predatesCurrentWorkingDay(readAt: stale.readAt, now: stale.now),
            "and the other is not"
        )
    }

    /// The other half of the two-active-sprints scenario: before the Operator answers, there is
    /// nothing honest to forecast. The prompt is the state, and it names both candidates in the
    /// Board's own words (#11) — the app never picks the shorter sprint, the earlier one, or the
    /// first in the envelope.
    func test_twoActiveSprints_unresolvedIsAPromptNamingBothCandidates() async throws {
        let gateway = try FixtureJiraGateway.bundled(.twoActiveSprints)

        let choice = SprintSnapshot.resolveTrackedSprint(
            in: try await gateway.activeSprints(), chosenSprintID: nil
        )

        guard case .awaitingOperatorChoice(let candidates) = choice else {
            return XCTFail("a Board reporting two active sprints must ask, got \(choice)")
        }
        XCTAssertEqual(
            candidates.map { "\($0.id) \($0.name)" },
            ["5311 Mobile Platform Sprint 34", "5312 Growth Experiment Sprint 7"]
        )
    }

    func test_bundledBaseline_readsTheScenarioSnapshotWhenOneIsBundled() throws {
        let growth = try XCTUnwrap(try FixtureJiraGateway.bundledBaseline(named: "scope-growth"))
        XCTAssertEqual(growth.sprintID, 8001)
        XCTAssertEqual(growth.points, 13, "the day-one snapshot: SGR-1801 (8) + SGR-1802 (5)")
        XCTAssertNil(
            try FixtureJiraGateway.bundledBaseline(named: "walking-skeleton"),
            "a first-observation scenario has witnessed no movement"
        )
    }

    /// The corpus is anonymised, and this repository is public. A raw capture dropped in as
    /// a *new* directory already fails the audit above — but a real instance host or a real
    /// mailbox smuggled into the text of an existing fixture would not, so every URL host
    /// and every mail address in every fixture file must belong to the `example` families
    /// reserved for documentation. This is the `.gitignore` comment ("fixtures stay
    /// anonymised") turned into a failing test rather than an aspiration.
    func test_corpus_isAnonymised_onlyExampleDomainsAppear() throws {
        let fixtures = try XCTUnwrap(
            Bundle.module.url(forResource: "Fixtures", withExtension: nil)
        )
        var offenders: [String] = []
        for name in try FixtureJiraGateway.corpusScenarioNames().sorted() {
            let directory = fixtures.appendingPathComponent(name)
            let files = try FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: nil
            )
            for file in files where file.pathExtension == "json" {
                let text = try String(contentsOf: file, encoding: .utf8)
                for host in Self.domains(in: text) where !Self.isExampleDomain(host) {
                    offenders.append("\(name)/\(file.lastPathComponent): \(host)")
                }
            }
        }
        XCTAssertTrue(
            offenders.isEmpty,
            "fixture corpus names non-example domains — anonymise before committing:\n"
                + offenders.joined(separator: "\n")
        )
    }

    /// Hosts of `http(s)://` URLs and domains of mail addresses anywhere in a JSON text.
    private static func domains(in text: String) -> [String] {
        let pattern = #"(?i)(?:https?://|@)([A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard let captured = Range(match.range(at: 1), in: text) else { return nil }
            return String(text[captured])
        }
    }

    private static func isExampleDomain(_ host: String) -> Bool {
        let lowered = host.lowercased()
        let allowed: [String] = [".example.com", ".example.org", ".example.net", ".test"]
        let roots: [String] = ["example.com", "example.org", "example.net"]
        return roots.contains(lowered) || allowed.contains { lowered.hasSuffix($0) }
    }
}

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

    private var allRows: [Row] { scenariosFromIssueOne + scenariosBeyondIssueOne }

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
    /// through the gateway in Jira shape, at its own pinned moment, with its bundled
    /// Baseline — and must produce the Confidence State its row promises.
    func test_everyScenario_loadsAtItsPinnedMoment_andProducesItsPromisedState() async throws {
        for row in allRows {
            let gateway = try FixtureJiraGateway.bundled(named: row.scenario.rawValue)
            let sprint = try SprintSnapshot.selectActiveSprint(from: try await gateway.activeSprints())
            let issues = try await gateway.issues(inSprint: sprint.id)
            XCTAssertEqual(issues.issues.count, issues.total, "\(row.scenario.rawValue): issue count matches total")
            XCTAssertFalse(issues.issues.isEmpty, "\(row.scenario.rawValue): has issues")

            let moment = try XCTUnwrap(
                FixtureJiraGateway.pinnedNow(row.scenario),
                "\(row.scenario.rawValue): no pinned moment"
            )
            let instrument = Forecast.evaluate(
                snapshot: SprintSnapshot(sprint: sprint, issues: issues.issues),
                identity: operatorIdentity,
                statusMap: .default,
                workingCalendar: workingCalendar,
                baseline: try FixtureJiraGateway.bundledBaseline(row.scenario),
                now: moment
            ).instrument
            XCTAssertEqual(instrument.sprintName, sprint.name, "\(row.scenario.rawValue)")
            XCTAssertEqual(
                instrument.confidenceState, row.state,
                "\(row.scenario.rawValue): clicking this picker entry must show the state its name promises"
            )
        }
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

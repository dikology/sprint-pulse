import XCTest
@testable import SprintPulseCore

/// The live half of the gateway seam (#11), exercised exactly where M1's testing decisions put
/// it: recorded response bodies replayed by a stubbed transport. No test here touches a network,
/// a Jira instance, a VPN, or a credential.
///
/// The bodies are in the shape Jira Data Center emits from `/rest/agile/1.0/`, carrying the
/// fields the model ignores — `expand`, `self` links, `avatarUrls`, `progress`, `worklog`,
/// `statusCategory`, and the custom fields that are not the configured Estimate field. A
/// decoding bug is meant to surface as a wrong `Instrument`, the way it does across the fixture
/// corpus, so the last test in this file hands the live client a corpus body and demands that
/// the two gateways agree.
final class LiveJiraGatewayTests: XCTestCase {
    /// An opaque stand-in for a real PAT: what is asserted about it is that it only ever travels
    /// in the `Authorization` header, never in a URL, a path, or a message (#10).
    let token = "MDEyMzQ1Njc4OWFiY2RlZjAxMjM0NTY3ODlhYmNkZWY"
    let boardID = 172
    let sprintID = 5311

    private func gateway(
        _ transport: RecordedJiraTransport,
        estimateFieldID: String = JiraDecoding.estimateFieldID
    ) throws -> LiveJiraGateway {
        let client = try JiraHTTPClient(
            baseURL: URL(string: "https://jira.example.com")!, token: token, transport: transport
        )
        return LiveJiraGateway(client: client, boardID: boardID, estimateFieldID: estimateFieldID)
    }

    // MARK: - The bounded call surface (#2's bound, checked at the boundary it is drawn at)

    /// The whole of what the live gateway may ask: two Agile listings, GET, Bearer-authenticated,
    /// and no third endpoint anywhere. `/rest/api/2/myself` belongs to credential setup (#10) and
    /// is not reachable from this type — which is what makes "three read operations" checkable by
    /// looking at the recorded requests rather than by trusting a sentence in an issue.
    func test_gateway_asksOnlyTheTwoAgileListings_andNeverAnythingElse() async throws {
        let transport = RecordedJiraTransport(bodies: [
            "rest/agile/1.0/board/172/sprint": [Self.sprintsBody],
            "rest/agile/1.0/sprint/5311/issue": [Self.issuesBody],
        ])

        let listed = try await gateway(transport).activeSprints()
        _ = try await gateway(transport).issues(inSprint: try XCTUnwrap(listed.values.first).id)

        XCTAssertEqual(
            transport.requests.map { $0.url?.path },
            ["/rest/agile/1.0/board/172/sprint", "/rest/agile/1.0/sprint/5311/issue"],
            "a third path is a fourth operation, and M1's bound is three"
        )
        for request in transport.requests {
            XCTAssertEqual(request.httpMethod, "GET", "M1 reads; writes are M2")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer \(token)")
            XCTAssertNil(request.httpBody, "a GET with a body is a write wearing a mask")
        }
    }

    /// The Board is the Operator's configuration, and it appears in the one path that takes it.
    /// A Board read that ignored `boardID` would forecast somebody else's sprint convincingly.
    func test_activeSprints_asksForTheConfiguredBoard_activeStateOnly() async throws {
        let transport = RecordedJiraTransport(bodies: [
            "rest/agile/1.0/board/172/sprint": [Self.sprintsBody],
        ])

        _ = try await gateway(transport).activeSprints()

        XCTAssertEqual(transport.requests.count, 1)
        XCTAssertEqual(
            transport.requests.first?.url?.absoluteString,
            "https://jira.example.com/rest/agile/1.0/board/172/sprint?maxResults=50&startAt=0&state=active"
        )
    }

    // MARK: - Decoding a captured envelope

    func test_activeSprints_decodesBothActiveSprintsAndTheirDates() async throws {
        let transport = RecordedJiraTransport(bodies: [
            "rest/agile/1.0/board/172/sprint": [Self.sprintsBody],
        ])

        let response = try await gateway(transport).activeSprints()

        XCTAssertEqual(
            response.values.map { "\($0.id) \($0.state)" },
            ["5311 active", "5312 active", "5310 future"]
        )
        let sprint = try XCTUnwrap(response.values.first)
        // Sprint start and end come from Jira's sprint object, never entered by the Operator
        // (#11) — the two figures Working Days Remaining is measured against.
        XCTAssertEqual(sprint.startDate, iso("2026-09-14T06:00:00Z"))
        XCTAssertEqual(sprint.endDate, iso("2026-09-25T15:00:00Z"))
        XCTAssertEqual(sprint.name, "Mobile Platform Sprint 34")
    }

    func test_issues_decodesTheSprintListingInJiraShape() async throws {
        let transport = RecordedJiraTransport(bodies: [
            "rest/agile/1.0/sprint/5311/issue": [Self.issuesBody],
        ])

        let response = try await gateway(transport).issues(inSprint: sprintID)

        XCTAssertEqual(response.total, 3)
        XCTAssertEqual(response.issues.count, 3)
        let byKey = Dictionary(uniqueKeysWithValues: response.issues.map { ($0.key, $0) })
        XCTAssertEqual(byKey["TAS-2101"]?.fields.summary, "Store the Personal Access Token as one Keychain item")
        XCTAssertEqual(byKey["TAS-2101"]?.fields.status.name, "Done")
        XCTAssertEqual(byKey["TAS-2101"]?.fields.issueType.subtask, false)
        XCTAssertEqual(byKey["TAS-2101"]?.fields.assignee?.key, "JIRAUSER10500")
        XCTAssertEqual(byKey["TAS-2101"]?.fields.estimate, 8)
        // Null in Jira is an Unestimated Issue, which is an admission of ignorance, not a zero.
        XCTAssertNil(byKey["TAS-2102"]?.fields.estimate)
        XCTAssertNil(byKey["TAS-2103"]?.fields.assignee, "nobody's work is not the Operator's")
        XCTAssertEqual(byKey["TAS-2102"]?.fields.issueType.subtask, true, "carried in the listing, excluded from the model")
    }

    /// Which custom field carries the Estimate is per-instance configuration, and both readings
    /// arrive from the same bytes: the configured field is the one that becomes Points, and every
    /// other plausible points field on the instance stays noise the model ignores (#11).
    func test_issues_readsTheConfiguredEstimateField_andOnlyThatField() async throws {
        let transport = RecordedJiraTransport(bodies: [
            "rest/agile/1.0/sprint/5311/issue": [Self.issuesBody],
        ])

        let response = try await gateway(transport, estimateFieldID: "customfield_10007")
            .issues(inSprint: sprintID)
        let byKey = Dictionary(uniqueKeysWithValues: response.issues.map { ($0.key, $0) })

        XCTAssertEqual(byKey["TAS-2101"]?.fields.estimate, 13, "customfield_10007 on this instance")
        XCTAssertEqual(byKey["TAS-2102"]?.fields.estimate, 5)
        XCTAssertNil(byKey["TAS-2103"]?.fields.estimate, "neither field is filled: still Unestimated")
    }

    // MARK: - Paging the listings

    /// A sprint larger than one page has to be read whole: `total` is Jira's word for how many
    /// Issues there are, and a forecast over the first 50 of 54 would be a confident number
    /// about a subset.
    func test_issues_pagesToTheEnvelopesTotal() async throws {
        let transport = RecordedJiraTransport(bodies: [
            "rest/agile/1.0/sprint/5311/issue": [
                Self.issuesPage(startAt: 0, count: 3, total: 5),
                Self.issuesPage(startAt: 3, count: 2, total: 5),
            ],
        ])

        let response = try await gateway(transport).issues(inSprint: sprintID)

        XCTAssertEqual(transport.requests.count, 2)
        XCTAssertEqual(
            transport.requests.compactMap { $0.url?.query },
            ["maxResults=50&startAt=0", "maxResults=50&startAt=3"]
        )
        XCTAssertEqual(response.issues.count, 5)
        XCTAssertEqual(response.total, 5)
        XCTAssertEqual(response.issues.map(\.key), ["P-1", "P-2", "P-3", "P-4", "P-5"])
    }

    /// A listing that hands back fewer Issues than it promised is not a shorter sprint — it is a
    /// read that failed, and it is named as one instead of forecasting half a sprint.
    func test_issues_listingThatStopsShortOfItsTotal_isReported_notTruncated() async throws {
        let transport = RecordedJiraTransport(bodies: [
            "rest/agile/1.0/sprint/5311/issue": [
                Self.issuesPage(startAt: 0, count: 3, total: 5),
                Self.issuesPage(startAt: 3, count: 0, total: 5),
            ],
        ])

        do {
            _ = try await gateway(transport).issues(inSprint: sprintID)
            XCTFail("expected an incomplete read")
        } catch let error as JiraClientError {
            XCTAssertEqual(error, .incompleteRead(received: 3, pages: 2))
        }
    }

    /// The bound that keeps a server ignoring `startAt` from turning one panel open into an
    /// endless loop of requests. The same page forever is the failure a captive portal produces.
    func test_issues_aListingThatNeverAdvances_stopsAtThePagingBound() async throws {
        let transport = RecordedJiraTransport(bodies: [
            "rest/agile/1.0/sprint/5311/issue": [Self.issuesPage(startAt: 0, count: 5, total: 500)],
        ])

        do {
            _ = try await gateway(transport).issues(inSprint: sprintID)
            XCTFail("expected an incomplete read")
        } catch let error as JiraClientError {
            XCTAssertEqual(error, .incompleteRead(received: 200, pages: 40))
            XCTAssertEqual(transport.requests.count, 40, "no more than the bound, no fewer than the loop")
        }
    }

    func test_issues_anEmptySprint_isAnEmptyListing_notAnIncompleteRead() async throws {
        let transport = RecordedJiraTransport(bodies: [
            "rest/agile/1.0/sprint/5311/issue": [Self.issuesPage(startAt: 0, count: 0, total: 0)],
        ])

        let response = try await gateway(transport).issues(inSprint: sprintID)

        XCTAssertEqual(response.issues.count, 0)
        XCTAssertEqual(response.total, 0)
        XCTAssertEqual(transport.requests.count, 1, "an empty sprint needs one request")
    }

    func test_activeSprints_pagesUntilTheListingSaysItIsLast() async throws {
        let transport = RecordedJiraTransport(bodies: [
            "rest/agile/1.0/board/172/sprint": [
                Self.sprintsPage(isLast: false, ids: [5311]),
                Self.sprintsPage(isLast: true, ids: [5312]),
            ],
        ])

        let response = try await gateway(transport).activeSprints()

        XCTAssertEqual(response.values.map(\.id), [5311, 5312])
        XCTAssertEqual(transport.requests.count, 2)
        XCTAssertEqual(
            transport.requests.compactMap { $0.url?.query },
            ["maxResults=50&startAt=0&state=active", "maxResults=50&startAt=1&state=active"]
        )
    }

    /// The Board listing hitting the same bound fails the read rather than returning a partial
    /// Board. Silently dropping a second active sprint here would not read as a smaller sprint —
    /// it would forecast the one that survived as the sprint the Operator named, which is the
    /// wrong subject wearing the right name (#11).
    func test_activeSprints_listingThatNeverCloses_isReported_notTruncated() async throws {
        let transport = RecordedJiraTransport(bodies: [
            "rest/agile/1.0/board/172/sprint": [Self.sprintsPage(isLast: false, ids: [5311])],
        ])

        do {
            _ = try await gateway(transport).activeSprints()
            XCTFail("expected an incomplete read")
        } catch let error as JiraClientError {
            XCTAssertEqual(error, .incompleteRead(received: 40, pages: 40))
        }
    }

    // MARK: - Failure states, shared with identity resolution (#10)

    /// The sprint reads fail through the same rule `/myself` does, which is why they distinguish
    /// the same conditions: the panel renders one vocabulary for a fetch, not one per endpoint.
    func test_sprintReads_failThroughTheSameStatesAsIdentity() async throws {
        for (code, expected) in [
            (401, JiraClientError.credentialRejected),
            (403, JiraClientError.credentialRejected),
            (500, JiraClientError.unexpectedStatus(code: 500)),
            (204, JiraClientError.unexpectedStatus(code: 204)),
        ] {
            let transport = RecordedJiraTransport(pages: [
                "rest/agile/1.0/board/172/sprint": [JiraHTTPResponse(statusCode: code, body: Data())],
            ])
            let error = await errorFromSprintRead(transport)
            XCTAssertEqual(error, expected, "status \(code)")
        }

        let notFound = RecordedJiraTransport(pages: [
            "rest/agile/1.0/board/172/sprint": [
                JiraHTTPResponse(statusCode: 404, body: Data(#"{"errorMessages":[],"errors":{}}"#.utf8)),
            ],
        ])
        let notFoundPath = await errorFromSprintRead(notFound)
        XCTAssertEqual(
            notFoundPath,
            .pathNotFound(
                path: "https://jira.example.com/rest/agile/1.0/board/172/sprint?maxResults=50&startAt=0&state=active"
            ),
            "a 404 has to name the whole configured path, parameters included, or a wrong base URL and a missing board look alike"
        )

        let loginPage = RecordedJiraTransport(pages: [
            "rest/agile/1.0/board/172/sprint": [
                JiraHTTPResponse(statusCode: 200, body: Data("<html><body>Sign in</body></html>".utf8)),
            ],
        ])
        let notJSON = await errorFromSprintRead(loginPage)
        XCTAssertEqual(notJSON, .malformedResponse)

        let vpnOff = RecordedJiraTransport(failure: URLError(.cannotConnectToHost), bodies: [:])
        let unreachable = await errorFromSprintRead(vpnOff)
        XCTAssertEqual(unreachable, .unreachableHost(host: "jira.example.com"))
    }

    /// The token is never in what the panel gets to show, including a 404 that quotes the whole
    /// request URL back — the one place a client could leak a credential into a path.
    func test_noSprintReadMessageCarriesTheToken() async {
        let transport = RecordedJiraTransport(pages: [
            "rest/agile/1.0/board/172/sprint": [
                JiraHTTPResponse(statusCode: 404, body: Data("no such board".utf8)),
            ],
        ])
        let error = await errorFromSprintRead(transport)
        guard case .pathNotFound(let path) = error ?? .malformedResponse else {
            return XCTFail("expected pathNotFound, got \(String(describing: error))")
        }
        XCTAssertFalse(path.contains(token), "the token belongs in a header, not in a path: \(path)")
    }

    // MARK: - The seam the protocol exists to hide

    /// The acceptance criterion in one comparison: hand the live gateway the corpus's own
    /// captured Data Center bodies and the domain cannot tell it from the fixture gateway — the
    /// same `Instrument`, field for field, with no change anywhere in `SprintPulseCore` (#2).
    /// A decoding bug now has one place to show up: a wrong `Instrument`.
    func test_liveGateway_andFixtureGateway_produceTheSameInstrumentFromTheSameBytes() async throws {
        let sprints = try fixtureFile("several-assignees", "active-sprints.json")
        let issues = try fixtureFile("several-assignees", "sprint-issues.json")

        let live = LiveJiraGateway(
            client: try JiraHTTPClient(
                baseURL: URL(string: "https://jira.example.com")!, token: token,
                transport: RecordedJiraTransport(pages: [
                    "rest/agile/1.0/board/172/sprint": [sprints],
                    "rest/agile/1.0/sprint/5401/issue": [issues],
                ])
            ),
            boardID: 172
        )
        let fixture = try FixtureJiraGateway.bundled(.severalAssignees)

        func read(_ gateway: any JiraGateway) async throws -> Instrument {
            let choice = SprintSnapshot.resolveTrackedSprint(
                in: try await gateway.activeSprints(), chosenSprintID: nil
            )
            let sprint = try XCTUnwrap(choice.sprint)
            let issues = try await gateway.issues(inSprint: sprint.id)
            return Forecast.evaluate(
                snapshot: SprintSnapshot(sprint: sprint, issues: issues.issues),
                identity: OperatorIdentity(key: "JIRAUSER10500", name: "dgimaletdinov"),
                statusMap: .default,
                workingCalendar: WorkingCalendar(timeZone: TimeZone(identifier: "UTC")!),
                baseline: nil,
                now: iso("2026-09-21T12:00:00Z")
            ).instrument
        }

        let fromLive = try await read(live)
        let fromFixture = try await read(fixture)

        XCTAssertEqual(fromLive, fromFixture)
        XCTAssertEqual(fromLive.confidenceState, .noSweat, "the corpus's own promise, read over HTTP")
        XCTAssertEqual(fromLive.liveSprintPoints, 43)
    }

    // MARK: - The corpus-wide parity check (#15)

    /// The whole corpus, not one scenario: every bundled scenario is served to the live client as
    /// the bytes it was written from, and both paths must agree field for field. #11 proved this
    /// for `several-assignees`; one scenario proves the decoder runs, and only all of them prove
    /// the protocol boundary is wide enough to stand on before writes are built on top of it (#2).
    ///
    /// This is the check whose *negative* result is the deliverable, so it compares the two paths
    /// against each other and against nothing else — no promised Confidence State is restated
    /// here, because `FixtureCorpusTests` already owns that table and a second copy of it would be
    /// a second thing to drift. (#15's own acceptance criterion is that no M0 test was edited to
    /// make this pass, which is why the two values this loop has to share with that file — the
    /// corpus's Operator and the one answered sprint prompt — are re-declared here rather than
    /// lifted into a shared helper: doing that would mean editing the M0 audit.)
    ///
    /// Each row carries its own `now`, `readAt`, and Baseline, read from the scenario's own
    /// `now.json`, `read-at.json` and `baseline.json` — the three app-owned values that never
    /// cross the gateway boundary (product.md, "Fixtures"). They reach both paths identically,
    /// because they are what the app would have supplied in live mode from its cache and its
    /// Baseline slot. Only the two Jira envelopes travel by different routes.
    func test_everyScenario_theLivePathProducesTheSameReadingAsTheFixturePath() async throws {
        for scenario in FixtureScenario.allCases {
            let (fromLive, fromFixture) = try await readEveryScenarioBothWays(scenario)
            XCTAssertEqual(
                fromLive, fromFixture,
                "\(scenario.rawValue): the two gateways disagree — the protocol boundary is in the wrong place"
            )
        }
    }

    /// The comparison above is only evidence if it can fail, and two paths that are both wrong the
    /// same way would agree happily. So the harness is checked the way #11's decode is: point the
    /// live path at an Estimate field the corpus does not keep its numbers in — the single
    /// configuration a real instance forces the Operator to get right (#11) — and require the two
    /// readings to part company. A parity test that passes while this one fails is a parity test
    /// comparing a decoder with itself.
    func test_theParityComparisonHasTeeth_misConfiguringOnlyTheLivePathBreaksIt() async throws {
        var diverging: [String] = []
        for scenario in FixtureScenario.allCases {
            let sprints = try fixtureFile(scenario.rawValue, "active-sprints.json")
            let issues = try fixtureFile(scenario.rawValue, "sprint-issues.json")
            let tracked = try trackedSprint(of: scenario, in: sprints)
            let live = try gateway(
                RecordedJiraTransport(pages: [
                    "rest/agile/1.0/board/\(boardID)/sprint": [sprints],
                    "rest/agile/1.0/sprint/\(tracked.id)/issue": [issues],
                ]),
                estimateFieldID: "customfield_10007"  // not the field the corpus estimates in
            )
            let fixture = try FixtureJiraGateway.bundled(scenario)
            if try await readThrough(live, scenario) != readThrough(fixture, scenario) {
                diverging.append(scenario.rawValue)
            }
        }
        XCTAssertFalse(
            diverging.isEmpty,
            "nothing diverged, so the parity comparison is not actually reading two paths"
        )
    }

    /// Reads one scenario through both gateways from the same bytes, and checks on the way that
    /// the live path asked exactly what #2 bounded it to ask.
    private func readEveryScenarioBothWays(
        _ scenario: FixtureScenario
    ) async throws -> (live: Instrument, fixture: Instrument) {
        let sprints = try fixtureFile(scenario.rawValue, "active-sprints.json")
        let issues = try fixtureFile(scenario.rawValue, "sprint-issues.json")

        // Which Issue listing the live client asks for is decided by which sprint the Board's own
        // envelope resolves to, so the recorded path is keyed on the resolved id rather than on a
        // number this test would have to keep in step with the corpus by hand. Asking the live
        // client to resolve it from the same bytes is the point: had the id come from the fixture
        // side instead, the transport would have confirmed an answer it was handed.
        let tracked = try trackedSprint(of: scenario, in: sprints)
        let transport = RecordedJiraTransport(pages: [
            "rest/agile/1.0/board/\(boardID)/sprint": [sprints],
            "rest/agile/1.0/sprint/\(tracked.id)/issue": [issues],
        ])
        let live = try gateway(transport)
        let fixture = try FixtureJiraGateway.bundled(scenario)

        let fromLive = try await readThrough(live, scenario)
        let fromFixture = try await readThrough(fixture, scenario)

        XCTAssertEqual(
            transport.requests.count, 2,
            "\(scenario.rawValue): more than two requests means the corpus holds a page the live client would keep walking"
        )
        XCTAssertEqual(
            Set(transport.requests.map { $0.httpMethod ?? "<unset>" }), ["GET"],
            "\(scenario.rawValue): the live path reached for something other than a GET"
        )
        return (fromLive, fromFixture)
    }

    /// The sprint a scenario's Board envelope resolves to, for the path its Issue listing is
    /// recorded under.
    private func trackedSprint(
        of scenario: FixtureScenario, in sprints: JiraHTTPResponse
    ) throws -> JiraSprint {
        let response = try JiraDecoding.decoder().decode(
            JiraSprintsResponse.self, from: sprints.body
        )
        return try XCTUnwrap(
            SprintSnapshot.resolveTrackedSprint(
                in: response, chosenSprintID: Self.chosenSprint(for: scenario)
            ).sprint,
            "\(scenario.rawValue): the corpus expects a tracked sprint"
        )
    }

    /// One scenario's reading, evaluated with the app-owned values that never cross the gateway:
    /// the corpus's Operator, the shipped map, the scenario's pinned moment, its own `readAt` when
    /// it carries one, and its bundled Baseline when it carries that. Identical for both paths —
    /// only the gateway differs, which is the whole of what is being compared.
    private func readThrough(
        _ gateway: any JiraGateway, _ scenario: FixtureScenario
    ) async throws -> Instrument {
        let moment = try XCTUnwrap(
            FixtureJiraGateway.pinnedNow(scenario), "\(scenario.rawValue): no pinned moment"
        )
        let readAt = try FixtureJiraGateway.bundledReadAt(scenario) ?? moment
        let baseline = try FixtureJiraGateway.bundledBaseline(scenario)
        let choice = SprintSnapshot.resolveTrackedSprint(
            in: try await gateway.activeSprints(),
            chosenSprintID: Self.chosenSprint(for: scenario)
        )
        let tracked = try XCTUnwrap(choice.sprint)
        let listing = try await gateway.issues(inSprint: tracked.id)
        return Forecast.evaluate(
            snapshot: SprintSnapshot(sprint: tracked, issues: listing.issues),
            identity: operatorIdentity,
            statusMap: .default,
            workingCalendar: WorkingCalendar(timeZone: TimeZone(identifier: "UTC")!),
            baseline: baseline,
            readAt: readAt,
            now: moment
        ).instrument
    }

    /// The Operator every scenario is written against — restated from `FixtureCorpusTests`, whose
    /// copy is private to that file and whose file this ticket may not edit.
    private let operatorIdentity = OperatorIdentity(
        key: "JIRAUSER10500", name: "dgimaletdinov"
    )

    /// The Operator's answer for the one scenario whose Board reports two active sprints, and no
    /// answer for any other. Restated from `FixtureCorpusTests` for the same reason as the identity
    /// above — and `FixtureCorpusTests` staying green is what stops this drifting: if that
    /// scenario's expected sprint changes, the audit fails before this loop silently follows.
    private static func chosenSprint(for scenario: FixtureScenario) -> Int? {
        scenario == .twoActiveSprints ? 5311 : nil
    }

    // MARK: - Helpers

    /// Runs both gateway reads against the transport and hands back whatever `JiraClientError`
    /// the first one raised.
    private func errorFromSprintRead(
        _ transport: RecordedJiraTransport,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async -> JiraClientError? {
        do {
            _ = try await gateway(transport).activeSprints()
            XCTFail("expected a JiraClientError", file: file, line: line)
            return nil
        } catch let error as JiraClientError {
            return error
        } catch let error as RecordedJiraTransport.UnexpectedRequest {
            XCTFail("the gateway asked for something unrecorded: \(error.path)", file: file, line: line)
            return nil
        } catch {
            XCTFail("expected JiraClientError, got \(error)", file: file, line: line)
            return nil
        }
    }

    /// A fixture's own bytes, served as an HTTP body — the corpus and the capture are the same
    /// shape by construction, which is the claim the test above is checking.
    private func fixtureFile(_ scenario: String, _ file: String) throws -> JiraHTTPResponse {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: "Fixtures", withExtension: nil)
        )
        .appendingPathComponent(scenario)
        .appendingPathComponent(file)
        return JiraHTTPResponse(statusCode: 200, body: try Data(contentsOf: url))
    }

    private func iso(_ string: String) -> Date { ISO8601DateFormatter().date(from: string)! }

    /// A `/rest/agile/1.0/board/{id}/sprint` body with everything the model ignores: `expand`,
    /// `self` links, `activatedDate`, `goal`, an `originBoardId` nobody reads, and a sprint in a
    /// state the instrument never asks about.
    static let sprintsBody = """
    {
      "maxResults": 50, "startAt": 0, "isLast": true,
      "values": [
        {
          "self": "https://jira.example.com/rest/agile/1.0/sprint/5311",
          "id": 5311, "state": "active", "name": "Mobile Platform Sprint 34",
          "startDate": "2026-09-14T09:00:00.000+0300",
          "endDate": "2026-09-25T18:00:00.000+0300",
          "completeDate": null, "activatedDate": "2026-09-14T09:03:11.000+0300",
          "originBoardId": 172, "goal": "Read a real sprint", "avatarAliasId": null
        },
        {
          "self": "https://jira.example.com/rest/agile/1.0/sprint/5312",
          "id": 5312, "state": "active", "name": "Growth Experiment Sprint 7",
          "startDate": "2026-09-14T09:00:00.000+0300",
          "endDate": "2026-10-09T18:00:00.000+0300",
          "completeDate": null, "activatedDate": "2026-09-14T09:11:40.000+0300",
          "originBoardId": 214, "goal": null, "avatarAliasId": null
        },
        {
          "self": "https://jira.example.com/rest/agile/1.0/sprint/5310",
          "id": 5310, "state": "future", "name": "Mobile Platform Sprint 35",
          "startDate": null, "endDate": null, "completeDate": null, "activatedDate": null,
          "originBoardId": 172, "goal": null, "avatarAliasId": null
        }
      ]
    }
    """

    /// A `/rest/agile/1.0/sprint/{id}/issue` body in Data Center's own shape: `expand` echoed on
    /// every issue, a `worklog` and `votes` nobody reads, a `statusCategory`, avatar URLs, three
    /// other plausible points fields, and a sub-task in the same listing as the Issues.
    static let issuesBody = """
    {
      "expand": "schema,names", "startAt": 0, "maxResults": 50, "total": 3,
      "issues": [
        {
          "expand": "operations,versionedRepresentations,editmeta,changelog,renderedFields",
          "id": "97401", "self": "https://jira.example.com/rest/api/2/issue/97401", "key": "TAS-2101",
          "fields": {
            "summary": "Store the Personal Access Token as one Keychain item",
            "labels": ["m1", "credential"],
            "status": { "self": "https://jira.example.com/rest/api/2/status/10000", "id": "10000",
              "description": "", "iconUrl": "https://jira.example.com/images/icons/statuses/generic.png",
              "name": "Done",
              "statusCategory": { "self": "https://jira.example.com/rest/api/2/statuscategory/3", "id": 3, "key": "done", "colorName": "green", "name": "Done" } },
            "issuetype": { "self": "https://jira.example.com/rest/api/2/issuetype/10001", "id": "10001",
              "description": "", "iconUrl": "https://jira.example.com/secure/viewavatar?size=xsmall&avatarId=10303&avatarType=issuetype",
              "name": "Task", "subtask": false, "avatarId": 10303 },
            "priority": { "self": "https://jira.example.com/rest/api/2/priority/2", "id": "2", "name": "High",
              "iconUrl": "https://jira.example.com/images/icons/priorities/high.svg" },
            "progress": { "progress": 0, "total": 14400 },
            "aggregateprogress": { "progress": 0, "total": 14400 },
            "timespent": 14400, "timeoriginalestimate": null, "timeestimate": null, "timetracking": {},
            "worklog": { "startAt": 0, "maxResults": 20, "total": 0, "worklogs": [] },
            "votes": { "self": "https://jira.example.com/rest/api/2/issue/97401/votes", "votes": 1, "hasVoted": true },
            "watches": { "self": "https://jira.example.com/rest/api/2/issue/97401/watchers", "watchCount": 3, "isWatching": true },
            "created": "2026-09-14T09:20:11.000+0300",
            "updated": "2026-09-18T14:05:00.000+0300",
            "resolutiondate": "2026-09-18T14:05:00.000+0300",
            "resolution": { "self": "https://jira.example.com/rest/api/2/resolution/10000", "id": "10000", "name": "Done" },
            "duedate": null, "fixVersions": [], "components": [], "versions": [], "issuelinks": [],
            "assignee": { "self": "https://jira.example.com/rest/api/2/user?username=dgimaletdinov",
              "name": "dgimaletdinov", "key": "JIRAUSER10500", "emailAddress": "denis@example.com",
              "avatarUrls": { "16x16": "https://jira.example.com/secure/useravatar?size=xsmall&ownerId=JIRAUSER10500&avatarId=10452",
                "24x24": "https://jira.example.com/secure/useravatar?size=small&ownerId=JIRAUSER10500&avatarId=10452",
                "32x32": "https://jira.example.com/secure/useravatar?size=medium&ownerId=JIRAUSER10500&avatarId=10452",
                "48x48": "https://jira.example.com/secure/useravatar?ownerId=JIRAUSER10500&avatarId=10452" },
              "displayName": "Denis Gimaletdinov", "active": true, "timeZone": "Europe/Moscow", "locale": "en_US" },
            "reporter": { "self": "https://jira.example.com/rest/api/2/user?username=psokolov",
              "name": "psokolov", "key": "JIRAUSER11204", "displayName": "Pavel Sokolov", "active": true },
            "customfield_10002": 8,
            "customfield_10004": ["com.atlassian.greenhopper.service.sprint.Sprint@1a2c3e[id=5311,name=Mobile Platform Sprint 34,state=ACTIVE]"],
            "customfield_10007": 13,
            "customfield_10404": 13,
            "customfield_22102": 0
          }
        },
        {
          "expand": "operations,versionedRepresentations,editmeta,changelog,renderedFields",
          "id": "97402", "self": "https://jira.example.com/rest/api/2/issue/97402", "key": "TAS-2102",
          "fields": {
            "summary": "Follow the startAt cursor",
            "labels": [],
            "status": { "self": "https://jira.example.com/rest/api/2/status/4", "id": "4",
              "description": "", "iconUrl": "https://jira.example.com/images/icons/statuses/inprogress.png",
              "name": "In Progress",
              "statusCategory": { "self": "https://jira.example.com/rest/api/2/statuscategory/4", "id": 4, "key": "indeterminate", "colorName": "medium-blue", "name": "In Progress" } },
            "issuetype": { "self": "https://jira.example.com/rest/api/2/issuetype/10003", "id": "10003",
              "description": "", "iconUrl": "https://jira.example.com/secure/viewavatar?size=xsmall&avatarId=10316&avatarType=issuetype",
              "name": "Sub-task", "subtask": true, "avatarId": 10316 },
            "parent": { "id": "97401", "key": "TAS-2101", "self": "https://jira.example.com/rest/api/2/issue/97401" },
            "priority": { "self": "https://jira.example.com/rest/api/2/priority/3", "id": "3", "name": "Medium" },
            "progress": { "progress": 0, "total": 0 }, "worklog": { "startAt": 0, "maxResults": 20, "total": 0, "worklogs": [] },
            "votes": { "self": "https://jira.example.com/rest/api/2/issue/97402/votes", "votes": 0, "hasVoted": false },
            "watches": { "self": "https://jira.example.com/rest/api/2/issue/97402/watchers", "watchCount": 0, "isWatching": false },
            "created": "2026-09-16T10:00:00.000+0300", "updated": "2026-09-21T11:41:19.000+0300",
            "resolution": null, "resolutiondate": null, "duedate": null,
            "fixVersions": [], "components": [], "versions": [], "issuelinks": [],
            "assignee": { "self": "https://jira.example.com/rest/api/2/user?username=dgimaletdinov",
              "name": "dgimaletdinov", "key": "JIRAUSER10500", "displayName": "Denis Gimaletdinov", "active": true },
            "reporter": { "self": "https://jira.example.com/rest/api/2/user?username=dgimaletdinov",
              "name": "dgimaletdinov", "key": "JIRAUSER10500", "displayName": "Denis Gimaletdinov", "active": true },
            "customfield_10002": null,
            "customfield_10004": ["com.atlassian.greenhopper.service.sprint.Sprint@1a2c3e[id=5311,name=Mobile Platform Sprint 34,state=ACTIVE]"],
            "customfield_10007": 5,
            "customfield_10404": null,
            "customfield_22102": null
          }
        },
        {
          "expand": "operations,versionedRepresentations,editmeta,changelog,renderedFields",
          "id": "97403", "self": "https://jira.example.com/rest/api/2/issue/97403", "key": "TAS-2103",
          "fields": {
            "summary": "Triage: how should a stale cache read?",
            "labels": [],
            "status": { "self": "https://jira.example.com/rest/api/2/status/1", "id": "1",
              "description": "", "iconUrl": "https://jira.example.com/images/icons/statuses/open.png",
              "name": "Open",
              "statusCategory": { "self": "https://jira.example.com/rest/api/2/statuscategory/2", "id": 2, "key": "new", "colorName": "blue-gray", "name": "To Do" } },
            "issuetype": { "self": "https://jira.example.com/rest/api/2/issuetype/10001", "id": "10001",
              "description": "", "iconUrl": "https://jira.example.com/secure/viewavatar?size=xsmall&avatarId=10303&avatarType=issuetype",
              "name": "Task", "subtask": false, "avatarId": 10303 },
            "priority": { "self": "https://jira.example.com/rest/api/2/priority/5", "id": "5", "name": "Lowest" },
            "progress": { "progress": 0, "total": 0 }, "worklog": { "startAt": 0, "maxResults": 20, "total": 0, "worklogs": [] },
            "votes": { "self": "https://jira.example.com/rest/api/2/issue/97403/votes", "votes": 0, "hasVoted": false },
            "watches": { "self": "https://jira.example.com/rest/api/2/issue/97403/watchers", "watchCount": 0, "isWatching": false },
            "created": "2026-09-16T09:00:00.000+0300", "updated": "2026-09-16T09:00:00.000+0300",
            "resolution": null, "resolutiondate": null, "duedate": null,
            "fixVersions": [], "components": [], "versions": [], "issuelinks": [],
            "assignee": null,
            "reporter": { "self": "https://jira.example.com/rest/api/2/user?username=dgimaletdinov",
              "name": "dgimaletdinov", "key": "JIRAUSER10500", "displayName": "Denis Gimaletdinov", "active": true },
            "customfield_10002": 3,
            "customfield_10004": ["com.atlassian.greenhopper.service.sprint.Sprint@1a2c3e[id=5311,name=Mobile Platform Sprint 34,state=ACTIVE]"],
            "customfield_10007": null,
            "customfield_10404": null,
            "customfield_22102": null
          }
        }
      ]
    }
    """

    /// A generated page of the sprint issue listing, for the paging tests: shape as captured,
    /// count as convenient — including a count of zero, which is a page that stopped short.
    static func issuesPage(startAt: Int, count: Int, total: Int) -> String {
        let issues = (0..<count).map { offset -> String in
            let number = startAt + offset + 1
            return """
            { "id": "98\(number)", "key": "P-\(number)",
              "fields": { "summary": "Issue \(number)",
                "issuetype": { "name": "Task", "subtask": false },
                "status": { "name": "Open" },
                "assignee": { "name": "dgimaletdinov", "key": "JIRAUSER10500", "displayName": "Denis Gimaletdinov" },
                "customfield_10002": 1 } }
            """
        }.joined(separator: ",\n      ")
        return """
        {
          "expand": "schema,names", "startAt": \(startAt), "maxResults": 50, "total": \(total),
          "issues": [
            \(issues)
          ]
        }
        """
    }

    static func sprintsPage(isLast: Bool, ids: [Int]) -> String {
        let values = ids.map {
            """
            { "id": \($0), "state": "active", "name": "Sprint \($0)",
              "startDate": "2026-09-14T09:00:00.000+0300", "endDate": "2026-09-25T18:00:00.000+0300" }
            """
        }.joined(separator: ",\n        ")
        return """
        { "maxResults": 50, "startAt": 0, "isLast": \(isLast),
          "values": [
            \(values)
          ]
        }
        """
    }
}

/// Replays recorded bodies per request path and records every request that was made.
///
/// A path with no recording is a request the milestone's bound forbids, so it is reported by the
/// transport that would have carried it — "no other request is ever made" is enforced here rather
/// than asserted afterwards (#11). Where a path holds several pages they are served in order and
/// the last one repeats, which is how a server that ignores `startAt` behaves.
private final class RecordedJiraTransport: JiraTransport, @unchecked Sendable {
    struct UnexpectedRequest: Error { let path: String }

    private let pages: [String: [JiraHTTPResponse]]
    private var served: [String: Int] = [:]
    private let failure: Error?
    private(set) var requests: [URLRequest] = []

    /// Pages keyed by path *suffix*, so a test names `rest/agile/1.0/sprint/5311/issue` and the
    /// transport matches whatever the client put in front of it — a context path included.
    init(failure: Error? = nil, pages: [String: [JiraHTTPResponse]]) {
        self.failure = failure
        self.pages = pages
    }

    convenience init(failure: Error? = nil, bodies: [String: [String]]) {
        self.init(
            failure: failure,
            pages: bodies.mapValues { body in
                body.map { JiraHTTPResponse(statusCode: 200, body: Data($0.utf8)) }
            }
        )
    }

    func send(_ request: URLRequest) async throws -> JiraHTTPResponse {
        requests.append(request)
        if let failure { throw failure }
        let url = request.url
        let path = url?.path ?? "<no url>"
        guard let key = pages.keys.first(where: { path.hasSuffix("/" + $0) }),
              let recorded = pages[key], !recorded.isEmpty else {
            throw UnexpectedRequest(path: url?.absoluteString ?? "<no url>")
        }
        // The last recorded page repeats once the listing is exhausted.
        let index = min(served[path, default: 0], recorded.count - 1)
        served[path] = index + 1
        return recorded[index]
    }
}

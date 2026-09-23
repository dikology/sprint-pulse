import Foundation

/// The domain's entry point: a pure transformation of
/// `(gateway response, Status Map, stored Sprint Baseline, readAt, now)` into
/// `(Instrument, updated Sprint Baseline)`.
///
/// No I/O happens here and there is no store protocol — the app reads and writes the baseline and
/// the cache and supplies the Status Map and the Working Calendar, the domain only computes. Both
/// the current date and the moment the data was read are arguments, so tests can pin either.
///
/// #4 partitions My Work by Flow State through the Status Map. #5 adds Working Days Remaining
/// through the `WorkingCalendar`. #6 adds the rates and the Confidence State. #7 adds the Caps
/// and the `ConfidenceReading` that explains the result; each extended this function's outputs
/// without replacing its predecessors. #8 adds the Scope Delta pair — the Baseline enters as a
/// value and leaves as an updated one, and no forecast number is read from it (invariant 9).
/// #11 changes none of this: reading a live sprint needed no different forecast, which is what
/// #2 asked for and what `LiveJiraGatewayTests` checks by comparing the two gateway paths byte
/// for byte. My Work itself moved out to `SprintSnapshot.myWork(assignedTo:)` in that ticket —
/// not because the forecast changed, but because the app has to ask the same question the
/// forecast asks in order to know whether there is anything to forecast.
///
/// #12 is the one place M1 touches the table, and only by reaching a rule M0 could not express:
/// `docs/agents/glossary.md` has always named two triggers for rule 1, and the second — data read
/// before the current Working Day — needed a cache to exist before it could fire. It arrives as an
/// argument, not as a re-derivation: rules 2–9, their order, and the Caps are untouched, and every
/// M0 call site keeps using the entry point below, which says what every M0 test already meant —
/// that the data was read at the moment it was evaluated.
public enum Forecast {
    /// A read evaluated at the moment it was taken: the fresh case, and the whole of what M0 ever
    /// had. A fixture is a frozen observation *at* its pinned instant, so reading it at `now` is
    /// the honest answer rather than a default.
    public static func evaluate(
        snapshot: SprintSnapshot,
        identity: OperatorIdentity,
        statusMap: StatusMap,
        workingCalendar: WorkingCalendar,
        baseline: SprintBaseline?,
        now: Date
    ) -> (instrument: Instrument, baseline: SprintBaseline) {
        evaluate(
            snapshot: snapshot,
            identity: identity,
            statusMap: statusMap,
            workingCalendar: workingCalendar,
            baseline: baseline,
            readAt: now,
            now: now
        )
    }

    /// The full entry point. `readAt` is the moment the data behind `snapshot` was taken; `now`
    /// is the moment the reading is judged at. When the two fall in different Working Days the
    /// forecast withdraws to `Unknown` (rule 1) while every Points total, Flow-State figure, and
    /// Scope Delta stays computed and visible — stale Points are still informative, a stale burn
    /// rate is worse than none (#12).
    public static func evaluate(
        snapshot: SprintSnapshot,
        identity: OperatorIdentity,
        statusMap: StatusMap,
        workingCalendar: WorkingCalendar,
        baseline: SprintBaseline?,
        readAt: Date,
        now: Date
    ) -> (instrument: Instrument, baseline: SprintBaseline) {

        // Sub-tasks are detail belonging to their parent, never Issues. Their Estimates are
        // ignored entirely rather than rolled up (CONTEXT invariant 8).
        let issues = snapshot.issues.filter { !$0.fields.issueType.subtask }

        // My Work: the Issues assigned to the Operator — `SprintSnapshot`'s definition, the same
        // one the app counts to know whether there is anything to forecast at all (#11). Team
        // Scope never enters here.
        let myWork = snapshot.myWork(assignedTo: identity)

        // Partition My Work by Flow State. A status with no Status Map entry is an Unmapped
        // Status: its Issues enter no set and the status name is surfaced. Never bucketed by
        // resemblance (ADR-0002).
        var byFlowState: [FlowState: [JiraIssue]] = [:]
        var unmapped: Set<String> = []
        for issue in myWork {
            if let state = statusMap.flowState(for: issue.fields.status.name) {
                byFlowState[state, default: []].append(issue)
            } else {
                unmapped.insert(issue.fields.status.name)
            }
        }

        // Points(S) sums Estimates over a set. An Unestimated Issue contributes nothing — it is
        // excluded, never coerced to zero-as-a-value (CONTEXT invariant 2).
        let pointsByFlowState = Dictionary(uniqueKeysWithValues: FlowState.allCases.map { state in
            (state, (byFlowState[state] ?? []).compactMap { $0.fields.estimate }.reduce(0, +))
        })

        // U — a count, not a sum. Only Unestimated Issues in Actionable ∪ Waiting count;
        // Unestimated Issues that are Done or Dropped can no longer affect the outcome.
        let unestimatedCount = (FlowState.actionable + FlowState.waiting)
            .flatMap { byFlowState[$0] ?? [] }
            .filter { $0.fields.estimate == nil }
            .count

        // WDR: the denominator of the Required Rate. Sprint bounds come from the sprint data,
        // never entered by the Operator; a sprint with no end date yet reports 0 rather than
        // guessing.
        let workingDaysRemaining = snapshot.sprint.endDate.map {
            workingCalendar.workingDaysRemaining(now: now, sprintEnd: $0)
        } ?? 0

        // WDE: the denominator of the Demonstrated Rate. A sprint with no start date yet reports
        // 0, the same as one that has not started.
        let workingDaysElapsed = snapshot.sprint.startDate.map {
            workingCalendar.workingDaysElapsed(now: now, sprintStart: $0)
        } ?? 0

        // A, W, C — summed via the same formula `Instrument.actionablePoints` /
        // `.waitingPoints` expose, so the rates are reproducible by hand from numbers already
        // on screen (CONTEXT invariant 10) and there is one place the sums are computed, not two.
        let actionablePoints = Instrument.sum(FlowState.actionable, of: pointsByFlowState)
        let waitingPoints = Instrument.sum(FlowState.waiting, of: pointsByFlowState)
        let completedPoints = pointsByFlowState[.done] ?? 0

        // R = A / WDR, defined once there is a Working Day left to burn against.
        let requiredRate: Double? = workingDaysRemaining > 0
            ? actionablePoints / Double(workingDaysRemaining)
            : nil

        // D = C / WDE, defined once there is both enough elapsed history and something
        // completed to measure it from.
        let demonstratedRate: Double? = (workingDaysElapsed >= 2 && completedPoints > 0)
            ? completedPoints / Double(workingDaysElapsed)
            : nil

        // Rule 1's stale-data trigger (#12), judged here rather than by whoever renders the
        // result: the question is whether the data predates the Working Day the reading is being
        // evaluated in, which only the domain has both moments and a Working Calendar to answer.
        // Nothing below withdraws because of it except rule 1 — the Points, the Flow-State
        // partition, and the Scope Delta are all still computed, because stale Points are still
        // informative.
        let predatesCurrentWorkingDay = workingCalendar.predatesCurrentWorkingDay(
            readAt: readAt, now: now
        )

        let reading = ConfidenceReading.evaluate(
            unmappedStatusPresent: !unmapped.isEmpty,
            dataPredatesWorkingDay: predatesCurrentWorkingDay,
            actionablePoints: actionablePoints,
            waitingPoints: waitingPoints,
            requiredRate: requiredRate,
            demonstratedRate: demonstratedRate,
            unestimatedCount: unestimatedCount
        )

        let updatedBaseline: SprintBaseline
        if let baseline, baseline.sprintID == snapshot.sprint.id {
            // Already observed this sprint as active — the baseline is fixed.
            updatedBaseline = baseline
        } else {
            // First observation of this sprint: snapshot the whole sprint's Issues. `capturedAt`
            // is the moment the data was read, not the moment it happened to be evaluated — the
            // Baseline records when the sprint looked like this, and a cached first read means it
            // looked like this then (#12).
            updatedBaseline = SprintBaseline(
                sprintID: snapshot.sprint.id,
                capturedAt: readAt,
                entries: issues.map { SprintBaseline.Entry(key: $0.key, estimate: $0.fields.estimate) }
            )
        }

        // The Scope Delta pair (#8): Points over the live sprint's task-level Issues against the
        // Points the Baseline recorded. Unestimated Issues are skipped rather than coerced to
        // zero-as-a-value (invariant 2), and only the Issue set and its Estimates move them — a
        // status change, `Dropped` included, is flow inside a sprint of the same shape, not a
        // movement of scope. On a first observation the Baseline is these same Points, so the
        // Delta is `0`: the instrument explains change it has itself witnessed, never day one
        // seen from day six. The forecast above reads live Points and none of these numbers.
        let liveSprintPoints = issues.compactMap { $0.fields.estimate }.reduce(0, +)
        let baselinePoints = updatedBaseline.points

        let instrument = Instrument(
            sprintName: snapshot.sprint.name,
            pointsByFlowState: pointsByFlowState,
            unestimatedCount: unestimatedCount,
            unmappedStatuses: unmapped.sorted(),
            workingDaysRemaining: workingDaysRemaining,
            workingDaysElapsed: workingDaysElapsed,
            requiredRate: requiredRate,
            demonstratedRate: demonstratedRate,
            reading: reading,
            liveSprintPoints: liveSprintPoints,
            baselinePoints: baselinePoints,
            readAt: readAt,
            predatesCurrentWorkingDay: predatesCurrentWorkingDay
        )

        return (instrument, updatedBaseline)
    }
}

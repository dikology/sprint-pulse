import Foundation

/// The domain's entry point: a pure transformation of
/// `(gateway response, Status Map, stored Sprint Baseline, now)` into
/// `(Instrument, updated Sprint Baseline)`.
///
/// No I/O happens here and there is no store protocol — the app reads and writes the baseline
/// and supplies the Status Map and the Working Calendar, the domain only computes. The current
/// date is an argument so tests can pin "today".
///
/// #4 partitions My Work by Flow State through the Status Map. #5 adds Working Days Remaining
/// through the `WorkingCalendar`. The forecast proper (#6) extends this function further; it
/// does not replace it.
public enum Forecast {
    public static func evaluate(
        snapshot: SprintSnapshot,
        identity: OperatorIdentity,
        statusMap: StatusMap,
        workingCalendar: WorkingCalendar,
        baseline: SprintBaseline?,
        now: Date
    ) -> (instrument: Instrument, baseline: SprintBaseline) {

        // Sub-tasks are detail belonging to their parent, never Issues. Their Estimates are
        // ignored entirely rather than rolled up (CONTEXT invariant 8).
        let issues = snapshot.issues.filter { !$0.fields.issueType.subtask }

        // My Work: the Issues assigned to the Operator. Team Scope never enters the forecast.
        let myWork = issues.filter { identity.matches($0.fields.assignee) }

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

        // WDR: the denominator of the Required Rate (#6). Sprint bounds come from the sprint
        // data, never entered by the Operator; a sprint with no end date yet reports 0 rather
        // than guessing.
        let workingDaysRemaining = snapshot.sprint.endDate.map {
            workingCalendar.workingDaysRemaining(now: now, sprintEnd: $0)
        } ?? 0

        let instrument = Instrument(
            sprintName: snapshot.sprint.name,
            pointsByFlowState: pointsByFlowState,
            unestimatedCount: unestimatedCount,
            unmappedStatuses: unmapped.sorted(),
            workingDaysRemaining: workingDaysRemaining
        )

        let updatedBaseline: SprintBaseline
        if let baseline, baseline.sprintID == snapshot.sprint.id {
            // Already observed this sprint as active — the baseline is fixed.
            updatedBaseline = baseline
        } else {
            // First observation of this sprint: snapshot the whole sprint's Issues.
            updatedBaseline = SprintBaseline(
                sprintID: snapshot.sprint.id,
                capturedAt: now,
                entries: issues.map { SprintBaseline.Entry(key: $0.key, estimate: $0.fields.estimate) }
            )
        }

        return (instrument, updatedBaseline)
    }
}

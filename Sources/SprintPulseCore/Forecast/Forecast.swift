import Foundation

/// The domain's entry point: a pure transformation of
/// `(gateway response, stored Sprint Baseline, now)` into `(Instrument, updated Sprint Baseline)`.
///
/// No I/O happens here and there is no store protocol — the app reads and writes the baseline,
/// the domain only computes the next one. The current date is an argument so tests can pin
/// "today".
///
/// The walking skeleton computes one number. Flow States (#4), Working Days (#5) and the
/// forecast proper (#6) extend this function; they do not replace it.
public enum Forecast {
    public static func evaluate(
        snapshot: SprintSnapshot,
        identity: OperatorIdentity,
        baseline: SprintBaseline?,
        now: Date
    ) -> (instrument: Instrument, baseline: SprintBaseline) {

        // Sub-tasks are detail belonging to their parent, never Issues.
        let issues = snapshot.issues.filter { !$0.fields.issueType.subtask }

        // My Work: the Issues assigned to the Operator. Team Scope never enters the forecast.
        let myWork = issues.filter { identity.matches($0.fields.assignee) }

        // An Unestimated Issue contributes nothing — it is excluded, never coerced to
        // zero-as-a-value (CONTEXT invariant 2).
        let pointsRemaining = myWork.compactMap { $0.fields.estimate }.reduce(0, +)

        let instrument = Instrument(
            sprintName: snapshot.sprint.name,
            pointsRemaining: pointsRemaining
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

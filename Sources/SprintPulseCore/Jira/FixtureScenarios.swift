/// The fixture corpus, as the Operator browses it (#9). Every scenario the instrument can
/// reach is one case, and the panel's scenario picker lists exactly these — so a state the
/// corpus holds but the picker cannot load is a test failure, not an invisible gap.
///
/// Case order is the picker's reading order: the Confidence States first, then the Caps, the
/// Scope figures, and the structural scenarios last. Raw values are the fixture directory
/// names inside `Fixtures/`; `FixtureCorpusTests` pins this list to the directories on disk
/// in both directions, so neither side can drift from the other.
///
/// Scenario titles are deliberately absent here, the way Flow State display labels are:
/// domain-facing code carries the vocabulary, the view renders the words.
public enum FixtureScenario: String, CaseIterable, Identifiable, Sendable {
    // MARK: Confidence States
    /// The corpus's front door: first observation of a sprint, nothing Completed yet.
    case walkingSkeleton = "walking-skeleton"
    case confidenceColdStart = "confidence-cold-start"
    case confidenceZeroCompleted = "confidence-zero-completed"
    case unmappedStatus = "unmapped-status"
    case confidenceOffTrack = "confidence-off-track"
    case confidenceDaysExhausted = "confidence-days-exhausted"
    case confidenceTight = "confidence-tight"
    case confidenceOnTrack = "confidence-on-track"
    case confidenceNoSweat = "confidence-no-sweat"
    case confidenceHandsOff = "confidence-hands-off"
    case confidenceFinished = "confidence-finished"

    // MARK: Caps
    case capUnestimated = "cap-unestimated"
    case capWaitingHeavy = "cap-waiting-heavy"
    case capBoth = "cap-both"
    case capAtBottom = "cap-at-bottom"
    case capHandsOff = "cap-hands-off"
    case capUnknown = "cap-unknown"

    // MARK: Scope
    case scopeGrowth = "scope-growth"
    case scopeShrink = "scope-shrink"
    case baselineColdStart = "baseline-cold-start"
    case allDropped = "all-dropped"

    // MARK: Structure
    case allFlowStates = "all-flow-states"
    case unestimatedAcrossStates = "unestimated-across-states"
    case subtasksWithEstimates = "subtasks-with-estimates"

    // MARK: Live reads
    // The states the M1 gateway meets on a real Board (#11), browsable here for the same reason
    // the rest of the corpus exists: a state that is reachable live has to be reachable by
    // clicking before it can be verified at all.
    /// A Board reporting two sprints in the `active` state — the one scenario the Operator is
    /// prompted about rather than shown, because the instrument never infers which sprint is
    /// being tracked.
    case twoActiveSprints = "two-active-sprints"
    /// A sprint whose Issues belong to three people and one empty assignee, of whom the Operator
    /// is one: My Work and Team Scope are two different numbers on purpose.
    case severalAssignees = "several-assignees"
    /// A resolved identity that matches nothing in the Active Sprint except a sub-task: No Work
    /// Assigned, which is a state of its own and not a zero (CONTEXT invariant 13).
    case noWorkAssigned = "no-work-assigned"

    // MARK: Cached reads
    // The same sprint, observed at two moments — which is the whole of what #12 adds. Both
    // scenarios are `several-assignees`' Board, its Issues, and its `now.json`, so the pair
    // differs in exactly one thing: the `read-at.json` beside them, the moment the data behind
    // the reading was taken. Reachable live on any evening the VPN is off, and reachable here by
    // clicking, which is the only way either can be checked (#9).
    /// Data read earlier in the same Working Day: Points are Points whenever they were counted,
    /// so the forecast stands at `No Sweat`.
    case cacheWithinWorkingDay = "cache-within-working-day"
    /// Data read before the current Working Day: rule 1's second trigger withdraws Confidence to
    /// `Unknown` while the Points totals, the Flow-State partition, and the Scope Delta — a real
    /// +7 in this scenario, both carry a Baseline — stay on screen.
    case cachePredatesWorkingDay = "cache-predates-working-day"

    public var id: String { rawValue }
}

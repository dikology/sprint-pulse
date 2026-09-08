# Sprint Pulse

A personal sprint-confidence instrument for macOS. It reads one Jira sprint and answers a
single question — *am I likely to finish my committed work?* — in a way the reader can
argue with. It is not a Jira client.

## Language

### Scope and subject

**Operator**:
The single person Sprint Pulse belongs to and forecasts for. There is exactly one, and the
application has no concept of other people beyond issue assignment.
_Avoid_: user, developer

**Board**:
The one Jira board Sprint Pulse watches, chosen once by the Operator.

**Active Sprint**:
The Jira sprint on the Board that Sprint Pulse is tracking. Where the Board has several sprints
in the `active` state, the Operator names the one being tracked; Sprint Pulse never infers it.
_Avoid_: current sprint, iteration

**Forecast Subject**:
Whose work the forecast is about. Sprint Pulse forecasts one subject only: the operator's own
assigned issues.
_Avoid_: user, owner

**My Work**:
The issues in the Active Sprint assigned to the operator. The forecast is computed over these
and nothing else.

**Team Scope**:
Every issue in the Active Sprint, regardless of assignee. Displayed as unforecasted context;
no confidence is ever computed over it.

### Work items and estimation

**Issue**:
A Jira work item at task level. Sub-tasks are not Issues; they are detail belonging to their
parent.

**Estimate**:
The story-point value carried by an Issue. Only task-level Issues carry an Estimate; sub-task
estimates are ignored entirely rather than rolled up.
_Avoid_: story points, size, points (when referring to a single Issue)

**Points**:
A sum of Estimates across a set of Issues. Always a total, never a single Issue's value.

**Unestimated Issue**:
An Issue in the Active Sprint with no Estimate. It contributes zero to every Points total, is
counted and displayed separately, and its existence bounds how much Confidence may be claimed.
An Unestimated Issue is an admission of ignorance, never a zero.

### Flow

**Flow State**:
Sprint Pulse's own vocabulary for where an Issue sits in the workflow. The vocabulary is fixed
and independent of any Jira installation.

**Status Map**:
The operator-editable translation from Jira's status names to Flow States. Jira status strings
appear only here; no other part of Sprint Pulse knows them.

**Unmapped Status**:
A Jira status with no entry in the Status Map. Issues in an Unmapped Status are surfaced
prominently and excluded from Points totals — never quietly bucketed into a Flow State.

**In Review**:
The Flow State of work that has left the operator's hands for someone else's judgement but is
not finished. It is a first-class Flow State, never a synonym for done.
_Avoid_: review, in PR, awaiting merge (as state names)

**Dropped**:
The Flow State of work removed from the sprint without being completed. Dropped Points leave
the sprint's remaining total and are never added to completed work.
_Avoid_: cancelled, killed, abandoned

**Actionable**:
Points the operator's own effort can move: Flow States `ToDo` and `InProgress`. The forecast is
computed over Actionable Points and nothing else.

**Waiting**:
Points that are unfinished but outside the operator's control: Flow States `InReview` and
`OnHold`. Displayed alongside the forecast and able to cap Confidence, never folded into it.
_Avoid_: blocked (which names only part of it)

**Intent**:
A goal the operator expresses by pressing one button — `Start`, `Send to Review`, `Mark Done`.
An Intent is resolved against the transitions Jira currently offers for that Issue; an Intent
with no legal transition is absent from the interface rather than shown as failing.
_Avoid_: action, transition (when referring to the button)

### Time

**Working Day**:
A calendar date that falls on a configured working weekday and is not a Non-Working Date.
The current date counts as a whole Working Day until local midnight.
_Avoid_: business day, day left

**Non-Working Date**:
A specific calendar date the operator has declared unavailable — a public holiday or personal
leave. Held locally; Sprint Pulse does not read any calendar.

**Working Days Remaining**:
The count of Working Days from today through the Active Sprint's end date, inclusive of today.

### Forecast

**Required Rate**:
Points remaining divided by Working Days Remaining. What the operator must burn per day to
finish.

**Demonstrated Rate**:
The observed rate at which the operator has been completing Points. The input the Required Rate
is judged against.

**Confidence**:
The relationship between Demonstrated Rate and Required Rate, expressed on a named scale. It
is a stated comparison of two visible numbers, not a probability.
_Avoid_: likelihood, probability, score, health

**Confidence State**:
One of seven named values Confidence may take: `Unknown`, `Off Track`, `Tight`, `On Track`,
`No Sweat`, `Hands Off`, `Finished`.

**Finished**:
The Confidence State when neither Actionable nor Waiting Points remain — every Issue of My Work
has reached `Done` or `Dropped`.

**Hands Off**:
The Confidence State when no Actionable Points remain but Waiting Points do — finished with
everything that is yours to do, without the sprint being finished.

**Cap**:
A condition that demotes the displayed Confidence State by one band. Caps only ever demote.

**Sprint Baseline**:
A snapshot of the Active Sprint's Issues and Estimates, taken the first time Sprint Pulse
observes the sprint as active. It exists to explain change, never to be forecast against.

**Scope Delta**:
The difference between the Active Sprint's live Points and its Sprint Baseline. Displayed so
that a movement in Confidence can be attributed either to the operator's progress or to the
sprint changing shape.
_Avoid_: scope creep, churn

## Invariants

1. Jira's status strings exist only inside the Status Map. No other part of the model knows them.
2. An Unestimated Issue is never treated as zero Points. It is excluded and counted separately.
3. Dropped Points are never counted as completed work.
4. Confidence is computed over the Actionable Points of My Work only. Waiting Points, Team Scope,
   and Unestimated Issues never enter the ratio.
5. A Cap may only demote a Confidence State, never promote one.
6. No Confidence is ever computed over Team Scope.
7. `Unknown` is a valid answer and is always preferred to a guess.
8. Sub-task estimates are ignored rather than rolled up.
9. The forecast runs on live Points. The Sprint Baseline explains movement; it is never the
   basis of a forecast.
10. Every number shown must be reproducible by hand from other numbers shown on the same screen.
11. An Intent with no legal Jira transition is absent from the interface, not disabled or errored.

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
in the `active` state, the Operator names the one being tracked; Sprint Pulse never infers it. The
answer is remembered for the life of that sprint, and belongs to the Board it was given on.
_Avoid_: current sprint, iteration

**Forecast Subject**:
Whose work the forecast is about. Sprint Pulse forecasts one subject only: the operator's own
assigned issues.
_Avoid_: user, owner

**My Work**:
The issues in the Active Sprint assigned to the operator. The forecast is computed over these
and nothing else. Defined once — `SprintSnapshot.myWork(assignedTo:)` — which is also how the app
knows whether there is anything to forecast at all.

**No Work Assigned**:
The displayed state where the resolved identity matches zero Issues in the Active Sprint. It is
not a Confidence State and not a zero: the forecast has no subject, and the panel says so instead
of rendering rule 2's `Finished`. Sub-tasks never give it a subject.
_Avoid_: empty sprint, finished (for an empty My Work), zero points

**Team Scope**:
Every issue in the Active Sprint, regardless of assignee. Displayed as a dim secondary Points
total — context, never a reading; no Confidence, forecast, or rate is ever computed over it.

### Work items and estimation

**Issue**:
A Jira work item at task level. Sub-tasks are not Issues; they are detail belonging to their
parent.

**Estimate**:
The story-point value carried by an Issue. Only task-level Issues carry an Estimate; sub-task
estimates are ignored entirely rather than rolled up. Jira keeps it in a custom field whose id is
assigned per installation, so the field is Operator configuration (#11) — and reading the wrong
one decodes every Estimate as absent.
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
prominently and excluded from the forecast's Points totals — never quietly bucketed into a Flow
State.

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

### Surfaces

**Glance**:
The collapsed surface Sprint Pulse keeps on screen beside the notch — or top-centre of a screen
without one. It shows Points remaining and nothing that can go stale or be demoted: no Confidence
State, no rate. Opening it is a click, never a hover.
_Avoid_: pill, island, notch view, HUD, menu bar item

**Panel**:
The expanded surface a click on the Glance opens: the reading and every figure it was computed
from. Configuration is not on it — the one exception is choosing a Flow State for an Unmapped
Status, which is resolved where it is seen.
_Avoid_: popover, window, dashboard

### Sources

**Fixture Mode**:
The panel reading the bundled corpus rather than a live Board. It is what a fresh install does — no
credential exists, so every state stays explorable before anything is authenticated — and it is also
something the Operator can *ask for* with a credential standing, to put a state the Board already
showed back on screen. The ask is theirs, persisted, and reversible; it is not a fact about the
connection, and the credential and Board survive it untouched.
_Avoid_: Demo mode, offline mode, sandbox.

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

**Reading**:
The pair of facts behind a displayed Confidence State — the rule of the Confidence table that
matched, and the Caps that fired. Carried as data, so the Explanation can be generated from the
same facts the number was.
_Avoid_: verdict, judgement, score

**Explanation**:
The one-line account of a displayed Confidence State, generated from its Reading — the rule that
matched and the Caps that fired. A demotion is never shown without its Explanation, and a Reading
that was not demoted never claims one.
_Avoid_: reason, tooltip, justification

**Cached Read**:
The last read of the Board that got through, kept by the app beside the instant its data was taken.
What the panel shows when Jira cannot be reached — a reading that survived the request that failed,
never dressed as a current one: it is labelled as cached, its age is on screen, and once it predates
the current Working Day the forecast withdraws to `Unknown` while its Points stay.
_Avoid_: stale data, offline mode, fallback, snapshot (the Sprint Baseline took that word)

**Sprint Baseline**:
A snapshot of the Active Sprint's Issues and Estimates, taken the first time Sprint Pulse
observes the sprint as active. It exists to explain change, never to be forecast against. One is
held per sprint, and it outlives quitting the app and the Operator naming a different active sprint:
a sprint's first observation is not something the app is entitled to lose. The Baseline's own moment
is what the Scope Delta is measured from, and it is shown beside the Delta — a Baseline taken on day
six is the definition of the term, not a failure to meet it.
_Avoid_: day-zero snapshot, original shape, drift

**Live Sprint Points**:
Points over every task-level Issue in the Active Sprint, regardless of assignee — the shape
the sprint has now, which the Sprint Baseline once recorded as Baseline Points. Shown on the
panel as the Team Scope total, which doubles as the Scope Delta's live operand; no forecast
figure is computed from either. One number is shown once, under one name.

**Scope Delta**:
The difference between the Active Sprint's live Points and its Sprint Baseline. Displayed so
that a movement in Confidence can be attributed either to the operator's progress or to the
sprint changing shape. It moves when the Issue set or its Estimates move — added, removed,
re-estimated — and never on a status change: work `Dropped` in place has left the remaining
total, not the sprint's shape.
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
10. Every number shown must be reproducible by hand from other numbers shown on the same Panel. The
    Glance shows Points remaining only, a figure that claims no Confidence.
11. An Intent with no legal Jira transition is absent from the interface, not disabled or errored.
12. A displayed Confidence State always carries its Reading — the rule that matched and the Caps
    that fired — as data. Its Explanation is rendered from that Reading and re-derives no
    arithmetic of its own.
13. An empty My Work is never rendered as a confident zero. Where the resolved identity matched no
    Issue, the Panel shows No Work Assigned instead of the reading, and the Glance shows no
    number; rule 2's `Finished` stays what it means — work completed, not work absent.
14. A live read is issued by the Operator, not by the app: when the Operator opens the Panel, on
    explicit refresh, and in answer to something they did to the connection — remembering a Board
    or an Estimate field, resolving or revoking a credential, naming the tracked sprint among
    several active ones, or switching the panel off Fixture Mode and back onto their Board. No
    timer and no polling reaches Jira, and no live read happens at launch.
15. Every reading carries the instant its data was taken, and a Cached Read is never shown as a
    live one: the Panel says which of the two it is and how old the data is. Data that predates the
    current Working Day withdraws Confidence to `Unknown` through rule 1 while its Point totals, its
    Flow-State partition, and its Scope Delta stay on screen. A read that failed overwrites neither
    the Cached Read nor the Sprint Baseline.

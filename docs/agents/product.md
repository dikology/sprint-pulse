# Sprint Pulse — Product Definition

The agreed definition of what Sprint Pulse is, settled by interview. Vocabulary is defined in
[`CONTEXT.md`](../../CONTEXT.md); exact arithmetic and edge cases are in
[`glossary.md`](./glossary.md). This file is the *what and why*.

## What it is

A personal sprint-confidence instrument for macOS. It watches one Jira board, reads one sprint,
and answers one question: **am I likely to finish my committed work?**

It answers in a form the Operator can argue with — two visible numbers and the relationship
between them — rather than a score to be trusted.

## What it is not

- **Not a Jira client.** It does not browse, search, comment, create, or edit issues.
- **Not a team dashboard.** It never forecasts anyone but the Operator.
- **Not a sync engine.** It reads, and occasionally writes one transition. It never queues,
  reconciles, or resolves conflicts.
- **Not a coach.** It reports state. It does not exhort, congratulate, or notify.

## The forecast

**Required Rate** is what the Operator must burn per day. **Demonstrated Rate** is what they
have been burning. **Confidence** is the ratio between them, mapped to a named state.

The choice of a deterministic ratio over a probabilistic model is deliberate: the primary
outcome is a forecast the Operator can check by hand, and a probability is not that. See
[ADR-0004](../adr/0004-required-rate-over-probabilistic-forecast.md).

Three properties matter more than accuracy:

1. **It can say `Unknown`.** With too little data, an unmapped status, or a stale cache, the
   forecast withdraws rather than guessing.
2. **It never counts work it hasn't got.** Unestimated Issues are counted and named, never
   silently treated as zero. Dropped work leaves the sprint without ever being credited as done.
3. **Every number is reproducible by hand** from other numbers on the same screen.

## Flow and review

Sprint Pulse has its own six-state vocabulary — `ToDo`, `InProgress`, `InReview`, `OnHold`,
`Done`, `Dropped` — and a Status Map translating the Operator's Jira statuses into it. Jira's
strings live nowhere else. See [ADR-0002](../adr/0002-flow-states-independent-of-jira.md).

The Status Map for the Operator's current workflow:

| Jira status | Flow State |
| --- | --- |
| Backlog | `ToDo` |
| Open | `ToDo` |
| Need Info | `OnHold` |
| In Progress | `InProgress` |
| In Review | `InReview` |
| Done | `Done` |
| Cancelled | `Dropped` |

`Backlog` occurs on issues inside an active sprint, not only outside one. Any Jira status absent
from the map is an `Unmapped Status`: surfaced prominently, excluded from totals, and it forces
Confidence to `Unknown`.

Remaining work splits in two. **Actionable** (`ToDo` + `InProgress`) is what the Operator's own
effort moves, and is the only thing the forecast runs on. **Waiting** (`InReview` + `OnHold`) is
unfinished but out of their hands; it is displayed alongside and can cap Confidence, but never
enters the ratio. Review is therefore neither completed work nor a debt against the Operator's
own rate. See [ADR-0003](../adr/0003-confidence-over-actionable-points-only.md).

## Scope change

The forecast always runs on live totals — the work exists whether or not it was there on day one.
A Sprint Baseline is captured the first time the sprint is seen active, and the Scope Delta is
displayed so a drop in Confidence is always attributable: the Operator can see whether they fell
behind or whether the sprint grew underneath them.

## Actions

Three Intents: `Start`, `Send to Review`, `Mark Done`. An Intent is not a hardcoded transition —
it resolves against the transitions Jira offers for that issue at that moment. An Intent with no
matching legal transition is **absent from the interface**, not shown as failing.

Confirmation is derived, not configured: **an Intent requires confirmation exactly when Jira
offers no transition back.** Reversible moves execute immediately with a five-second undo that
fires the reverse transition. Irreversible ones confirm once, naming the issue key. This keeps
the confirmation rule correct when the workflow changes.

## Data and connectivity

Jira **Data Center**: REST API v2 (`/rest/api/2/`) plus Agile (`/rest/agile/1.0/`), Bearer auth
with a Personal Access Token, operator-configured base URL.

"Bounded" describes the call surface, not the mechanism. Sprint Pulse performs exactly four
operations and no others:

1. Read the Active Sprint on the Board.
2. Read that sprint's issues.
3. Read one issue's legal transitions.
4. Execute one transition.

Refresh happens on window open, on explicit refresh, and as a targeted re-read of a single issue
after a successful write. There is no background polling.

Identity is resolved once at credential setup via `/rest/api/2/myself`, storing both `key` and
`name` and matching assignees on `key` with `name` as fallback. The Operator is never asked to
type their own username — a typo there yields a confident, empty forecast rather than an error.
A resolved identity matching zero issues in an active sprint is its own displayed state.

The PAT is a single Keychain item. It is never logged and never written to the cache.

## When Jira is unavailable

A self-hosted instance usually means VPN, so unreachability is an ordinary condition, not an
edge case.

**Reads:** the cache displays indefinitely with a visible age. Once the data predates the
current Working Day, Confidence is forced to `Unknown` — stale point totals remain useful, but a
stale burn rate is worse than none.

**Writes never queue.** By the time connectivity returns, the transition may be illegal, the
issue may have moved, or someone else may have actioned it; replaying an intent formed against a
stale world is how a reader turns into a broken sync engine. Offline, the Intent buttons are
simply absent — the same rule as an Intent with no legal transition.

## Fixtures

Fixtures are JSON in the exact shape of Jira Data Center's responses, served through the same
gateway as the live client. `SprintPulseCore` cannot tell which it is talking to.

Fixture mode is the **default whenever no credential exists**, so the app is fully explorable
before anything is authenticated. Fixtures are the project's test corpus, not a demo: the set
covers every reachable state — each Confidence State, both Caps firing, an `Unmapped Status`
present, `Hands Off`, a large Scope Delta, a mid-sprint cold start, and a sprint entirely
`Dropped`. A state absent from the fixtures is untestable and will ship broken.

## Presentation, motion, and accessibility

The mascot depicts **terrain and weather, never judgement**. `Tight` is steep ground and
gathering cloud; `Off Track` is a long climb in bad light. Never a disappointed face, never a
slumped posture. An expedition has hard days without the climber having failed; a sad mascot
would make the instrument an authority figure and productivity performative.

- Animation fires **only on a change of Confidence State**. Nothing idle-loops — a looping
  animation in peripheral vision is a permanent low-grade demand for attention.
- Under `accessibilityDisplayShouldReduceMotion`, transitions become cross-fades.
- An **independent** "no animation" preference exists, because "I find it distracting" is a
  different reason from an accessibility need and should not require changing a system setting.
- The mascot is decorative and `accessibilityHidden`. It never carries information absent from
  the text, and every Confidence State is a readable string.

## Notifications

**None.** Sprint Pulse never notifies about Confidence. A push saying confidence dropped to
`Tight` converts a glanceable instrument into a source of anxiety that cannot be dismissed — the
exact failure the design is avoiding. The contract is: *it tells you when you look at it.*

## Delivery

All domain logic, the Jira gateway, and the cache live in a `SprintPulseCore` SPM package with
**zero UI dependencies** — it compiles without SwiftUI. The macOS app is a thin view layer.

**The MVP is M0 + M1: a read-only instrument.** M2 is built only after living with M0+M1 for a
full sprint.

| Milestone | Contents | In MVP |
| --- | --- | --- |
| **M0** — the instrument, offline | `SprintPulseCore` (Flow States, Status Map, forecast, Confidence States, Caps); the fixture corpus; a menu-bar panel showing Points by Flow State, Working Days Remaining, Required Rate, Demonstrated Rate, Confidence State with a one-line explanation, and the unestimated / dropped / Scope Delta lines. No Jira. | ✅ |
| **M1** — live reads | Keychain PAT, base URL and board config, `/myself` identity, live sprint and issue fetch, cache with age stamp, `Unknown` on stale, Status Map editor. | ✅ |
| **M2** — writes | Per-issue legal transitions, the three Intents, reversibility-derived confirmation, undo. | ❌ |
| **M3** — the mascot | Terrain and weather states, change-only animation, reduced-motion handling. | ❌ |

The sequencing is deliberate. The project's risk is concentrated in M0: the forecast either says
something true about a sprint or it does not, and that is answerable with fixtures alone, before
a line of networking code. M2 is the only part that can damage anything — writes against a
workflow the Operator does not control belong on top of an integration already trusted, not
built beside it. M3 is last because a mascot rendering an unvalidated forecast is decoration on
a possibly-wrong number.

**The cheapest possible gut-check** is M0 alone, pointed at fixtures hand-transcribed from a real
current sprint. If the Confidence State matches the Operator's own felt sense of that sprint, the
model is right and M1 is plumbing.

## Hosting

Sprint Pulse ships as a standalone menu-bar app, not a Boring Notch fork. Licence: MIT. See
[ADR-0005](../adr/0005-standalone-app-not-a-boring-notch-fork.md).

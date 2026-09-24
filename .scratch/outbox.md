# Outbox — cross-repo signals

Append-only. One entry per change made in **this repo** that matters *beyond*
this repo:

- something the `agents across repos` series can now claim — sprint-pulse is
  dogfood source material for it, a live example of the same `AGENTS.md` +
  `docs/agents/` + single `CONTEXT.md` + GitHub-issues-as-specs substrate as
  `ae-daily-driver`,
- a shift in the M0 / M1 / M2 milestone narrative,
- a decision worth citing as a worked example of the workflow.

Consumed by `/wdwgfh` in the tapestry vault. wdwgfh tracks a high-water mark
per repo and only reads entries dated after its last run, so **do not delete
entries** — it decides what is already folded in.

Not a changelog. Routine commits do not belong here. If you can't name the
cross-repo stake in one sentence, it isn't an outbox entry.

## Format

```
### YYYY-MM-DD — <short title>
<2–4 lines: what changed, and why it matters outside this repo.>
Refs: <commit / file / issue>
```

---

## Entries

### 2026-09-12 — Outbox created
Cross-repo signal channel from this repo to the wdwgfh strategic review,
mirroring the mechanism already built in `ae-daily-driver`. Before this,
wdwgfh could only learn of changes here by scanning git log and re-inferring
their stakes.
Refs: `AGENTS.md` "Cross-repo signals"; `ae-daily-driver/.scratch/outbox.md`; `tapestry/projects/agents across repos.md`

### 2026-09-16 — M0 closed: the instrument is explorable and legible
Issue #9 shipped the fixture scenario picker (its list pinned to the corpus directories by a
test, so no state can ship unclickable and no fixture untested), the dim Team Scope total, a
VoiceOver pass, and a zero-motion panel — closing the M0 milestone. The cross-repo claim the
series can now make: an agent pipeline can close a milestone whose final acceptance test is
explicitly *not* automatable, because the issue-as-spec + `CONTEXT.md` + glossary substrate
carried enough judgement for everything before it.
Refs: #9; `Sources/SprintPulseCore/Jira/FixtureScenarios.swift`; `Tests/SprintPulseCoreTests/FixtureCorpusTests.swift`

### 2026-09-17 — M1 opens: the milestone boundary crossed without touching the model
Issue #10 shipped credential + identity — Keychain PAT, `/myself` resolution behind an injected
transport, distinct failure states — and the forecast model did not change by one line, exactly
as #2's decision demanded. The cross-repo claim the series can now make: an agent pipeline that
agrees its seams up front (gateway protocol, transport seam, probe seam in the app) can cross the
offline→online milestone boundary as ordinary ticket work; the seam discipline written in the
walking-skeleton ticket held under a security-critical extension of the same repo.
Refs: #10; `Sources/SprintPulseCore/Jira/JiraTransport.swift`; `Tests/SprintPulseAppTests/`

### 2026-09-21 — The live read landed on the fixture protocol, unchanged
Issue #11 put a real Jira Data Center Board behind the same `JiraGateway` the fixture corpus had
satisfied since #3: two Agile listings, paged to their own `total`, decoded by the same decoder
that reads the corpus — and a test that serves the corpus's own bytes through the live client and
demands an identical `Instrument`. The rule table, its evaluation order, and the Caps are
untouched, and so is the model's output shape: the one thing the panel needed to know that
`Instrument` did not say — whether My Work has any subject at all — is asked of
`SprintSnapshot.myWork(assignedTo:)`, the same definition the forecast sums over, rather than
being added as a field. The cross-repo claim: a spec that pre-commits to "if the live integration
needs a model change, the seam was drawn wrong" is checkable in review, and the check is a
byte-for-byte equality between the fixture path and the network path plus a M0 whole-value
assertion that survives untouched — not a reviewer's assurance.
Refs: #11; `Sources/SprintPulseCore/Jira/LiveJiraGateway.swift`;
`Tests/SprintPulseCoreTests/LiveJiraGatewayTests.swift`

### 2026-09-23 — The stale-data rule was written down before the thing that could violate it
#12 added the cache, and with it the one change to the forecast that M1's own ticket list
allowed: rule 1 of the Confidence table already named "the cache predates the current Working
Day" in `docs/agents/glossary.md` back at #6, when there was no cache to go stale. So the
implementation widened an existing rule rather than inventing one — an enum case, a
`readAt` argument, and a `WorkingCalendar` comparison, with rules 2–9 and the Caps untouched
and every M0 call site compiling unchanged against a convenience entry point. The cross-repo
claim: a glossary that records a rule before the mechanism exists turns the milestone's
hardest behavioural change into a reviewable diff, and the check that it stayed a widening
rather than a rewrite is executable — the corpus audit and #4's whole-value assertion still
decide the argument.
Refs: #12; `Sources/SprintPulseCore/Domain/WorkingCalendar.swift`;
`Sources/SprintPulseCore/Domain/CachedSprint.swift`; `docs/agents/glossary.md`

### 2026-09-24 — An operator-facing write path landed without a single new rule
#13 shipped the Status Map editor — the milestone's only *write* surface: the Operator adds,
re-maps, and removes Jira-status translations, persisted across launches. The cross-repo claim the
series can now make: an agent pipeline can put an editor in front of a user without touching the
decision logic, when the domain already took that configuration as a value (`Forecast.evaluate` had
taken `statusMap` as an argument since #4) — here the rule table, its order, and the Caps changed by
zero lines, and the new "an edit re-judges the standing read instead of issuing a fetch" rule kept a
stated invariant (a live read happens only on the Operator's initiative) true by construction rather
than by discipline. M1's instrument work is now closed; only Baseline persistence (#14) and the
mode-switch parity check (#15) stand between this repo and its MVP.
Refs: #13; `Sources/SprintPulse/StatusMapStore.swift`; `Sources/SprintPulse/PanelModel.swift`

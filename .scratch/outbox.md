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

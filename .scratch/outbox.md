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

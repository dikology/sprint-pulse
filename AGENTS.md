# AGENTS.md

## Agent skills

### Issue tracker

Issues and specs live as GitHub issues (`gh` CLI), repo `dikology/sprint-pulse`. See `docs/agents/issue-tracker.md`.

### Triage labels

Default vocabulary: `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: `CONTEXT.md` + `docs/adr/` at the repo root. See `docs/agents/domain.md`.

### Product definition

The agreed product definition lives in `docs/agents/product.md`; precise arithmetic and edge cases in `docs/agents/glossary.md`.

### Cross-repo signals

When you finish a change here that matters *beyond this repo* — something the `agents across repos` series can now claim (this repo is dogfood source material for it), or a shift in the M0/M1/M2 milestone narrative — append a dated entry to `.scratch/outbox.md`. Name the cross-repo stake in one sentence; routine commits do not belong there. The wdwgfh strategic review (tapestry vault) reads that file on its next run.

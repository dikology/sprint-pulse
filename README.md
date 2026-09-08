# Sprint Pulse

A personal sprint-confidence instrument for macOS. It reads one Jira sprint and answers a
single question — *am I likely to finish my committed work?* — in a way the reader can argue
with. It is not a Jira client.

See [`CONTEXT.md`](./CONTEXT.md) for the vocabulary, [`docs/agents/product.md`](./docs/agents/product.md)
for what it is and why, and [`docs/adr/`](./docs/adr/) for the decisions.

## Layout

| Path | What it is |
| --- | --- |
| `Sources/SprintPulseCore/` | The domain model, the forecast, and the Jira gateway. Builds without SwiftUI ([ADR-0005](./docs/adr/0005-standalone-app-not-a-boring-notch-fork.md)). |
| `Sources/SprintPulseCore/Fixtures/` | The fixture corpus: JSON in the exact shape of Jira Data Center responses, one directory per sprint scenario. |
| `Sources/SprintPulse/` | The macOS menu-bar app. A thin view layer holding platform and persistence concerns. |
| `Tests/SprintPulseCoreTests/` | Domain tests, run against fixtures with a pinned date. |

## Build and test

```sh
swift test          # the domain
swift run SprintPulse   # the menu-bar app, on fixtures
```

The menu-bar app currently runs entirely on fixtures — no Jira, no network, no credential.
It shows Points per Flow State for the Active Sprint's My Work: Actionable and Waiting as
separate totals, Completed and Dropped as their own figures, a count of Unestimated Issues,
and any Unmapped Status named prominently. The Status Map is shown read-only ([ADR-0002](./docs/adr/0002-flow-states-independent-of-jira.md));
its editor is M1.

## Status

Milestone **M0** — the offline instrument. The walking skeleton
([#3](https://github.com/dikology/sprint-pulse/issues/3)) established both seams, the package
boundary, and the testing pattern. Flow States and the Status Map
([#4](https://github.com/dikology/sprint-pulse/issues/4)) turn the single Points figure into
Points per Flow State. Working Days Remaining (#5) and the forecast proper (#6) come next.

## Licence

MIT. See [`LICENSE`](./LICENSE).

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
| `Tests/SprintPulseAppTests/` | The app's own seams: the single Keychain item, the preferences store, and the setup flow that persists through them. Still no network — the identity probe is injected, as the transport is on the core side. |

## Build and test

```sh
swift test          # the domain
swift run SprintPulse   # the menu-bar app, on fixtures
```

The panel's reading still runs entirely on fixtures, and first launch presents no
authentication wall: a scenario picker at the top of the panel loads any fixture in the
corpus, so every state the instrument can reach is reachable by clicking, at the moment each
scenario pins for itself. What the credential half of M1 adds beside it
([#10](https://github.com/dikology/sprint-pulse/issues/10)) is a Jira connection section:
it stores a Personal Access Token as a single macOS Keychain item and resolves the Operator's
identity from `/rest/api/2/myself` — but it fetches no sprint yet, so fixtures stay the
default reading whatever the connection state is, and live reads follow with the Board
configuration (#11).

It shows Points per Flow State for the Active Sprint's My Work: Actionable and Waiting as
separate totals, Completed and Dropped as their own figures, a count of Unestimated Issues,
and any Unmapped Status named prominently. Above them sit Working Days Remaining and Elapsed,
the Required Rate, the Demonstrated Rate, and the Confidence State with the one-line explanation
of it — the rule that matched, plus any Cap that demoted the reading, spelled out from the
numbers underneath. Below them, the sprint's shape: the Team Scope total — every Issue in the
sprint, dim and secondary, with no forecast ever attached to it — the Points recorded the first
time the sprint was observed, and the Scope Delta between them — added scope and removed work
read as different words, not just different signs. The Status Map is shown read-only ([ADR-0002](./docs/adr/0002-flow-states-independent-of-jira.md));
its editor is M1. Nothing on the panel animates or loops, and nothing conveys meaning by image
or colour alone: every figure is spelled out for a screen reader.

## Status

Milestone **M0** — the offline instrument. The walking skeleton
([#3](https://github.com/dikology/sprint-pulse/issues/3)) established both seams, the package
boundary, and the testing pattern. Flow States and the Status Map
([#4](https://github.com/dikology/sprint-pulse/issues/4)) turned the single Points figure into
Points per Flow State, Working Days Remaining
([#5](https://github.com/dikology/sprint-pulse/issues/5)) the calendar, and the forecast proper
([#6](https://github.com/dikology/sprint-pulse/issues/6)) the two rates and the Confidence
States. Caps and the explanation
([#7](https://github.com/dikology/sprint-pulse/issues/7)) made the reading say why: `Instrument`
now carries a `ConfidenceReading` — the rule that matched plus the Caps that fired — and the
panel renders its one line from that rather than from a guess. Sprint Baseline and Scope Delta
([#8](https://github.com/dikology/sprint-pulse/issues/8)) closed the attribution gap: the
Baseline enters and leaves the forecast as a value, and the panel shows whether a moved reading
is the Operator falling behind or the sprint changing shape. Explorable and legible
([#9](https://github.com/dikology/sprint-pulse/issues/9)) closed M0: the scenario picker's list
is pinned to the corpus by a test, the corpus is audited against the scenario list in
[#1](https://github.com/dikology/sprint-pulse/issues/1), and the panel carries the accessibility
and no-motion properties above. What remains of the milestone is the one test that cannot be
automated: transcribe a real, remembered sprint into a fixture and check whether the reported
Confidence State matches what that sprint actually felt like.

Milestone **M1** — live reads — opens with Credential and identity
([#10](https://github.com/dikology/sprint-pulse/issues/10)). The Operator configures a Jira
Data Center base URL and authenticates with a Personal Access Token — Bearer only, no Basic,
no OAuth, no Cloud. The token's only resting place is a single macOS Keychain item: never
preferences, never a cache, never a log, and no error message quotes it. Identity resolves
once at setup from `/rest/api/2/myself` — both `key` and `name`, so a username change cannot
empty the forecast — and the app confirms who it thinks the Operator is before anything is
stored; a failed setup stores nothing, because the app refuses a live request rather than
falling back to any other credential source. The failure states are distinguished, not
collapsed: unreachable host, TLS rejection, rejected token, 404 on the configured path, and
a malformed response each say which one they were. The credential can be removed from the
panel, which returns the app to its fixture default.

## Licence

MIT. See [`LICENSE`](./LICENSE).

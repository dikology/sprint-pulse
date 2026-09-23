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
swift test          # the domain, the gateway, and the app's seams — no network, no Jira
swift run SprintPulse   # the menu-bar app
```

With no credential, or a credential with no Board yet, the panel reads the fixture corpus:
a scenario picker at the top lists every state the instrument can reach, each read at the moment
that scenario pins for itself, so everything below is explorable by clicking before anything is
authenticated. Configure a base URL, a Personal Access Token, and one Board and the panel reads
that Board's live sprint instead — the same gateway protocol, the same forecast, no scenario
picker until the credential goes away (#15 adds the switch back). When the Board cannot be reached
the panel keeps showing the last read that got through, labelled as cached and dated (#12).

The reading shows Points per Flow State for the Active Sprint's My Work: Actionable and Waiting as
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

The live gateway ([#11](https://github.com/dikology/sprint-pulse/issues/11)) is the second
M1 ticket, and the one the milestone was scoped around: a `JiraGateway` reading the active
sprints on one Board and that sprint's Issues over `/rest/agile/1.0/`, behind the same protocol
the fixtures already satisfy. The forecast did not change by a line. The bound holds — three
read operations in total, direct HTTP with no subprocess, and the recorded-request tests fail on
a fourth; listings are paged to their own `total`, because a slice of a sprint is not a smaller
truth. A Board with two active sprints asks the Operator which one is tracked and remembers the
answer for the life of that sprint; the app never guesses. A read happens on window open, on
Refresh, and when the Operator names the Board to read — there is no timer anywhere in the app,
and no request at launch. A failed fetch leaves the last reading standing and says which condition
it met, and a resolved identity that matches no Issue at all is shown as **No Work Assigned**
rather than as `Finished`. Two more things are configured once and remembered: the Board, typed
by id because listing boards would be a fourth read, and the custom field carrying Estimates,
which is per installation and decides whether any Points are found at all.

The cache ([#12](https://github.com/dikology/sprint-pulse/issues/12)) is what makes an
unreachable Board an ordinary evening rather than an error screen. The last read that got through
is persisted beside the instant its data was taken, and the panel opens on it: the caption says
which of the two is on screen — `Live — Board 172, as …` or `Cached — Board 172, as …` — and the
age is spelled out under it, as a date and a time rather than a countdown, because nothing in this
app re-times a sentence once it has been printed. How old the data is stays the domain's judgement:
`readAt` enters `Forecast.evaluate`, which asks the `WorkingCalendar` whether the data predates the
current Working Day, and that answer is rule 1's second trigger — the one the glossary has named
since #6 and nothing could reach until there was a cache to go stale. When it fires, Confidence
withdraws to `Unknown` with an Explanation of its own while the Points, the Flow-State partition,
and the Scope Delta all stay on the panel: a stale burn rate is worse than none, stale Points are
still informative. A read that failed overwrites nothing — the cache is written only past the point
where both envelopes have decoded and the tracked sprint is resolved, so a truncated response leaves
the good entry standing, and `CachedSprint` is the app's own JSON with no field a credential could
be parked in. Two corpus scenarios carry the pair — same Board, same Issues, same observed moment,
one `read-at.json` apart — so the withdrawn reading is reachable by clicking it.

## Licence

MIT. See [`LICENSE`](./LICENSE).

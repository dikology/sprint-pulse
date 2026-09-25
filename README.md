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
| `fixtures/` | Captured from a live instance and anonymised, but deliberately *not* corpus scenarios: nothing in M0 or M1 reads it, and it is not a state to click. The raw form lives in `captures/`, which is gitignored. |
| `scripts/` | The one command that cannot be a test — re-capturing the live transition graph behind `fixtures/`. |
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
that Board's live sprint instead — the same gateway protocol, the same forecast. When the Board
cannot be reached the panel keeps showing the last read that got through, labelled as cached and
dated (#12).

The two are switchable, and the switch is one click in each direction with the credential left in
place (#15): "Read fixtures instead" from a live Board, "Read Board N" from the picker. Fixture
mode is still what a fresh install does — nobody has to ask for it — and asking for it is
remembered across launches, because the thing it is for is catching a bug that only shows on
certain data, and that survives quitting the app. Whichever way the reading came, the corpus and
the Board are the same program: every bundled scenario is served to the live client as the bytes it
was written from and the two readings are compared field for field, so the whole M0 corpus is
re-verified against the live path on every test run rather than only against itself.

The reading shows Points per Flow State for the Active Sprint's My Work: Actionable and Waiting as
separate totals, Completed and Dropped as their own figures, a count of Unestimated Issues,
and any Unmapped Status named prominently. Above them sit Working Days Remaining and Elapsed,
the Required Rate, the Demonstrated Rate, and the Confidence State with the one-line explanation
of it — the rule that matched, plus any Cap that demoted the reading, spelled out from the
numbers underneath. Below them, the sprint's shape: the Team Scope total — every Issue in the
sprint, dim and secondary, with no forecast ever attached to it — the Points recorded the first
time the sprint was observed, dated with the moment that observation happened (#14), and the Scope
Delta between them — added scope and removed work read as different words, not just different
signs. The Status Map is the Operator's own
([ADR-0002](./docs/adr/0002-flow-states-independent-of-jira.md)): every row is a menu over the six
Flow States, a status can be added or taken out, and the edit is persisted — an `Unmapped Status`
arrives with a menu beside it and mapping it recomputes the reading on the spot (#13). Nothing on
the panel animates or loops, and nothing conveys meaning by image or colour alone: every figure is
spelled out for a screen reader.

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

The Status Map editor ([#13](https://github.com/dikology/sprint-pulse/issues/13)) is what turns an
`Unmapped Status` from a fact the panel reports into a condition the Operator can resolve. The map
ships as the same seven rows from `docs/agents/product.md` and every change after that is the
Operator's own — a status added, re-mapped, or taken out — persisted in the preferences beside the
rest of the Jira configuration and read back at launch, so a column is discovered once rather than
every evening. The read-only disclosure became menus: each row offers all six Flow States plus
"Not mapped", which is how any status reaches any state, `Dropped` included. That mapping stays the
Operator's to make and the accounting stays the model's — shed Points leave the remaining total and
never arrive as Completed — and the warning a real workflow produces now arrives with the menu
beside it. A pick is written through and re-judged in the same breath: `PanelModel` keeps the inputs
of the read that produced what is on screen and runs them through `Forecast.evaluate` again, so
mapping a status restores the forecast on the click rather than at the next Refresh. Deliberately no
request: an edit changes what the app knows about a workflow, not what the Board is asked about
(#2's rule that a live read happens only on the Operator's initiative), and off the VPN the cached
read is the thing that gets re-judged. What an edit cannot do either way is change the age of the
data: a reading that was withdrawn because it predates the current Working Day stays withdrawn after
the map is fixed, and a reading that was fresh when it was taken stays an answer for the moment it
was taken — the moment a live read was judged at belongs to that read, and the next window open is
what re-takes the verdict. A better map is not a fresher read. Core gained two value-returning
operations and a `Codable` conformance, still performs no I/O, and the Confidence table is
untouched: #13 changed what the map can say, not what the forecast does with it.

The Baseline on a live sprint ([#14](https://github.com/dikology/sprint-pulse/issues/14)) is what
makes the Scope Delta a fact about the Operator's own Board rather than about the corpus. The
capture rule was #8's and did not move: the first time the app sees a sprint active, its Issues and
Estimates become that sprint's Baseline, and from then on the Baseline is fixed. What #14 added is
where that answer lives and what it is allowed to claim. The slot is filed by sprint id, because one
Board can report two active sprints and the Operator can name one, then the other, then the first
again — a single slot would make that sequence destructive, quietly restarting a sprint's Delta at
zero on a Board the app has watched grow for a week. A relaunch reads the Baseline the first session
captured, so scope added while the app was shut arrives as movement rather than as a sprint that
never changed, and a cached read of last week's sprint is measured against last week's Baseline
rather than whatever the current one happens to be. Core gained no store, no protocol, and no I/O:
`Forecast.evaluate` takes the Baseline as a value and returns an updated one exactly as before, and
the reading now carries the moment its Baseline was taken.

That last field is the ticket's honesty requirement, and the glossary has always carried the rule it
serves: a Sprint Baseline is the sprint's first *observation*, which may fall partway through the
sprint. Nothing here can tell whether the two coincide — Jira reports a start date, and the app may
have been pointed at the Board a week after it. So the row beside the Delta names the day and time
the app arrived, and the `0` under it means nothing has moved *since then*: the claim the instrument
can actually make, and the one `baseline-cold-start` lets the Operator click and check.

The mode switch ([#15](https://github.com/dikology/sprint-pulse/issues/15)) closes M1, and it is
deliberately small: one control each way, "Read fixtures instead" beside Refresh and "Read Board N"
beside the picker, with the credential never touched. The ask is stored beside the rest of the
connection, so an excursion taken to catch a bug survives quitting the app and does not put the
Operator back on the live Board before the bug has reappeared — and fixture mode is still what a
fresh install does, with nobody having to ask for it. Two older rules had to survive the new door
rather than be re-stated near it: an answer given to a fixture's prompt is still nobody's
configuration, however completely the credential is configured, and a corpus read reached over a
standing Board still writes neither the cache drawer nor the Baseline slot.

The corpus check is what the ticket was actually for. Every scenario in the corpus — all 29 — is
now served to the live client as the bytes it was written from, so the same Board envelope and the
same Issue listing travel the HTTP path, get paged and stitched and decoded by `JiraHTTPClient`,
and come out the other side as an `Instrument` compared field for field against the one the fixture
path produced from those same files. Every row agrees, and not one M0 test was edited to make it
so: that is the answer to the question #2 asked before any write was built on top of the boundary,
and it is checked on every run rather than asserted in a sentence. The comparison is checked for
having teeth, too — a second test points the live path alone at an Estimate field the corpus does
not keep its numbers in and requires the readings to part company, because two paths decoded
wrongly in the same way would agree happily.

The one thing that could not be a test is in `fixtures/m2-transition-graph.json`: the Operator's
real transition graph, captured from all 84 Issues of a live sprint while the VPN and the credential
were both to hand, anonymised, and read by nothing in this milestone. M2's confirmation rule is
derived from it — an Intent needs confirming exactly when no transition returns — and the capture is
already informative before that rule exists: `Done` offers one transition, `Reopen`, and it lands in
`Open` rather than back in `In Review` — so a move to `Done` has no single step back, which is what
M2's rule counts, and that Intent is confirmation-required. (Three steps through `Open` and
`In Progress` gets there; reachable is not the same as reversible.) The move into `In Progress` is
spelled `' In Progress'`, with a leading space, when `Open` and `In Review` offer it and without one
when `Need Info` and `On hold` do, which is the shape of the problem M2's resolution has to survive.
`scripts/capture-transition-graph.sh` re-runs the capture when the workflow moves.

## Licence

MIT. See [`LICENSE`](./LICENSE).

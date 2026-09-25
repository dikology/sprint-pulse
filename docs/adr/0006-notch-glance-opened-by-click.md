# A notch Glance, opened by click

Sprint Pulse moves off the menu bar and onto the notch: a collapsed **Glance** sits beside the
notch — or top-centre of a screen without one — and a click on it opens the **Panel**. The Glance
is drawn by Sprint Pulse's own window; ADR-0005 stands, and this is the "second thin view layer" its
Consequences anticipated rather than a Boring Notch host. `MenuBarExtra` is removed, not kept as a
fallback: two hosts would mean every Panel change is made twice.

The Panel opens on a **click, never a hover**, which departs from the notch-app convention. Invariant
14 says a live read is issued by the Operator when they open the Panel; a hover-expanded Panel
would turn a cursor crossing the top of the screen into a Jira read — polling by another name, on
a self-hosted instance usually behind a VPN. Keeping the read on the click keeps invariant 14 true
without a special case.

## Considered options

- **Hover to expand, read on hover.** The convention; rejected for the reason above.
- **Hover to expand, read only on click.** Keeps the invariant, but the Panel would open showing a
  reading the Operator had not asked to refresh, and "opening the Panel" would mean two different
  things depending on how it was opened.
- **Glance on notched screens, menu bar elsewhere.** Rejected for the doubled host.

## Consequences

- The Glance shows Points remaining and nothing else — no Confidence State, no rate — so it claims
  nothing that can go stale or be demoted, and invariant 10 binds the Panel rather than the Glance.
- Configuration (Jira connection, Board, Estimate field, Status Map, Fixture Mode and its scenario
  picker) moves to a Settings window, reached from the Glance's context menu or ⌘, in the Panel.
  The one exception is choosing a Flow State for an Unmapped Status, resolved in the Panel where
  it is seen (#13).
- The Panel opens instantly. Expansion is motion, and motion stays reserved for Confidence State
  changes in M3.
- A borderless window is not reachable the way a menu-bar item is, so the Glance must be a single
  accessibility element with a press action, verified with VoiceOver navigation.

# The Glance reads as hardware, and grows into the Panel

M1.5 put Sprint Pulse at the notch as a dark capsule *beside* it and a system-coloured Panel *below*
it: two objects that look like macOS UI sitting near the notch. This replaces that look with one black
shape that reads as part of the notch itself, the direction of notch apps such as Taby. It amends
ADR-0006 on placement and motion; ADR-0006's click-not-hover decision stands unchanged.

- **The Glance wraps the notch.** One black band, a little wider than the notch, flush with the top
  edge, with the Points figure in the right wing and the left wing empty — the Glance has one figure
  to show (invariant 10), and an empty wing says so. On a screen without a notch the same shape is
  drawn flush with the top edge at the menu bar's centre, as a notch would be.
- **The Panel grows out of the Glance.** The band stays and the Panel hangs from it as one
  silhouette; the band's figure withdraws while the Panel is open, so Points remaining is stated
  once (`CONTEXT.md`, Live Sprint Points: "One number is shown once, under one name").
- **Always black.** The Glance and Panel are notch-black with dark content whatever the system
  appearance; a light surface cannot read as hardware. Settings stays an ordinary window that
  follows the system.
- **Hidden in fullscreen**, where the notch already sits in black bars and the Operator has chosen
  to attend to something else. An auto-hidden menu bar does not hide it.

## Motion

ADR-0006 said the Panel opens instantly because "expansion is motion, and motion stays reserved for
Confidence State changes in M3". That reservation goes: M3's mascot is now ornament invariant to
every reading (`product.md`), so nothing was left for it to reserve motion for. What remains is
**structural motion** — the shape growing and shrinking, identical every time, carrying no
information. It is short (~200–250 ms) and instant under Reduce Motion. No motion in Sprint Pulse
depends on the reading.

The live read fires on the click, never on the animation's completion, so invariant 14 is untouched.
A hover may at most make the Glance say it can be clicked; it never reads and never opens the Panel.

## Considered options

- **Keep the Glance beside the notch, restyled black.** Cheaper, but a black object next to a black
  cutout reads as two objects, which is the look being left behind.
- **Wrap symmetrically, a figure in both wings.** Rejected: the Glance has one figure, and filling
  the second wing would mean inventing a second one.
- **Follow the system appearance.** Rejected: a light-mode Panel cannot read as the notch growing.
- **Draw the notch-less shape below the menu bar**, as M1.5 did to avoid covering anyone's UI.
  Rejected: a black tab floating under the menu bar is neither hardware nor system UI. The cost is
  accepted — a long app menu (Xcode, Office) can reach the centre of the menu bar and meet it.

## Consequences

- The Glance and Panel become one window that resizes, not two windows aligned to look like one.
- The Panel's content is designed for a forced dark scheme; `windowBackgroundColor` and the
  separator stroke go.
- The Glance remains one accessibility element with a press action (ADR-0006).

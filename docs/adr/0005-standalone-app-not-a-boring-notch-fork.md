# Ship standalone, do not fork Boring Notch

Sprint Pulse ships as a standalone macOS menu-bar app under MIT, not as a fork of or extension to
Boring Notch. This reverses the framing the project started from, so it is recorded here.

Boring Notch has no extension point. Its notch content switches between exactly two views
(`.home` / `.shelf`), and features are hardcoded `if Defaults[.showX]` branches inside
`NotchHomeView.swift`; the "Extension system" remains an unchecked item on its own roadmap, and
the only registration protocol in the codebase is scoped to media controllers. Adding Sprint
Pulse would mean editing core files against a `dev` branch hundreds of commits ahead of `main` —
a permanent merge burden, not a plug-in. It is also GPLv3, so a fork must ship as GPLv3 with full
source. Separately, it uses no Keychain and honours no reduced-motion setting, so two of Sprint
Pulse's requirements would have to be built there regardless.

## Consequences

All domain logic, the Jira gateway, and the cache live in a `SprintPulseCore` SPM package with
**zero UI dependencies** — it must compile without SwiftUI. This is the same seam that lets
fixtures and the live Jira client be indistinguishable to the domain. If an extension system ever
ships upstream, hosting Sprint Pulse becomes "write a second thin view layer" rather than "port
the app".

MIT is chosen now rather than GPLv3. The Operator is sole author and can relicense later if a
merge becomes real; adopting copyleft today would pay a cost now to preserve an option on a fork
just decided against.

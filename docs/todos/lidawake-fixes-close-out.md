# lidawake-fixes review close-out

Theoretical leftovers from the lidawake-fixes reviews that have no index line of their own. Verbatim from docs/reviews/lidawake-fixes/round3.md.

- [conf:0.5] Sources/LidAwakeCore/Uninstaller.swift:43 — with sudo revoked while keep-awake is on, `stopSleep` fails and aborts before the admin restore script runs. Same family as the filed Uninstaller:43 P2; this variant isn't spelled out there. Pathological.
- [conf:0.4] Sources/LidAwakeCore/LoginItems.swift:30 — rollback `setEnabled(true)` deletes every login item named "LidAwake"; pre-existing behavior the new uninstall rollback now exercises. Edge case.

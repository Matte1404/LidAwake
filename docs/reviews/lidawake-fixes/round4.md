# codex challenge — range feb1c0b5ed4cf4eafc115790486de0cc9e87209a..fc93fc6142fe1695005c42f8f5184dd31dd8fa44 — checkout /Users/turbokach/Dev/LidAwake — model gpt-6.1-sol/medium — exit 0 — 139s
Sources/LidAwakeCore/Uninstaller.swift:43 — Stopping the worker releases the session lock before authorization; launch another instance during the admin prompt and it can disable sleep between restoration verification and rule removal, after which uninstall deletes its recovery journal and restoration permissions.
Sources/LidAwakeCore/SleepControl.swift:130 — If another process changes `SleepDisabled` from 1 to 0 between the session and probe reads, then the probe writes 1 and fails restoring 0, `releaseClaim()` clears the journal based on the stale initial 1, leaving sleep disabled without recovery ownership.
Sources/LidAwakeCore/SleepWorker.swift:132 — After a transport failure closes the connection, `stop()` accepts worker exit without checking its status; failed EOF restoration followed by another Quit silently exits while sleep remains disabled.
Sources/LidAwakeCore/Uninstaller.swift:43 — Revoke sudo permission while keep-awake is active, then uninstall: worker restoration fails and aborts uninstall before the administrator-authorized script that could restore sleep runs.
Sources/LidAwakeCore/SleepControl.swift:54 — Start with `SleepDisabled=1` and a sudo policy permitting 1 but denying 0: acquisition succeeds without proving restoration permission, so disabling keep-awake and quitting cannot restore sleep.
LidAwake.swift:56 — Delay worker exit beyond the five-second uninstall shutdown deadline: replacement startup fails against its lock, the error is swallowed, and the controller remains attached to a permanently closed client after the old worker exits.
Sources/LidAwakeCore/Uninstaller.swift:60 — Make support-directory deletion fail after rule removal: uninstall leaves the app open with its worker stopped, and Repair Sleep Setup cannot resume control until relaunch.
Sources/LidAwakeCore/Uninstaller.swift:57 — Deny traversal of the support directory’s parent after worker startup: the metadata error is treated as absence, so uninstall reports success and trashes the app while leaving its data behind.
Sources/LidAwakeCore/LoginItems.swift:30 — Cancel uninstall’s admin prompt with Launch at Login enabled and another LidAwake copy registered: rollback deletes every login item named “LidAwake” before recreating this copy’s entry, silently removing the other registrations while reporting nothing was removed.
## Triage verdict (round 4, feb1c0b..fc93fc6)

1 real (P2), 1 theoretical, 0 blocking. 9 codex findings: 1 new, 8 already filed (docs/tech-debt.md, docs/todos/lidawake-fixes-close-out.md). `releaseClaim` is correct on every probe failure path except the race below: from a 0-start it keeps ownership unless a re-read confirms 0 (a failed re-read keeps); from a 1-start it clears the marker, so a relaunch can't write 0 over a setting LidAwake never owned; a failed journal save keeps ownership.

### real
<a id="finding-1"></a>1. [P2 conf:0.4] Sources/LidAwakeCore/SleepControl.swift:130 (releaseClaim) — `setAwake` reads `current` once, then `probeRule()` re-reads it. If another tool flips SleepDisabled 1→0 between the two reads, the probe takes the 0-start path: writes 1, then fails restoring 0; `releaseClaim(startedAwake: true)` then clears the journal, leaving sleep disabled with no recovery owner. Needs an external writer racing a few-ms window plus a rule that allows 1 and denies 0. Fix idea: have the probe report the state it actually started from. Owner decision 2026-10-06: defer.

### theoretical
- [conf:0.5] SleepControl.swift:54 — one-sided rule when SleepDisabled is already 1. Filed, accepted by owner.

Already filed, not new: Uninstaller.swift:43 (second instance during admin prompt; sudo revoked while keep-awake is on), SleepWorker.swift:132, LidAwake.swift:56, Uninstaller.swift:57 and :60, LoginItems.swift:30.

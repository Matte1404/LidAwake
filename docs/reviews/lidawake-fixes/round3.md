# codex challenge — range feb1c0b5ed4cf4eafc115790486de0cc9e87209a..263c99c323ad8e2c9f64c98a8b49e29e70211f45 — checkout /Users/turbokach/Dev/LidAwake — model gpt-6.1-sol/medium — exit 0 — 153s
Sources/LidAwakeCore/SleepControl.swift:55 — The probe disables sleep before `SleepSession` records recovery ownership; kill the worker between the `1` and `0` writes, or make restoration fail, and sleep remains disabled without a recovery marker.

Sources/LidAwakeCore/Uninstaller.swift:43 — Stopping the worker releases the session lock before authorization; launch another instance during the admin prompt and its writes can race restoration, leaving sleep disabled after uninstall deletes its journal and sudo permissions.

Sources/LidAwakeCore/Uninstaller.swift:43 — Revoke sudo permission while keep-awake is active, then uninstall: worker shutdown fails and aborts before the administrator-authorized restoration script can repair the setting.

Sources/LidAwakeCore/SleepControl.swift:54 — With `SleepDisabled=1`, a sudo policy allowing `1` but denying `0` passes acquisition; turning keep-awake off or quitting then cannot restore sleep.

Sources/LidAwakeCore/SleepWorker.swift:137 — After a transport failure disconnects the worker, `stop()` accepts its exit without checking exit status; failed EOF recovery therefore lets Quit succeed silently while sleep remains disabled.

LidAwake.swift:56 — Delay worker exit beyond the five-second shutdown deadline during uninstall: replacement startup fails against its lock and that failure is swallowed, leaving the controller attached to a permanently closed client after the old worker exits.

Sources/LidAwakeCore/Uninstaller.swift:60 — Make support-directory deletion fail after rule removal: uninstall leaves the app open with its worker permanently stopped; even Repair Sleep Setup cannot resume sleep control until relaunch.

Sources/LidAwakeCore/Uninstaller.swift:57 — Deny traversal of the support directory’s parent after worker startup: the failed metadata lookup is treated as absence, so uninstall reports success and trashes the app while leaving its data behind.

Sources/LidAwakeCore/LoginItems.swift:30 — Cancel uninstall’s admin prompt with Launch at Login initially enabled: rollback deletes every login item named “LidAwake” before recreating this bundle’s entry, silently removing entries for other copies despite reporting that nothing was removed.
## Triage verdict (round 3, feb1c0b..263c99c)

0 P0, 0 P1, 3 real (P2, new), 0 regression, 0 test-gap, 6 theoretical (already filed). Nothing blocks the push. The round-2 fixes (34e807e uninstall gate, 263c99c two-direction probe) are correct.

### real
<a id="finding-1"></a>1. [P2 conf:0.6] Sources/LidAwakeCore/SleepControl.swift:55 — new in 263c99c. On a 0-start the probe writes 1 then 0 inside `requireAutomaticControl`, before `SleepSession` commits its journal; a kill or failed restore between the writes leaves SleepDisabled=1 with no recovery marker. Same mechanism as the round-1 probe/journal race (conf 0.35). Owner: fix now.
<a id="finding-2"></a>2. [P2 conf:0.5] Sources/LidAwakeCore/Uninstaller.swift:60 — support-dir `removeItem` fails after the rules are already removed: returns `.incomplete`, but the worker stays stopped and `resumeSleep` isn't called on this path, so the app is unusable until relaunch. Owner: defer.
<a id="finding-3"></a>3. [P2 conf:0.4] Sources/LidAwakeCore/Uninstaller.swift:57 — `try? attributesOfItem` treats any error (e.g. permission-denied parent) as "absent"; uninstall reports success and leaves data behind. Owner: defer.

### theoretical
- [conf:0.5] Uninstaller.swift:43 — session lock released during the admin prompt; a second instance can race cleanup. Filed (tech-debt P2).
- [conf:0.5] Uninstaller.swift:43 — with sudo revoked while keep-awake is on, `stopSleep` fails and aborts before the admin restore script runs. Same family as the filed Uninstaller:43 item; this variant isn't spelled out there. Pathological.
- [conf:0.5] SleepWorker.swift:137 — `stop()` after disconnect doesn't check worker exit status. Filed.
- [conf:0.5] LidAwake.swift:56 — swallowed `resumeSleep` failure after stop timeout leaves the controller bound to a closed worker. Filed.
- [conf:0.4] LoginItems.swift:30 — rollback `setEnabled(true)` deletes every login item named "LidAwake"; not in the diff, pre-existing behavior the new uninstall rollback now exercises. Edge case.
- [conf:0.5] SleepControl.swift:54 — one-sided sudo rule when SleepDisabled is already 1. Owner decision 2026-10-06: accept the gap, keep filed.

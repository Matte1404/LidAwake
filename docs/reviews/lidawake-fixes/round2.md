# codex challenge — range feb1c0b5ed4cf4eafc115790486de0cc9e87209a..21144f10294c2f60ec206b3fd309ef107f4fd4f0 — checkout /Users/turbokach/Dev/LidAwake — model gpt-6-astra/medium — exit 0 — 87s
Sources/LidAwakeCore/Uninstaller.swift:43 — Stopping the worker releases the global session lock before the admin prompt; launching another instance during that prompt lets cleanup race its writes, remove its recovery journal, and revoke restoration permissions while sleep remains disabled.

Sources/LidAwakeCore/SleepControl.swift:47 — With `SleepDisabled=1`, the probe checks only permission to write `1`; a sudo policy denying `0` passes acquisition, but disabling keep-awake and quitting cannot restore sleep.

Sources/LidAwakeCore/Uninstaller.swift:43 — Revoke sudo permission while keep-awake is active, then uninstall: `stopSleep()` fails and aborts before the administrator-authorized restoration script can run, leaving sleep disabled and uninstall blocked.

LidAwake.swift:56 — If shutdown exceeds its five-second exit deadline, the replacement worker fails against the old worker’s lock; that failure is swallowed, leaving the controller attached to a closed worker even after it exits, so sleep control requires restarting the app.

LidAwake.swift:278 — Controls become enabled before asynchronous recycling finishes because they ignore `gate.uninstalling`; during slow recycling, Launch at Login or Sleep Setup can recreate items already removed, after which uninstall still trashes the app and quits.

Sources/LidAwakeCore/SleepWorker.swift:131 — After a transport timeout closes the connection, retrying `stop()` treats worker exit as successful restoration without checking its exit status; if EOF recovery failed, Quit silently succeeds while sleep remains disabled.
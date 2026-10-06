# Tech debt index

One line per item, context in the linked file. Product ideas live in `TODO.md`.

## Gates (P1)

## P2
- **[P2 conf:0.5] LidAwake.swift:56** — `resumeSleep` failure after a stop timeout is swallowed; the controller stays bound to the old, closed worker until relaunch → docs/reviews/lidawake-fixes/round2.md
- **[P2 conf:0.5] Sources/LidAwakeCore/SleepWorker.swift:131** — a retried `stop()` after a transport failure waits for the exit but doesn't check whether the worker actually restored sleep → docs/reviews/lidawake-fixes/round2.md
- **[P2 conf:0.45] Sources/LidAwakeCore/Uninstaller.swift:43** — a second app instance during the admin prompt, or external sudoers tampering before `rules.uninstall()`, can leave sleep off → docs/reviews/lidawake-fixes/round2.md
- **[P2 conf:0.5] Sources/LidAwakeCore/Uninstaller.swift:60** — support-dir removal fails after the rules are removed: `.incomplete`, but the worker stays stopped until relaunch → docs/reviews/lidawake-fixes/round3.md #finding-2
- **[P2 conf:0.4] Sources/LidAwakeCore/Uninstaller.swift:57** — `try? attributesOfItem` treats any error as "absent"; uninstall reports success and leaves data behind → docs/reviews/lidawake-fixes/round3.md #finding-3

## Unprioritized
- **[conf:0.5] Sources/LidAwakeCore/SleepControl.swift:47** — when SleepDisabled is already 1 and not owned, `probeRule()` proves only `disablesleep 1`; a rule denying `0` still passes → docs/todos/probe-one-sided-rule-when-already-awake.md
- **[conf:0.35] Sources/LidAwakeCore/SleepControl.swift:47** — `probeRule()` writes the value back before `SleepSession` commits its journal (narrow external-writer race) → docs/reviews/lidawake-fixes/round1.md
- **lidawake-fixes review close-out** — 2 theoretical leftovers (uninstall abort variant, login-item rollback) → docs/todos/lidawake-fixes-close-out.md

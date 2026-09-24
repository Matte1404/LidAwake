# Tech debt index

One line per item, context in the linked file. Product ideas live in `TODO.md`.

## Gates (P1)
- **[P1 conf:0.5] LidAwake.swift:278** — `controlsEnabled` ignores the uninstall-in-progress gate; menu items re-enable between `perform()` finishing and the uninstall completion — **BLOCKS lidawake-fixes push** → docs/reviews/lidawake-fixes/round2.md
- **[P1 conf:0.4] Sources/LidAwakeCore/SleepControl.swift:47** — `probeRule()` proves only the current value; an asymmetric sudoers rule passes the probe, then blocks enable or restore — **BLOCKS lidawake-fixes push** → docs/reviews/lidawake-fixes/round2.md

## P2
- **[P2 conf:0.5] LidAwake.swift:56** — `resumeSleep` failure after a stop timeout is swallowed; the controller stays bound to the old, closed worker until relaunch → docs/reviews/lidawake-fixes/round2.md
- **[P2 conf:0.5] Sources/LidAwakeCore/SleepWorker.swift:131** — a retried `stop()` after a transport failure waits for the exit but doesn't check whether the worker actually restored sleep → docs/reviews/lidawake-fixes/round2.md
- **[P2 conf:0.45] Sources/LidAwakeCore/Uninstaller.swift:43** — a second app instance during the admin prompt, or external sudoers tampering before `rules.uninstall()`, can leave sleep off → docs/reviews/lidawake-fixes/round2.md

## Unprioritized
- **[conf:0.35] Sources/LidAwakeCore/SleepControl.swift:47** — `probeRule()` writes the value back before `SleepSession` commits its journal (narrow external-writer race) → docs/reviews/lidawake-fixes/round1.md

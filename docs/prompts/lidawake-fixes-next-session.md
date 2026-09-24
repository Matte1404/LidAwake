# Handoff: LidAwake direct-build fixes follow-up

Repo: /Users/turbokach/Dev/LidAwake, public repo `origin` = github.com/TurboKach/LidAwake. The branch is `lidawake-fixes`, based on local `main` at feb1c0b (the parked leases-plan commit, also unpushed). Everything is local and nothing is pushed. Pushing needs the owner's explicit approval.

## Context
The Mac App Store app shipped separately as **Clamstay**: private repo TurboKach/Clamstay, local remote `clamstay`, branch `feature/mac-app-store`. LidAwake keeps its name. The only changes it gets are three direct-build behaviors ported from Clamstay, with no store code:
- 4275855: probe fix, a no-op write of the current value instead of `sudo -l`.
- 3cba18d: `SleepWorkerClient.stop()` waits up to 5 s for the worker to exit.
- d6fd7b7: "Uninstall LidAwake…".
- 21144f1: round 1 review fixes. A `TerminationGate` defers Quit during an uninstall, and `stop()` always runs its bounded wait.

Tests at 21144f1: `swift test` 66 executed, 0 failed, 0 skipped. `scripts/test-recovery.sh` passes all 4 modes.

## Goal of this session (one-shot, with a codex review of the diff)
Fix the two P1s that `docs/tech-debt.md` lists as **BLOCKS lidawake-fixes push** (context in `docs/reviews/lidawake-fixes/round2.md`):
1. `LidAwake.swift:278`: `controlsEnabled` must also respect the uninstall-in-progress gate. The invariant is that no menu action becomes available between the end of `perform()` and the uninstall completion.
2. `Sources/LidAwakeCore/SleepControl.swift:47`: `probeRule()` must prove both directions of the rule without changing the setting. For example, write the current value and then the opposite value, then restore, with a restore-on-failure step. Or reject rules that don't match LidAwake's own exact rule. The fixer chooses, and states the choice and why.

Write each test red first, then make it pass. Afterwards run `codex-challenge.sh feb1c0b..HEAD`, triage the result, and bring the P2s to the owner with a fix-or-defer question.

## Owner manual test before any push
Build with `./build.sh --no-install`, copy the app to a scratch folder and run the copy:
- Uninstall LidAwake… → Uninstall → at the admin prompt press **Quit** in the menu, then **Cancel** the prompt. Expect "Uninstall was canceled. Nothing was removed.", then the app quits.
- Optionally, run a full uninstall on the scratch copy. It removes the real sudoers rule; reinstall afterwards with Enable Automatic Sleep Control….

## Traps
- The owner's installed `/Applications/LidAwake.app` sets SleepDisabled back to 1 about 1.5 s after any outside change.
- The dev build and the installed app share the name "LidAwake", so kill processes by pid.
- Never enter a password at a SecurityAgent prompt.
- `screencapture` fails in this environment.
- SourceKit diagnostics are stale; trust `swift test`.

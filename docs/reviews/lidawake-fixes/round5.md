# codex challenge — range feb1c0b5ed4cf4eafc115790486de0cc9e87209a..0a8fa7e42eb10df71087286524769244ad099935 — checkout /Users/turbokach/Dev/LidAwake — model gpt-6.1-sol/medium — exit 0 — 118s
Sources/LidAwakeCore/Uninstaller.swift:43 — Stopping the worker releases the session lock before authorization; launch another instance during the admin prompt and it can disable sleep between restoration verification and rule removal, after which uninstall deletes its recovery journal and restoration permissions.

Sources/LidAwakeCore/SleepWorker.swift:132 — After a transport failure closes the connection, `stop()` accepts worker exit without checking its status; failed EOF recovery followed by another Quit silently exits while sleep remains disabled.

Sources/LidAwakeCore/SleepControl.swift:130 — If an external writer changes SleepDisabled from 1 to 0 between the session and probe reads, and the probe’s final restore fails after successfully writing 0 then 1, `releaseClaim()` clears the journal using the stale initial 1, leaving sleep disabled without recovery ownership.

Sources/LidAwakeCore/SleepControl.swift:119 — Change SleepDisabled from 1 to 0 between the session and probe reads; a successful probe finishes at 0, but the stale `current == true` skips the final enable, reporting success and potentially allowing lid-close sleep before the next reconciliation.

Sources/LidAwakeCore/SleepControl.swift:54 — Starting with SleepDisabled=1 tests only permission to write 1; a sudoers override denying 0 passes acquisition, but turning keep-awake off or quitting cannot restore sleep.

Sources/LidAwakeCore/Uninstaller.swift:43 — Revoke sudo permission while keep-awake is active, then uninstall; worker restoration fails and aborts uninstall before its administrator-authorized restoration script can repair the setting.

LidAwake.swift:56 — Delay worker exit beyond the five-second uninstall shutdown deadline; replacement startup fails against the old worker’s lock, its error is swallowed, and the controller remains attached to a permanently closed client after the worker exits.

LidAwake.swift:168 — Choose “Stay Open” after Quit times out waiting for worker exit; shutdown has already closed the client, so reconciliation and Repair Sleep Setup cannot resume sleep control even after the worker exits.

Sources/LidAwakeCore/Uninstaller.swift:60 — Make support-directory deletion fail after rule removal; uninstall returns an error with the worker stopped and never resumes it, leaving sleep control unusable even after Repair Sleep Setup until relaunch.

Sources/LidAwakeCore/Uninstaller.swift:57 — Deny traversal of the support directory’s parent after worker startup; the metadata error is treated as absence, so uninstall reports success and trashes the app while leaving its data behind.

Sources/LidAwakeCore/LoginItems.swift:30 — Cancel uninstall’s admin prompt with Launch at Login enabled and another LidAwake copy registered; rollback deletes every login item named “LidAwake” before recreating this copy’s entry, silently removing the other registrations while reporting nothing was removed.
## Triage verdict (round 5, feb1c0b..0a8fa7e)

0 P0/P1, 2 real P2 (variants of filed items), 0 regression, 0 test-gap, 9 theoretical (already filed). No push blocker. 0a8fa7e (post-uninstall quit deadlock, found in the owner's manual test) checked by reading: no deadlock path remains (deferred quit → `reply(true)`; failure/cancel → `restoreSleepThenReply`, never `terminate`; "Stay Open" then Quit starts a fresh `.start` outside a main-queue block), `uninstalled` can't leak into a normal quit (set only by `endUninstall(succeeded: true)`, reset on failure), and no other terminate/reply waits on a nested main-queue block.

### real
<a id="finding-1"></a>1. [P2 conf:0.4] Sources/LidAwakeCore/SleepControl.swift:119 — an external 1→0 flip between the session read and the probe read leaves `current` stale at true, so the final enable is skipped and sleep stays enabled. Same stale-read mechanism as round4 #finding-1 (:130), different consequence. Folded into that tech-debt line.
<a id="finding-2"></a>2. [P2 conf:0.4] LidAwake.swift:168 — "Stay Open" after a Quit that timed out waiting for the worker exit leaves the client closed, so reconcile and Repair can't resume. Same mechanism as the round2 LidAwake.swift:56 item (controller bound to a closed worker). Folded into that tech-debt line.

### theoretical
Already filed: Uninstaller.swift:43 (second instance during the admin prompt; sudo revoked while keep-awake is on), SleepWorker.swift:132, SleepControl.swift:54 (owner-accepted), Uninstaller.swift:57 and :60 (owner-deferred), LoginItems.swift:30.

<!-- /autoplan restore point: /Users/turbokach/.gstack/projects/TurboKach-LidAwake/main-autoplan-restore-20260527-165654.md -->
# Keep-Awake Leases — plan

> **Safety correction (2026-09-14; takes precedence over the historical review below).**
> A live interactive process does not prove that a turn is still active. Every lease,
> including a verified lease, must have a finite expiry. Start with a **6-hour maximum
> hold**, show the expiry in the menu, and allow explicit renewal. PID checks may end a
> lease early; they must never extend its expiry. Interrupted or failed turns without a
> release can therefore delay sleep until expiry, but cannot strand the Mac indefinitely.
> Work longer than the maximum hold requires explicit renewal; do not promise unlimited
> runtime. A future integration may renew from a documented, verified work signal, never
> from PID liveness alone. Immediate cleanup on interrupt remains a validation gate.
>
> The app now uses a pipe-connected sleep worker: it is the sole `pmset` writer, restores
> its owned override on GUI exit/EOF, and journals recovery before enabling it. Leases
> must use that existing control path. If both processes die or permission is revoked,
> the next launch retries the journaled restoration; shutdown is not inherently safe
> just because no coordinator is running. Automatic setup is required before enabling
> keep-awake. The lease feature itself is still a plan, not a shipped integration.

> **Reviewed by /autoplan (2026-05-27).** CEO + Eng + DX phases, dual voices (Codex gpt-5.5 +
> independent Claude subagents) + a Claude Code hooks fact-check. Decisions and the audit
> trail are at the bottom. The three forced open questions are resolved inline and flagged
> **[DECISION]**.

## Goal / user story

> I run coding CLIs (Claude Code today; codex/aider/etc. later) in a few terminal tabs,
> close the lid, and walk away. While any of them is **actively working**, the Mac stays
> awake. When the **last** one finishes and everything is idle, the Mac is allowed to
> sleep again — so it isn't burning power with the lid closed and no work happening.

LidAwake already keeps the Mac awake on lid close via the global `pmset disablesleep`
parameter, with a per-power-source policy. This feature adds **temporary, auto-expiring
"keep awake" leases** layered on top of that policy.

## Why leases (and why one coordinator)

- Lid-close sleep is governed by `pmset disablesleep` — a single **global boolean**, not a
  ref-counted assertion stack. `caffeinate` does **not** affect it (only idle sleep).
- Therefore "stay awake while ≥1 job is working" needs a coordinator that ref-counts who
  wants to be awake and flips the global boolean only on 0↔1 transitions.
- **LidAwake is the single owner/writer** of `disablesleep` (it already holds the scoped
  passwordless sudoers rule). No other tool ever writes the param — they only acquire/
  release leases. This avoids races and a second writer.

### Lease lifecycle model (the core mental model — read this first)

A lease is **held until release or finite expiry**: created on `UserPromptSubmit`
(work started), deleted on `Stop`/`SessionEnd` (work done, idle at the prompt), or expired
at its explicit `expiresAt` deadline. The default maximum hold is **6 hours**, for both
verified and unverified owners. A 40-minute turn is covered without a mid-turn hook.
Longer work must explicitly renew before expiry; show the deadline and a renewal action.

PID identity is an early crash backstop. Expiry is the backstop when the owner remains
alive after interruption, an API failure, or a lost release event. Neither a timer nor a
live PID may refresh a lease automatically. Renewal must represent actual work or an
explicit user action. Clean release remains the primary "work finished" signal.

> Note: the interactive `claude` process stays alive at the prompt *between* turns, so PID
> liveness alone cannot mean "still working" — only the `Stop` hook tells us a turn finished.
> PID liveness answers a different question: "did the owner die without releasing?"

## Reconciliation — runs every tick, regardless of lid state

```
keepAwake = policyForCurrentSource (awakeOnAC / awakeOnBattery)  ||  activeLeaseCount > 0
```

Today `applyForCurrentSource` is called only at launch and on power-source change, and
`lidTick` (LidAwake.swift:51) returns early when the lid is open. **Leases require
`disablesleep` to be re-evaluated on every 2s tick, independent of lid state.** Split the
tick into two concerns:

```
func tick() {
    reconcileSleepPolicy()   // ALWAYS runs — computes keepAwake, writes disablesleep on change
    manageDisplay()          // the existing lidClosed()-gated display-sleep logic (unchanged)
}
```

- **Why "regardless of lid state" is mandatory:** if reconciliation stays gated behind
  `lidClosed()`, a lease released while the lid is *open* drops the count to 0 but leaves
  `disablesleep 1` set forever → the Mac is stranded awake. That is the exact safety
  violation this feature must never cause.
- `reconcileSleepPolicy()` mirrors the existing `liveAwake() != desired` write guard
  (LidAwake.swift:104) so it only shells out to `sudo pmset` on an actual transition, not
  every 2s. Track intended state in memory; don't fork `pmset -g` every tick just to decide.
- Keep the `auto && !hasPasswordlessSetup` guard: reconciliation must **never** trigger an
  admin password prompt from a timer. Without passwordless sudoers, leases silently no-op —
  so the wizard **requires** sudoers setup (see wizard prerequisites).
- **0-transition race guard:** before writing `disablesleep 0` on last release, take the
  lease lock, **re-scan** the directory one final time, and only clear if still zero. Add a
  short debounce (one extra tick) so an acquire landing microseconds after a release isn't
  lost. Without this, a last-release scan can see zero, a new acquire writes its file, and
  the coordinator still clears the flag → sleeps during fresh work.

[DECISION Q2 — see decisions section] On last release with the lid closed: **just set
`disablesleep 0` and let macOS sleep naturally.** Do **not** call `pmset sleepnow`. With the
lid already shut, clearing the flag triggers clamshell sleep within seconds on its own, and
`sleepnow` is **not** covered by the scoped sudoers rule (LidAwake.swift:142) — it would
force a password prompt from a background path. `sleepnow` stays in "Later."

## Coordinator must be running (new MVP requirement)

The CLI (`LidAwake lease …`) only writes/deletes lease files. The **GUI process is the only
thing that reconciles** `disablesleep`. If LidAwake is quit, crashed, or never launched,
hooks write lease files that nobody acts on → no new sleep override is applied. An earlier
owned override must still be restored by the sleep worker or its recovery journal. To make
the feature actually work:

- The Claude Code integration wizard **requires** (a) passwordless sudoers setup and
  (b) Launch at Login enabled, and refuses to install hooks until both are true.
- On launch, the coordinator reconciles immediately and reaps stale leases (don't wait for
  the first tick).
- The menu surfaces a visible error if prerequisites are missing (e.g. "⚠︎ needs admin
  setup" / "⚠︎ enable Launch at Login").

We keep "single writer = one LidAwake-owned GUI process." We reject Codex's alternative of
having the CLI self-reconcile when no coordinator is running — it duplicates the privileged
write path and breaks the single-writer invariant. Out of scope for v1.

## Lease store & format

- Directory: `~/.lidawake/leases/`, created `mkdir -p` mode **0700** by both the CLI and the
  coordinator (they may race to create it). Lease files mode **0600**. Do not follow symlinks.
- **Filename is `sha256(source + ":" + session_id)`**, not the raw `session_id`. The hook
  JSON is external input; never let it become a path component (path traversal / weird
  filenames). The `source`+`session_id` pair is stored inside the file for the UI.
- One file per lease. Contents (small JSON, parsed with `JSONDecoder`):
  - `key` — `source:session_id` (human-readable, for the status UI)
  - `source` — which tool created it (e.g. `claude-code`)
  - `pid` — resolved owning process (see reaping); `0`/absent if unresolved
  - `pidStartTime` — the owner's start time (epoch), for PID-identity validation
  - `pidName` — the owner's executable basename, a secondary identity check
  - `verified` — bool: was a confident owner PID resolved at acquire time?
  - `created` / `refreshed` — epoch timestamps of acquire or explicit renewal
  - `expiresAt` — bounded deadline, required for **every** lease
- **Atomic writes:** write to `leases/.tmp.<uuid>`, then `rename()` into place (atomic on
  APFS). Swift `Data.write(to:options:.atomic)` does this. The coordinator never sees a torn
  file.
- **Tolerant reads:** the coordinator ignores dotfiles/temp files; treats ENOENT (file
  deleted mid-scan) as "skip, not an error"; and treats a parse failure as "skip this tick,
  re-read next tick" — **never** as "reap." A file that fails to parse for several
  consecutive ticks is quarantined/deleted under the corruption rule.

## Reaping (must never strand the Mac awake)

Primary path is the **clean release** hook. PID liveness and staleness are **backstops** for
when release never fires.

A lease is removed when any of:

1. **Clean release** — `Stop` / `SessionEnd` deletes it. This is the normal path and the one
   that delivers "sleep when idle." (See Stop-semantics caveats under Claude integration.)
2. **Dead / re-used owner (verified leases)** — the coordinator validates **PID identity**,
   not just `kill -0`:
   - reap if the PID is gone, **or** if the PID now exists but its start-time / basename no
     longer match what was stored (PID was recycled to a different process).
   - bare `kill -0` is insufficient: a recycled PID would read as "alive" and retain a stale
     lease until expiry. Start-time comparison allows immediate cleanup.
   - resolve the owner at acquire time by walking `getppid()` from the hook process up the
     parent chain to the `claude` (or `node`-hosting-claude) process and storing
     `pid + pidStartTime + pidName`. **Must verify locally** which process/basename the chain
     actually reaches — this is the one empirically-unconfirmed mechanism (see Validation gate).
3. **Finite expiry (all leases)** — reap when `now >= expiresAt`, even if the verified
   owner is still alive. Use a default **6-hour maximum hold** and persist the deadline at
   acquire/explicit renewal. Show unverified owners and expiry in the menu. Persisted
   deadlines must be bounded on load; future/corrupt timestamps must not create unlimited
   holds. Use monotonic elapsed time during a running coordinator so moving the wall clock
   backward cannot prolong a lease indefinitely.
4. **Explicit release** — provide a menu/CLI action to release a stuck lease without having
   to close the coding terminal.

Do not equate a live PID with active work: an interrupted interactive session can sit at
its prompt indefinitely. Add a validated terminal-failure hook where supported; keep the
finite expiry even if that hook is available. A missing hook delays cleanup until expiry,
so the integration must state that limit instead of promising immediate sleep on every
interrupt. Renewal from future work hooks is allowed only after their semantics are
validated for long single calls, background work, and interruptions.

## Acquire / release mechanism — reuse the LidAwake binary (no extra deps)

Make the `LidAwake` binary **dual-mode**, dispatching on `CommandLine.arguments` **before any
AppKit symbol is touched**:

```swift
// must be the FIRST top-level code, before NSApplication/AppDelegate exist
let args = CommandLine.arguments
if args.count >= 2, args[1] == "lease" {
    exit(LeaseCLI.run(args))   // Foundation/Darwin only — no Cocoa, no NSApplication
}
let app = NSApplication.shared      // GUI path unchanged from here
let delegate = AppDelegate()
app.delegate = delegate
app.run()
```

- **Why this matters (critical):** today the bottom of LidAwake.swift (lines 266–269)
  unconditionally builds `NSApplication` and calls `app.run()` (which never returns). If a
  hook invoked that, it would: connect to the WindowServer, run `applicationDidFinishLaunching`
  (which can pop the sudoers `promptSetup()` alert mid-turn), install timers — and hang until
  Claude's 30s `UserPromptSubmit` timeout kills it, **blocking every turn for 30s**. The
  `statusItem` is a stored property of `AppDelegate` (line 10), so it only fires if
  `AppDelegate()` is constructed — keep that strictly inside the GUI branch.
- `LeaseCLI` imports only `Foundation` (+ `Darwin` for `sysctl`/`kill`). It: reads hook JSON
  from stdin, parses `session_id` (tolerating malformed input), resolves the owner PID, writes
  or removes the lease file, **always exits 0**, emits **nothing** on stdout (UserPromptSubmit
  stdout is injected into Claude's context) and nothing on stderr on success.
- **Malformed / missing `session_id`:** still `exit 0`. Fall back to a key derived from
  `cwd` + resolved PID so the lease still works rather than blocking the turn.
- The acquire path must be near-instant: parse, `mkdir -p`, atomic-write one small file, exit.
  No `pmset`, no `sudo`, no network — LidAwake remains the sole writer; the CLI just drops a file.

## Claude Code integration (v1) — via global hooks

Installed into `~/.claude/settings.json` (user-global; applies to all sessions; the file
watcher reloads hook changes live, no restart). Strict JSON (no comments / trailing commas).

- `UserPromptSubmit` → `acquire` (turn started). Default 30s timeout, **only exit 2 blocks**
  the turn (verified against current docs) — so keep it instant and always exit 0.
- `Stop` → `release` (turn finished). **Caveat:** `Stop` input can carry `background_tasks`,
  `session_crons`, and `stop_hook_active`. Release on `Stop` **only when no background work /
  scheduled wakeup remains**; otherwise keep the lease (the PID backstop still covers a later
  crash). `Stop` does **not** fire on user interrupt, and API errors surface as `StopFailure`,
  not `Stop` — a live interactive owner may remain at its prompt in both cases. Validate a
  terminal-failure release hook; otherwise finite expiry or explicit release is required.
  PID liveness alone does not handle these cases.
- `SessionEnd` → `release` (cleanup on normal exit). **Not guaranteed on crash/force-kill**
  (undocumented) → the PID backstop is the real crash safety net, not `SessionEnd`.

### Hook command form — guarded shim, never a raw binary path

[DECISION Q3 — see decisions section] settings.json points at a **stable per-user shim**, not
the app binary directly:

```json
{
  "hooks": {
    "UserPromptSubmit": [{ "matcher": "", "hooks": [{ "type": "command",
      "command": "/bin/sh -c 'h=\"$HOME/.lidawake/hooks/claude-acquire\"; [ -x \"$h\" ] && exec \"$h\" >/dev/null 2>&1; exit 0'" }]}],
    "Stop":             [{ "matcher": "", "hooks": [{ "type": "command",
      "command": "/bin/sh -c 'h=\"$HOME/.lidawake/hooks/claude-release\"; [ -x \"$h\" ] && exec \"$h\" >/dev/null 2>&1; exit 0'" }]}],
    "SessionEnd":       [{ "matcher": "", "hooks": [{ "type": "command",
      "command": "/bin/sh -c 'h=\"$HOME/.lidawake/hooks/claude-release\"; [ -x \"$h\" ] && exec \"$h\" >/dev/null 2>&1; exit 0'" }]}]
  }
}
```

- `~/.lidawake/hooks/claude-acquire` and `…/claude-release` are tiny shims (symlink or
  one-line script) that `exec` the current app binary with `lease acquire|release`. **The app
  rewrites the shim's target on every launch** — so when the app moves, only the shim updates;
  `settings.json` is written once and never re-touched.
- The guard (`[ -x "$h" ] && … ; exit 0`) makes a deleted app a **silent no-op** that always
  exits 0 — no orphaned-hook noise, no blocked turns. (Orphaned raw-binary hooks wouldn't
  block `UserPromptSubmit` either — only exit 2 blocks — but they would print per-turn hook
  errors. The shim avoids that.)
- The shim path is also the **durable identity marker** for safe merge/remove: the wizard
  matches `~/.lidawake/hooks/` in the command string, so Remove works even after the app moved.

This dominates both originally-proposed options. "Hardcode /Applications" is brittle (and
repeats the existing login-item hardcode at LidAwake.swift:259); "write the resolved path into
settings.json and re-point" means re-writing a file we don't own every time the app moves. The
shim re-points without ever re-touching settings.json after install.

## The wizard / explicit consent (required)

Never touch `~/.claude/settings.json` silently. Menu: **"Integrations…"** → **"Set Up Claude
Code…"** (shown only when `~/.claude` exists).

**Prerequisites the wizard enforces before installing hooks:**
- passwordless sudoers installed (else reconcile can't write `disablesleep` without prompting);
- Launch at Login enabled (else the coordinator isn't running when hooks fire).
- If either is missing, the wizard offers to set it up first.

**Copy / altitude:** lead with plain language, JSON behind a disclosure:
> **Set up Claude Code** — LidAwake will keep your Mac awake while Claude Code is actively
> working, and let it sleep again when every session is idle. This adds three hooks to
> `~/.claude/settings.json`; your other settings and hooks are left untouched.  ▸ Show exactly
> what will be added

**State machine (the wizard must handle all of these):**

| State | Detection | Behavior |
|---|---|---|
| `~/.claude` missing | dir absent | menu item hidden |
| `settings.json` missing (dir exists) | file absent | offer to **create** with just our hooks |
| `settings.json` unparseable | JSON parse throws | **abort, never overwrite**; show "settings.json has a syntax error — fix it, or let me back it up first" |
| not installed (valid file) | our shim paths absent | **Install** |
| installed | our shim paths present | **Installed ✓** + **Remove** |
| partially installed | 1–2 of 3 present | **Repair** → reconcile to full set |

**Safe merge algorithm:**
1. Read raw bytes. Missing → start `{}`. Unparseable → abort with error dialog (never clobber).
2. Ensure `hooks` is a dict and `hooks[event]` is an array (create `[]` if absent; if present
   but wrong shape, abort and warn).
3. **Append** our `{matcher:"", hooks:[…]}` entry only if our shim path isn't already present
   (idempotent; drives the toggle state).
4. Back up to `settings.json.lidawake.bak` before the first write. Serialize with
   `.sortedKeys`; write **atomically** (temp in `~/.claude/`, then `rename`).
5. **Remove** = filter out only entries whose command references `~/.lidawake/hooks/`; prune
   now-empty arrays / empty `hooks`. Re-serialize + atomic write.

**First-run trust loop:** after Install, prompt "Send a message in Claude Code now — you
should see this go to '1 job'." Converting the abstract install into one observed success is
what makes a user trust it enough to actually close the lid.

## Feedback & debuggability (the silent-failure problem)

The value prop is "set it and walk away" — so the user is never looking at the screen when it
matters (lid closed), and the only failure symptom is the Mac sleeping mid-work. The plan must
add a feedback trail:

- **Append-only log** at `~/.lidawake/logs/hooks.log` (and coordinator events): timestamped
  acquire / release / reap-reason / resolved-pid, bounded size. Highest-leverage, near-zero
  cost: `tail` answers "did acquire fire? did it reap? why?" The hook CLI logs only on
  failure (keeps the hot path silent).
- **Per-lease submenu** under the status line: list active leases (`source · age · pid ·
  verified?`) so a stuck/unverified lease is visible.
- **"Last lease activity: 3s ago"** in the menu so the user can tell "working, nothing
  running" from "hooks never fired."

## Extensibility (Claude now, more later) — keep it light

```
struct Integration { name; detect()->Bool; isInstalled()->Bool; install(); remove() }
let integrations = [claudeCode]   // add codex, aider, … later
```

The **coordinator + lease store + `LidAwake lease` CLI + shim mechanism are tool-agnostic.**
Per-tool work is only: detection + how to install its hooks (or a `lidawake-keep`-style
wrapper for tools without hooks). The "Integrations" submenu iterates this list.

## Menu / UI changes

- Status line includes active lease count, e.g. *"On AC · staying awake · 2 jobs"* (verb
  included so it reads as a reason, not a bare count). Expand the count into the per-lease
  submenu above.
- Icon already flips moon↔cup based on live `disablesleep`; leases drive that automatically.
- New "Integrations" submenu with the Claude Code install/remove/repair toggle and prereq
  warnings.

## MVP scope (this feature) vs later

**MVP (build now):**
1. Dual-mode entry point: arg-dispatch before AppKit; Foundation-only `LeaseCLI`.
2. `LidAwake lease acquire|release` (stdin JSON → hashed lease file, PID-identity resolution,
   atomic write, finite expiry, explicit renewal/release, always exit 0, silent).
3. Coordinator: per-tick `reconcileSleepPolicy()` regardless of lid state; lock + final
   rescan + debounce before clearing; reap by PID identity or finite expiry (all leases);
   reconcile + reap on launch; send changes through the existing sleep worker.
4. Claude Code wizard: prereq enforcement (sudoers + login item), guarded-shim hooks, safe
   merge/remove with backup + atomic write + abort-on-unparseable, full state machine,
   first-run trust prompt.
5. Shim mechanism: `~/.lidawake/hooks/claude-{acquire,release}` re-pointed on every launch.
6. Status-line lease count + per-lease submenu + `~/.lidawake/logs/hooks.log`.

**Later:**
- Additional tools (codex/aider) + generic `lidawake-keep` wrapper + shell `trap` snippet.
- Manual "keep awake until I stop" lease (menu/CLI) for multi-turn holds.
- `pmset sleepnow` on last-release-while-lid-closed (needs a widened sudoers rule).
- `PostToolUse`-refresh backstop if PID resolution proves unreliable in the field.

## Validation gate (do before/with implementation)

These must be confirmed on the real machine — the plan's safety rests on them:
1. **PID resolution:** from a real Claude Code hook, walk `getppid()` and confirm it reliably
   reaches a stable, identifiable owner (record its `comm`/basename). Define the
   `verified=false` fallback if it doesn't.
2. **Quarantined-binary exec:** confirm the app binary, spawned by a hook on a fresh
   *quarantined* (Gatekeeper) install, runs without a prompt. If Gatekeeper can block the
   spawned helper, leases silently never acquire — the wizard must handle/notify.
3. **Live reload for an already-open session:** confirm a session open at install time picks
   up the new hooks (or document "start a new session").
4. **`Stop` input fields:** confirm `background_tasks`/`session_crons`/`stop_hook_active`
   shapes so the "release only when idle" check is correct.

## Testing plan

- **Happy path:** acquire then release by hand → `disablesleep` 1→…→0; icon/status update.
- **Release while lid OPEN:** must clear `disablesleep` (regression guard for the tick-gating bug).
- **Crash:** acquire, `kill -9` the owner → coordinator reaps within a couple ticks → sleeps.
- **PID reuse:** acquire, kill owner, spawn a new process onto the same PID → identity check
  must still reap (don't be fooled by `kill -0`).
- **Unresolved PID:** force `verified=false` → expires at its bounded deadline, shows "unverified."
- **Live but idle owner:** acquire, interrupt the turn, keep the process alive → expires on
  deadline even though PID identity still matches; explicit release clears it immediately.
- **Renewal:** explicit renewal extends a finite deadline; a live-PID poll never does.
- **Clock changes/restart:** backward clock jumps, future timestamps, and relaunch cannot
  create an indefinite hold; verify bounded expiry with an injected clock.
- **Concurrency:** two sessions acquire/release concurrently; count stays correct; no torn reads.
- **0-transition race:** release-then-immediate-acquire must not clear `disablesleep`.
- **Real Claude, lid closed:** stays awake through a long turn (incl. thinking + a long single
  tool call); sleeps shortly after `Stop`; two tabs → sleeps only after both finish.
- **`Stop` with background tasks pending:** lease is NOT released early.
- **Interrupt / `StopFailure`:** validate available release hooks; test the missing-hook
  path with an owner that remains alive. Expiry still releases that lease.
- **Coordinator not running:** hooks do not enable sleep prevention; verify the sleep
  worker restores any prior owned override on GUI exit, and journal recovery after both die.
- **Wizard merge:** existing user hooks preserved; create-when-missing; **abort on unparseable
  settings.json** (no clobber); backup written; Remove pulls only our entries even after the
  app moved; partial-install → Repair.
- **Malformed hook stdin:** acquire still exits 0, falls back to cwd+pid key.
- **Orphaned hooks (app deleted):** guarded shim → silent no-op, no blocked turns, no errors.

---

## Historical /autoplan review report

The report and decision tables below record the original review. The 2026-09-14 safety
correction above supersedes claims that verified leases never expire, that PID liveness
handles an idle interrupted process, or that coordinator absence alone guarantees sleep.

### Voices
- **Codex (gpt-5.5, read-only):** ran, comprehensive review (strategy + arch + DX).
- **Claude eng subagent (independent):** ran.
- **Claude DX subagent (independent):** ran.
- **claude-code-guide (fact-check):** ran — verified hook semantics against current docs.
- **Design phase:** skipped — the only UI is a native consent dialog + menu, not a web/visual
  surface the design-review skill targets. Wizard UX folded into DX instead.
- **Voice consolidation:** for a 162-line plan on a single 269-line file, one comprehensive
  Codex pass + independent Claude eng/DX subagents + the facts agent was run instead of three
  separate per-phase Codex calls (which would have been highly redundant). Pragmatic call (P3/P6).

### Eng consensus table
```
  Dimension                          Claude  Codex  Consensus
  ─────────────────────────────────── ─────── ─────── ─────────
  1. Architecture sound?              YES*    YES*   CONFIRMED (with fixes)
  2. Test coverage sufficient?        NO      NO     CONFIRMED gap → expanded
  3. Concurrency/races addressed?     NO      NO     CONFIRMED gap → lock+rescan+atomic
  4. Security surface ok?             YES     mostly DISAGREE → hash session_id, 0700/0600
  5. Reaping correct as written?      NO      NO     CONFIRMED → PID-identity + backstop
  6. Crash safety (Stop/SessionEnd)?  partial NO     CONFIRMED → PID backstop is the net
  * sound only after the dual-mode entry-point + per-tick reconcile fixes
```

### Cross-phase themes (flagged by 2+ voices independently)
- **Silent failure / no diagnostics** — eng + DX + Codex. → log + per-lease submenu + last-activity.
- **Coordinator/GUI must be running** — Codex (critical); implied by eng. → wizard requires login item.
- **settings.json safety** — all three. → abort-on-unparseable, backup, atomic, shim-path marker.
- **Reaping under-specified** — all three (with the one disagreement resolved). → PID identity.

### NOT in scope (deferred)
- CLI self-reconcile when no coordinator runs (breaks single-writer; complexity) — rejected.
- `pmset sleepnow` (needs widened sudoers) — Later.
- `PostToolUse`-refresh backstop — Later, only if PID resolution proves flaky.
- codex/aider integrations, manual hold lease, `trap`/wrapper — Later (already in plan).

### What already exists (reused, not rebuilt)
- `disablesleep` write path + scoped passwordless sudoers (LidAwake.swift:117–148) — leases
  drive it via the existing `setDisableSleep` + `liveAwake` guard.
- 2s `Timer` / `lidTick` (line 42, 51) — split, not replaced.
- Icon flip on live `disablesleep` (line 197) — leases drive it for free.
- Login-item plumbing (line 255) — reused for the "require Launch at Login" prereq, and the
  hardcoded `/Applications` path there (line 259) should move to the resolved path for consistency.

### Decisions (forced open questions)

| # | Question | Decision | Why |
|---|----------|----------|-----|
| Q1 | Reaping: PID-walk vs staleness | **PID liveness with identity validation** (pid+start-time+basename) as crash backstop; staleness (long, ~6h) only for unverified leases. Clean release stays primary. | Lease is held acquire→release, so turn length is irrelevant for verified leases; identity check defeats PID-reuse (the eng subagent's valid objection); short staleness would wrongly reap unresolved long jobs. Codex + Claude eng converge here once "release is primary" is made explicit. |
| Q2 | sleepnow vs natural sleep | **Natural sleep** (set `disablesleep 0`, no `sleepnow`). | Unanimous. Lid-closed + clear flag = clamshell sleep in seconds anyway; `sleepnow` isn't in the sudoers rule and would prompt for a password from a timer. |
| Q3 | Hook path: /Applications vs resolved+re-point | **Guarded shim under `~/.lidawake/hooks/`**, app re-points the shim on launch. | Dominates both: settings.json written once with a stable path + durable remove-marker; re-pointing never re-touches a file we don't own; guard makes a deleted app a silent no-op. |

### Decision Audit Trail

| # | Phase | Decision | Class | Principle | Rationale |
|---|-------|----------|-------|-----------|-----------|
| 1 | Eng | Dual-mode: arg-dispatch before NSApplication; Foundation-only CLI | Mechanical | P5 | Otherwise hooks launch AppKit and hang 30s/turn. |
| 2 | Eng | Per-tick `reconcileSleepPolicy()` regardless of lid state | Mechanical | P1 | Release-while-lid-open would strand the Mac awake. |
| 3 | Eng | PID-identity reaping + long backstop for unverified | Taste→resolved | P1/P5 | See Q1; resolves the one cross-voice disagreement. |
| 4 | Eng | Lock + final rescan + debounce before clearing on last release | Mechanical | P1 | Closes the 0-transition race (Codex critical). |
| 5 | Eng | Atomic writes + tolerant reads; hash session_id; 0700/0600 | Mechanical | P1/P4 | Torn reads, path-injection, perms. |
| 6 | Eng | Stop only releases when no background_tasks/session_crons; PID backstop for interrupt/StopFailure | Mechanical | P1 | Verified hook semantics; avoids release-too-early. |
| 7 | Arch | Coordinator must run → wizard requires sudoers + Launch at Login | Mechanical | P1 | Feature is inert otherwise (Codex critical). |
| 8 | DX | Guarded shim hook command + app re-points shim | Taste→resolved | P5 | See Q3. |
| 9 | DX | settings.json: abort-on-unparseable, backup, atomic, append-not-set, shim-path marker | Mechanical | P1 | Never corrupt a file Claude Code depends on. |
| 10 | DX | Add `~/.lidawake/logs/hooks.log` + per-lease submenu + last-activity | Mechanical | P1 | Silent-failure is undebuggable otherwise (3-voice theme). |
| 11 | DX | Wizard plain-language + JSON disclosure + first-run trust prompt + full state machine | Mechanical | P5 | Consent clarity + observed-success trust beat. |
| 12 | CEO | sleepnow → Later (natural sleep v1) | Mechanical | P3 | See Q2. |
| 13 | Eng | Reject CLI self-reconcile fallback | Mechanical | P3/P5 | Duplicates privileged write path, breaks single-writer. |

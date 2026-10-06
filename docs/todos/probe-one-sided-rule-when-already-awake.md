# probeRule cannot prove `disablesleep 0` while sleep is already disabled

What: `PMSet.probeRule()` proves both directions only when SleepDisabled starts at 0 (0, 1, 0). When it starts at 1 and LidAwake does not own it, only `1` is proven.

Why: the 0 write could let the Mac sleep (lid closed, clamshell mode) while something else holds it awake. A one-sided sudoers rule denying `0` therefore still passes in that state, and the later restore fails (journal kept, error shown).

Context: found in review round 2 (docs/reviews/lidawake-fixes/round2.md); fixed for the 0 start only. Options: refuse to take ownership until the setting is 0, or accept the gap.

Effort: small, but it needs a product call on refusing to enable.

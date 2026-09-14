# Validation

`swift test` exercises the real control modules with simulated system settings. Tests
cover restoration on Quit and parent EOF, retry after a denied restore, recovery after
relaunch, journal failures, canceled toggles, master enable/disable and saved source
choices, power-source transitions, stable menu updates, command failures
and timeouts, exact sudo rules and legacy migration, login paths, and update comparisons.
`./scripts/test-recovery.sh` additionally kills a simulated GUI, including during an
in-flight write, and checks restoration by the real child-process transport.
No test changes the host's power settings, sudoers files, or login items.

`./scripts/build-app.sh universal` builds and signs the app for arm64 and x86_64.
`./scripts/check-build.sh universal` checks the signature, plist, and both macOS 12
Mach-O deployment targets. GitHub Actions runs tests and these bundle checks.

## Manual checks before publishing

Use a ventilated MacBook. Record the original `pmset -g` state and quit any old LidAwake
copy first. These checks deliberately change sleep settings and require interactive
admin/Automation approval; they are not part of the automated tests.

1. Build/open `LidAwake.app`. Choose Not Now, then try enabling keep-awake. Confirm setup
   is offered again and canceling leaves the preference unchanged. Complete setup and
   verify its two exact commands using `sudo -l`. A legacy installation should preserve
   the old account while removing every wildcard from its rule.
2. Enable AC and disable battery. Plug/unplug with the lid open, closed, and the menu
   left open. Check actual `SleepDisabled` state, icon, and menu. Battery must restore
   sleep; a permission failure must be visible. Check both Apple Silicon and Intel when
   hardware is available, including the oldest supported macOS version.
   Turn the **LidAwake** switch off while awake: sleep must be restored and the AC, battery,
   and external-display controls must dim without losing their checkmarks. Keep the
   menu open through several polls, switch power sources, and relaunch: the master
   must stay off. Enable it on battery: AC-only settings must still allow sleep until
   plugged in. Setup, login, and update actions must remain usable while disabled.
   Check the native switch with mouse, VoiceOver, and `⌘E` while the menu is open,
   including canceling setup and a failed change. Verify its appearance in light and
   dark mode and that neither the switch nor the menu blinks during background polls.
3. Close/open the lid with no external display, with an external display, and with the
   external-display toggle in both states. Confirm internal blanking and external-display
   behavior. Verify hotplugging a display and unlocking the Mac afterward.
4. Enable keep-awake and Quit: `SleepDisabled` must return to 0. Repeat by force-quitting
   only the GUI PID, leaving its `--sleep-worker` child alive. The child should restore
   sleep within a few seconds after any in-flight command completes, then exit.
5. On a test machine, kill both GUI and worker while awake. Relaunch and confirm journal
   recovery restores the old override before applying the current saved policy. For a
   visible final 0, save both source policies off before the recovery launch. Also test
   revoked sudo permission: Quit must report failure and retain the marker until repair.
6. Open two app copies: only one worker may manage the setting. The second must report
   that another session is active and must not clear the first one's override on exit.
7. Put the app in a folder with spaces and quotes. Enable Launch at Login, log out/in,
   and confirm that exact copy launches. Deny Automation access and confirm a useful
   error without an unresponsive menu. Move the app, enable the item again, and confirm
   the previous LidAwake entry is replaced.
8. Open About and check TurboKach's credit, version, and GitHub link in English/Russian.
   Check updates while online/offline. Verify a newer stable release opens the correct
   release page only after confirmation. There must be no update request at startup.

After testing, quit the app and verify sleep is enabled. If both processes were killed
and recovery cannot run, use `sudo pmset -a disablesleep 0` to restore sleep manually.

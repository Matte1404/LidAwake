#!/bin/bash
# Exercise real parent/child death with file-backed power settings, never pmset.
set -euo pipefail
cd "$(dirname "$0")/.."
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
export CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache"
swiftc Sources/LidAwakeCore/*.swift Tests/RecoveryProcess/main.swift \
    -module-cache-path "$CLANG_MODULE_CACHE_PATH" -o "$WORK/recovery-test"
for mode in quit handover crash crash-during-write crash-during-probe; do
    export LIDAWAKE_RECOVERY_TEST_DIR="$WORK/$mode"
    mkdir -m 700 "$LIDAWAKE_RECOVERY_TEST_DIR"
    printf 0 > "$LIDAWAKE_RECOVERY_TEST_DIR/awake"
    if [ "$mode" = crash-during-probe ]; then export LIDAWAKE_RECOVERY_PROBE=1; else unset LIDAWAKE_RECOVERY_PROBE; fi
    if "$WORK/recovery-test" "$mode"; then
        if [ "$mode" != quit ] && [ "$mode" != handover ]; then echo "Expected simulated GUI death" >&2; exit 1; fi
    else
        status=$?
        if [ "$mode" = quit ] || [ "$mode" = handover ] || [ "$status" != 137 ]; then exit "$status"; fi
    fi
    recovered=false
    for attempt in {1..50}; do
        if [ "$(cat "$LIDAWAKE_RECOVERY_TEST_DIR/awake")" = 0 ] && [ ! -s "$LIDAWAKE_RECOVERY_TEST_DIR/restore-sleep" ]; then
            recovered=true
            break
        fi
        sleep 0.1
    done
    if [ "$recovered" != true ]; then echo "Recovery failed: $mode" >&2; exit 1; fi
    echo "Restored sleep after $mode."
done

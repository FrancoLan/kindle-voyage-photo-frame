#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TMP=$(mktemp -d "${TMPDIR:-/tmp}/completed-command.XXXXXX")
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
# Exercise the real validation/deduplication prefix without executing any device action.
awk '/^execute_command\(\)/ {capture=1} capture {print} capture && /status_action=\$command_action/ {print "return 99";print "}";exit}' "$ROOT/implementation/kindle-manager/manager.sh" > "$TMP/prefix.sh"
. "$TMP/prefix.sh"
LAST_COMMAND_FILE="$TMP/last-id"
id=aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa
expiry=90
field() { case "$1" in id) printf '%s' "$id" ;; expires) printf '%s' "$expiry" ;; action) printf diagnose ;; esac; }
date() { printf '100\n'; }
printf '%s\n' "$id" > "$LAST_COMMAND_FILE"
execute_command
printf '%s\n' bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb > "$LAST_COMMAND_FILE"
set +e
execute_command
code=$?
set -e
[ "$code" = 72 ]
expiry=110
set +e
execute_command
code=$?
set -e
[ "$code" = 99 ]
echo 'Completed command expiry checks passed.'

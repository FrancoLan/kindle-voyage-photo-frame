#!/bin/sh

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
cd "$ROOT"

find implementation scripts -type f -name '*.sh' -print0 | xargs -0 -n 1 sh -n
find implementation scripts -type f -name '*.mjs' -print0 | xargs -0 -n 1 node --check
PYTHONPYCACHEPREFIX=/tmp/kindle-voyage-photo-frame-pycache python3 -m py_compile implementation/kindle/native/build-arm-elf.py
./scripts/test-render-modes.sh
./scripts/test-cleanup-storage.sh
./scripts/test-frontlight-policy.sh

SWIFT_TMP=$(mktemp -d /tmp/kindle-voyage-photo-frame-swift.XXXXXX)
trap 'rm -rf "$SWIFT_TMP"' EXIT HUP INT TERM
CLANG_MODULE_CACHE_PATH="$SWIFT_TMP/module-cache" swiftc implementation/mac/metadata-overlay.swift -o "$SWIFT_TMP/metadata-overlay"
CLANG_MODULE_CACHE_PATH="$SWIFT_TMP/module-cache" swiftc -parse-as-library implementation/mac/reverse-geocode.swift -o "$SWIFT_TMP/reverse-geocode"

if rg -n '/Users/[^/]+|192\.168\.1\.106|server-token[[:space:]]*:' \
    --glob '!scripts/check.sh' .; then
    echo "Privacy scan found a local path, private address, or token material." >&2
    exit 1
fi

if rg -n 'https://photos\.icloud\.com/shared/album/[A-Za-z0-9_-]{10,}' \
    --glob '!implementation/mac/config.example.json' .; then
    echo "Privacy scan found what may be a real iCloud Shared Album URL." >&2
    exit 1
fi

if find implementation/mac -maxdepth 1 -type f -exec file {} + | grep -q 'Mach-O'; then
    echo "Compiled macOS binaries must not be committed." >&2
    exit 1
fi

echo "All checks passed."

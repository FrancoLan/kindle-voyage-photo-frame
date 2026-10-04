#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TEMP=$(mktemp -d)
trap 'rm -rf "$TEMP"' EXIT
mkdir "$TEMP/bin"
cat > "$TEMP/bin/curl" <<'MOCK'
#!/bin/sh
for arg do
 case "$arg" in
  http://127.0.0.1:8787/v1/manifest) [ "$MODE" = primary ] && exit 0; exit 7 ;;
  http://127.0.0.2:8787/v1/manifest) [ "$MODE" != offline ] && exit 0; exit 7 ;;
 esac
done
exit 1
MOCK
chmod +x "$TEMP/bin/curl"
PATH="$TEMP/bin:$PATH"; export PATH
. "$ROOT/implementation/kindle-manager/server-fallback.sh"
MODE=primary; export MODE
[ "$(choose_server http://127.0.0.1:8787 http://127.0.0.2:8787 test-token)" = http://127.0.0.1:8787 ]
MODE=backup
[ "$(choose_server http://127.0.0.1:8787 http://127.0.0.2:8787 test-token)" = http://127.0.0.2:8787 ]
MODE=primary
[ "$(choose_server http://127.0.0.1:8787 http://127.0.0.2:8787 test-token)" = http://127.0.0.1:8787 ]
MODE=offline
if choose_server http://127.0.0.1:8787 http://127.0.0.2:8787 test-token; then exit 1; fi
printf 'Server fallback checks passed.\n'

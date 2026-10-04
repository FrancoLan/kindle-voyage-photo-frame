#!/bin/sh
# Probe only read-only authenticated requests before selecting an endpoint.
choose_server() {
    primary=$1
    backup=$2
    token=$3
    for candidate in "$primary" "$backup"; do
        [ -n "$candidate" ] || continue
        case "$candidate" in http://*) ;; *) continue ;; esac
        if curl -fsS --connect-timeout 3 --max-time 8 -H "Authorization: Bearer $token" "${candidate%/}/v1/manifest" -o /dev/null; then
            printf '%s\n' "${candidate%/}"
            return 0
        fi
    done
    return 1
}

#!/bin/sh
# Read powerd without changing charging or power settings.
level=$(lipc-get-prop com.lab126.powerd battLevel 2>/dev/null || true)
case "$level" in
    ''|*[!0-9]*) level=unknown ;;
    *) [ "$level" -le 100 ] 2>/dev/null || level=unknown ;;
esac
charging=$(lipc-get-prop com.lab126.powerd isCharging 2>/dev/null || true)
case "$charging" in
    1) power=charging ;;
    0) power=not-charging ;;
    *) power=unknown ;;
esac
printf 'battery=%s; power=%s\n' "$level" "$power"

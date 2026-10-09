# Presence-gated Kindle frontlight

Optional household presence gating keeps the existing ambient-light policy while someone is home and forces the frame frontlight off when everyone is away. Configure Home automations for **The First Person Arrives** and **The Last Person Leaves**, selecting all relevant household members.

The Mac server defaults to disabled. Enable with `presenceEnabled: true` and `presenceTokenFile` pointing to a private random 32-byte hex event token. POST to `/v1/presence/event/<event-token>/home` or `/away` from a Home automation converted to a Shortcut using Get Contents of URL. Use a stable reachable LAN endpoint; do not forward the port to the Internet. The dedicated event credential can only record occupancy, not invoke device controls. Keep the full URLs and presence logs private.

The authenticated device endpoint GET `/v1/presence` returns disabled, home, away or unknown. Set `PRESENCE_FRONTLIGHT_ENABLED=1` in both the Kindle photo and manager configuration files. The manager refreshes its local state once per polling cycle; the frontlight watcher checks it every five seconds. Away, unknown and device samples older than ten minutes force both automatic light and intensity off, including when the sensor is unavailable. Home returns to the existing lux policy. Disabled mode preserves the prior behavior. HomeKit events persist until the next event; missed location triggers cannot be inferred from a healthy network connection.

Before enabling, verify both Home automations, establish the actual initial occupancy, deploy both device scripts/configurations and future update sources, and test bright-room away/off and home/auto on the device. Mac restart preserves recorded occupancy, but household events require a working Home hub, location settings and reachable Mac. Exit from frame mode restores the user's original Kindle light settings; this gate applies during frame playback.

FRONTLIGHT_MIN_LEVEL optionally sets a minimum (0-24) during permitted ambient-auto mode. Away, unknown and dark-room states remain off; an already brighter setting is preserved. After runtime changes, verify actual LAN HTTP traffic as well as loopback tests, and pin a tested Node executable for deployment.

When a runtime is newly installed or upgraded, complete any macOS incoming-network permission prompt before diagnosing it as a networking regression. Verify actual LAN requests: a listening socket or a permitted-rule listing alone is insufficient.

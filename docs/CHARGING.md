# Battery-controlled HomeKit charging

A local Mac controller reads existing authenticated device status files and runs four user-configured HomeKit shortcuts. A fresh battery below 40 turns on the corresponding charger; above 80 turns it off; 40–80 inclusive preserves the existing state. Kindle status includes battery and power through the manager battery-status helper. BOOX Android 1.2.5 already provides battery status.

Copy implementation/mac/charge-config.example.json to a private local config and set controlDir. Create the four shortcuts listed in the config using Control Home and verify each against the correct plug. Run charge-control.mjs CONFIG --dry-run first. Enable a device only after its on/off shortcuts are verified, then set enabled=true and schedule --apply every minute using a LaunchAgent. Verify background execution while the Mac is locked before relying on it.

Missing, invalid, future, or stale readings never change power. Only successful shortcut completion records an applied state; failures retry on subsequent checks. Commands are reasserted at most once per configured interval. A lock prevents overlapping runs; if a crash leaves a lock, confirm no controller is running before removing it.

The Mac must remain powered on, logged in, and connected to the network. This controller cannot recover a powered-off Kindle; start its wireless manager after reboot. Validate the replacement controller before disabling existing time-based charging automations to prevent conflicting control. Keep config, state, logs and device telemetry private.

Verification: node --test implementation/mac/charge-policy.test.mjs, node --check implementation/mac/charge-control.mjs, and the full scripts/check.sh.

Each device keeps a private append-only JSONL file in controlDir/charge-logs: kindle.jsonl and boox.jsonl. Entries include UTC timestamp, Sydney local time to seconds, device, battery percentage and the source telemetry timestamp. Successful and failed HomeKit commands record on/off separately from observed charging transitions; command completion alone does not prove a physical plug transition. Charging samples are recorded every five minutes when new valid telemetry is available. Missing or stale telemetry records an unavailable event, without fabricated battery readings. Manual Home app switching is only visible through subsequent charging telemetry, not as a precise plug action timestamp. Dry runs do not write logs or state.

The subprocess runner closes its stdin after launching Shortcuts, since the CLI supports piped input and otherwise waits for EOF. Charge execution regression tests cover this and preserve failure diagnostics.

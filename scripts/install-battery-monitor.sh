#!/bin/sh
set -eu
[ "$(uname -s)" = Darwin ] || { echo 'This installer requires macOS.' >&2; exit 1; }
[ "$#" -ge 1 ] && [ "$#" -le 2 ] || { echo 'usage: install-battery-monitor.sh PRIVATE_CHARGE_CONFIG [RUNTIME_DIR]' >&2; exit 1; }
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
RUNTIME=${2:-$HOME/Library/Application Support/KindleVoyagePhotoFrame/runtime}
NODE=${PHOTOFRAME_NODE_PATH:-$(command -v node || true)}
[ -x "$NODE" ] && [ -f "$RUNTIME/battery-monitor.mjs" ] && [ -f "$1" ] || { echo 'Node, deployed runtime and private configuration are required.' >&2; exit 1; }
LABEL=io.github.francolan.kindle-voyage-photo-frame.battery-monitor
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOGS="$HOME/Library/Logs/KindleVoyagePhotoFrame"
mkdir -p "$(dirname "$PLIST")" "$LOGS"
"$NODE" --input-type=module - "$SCRIPT_DIR/../implementation/mac/launchagents/$LABEL.plist.template" "$PLIST" "$NODE" "$RUNTIME" "$1" "$LOGS" <<'JS'
import {readFile,writeFile} from 'node:fs/promises';
import {resolve,isAbsolute} from 'node:path';
const [template,target,node,runtime,config,logs]=process.argv.slice(2);
const c=JSON.parse(await readFile(config,'utf8'));
if(typeof c.controlDir !== 'string' || !isAbsolute(c.controlDir) || !c.devices || !Object.keys(c.devices).length) throw new Error('Invalid monitoring configuration');
const xml=v=>v.replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('>','&gt;').replaceAll('"','&quot;');
let body=await readFile(template,'utf8');
for(const [key,value] of Object.entries({__NODE__:node,__RUNTIME__:runtime,__CONFIG__:config,__LOGS__:logs})) body=body.replaceAll(key,xml(resolve(value)));
await writeFile(target,body,{mode:0o600});
JS
plutil -lint "$PLIST" >/dev/null
launchctl bootout "gui/$UID/$LABEL" >/dev/null 2>&1 || true
launchctl bootstrap "gui/$UID" "$PLIST"
echo 'Read-only battery monitoring installed; charger policy is unchanged.'

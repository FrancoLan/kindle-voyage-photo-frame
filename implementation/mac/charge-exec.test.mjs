import test from 'node:test';
import assert from 'node:assert/strict';
import { run } from './charge-exec.mjs';
test('command waiting for stdin EOF completes without timing out', async () => {
 const result = await run(process.execPath, ['-e', "process.stdin.resume(); process.stdin.on('end', () => process.stdout.write('EOF'));"], {timeout: 2000});
 assert.equal(result.stdout, 'EOF');
});
test('failed command preserves diagnostics', async () => {
 await assert.rejects(run(process.execPath, ['-e', "process.stderr.write('failure');process.exit(7)"], {timeout:2000}), error => error.code === 7 && error.stderr === 'failure');
});

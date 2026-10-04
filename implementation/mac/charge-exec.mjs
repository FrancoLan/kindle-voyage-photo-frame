import { execFile } from 'node:child_process';
export const run = (file, args, options) => new Promise((resolve, reject) => {
  const child = execFile(file, args, options, (error, stdout, stderr) => {
    if (error) { error.stderr = stderr; reject(error); } else resolve({ stdout, stderr });
  });
  // Shortcuts accepts piped input: send EOF so it does not wait forever.
  child.stdin.end();
});

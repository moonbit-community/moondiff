import { spawn } from 'node:child_process';
import { once } from 'node:events';
import { constants } from 'node:os';
import { join, resolve } from 'node:path';
import { loadEnvFile } from 'node:process';

const playground = resolve(import.meta.dirname, '..');

async function run(command, args) {
  // Keep each step in its own process group so stopping also reaches the compiler.
  const processGroup = process.platform !== 'win32';
  const child = spawn(command, args, {
    cwd: playground,
    stdio: 'inherit',
    detached: processGroup,
  });
  let stopSignal;
  const handlers = ['SIGINT', 'SIGTERM', 'SIGHUP'].map(signal => {
    const handler = () => {
      stopSignal = signal;
      if (!child.pid) return;
      try {
        if (processGroup) process.kill(-child.pid, signal);
        else child.kill(signal);
      } catch (error) {
        if (error.code !== 'ESRCH') throw error;
      }
    };
    process.on(signal, handler);
    return [signal, handler];
  });
  try {
    const [code, signal] = await once(child, 'exit');
    const stopped = stopSignal || signal;
    return stopped ? 128 + constants.signals[stopped] : (code ?? 1);
  } finally {
    for (const [signal, handler] of handlers) process.off(signal, handler);
  }
}

try {
  try {
    loadEnvFile(join(playground, '.env'));
  } catch (error) {
    // Configuration can also come entirely from the parent environment.
    if (error.code !== 'ENOENT') throw error;
  }
  process.exitCode = await run(process.execPath, [join(playground, 'scripts/build.mjs')]);
  if (process.exitCode === 0) {
    process.exitCode = await run('moonrun', ['dist/moondiff-server.wasm']);
  }
} catch (error) {
  console.error(error.message);
  process.exitCode = 1;
}

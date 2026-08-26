import { spawn } from 'node:child_process';
import DubbingError from './DubbingError.js';

function appendBounded(current, chunk, maxBytes) {
  const text = chunk.toString();
  const combined = current + text;
  if (Buffer.byteLength(combined) <= maxBytes) return combined;
  return combined.slice(-maxBytes);
}

export function runProcess(command, args, options = {}) {
  const {
    cwd,
    env,
    signal,
    timeoutMs = 600000,
    maxOutputBytes = 64 * 1024,
    errorCode = 'PROCESS_FAILED',
  } = options;

  return new Promise((resolve, reject) => {
    if (signal?.aborted) {
      reject(new DubbingError('CANCELLED', 'Operation cancelled.'));
      return;
    }

    let stdout = '';
    let stderr = '';
    let settled = false;
    let timedOut = false;

    const child = spawn(command, args, {
      cwd,
      env: env || process.env,
      windowsHide: true,
      stdio: ['ignore', 'pipe', 'pipe'],
    });

    const finish = (callback) => {
      if (settled) return;
      settled = true;
      clearTimeout(timeout);
      signal?.removeEventListener('abort', onAbort);
      callback();
    };

    const stopChild = () => {
      if (child.exitCode == null) child.kill('SIGTERM');
      const forceTimer = setTimeout(() => {
        if (child.exitCode == null) child.kill('SIGKILL');
      }, 5000);
      forceTimer.unref?.();
    };

    const onAbort = () => {
      stopChild();
    };

    signal?.addEventListener('abort', onAbort, { once: true });

    child.stdout.on('data', (chunk) => {
      stdout = appendBounded(stdout, chunk, maxOutputBytes);
    });
    child.stderr.on('data', (chunk) => {
      stderr = appendBounded(stderr, chunk, maxOutputBytes);
    });

    const timeout = setTimeout(() => {
      timedOut = true;
      stopChild();
    }, timeoutMs);
    timeout.unref?.();

    child.on('error', (error) => {
      finish(() => reject(new DubbingError(
        errorCode,
        `Unable to start ${command}: ${error.message}`,
        { cause: error },
      )));
    });

    child.on('close', (exitCode, closeSignal) => {
      finish(() => {
        if (signal?.aborted) {
          reject(new DubbingError('CANCELLED', 'Operation cancelled.'));
          return;
        }
        if (timedOut) {
          reject(new DubbingError(errorCode, `${command} timed out after ${timeoutMs}ms.`, { retryable: true }));
          return;
        }
        if (exitCode !== 0) {
          const detail = stderr.trim() || stdout.trim() || `signal ${closeSignal || 'unknown'}`;
          reject(new DubbingError(errorCode, `${command} exited with code ${exitCode}: ${detail}`));
          return;
        }
        resolve({ stdout, stderr, exitCode });
      });
    });
  });
}

export function abortableDelay(milliseconds, signal) {
  return new Promise((resolve, reject) => {
    if (signal?.aborted) {
      reject(new DubbingError('CANCELLED', 'Operation cancelled.'));
      return;
    }
    const timeout = setTimeout(() => {
      signal?.removeEventListener('abort', onAbort);
      resolve();
    }, milliseconds);
    const onAbort = () => {
      clearTimeout(timeout);
      reject(new DubbingError('CANCELLED', 'Operation cancelled.'));
    };
    signal?.addEventListener('abort', onAbort, { once: true });
  });
}

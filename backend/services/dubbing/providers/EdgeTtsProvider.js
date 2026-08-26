import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import DubbingError from '../DubbingError.js';
import { abortableDelay, runProcess } from '../processRunner.js';

const WRAPPER_PATH = fileURLToPath(new URL('../../../scripts/edge_tts_synthesize.py', import.meta.url));
const ALLOWED_VOICES = new Set(['hi-IN-SwaraNeural', 'en-US-AriaNeural']);

export default class EdgeTtsProvider {
  constructor({ pythonBin = '', timeoutMs = 300000, logger = console }) {
    this.pythonBin = pythonBin;
    this.timeoutMs = timeoutMs;
    this.logger = logger;
    this.resolvedPython = null;
    this.available = false;
  }

  async assertAvailable(signal) {
    if (this.available) return;
    const python = await this.resolvePython(signal);
    const args = python === 'py'
      ? ['-3', '-c', 'import edge_tts']
      : ['-c', 'import edge_tts'];
    try {
      await runProcess(python, args, {
        signal,
        timeoutMs: 15000,
        errorCode: 'EDGE_TTS_NOT_INSTALLED',
      });
      this.available = true;
    } catch (error) {
      if (error.code === 'CANCELLED') throw error;
      throw new DubbingError(
        'EDGE_TTS_NOT_INSTALLED',
        'The selected Python runtime cannot import edge_tts. Install edge-tts or set DUBBING_PYTHON_BIN.',
        { cause: error },
      );
    }
  }

  async resolvePython(signal) {
    if (this.resolvedPython) return this.resolvedPython;
    const candidates = this.pythonBin
      ? [this.pythonBin]
      : process.platform === 'win32'
        ? ['python', 'py']
        : ['python3', 'python'];

    for (const candidate of candidates) {
      try {
        const args = candidate === 'py' ? ['-3', '--version'] : ['--version'];
        await runProcess(candidate, args, {
          signal,
          timeoutMs: 10000,
          errorCode: 'PYTHON_NOT_FOUND',
        });
        this.resolvedPython = candidate;
        return candidate;
      } catch (error) {
        if (error.code === 'CANCELLED') throw error;
      }
    }
    throw new DubbingError('PYTHON_NOT_FOUND', 'Python 3 is required to run edge-tts.');
  }

  async synthesize({ text, voice, rate = '+0%', outputPath, signal }) {
    if (!ALLOWED_VOICES.has(voice)) {
      throw new DubbingError('UNSUPPORTED_VOICE', `Voice ${voice} is not allowed.`);
    }
    if (!/^[-+]\d{1,3}%$/.test(rate)) {
      throw new DubbingError('INVALID_TTS_RATE', `Invalid Edge TTS rate: ${rate}`);
    }

    await this.assertAvailable(signal);
    const python = this.resolvedPython;
    const inputPath = path.join(path.dirname(outputPath), `${path.basename(outputPath, path.extname(outputPath))}.json`);
    await fs.writeFile(inputPath, JSON.stringify({ text, voice, rate }), 'utf8');

    try {
      let lastError;
      for (let attempt = 1; attempt <= 3; attempt += 1) {
        try {
          const pythonArgs = python === 'py'
            ? ['-3', WRAPPER_PATH, '--input', inputPath, '--output', outputPath]
            : [WRAPPER_PATH, '--input', inputPath, '--output', outputPath];
          await runProcess(python, pythonArgs, {
            signal,
            timeoutMs: this.timeoutMs,
            errorCode: 'TTS_FAILED',
          });
          const stats = await fs.stat(outputPath);
          if (stats.size === 0) throw new DubbingError('TTS_FAILED', 'Edge TTS created an empty file.');
          return outputPath;
        } catch (error) {
          if (error.code === 'CANCELLED' || error.code === 'PYTHON_NOT_FOUND') throw error;
          lastError = error;
          if (attempt === 3) break;
          const delayMs = 1000 * (2 ** (attempt - 1));
          this.logger.warn?.(`[edge-tts] synthesis failed; retrying in ${delayMs}ms (attempt ${attempt}/3)`);
          await abortableDelay(delayMs, signal);
        }
      }
      throw new DubbingError('TTS_FAILED', 'Edge TTS synthesis failed after three attempts.', {
        retryable: true,
        cause: lastError,
      });
    } finally {
      await fs.rm(inputPath, { force: true }).catch(() => {});
    }
  }
}

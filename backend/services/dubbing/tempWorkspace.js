import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import DubbingError from './DubbingError.js';

function isSamePath(left, right) {
  return process.platform === 'win32'
    ? left.toLowerCase() === right.toLowerCase()
    : left === right;
}

export default class TempWorkspaceManager {
  constructor({ root, staleHours = 24, logger = console }) {
    this.root = path.resolve(root);
    this.staleHours = staleHours;
    this.logger = logger;
    this.assertSafeRoot();
  }

  assertSafeRoot() {
    const parsedRoot = path.parse(this.root).root;
    const unsafeRoots = [parsedRoot, path.resolve(process.cwd()), path.resolve(os.homedir())];
    if (unsafeRoots.some((unsafe) => isSamePath(this.root, unsafe))) {
      throw new DubbingError('UNSAFE_TEMP_ROOT', `Unsafe DUBBING_TEMP_ROOT: ${this.root}`);
    }
  }

  assertSafeWorkspace(workspacePath) {
    const resolved = path.resolve(workspacePath);
    const basename = path.basename(resolved);
    if (!isSamePath(path.dirname(resolved), this.root) || !basename.startsWith('dub-')) {
      throw new DubbingError('UNSAFE_CLEANUP_TARGET', `Refusing to clean unsafe path: ${resolved}`);
    }
    return resolved;
  }

  async initialize() {
    await fs.mkdir(this.root, { recursive: true });
    await this.sweepStaleWorkspaces();
  }

  async create(videoId) {
    await fs.mkdir(this.root, { recursive: true });
    const safeVideoId = String(videoId).replace(/[^a-zA-Z0-9_-]/g, '').slice(0, 32) || 'video';
    const workspace = await fs.mkdtemp(path.join(this.root, `dub-${safeVideoId}-`));
    return this.assertSafeWorkspace(workspace);
  }

  async cleanup(workspacePath) {
    if (!workspacePath) return;
    const safePath = this.assertSafeWorkspace(workspacePath);
    await fs.rm(safePath, { recursive: true, force: true });
  }

  async sweepStaleWorkspaces(now = Date.now()) {
    const entries = await fs.readdir(this.root, { withFileTypes: true }).catch((error) => {
      if (error.code === 'ENOENT') return [];
      throw error;
    });
    const staleBefore = now - (this.staleHours * 60 * 60 * 1000);

    for (const entry of entries) {
      if (!entry.isDirectory() || !entry.name.startsWith('dub-')) continue;
      const candidate = this.assertSafeWorkspace(path.join(this.root, entry.name));
      const stats = await fs.stat(candidate);
      if (stats.mtimeMs >= staleBefore) continue;
      await fs.rm(candidate, { recursive: true, force: true });
      this.logger.info?.(`[cleanup] removed stale workspace ${entry.name}`);
    }
  }

  async getAvailableDiskMb() {
    if (typeof fs.statfs !== 'function') return null;
    const stats = await fs.statfs(this.root);
    return Number(stats.bavail * stats.bsize) / (1024 * 1024);
  }
}

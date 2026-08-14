import fs from 'node:fs/promises';

import { DATA_ROOT, HISTORY_FILE } from './config.js';

export async function readHistory(limit = 20) {
  try {
    const text = await fs.readFile(HISTORY_FILE, 'utf8');
    return text.split('\n').filter(Boolean).slice(-limit).map((line) => JSON.parse(line));
  } catch (error) {
    if (error.code === 'ENOENT') return [];
    throw error;
  }
}

export async function appendHistory(entry) {
  await fs.mkdir(DATA_ROOT, { recursive: true });
  await fs.appendFile(HISTORY_FILE, `${JSON.stringify(entry)}\n`, 'utf8');
}

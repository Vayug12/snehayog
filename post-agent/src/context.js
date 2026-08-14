import fs from 'node:fs/promises';
import path from 'node:path';

import { PROJECT_FILES, PROJECT_ROOT } from './config.js';

// llm.txt is ~20k chars and is the canonical product overview; anything below
// this cut its monetization model, FAQ, and recommendation guidance.
const MAX_FILE_CHARS = 24000;
const MAX_CONTEXT_CHARS = 42000;

function trimDocument(text) {
  if (text.length <= MAX_FILE_CHARS) return text;
  return `${text.slice(0, MAX_FILE_CHARS)}\n\n[File truncated for context size]`;
}

export async function loadProjectContext() {
  const documents = [];
  const missing = [];

  for (const relativePath of PROJECT_FILES) {
    const absolutePath = path.join(PROJECT_ROOT, relativePath);
    try {
      const text = await fs.readFile(absolutePath, 'utf8');
      documents.push(`### ${relativePath}\n${trimDocument(text)}`);
    } catch (error) {
      if (error.code !== 'ENOENT') throw error;
      missing.push(relativePath);
    }
  }

  if (documents.length === 0) {
    throw new Error(`No project context files found under ${PROJECT_ROOT}`);
  }

  const combined = documents.join('\n\n');
  return {
    projectRoot: PROJECT_ROOT,
    text: combined.slice(0, MAX_CONTEXT_CHARS),
    files: documents.map((document) => document.match(/^### (.+)$/m)?.[1]).filter(Boolean),
    missing,
  };
}

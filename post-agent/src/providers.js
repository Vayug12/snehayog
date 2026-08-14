import { spawn } from 'node:child_process';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';

import { PROVIDER_MODELS } from './config.js';

const CLI_ONLY_PREAMBLE =
  'You are a text-only content generator. Do not use tools, browse, read files, write files, or run commands. Reply directly with the requested post only.';

export async function generateWithProvider(prompt, provider) {
  if (provider === 'claude') return generateWithClaude(prompt);
  if (provider === 'claude-code') return runClaudeCode(prompt);
  if (provider === 'codex') return runCodex(prompt);
  if (provider === 'opencode') return runOpencode(prompt);
  throw new Error(`unsupported provider: ${provider}`);
}

async function generateWithClaude(prompt) {
  const key = process.env.ANTHROPIC_API_KEY || process.env.ANTHROPIC_AUTH_TOKEN;
  if (!key) throw new Error('ANTHROPIC_API_KEY or ANTHROPIC_AUTH_TOKEN is required for --provider claude');
  const response = await fetch('https://api.anthropic.com/v1/messages', {
    method: 'POST',
    signal: AbortSignal.timeout(120000),
    headers: {
      'x-api-key': key,
      'anthropic-version': '2023-06-01',
      'content-type': 'application/json',
    },
    body: JSON.stringify({
      model: PROVIDER_MODELS.claude,
      max_tokens: 3000,
      system: CLI_ONLY_PREAMBLE,
      messages: [{ role: 'user', content: prompt }],
    }),
  });
  const data = await response.json();
  if (!response.ok) throw new Error(data.error?.message || `Claude API failed with HTTP ${response.status}`);
  return data.content?.filter((item) => item.type === 'text').map((item) => item.text).join('') || '';
}

async function runClaudeCode(prompt) {
  const args = ['-p', '--output-format', 'text'];
  if (PROVIDER_MODELS['claude-code']) args.push('--model', PROVIDER_MODELS['claude-code']);
  return runCli('claude', args, `${CLI_ONLY_PREAMBLE}\n\n${prompt}`);
}

async function runCodex(prompt) {
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), 'snehayog-post-agent-'));
  const outputFile = path.join(directory, 'last-message.txt');
  try {
    const args = ['exec', '--skip-git-repo-check', '-s', 'read-only', '--output-last-message', outputFile];
    if (PROVIDER_MODELS.codex) args.push('-m', PROVIDER_MODELS.codex);
    args.push('-');
    await runCli('codex', args, `${CLI_ONLY_PREAMBLE}\n\n${prompt}`);
    return fs.readFile(outputFile, 'utf8');
  } finally {
    await fs.rm(directory, { recursive: true, force: true }).catch(() => {});
  }
}

async function runOpencode(prompt) {
  const args = ['run', '--pure'];
  if (PROVIDER_MODELS.opencode) args.push('-m', PROVIDER_MODELS.opencode);
  return runCli('opencode', args, `${CLI_ONLY_PREAMBLE}\n\n${prompt}`);
}

function runCli(command, args, input) {
  return new Promise((resolve, reject) => {
    const useShell = process.platform === 'win32';
    const shellArgs = useShell
      ? args.map((arg) => (/\s/.test(arg) ? `"${arg.replaceAll('"', '\\"')}"` : arg))
      : args;
    const child = spawn(command, shellArgs, { shell: useShell, windowsHide: true });
    let stdout = '';
    let stderr = '';
    child.stdout.on('data', (chunk) => (stdout += chunk));
    child.stderr.on('data', (chunk) => (stderr += chunk));
    child.on('error', (error) => reject(new Error(`could not start ${command}: ${error.message}`)));
    child.on('close', (code) => {
      if (code !== 0) reject(new Error(`${command} exited with ${code}: ${stderr.trim().slice(-500)}`));
      else resolve(stdout.trim());
    });
    child.stdin.on('error', () => {});
    child.stdin.end(input);
  });
}

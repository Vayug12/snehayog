import DubbingError from './DubbingError.js';

const BOOLEAN_FLAGS = new Set(['dry-run', 'force', 'yes', 'fail-fast', 'help']);
const VALUE_FLAGS = new Set(['channel', 'channel-id', 'target', 'target-language', 'limit']);

export function parseDubbingCliArgs(argv) {
  const values = {};
  const booleans = {};

  for (let index = 0; index < argv.length; index += 1) {
    const token = argv[index];
    if (!token.startsWith('--')) {
      throw new DubbingError('INVALID_ARGUMENT', `Unexpected argument: ${token}`);
    }
    const [rawName, inlineValue] = token.slice(2).split(/=(.*)/s, 2);
    if (BOOLEAN_FLAGS.has(rawName)) {
      if (inlineValue != null && inlineValue !== '') {
        throw new DubbingError('INVALID_ARGUMENT', `--${rawName} does not accept a value.`);
      }
      booleans[rawName] = true;
      continue;
    }
    if (!VALUE_FLAGS.has(rawName)) {
      throw new DubbingError('INVALID_ARGUMENT', `Unknown option: --${rawName}`);
    }
    const value = inlineValue != null && inlineValue !== '' ? inlineValue : argv[++index];
    if (value == null || value.startsWith('--')) {
      throw new DubbingError('INVALID_ARGUMENT', `--${rawName} requires a value.`);
    }
    values[rawName] = value;
  }

  if (booleans.help) return { help: true };

  if (!values.channel && !values['channel-id']) {
    throw new DubbingError('CHANNEL_REQUIRED', 'Use --channel="Channel Name" or --channel-id=<id>.');
  }
  const targetLanguage = values.target || values['target-language'];
  if (!targetLanguage) {
    throw new DubbingError('TARGET_REQUIRED', 'Use --target=hi or --target=en.');
  }

  let limit = null;
  if (values.limit != null) {
    limit = Number(values.limit);
    if (!Number.isInteger(limit) || limit <= 0) {
      throw new DubbingError('INVALID_LIMIT', '--limit must be a positive integer.');
    }
  }

  return {
    channelName: values.channel || null,
    channelId: values['channel-id'] || null,
    targetLanguage,
    limit,
    dryRun: Boolean(booleans['dry-run']),
    force: Boolean(booleans.force),
    yes: Boolean(booleans.yes),
    failFast: Boolean(booleans['fail-fast']),
  };
}

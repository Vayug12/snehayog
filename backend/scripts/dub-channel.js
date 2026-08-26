import 'dotenv/config';
import crypto from 'node:crypto';
import process from 'node:process';
import readline from 'node:readline/promises';
import mongoose from 'mongoose';
import ChannelDubbingRunner from '../services/dubbing/ChannelDubbingRunner.js';
import DubbingPipeline from '../services/dubbing/DubbingPipeline.js';
import VideoDubbingRepository from '../services/dubbing/VideoDubbingRepository.js';
import { assertExecutionConfig, loadDubbingConfig } from '../services/dubbing/dubbingConfig.js';
import { parseDubbingCliArgs } from '../services/dubbing/cliArgs.js';
import TempWorkspaceManager from '../services/dubbing/tempWorkspace.js';
import GroqSttProvider from '../services/dubbing/providers/GroqSttProvider.js';
import AzureTranslationProvider from '../services/dubbing/providers/AzureTranslationProvider.js';
import EdgeTtsProvider from '../services/dubbing/providers/EdgeTtsProvider.js';
import MediaTools from '../services/dubbing/media/MediaTools.js';
import R2DubbingStorage from '../services/dubbing/storage/R2DubbingStorage.js';

function formatMinutes(seconds) {
  return (seconds / 60).toFixed(1);
}

function printUsage() {
  console.log(`
Usage:
  npm run dub:channel -- --channel="Channel Name" --target=hi [options]

Required:
  --channel=<name>          Exact creator User.name (case-insensitive)
  --target=<hi|en>         Target dubbing language

Options:
  --channel-id=<id>        Unambiguous fallback when names are duplicated
  --target-language=<lang> Alias for --target; accepts hindi/english too
  --dry-run                Read-only preflight; no provider/R2/DB writes
  --limit=<count>          Process only the first N eligible videos
  --force                  Regenerate existing same-language dubs
  --yes                    Skip the interactive confirmation
  --fail-fast              Stop the batch after the first failed video
  --help                   Show this help
`);
}

function printPreflight(preflight, options) {
  console.log('\nChannel dubbing preflight');
  console.log(`  Channel: ${preflight.channel.name} (${preflight.channel._id})`);
  console.log(`  Target: ${preflight.targetLanguage}`);
  console.log(`  Videos found: ${preflight.totalVideos}`);
  console.log(`  Existing dubbed URL/cache hits: ${preflight.cached.length}`);
  console.log(`  Missing canonical MP4: ${preflight.missingCanonical.length}`);
  console.log(`  Over duration limit: ${preflight.tooLong.length}`);
  console.log(`  Eligible: ${preflight.eligible.length}`);
  console.log(`  Selected this run: ${preflight.selected.length}`);
  console.log(`  Recorded selected duration: ${formatMinutes(preflight.totalSelectedSeconds)} minutes`);
  console.log(`  Force regeneration: ${options.force ? 'yes' : 'no'}`);
}

function printSummary(summary) {
  console.log('\nChannel dubbing summary');
  console.log(`  Selected: ${summary.selected}`);
  console.log(`  Completed: ${summary.completed}`);
  console.log(`  Skipped/cache hits: ${summary.skipped}`);
  console.log(`  Not suitable: ${summary.notSuitable}`);
  console.log(`  Failed: ${summary.failed}`);
  console.log(`  Groq audio processed: ${formatMinutes(summary.audioSeconds)} minutes`);
  console.log(`  Azure source characters: ${summary.azureSourceCharacters}`);
  if (summary.failures.length > 0) {
    console.log('  Failures:');
    summary.failures.forEach((failure) => {
      console.log(`    - ${failure.videoName || failure.videoId}: ${failure.code}`);
    });
  }
}

async function askForConfirmation(signal) {
  const terminal = readline.createInterface({ input: process.stdin, output: process.stdout });
  try {
    const answer = await terminal.question('Start dubbing? (y/N) ', { signal });
    return ['y', 'yes'].includes(answer.trim().toLowerCase());
  } finally {
    terminal.close();
  }
}

async function buildPipeline({ config, repository, workspaceManager, signal }) {
  const { default: cloudflareR2Service } = await import('../services/uploadServices/cloudflareR2Service.js');
  const storage = new R2DubbingStorage({
    r2Service: cloudflareR2Service,
    accountId: process.env.CLOUDFLARE_ACCOUNT_ID,
    bucketName: process.env.CLOUDFLARE_R2_BUCKET_NAME,
    publicDomain: process.env.CLOUDFLARE_R2_PUBLIC_DOMAIN,
  });
  const ttsProvider = new EdgeTtsProvider({
    pythonBin: config.pythonBin,
    timeoutMs: config.providerTimeoutMs,
  });
  const mediaTools = new MediaTools({
    timeoutMs: config.processTimeoutMs,
    maxTempo: config.maxTempo,
    ttsConcurrency: config.ttsConcurrency,
  });
  await Promise.all([
    ttsProvider.assertAvailable(signal),
    mediaTools.assertAvailable(signal),
  ]);

  return new DubbingPipeline({
    config,
    workspaceManager,
    storage,
    repository,
    sttProvider: new GroqSttProvider({
      apiKey: config.groqApiKey,
      model: config.groqModel,
      endpoint: config.groqEndpoint,
      maxUploadMb: config.maxAudioUploadMb,
      timeoutMs: config.providerTimeoutMs,
    }),
    translationProvider: new AzureTranslationProvider({
      key: config.azureKey,
      region: config.azureRegion,
      endpoint: config.azureEndpoint,
      maxBatchCharacters: config.azureBatchCharacters,
      timeoutMs: config.providerTimeoutMs,
    }),
    ttsProvider,
    mediaTools,
  });
}

async function main() {
  const options = parseDubbingCliArgs(process.argv.slice(2));
  if (options.help) {
    printUsage();
    return;
  }
  const config = loadDubbingConfig();
  if (!config.mongoUri) throw new Error('MONGO_URI is required.');

  const abortController = new AbortController();
  let interruptedSignal = null;
  let fatalError = null;

  const interrupt = (signalName) => {
    interruptedSignal = interruptedSignal || signalName;
    console.warn(`\n${signalName} received; stopping after cleanup...`);
    abortController.abort();
  };
  const onSigint = () => interrupt('SIGINT');
  const onSigterm = () => interrupt('SIGTERM');
  const onUncaughtException = (error) => {
    fatalError = error;
    interrupt('uncaughtException');
  };
  const onUnhandledRejection = (error) => {
    fatalError = error instanceof Error ? error : new Error(String(error));
    interrupt('unhandledRejection');
  };

  process.once('SIGINT', onSigint);
  process.once('SIGTERM', onSigterm);
  process.once('uncaughtException', onUncaughtException);
  process.once('unhandledRejection', onUnhandledRejection);

  try {
    await mongoose.connect(config.mongoUri);
    const repository = new VideoDubbingRepository();
    const runner = new ChannelDubbingRunner({
      repository,
      maxVideoSeconds: config.maxVideoSeconds,
    });
    const preflight = await runner.preflight(options);
    printPreflight(preflight, options);

    if (options.dryRun) {
      console.log('\nDry run complete; no provider, R2 write, or MongoDB write calls were made.');
      return;
    }
    if (preflight.selected.length === 0) {
      console.log('\nNothing to dub.');
      return;
    }

    if (!options.yes && !await askForConfirmation(abortController.signal)) {
      console.log('Cancelled before dubbing started.');
      return;
    }

    assertExecutionConfig(config);
    const workspaceManager = new TempWorkspaceManager({
      root: config.tempRoot,
      staleHours: config.staleTempHours,
    });
    await workspaceManager.initialize();
    const availableDiskMb = await workspaceManager.getAvailableDiskMb();
    if (availableDiskMb != null && availableDiskMb < config.minFreeDiskMb) {
      throw new Error(
        `Insufficient local disk: ${availableDiskMb.toFixed(0)} MB free; ${config.minFreeDiskMb} MB required.`,
      );
    }

    runner.pipeline = await buildPipeline({
      config,
      repository,
      workspaceManager,
      signal: abortController.signal,
    });
    const runId = `${Date.now()}-${crypto.randomBytes(4).toString('hex')}`;
    const summary = await runner.run(preflight, {
      runId,
      failFast: options.failFast,
      signal: abortController.signal,
    });
    printSummary(summary);
    if (summary.failed > 0) process.exitCode = 2;
    if (fatalError) throw fatalError;
  } finally {
    process.removeListener('SIGINT', onSigint);
    process.removeListener('SIGTERM', onSigterm);
    process.removeListener('uncaughtException', onUncaughtException);
    process.removeListener('unhandledRejection', onUnhandledRejection);
    await mongoose.disconnect().catch(() => {});
    if (interruptedSignal && process.exitCode == null) process.exitCode = 130;
  }
}

main().catch((error) => {
  const code = error?.code ? `${error.code}: ` : '';
  console.error(`\nDubbing command failed: ${code}${error.message}`);
  process.exitCode = process.exitCode || 1;
});

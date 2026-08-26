import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { parseDubbingCliArgs } from '../../services/dubbing/cliArgs.js';
import AzureTranslationProvider, { createTranslationBatches } from '../../services/dubbing/providers/AzureTranslationProvider.js';
import GroqSttProvider from '../../services/dubbing/providers/GroqSttProvider.js';
import MediaTools, { buildAtempoFilter } from '../../services/dubbing/media/MediaTools.js';
import TempWorkspaceManager from '../../services/dubbing/tempWorkspace.js';
import ChannelDubbingRunner from '../../services/dubbing/ChannelDubbingRunner.js';
import DubbingPipeline from '../../services/dubbing/DubbingPipeline.js';
import R2DubbingStorage, { validateKey } from '../../services/dubbing/storage/R2DubbingStorage.js';

const silentLogger = {
  info() {},
  warn() {},
  error() {},
};

async function createTempFixture(t) {
  const base = await fs.mkdtemp(path.join(os.tmpdir(), 'vayug-dubbing-test-'));
  t.after(() => fs.rm(base, { recursive: true, force: true }));
  return { base, root: path.join(base, 'workspaces') };
}

test('CLI parser accepts channel, target, and operational flags', () => {
  const parsed = parseDubbingCliArgs([
    '--channel=My Channel',
    '--target', 'hindi',
    '--limit=5',
    '--force',
    '--yes',
  ]);
  assert.equal(parsed.channelName, 'My Channel');
  assert.equal(parsed.targetLanguage, 'hindi');
  assert.equal(parsed.limit, 5);
  assert.equal(parsed.force, true);
  assert.equal(parsed.yes, true);
});

test('CLI parser rejects missing target and invalid limit', () => {
  assert.throws(() => parseDubbingCliArgs(['--channel=X']), { code: 'TARGET_REQUIRED' });
  assert.throws(
    () => parseDubbingCliArgs(['--channel=X', '--target=hi', '--limit=0']),
    { code: 'INVALID_LIMIT' },
  );
});

test('CLI parser supports help and target-language alias', () => {
  assert.deepEqual(parseDubbingCliArgs(['--help']), { help: true });
  const parsed = parseDubbingCliArgs(['--channel=X', '--target-language=english']);
  assert.equal(parsed.targetLanguage, 'english');
});

test('Azure batching preserves segments and stays below limits', () => {
  const segments = [
    { id: 0, sourceText: '12345' },
    { id: 1, sourceText: '67890' },
    { id: 2, sourceText: 'abc' },
  ];
  const batches = createTranslationBatches(segments, 10, 1000);
  assert.deepEqual(batches.map((batch) => batch.map((segment) => segment.id)), [[0, 1], [2]]);
});

test('Azure provider maps response positions back to segment IDs and counts characters', async () => {
  const calls = [];
  const provider = new AzureTranslationProvider({
    key: 'test-key',
    region: 'centralindia',
    endpoint: 'https://api.cognitive.microsofttranslator.com',
    httpClient: {
      async post(url, body, options) {
        calls.push({ url, body, options });
        return {
          data: body.map((item) => ({ translations: [{ to: 'hi', text: `hi:${item.text}` }] })),
        };
      },
    },
  });
  const result = await provider.translateSegments([
    { id: 7, sourceText: 'hello' },
    { id: 9, sourceText: 'world' },
  ], { sourceLanguage: 'en', targetLanguage: 'hi' });
  assert.deepEqual(result.segments.map((segment) => [segment.id, segment.translatedText]), [
    [7, 'hi:hello'],
    [9, 'hi:world'],
  ]);
  assert.equal(result.sourceCharacters, 10);
  assert.match(calls[0].url, /from=en/);
  assert.match(calls[0].url, /to=hi/);
  assert.equal(calls[0].options.headers['Ocp-Apim-Subscription-Region'], 'centralindia');
});

test('Groq provider normalizes timestamped verbose JSON without transcript logging', () => {
  const provider = new GroqSttProvider({
    apiKey: 'test-key',
    model: 'whisper-large-v3-turbo',
    endpoint: 'https://example.invalid',
  });
  const result = provider.normalizeResponse({
    language: 'English',
    duration: 2,
    segments: [
      { start: 0.2, end: 0.9, text: ' Hello ' },
      { start: 1.1, end: 1.8, text: ' world ' },
    ],
  }, 2000);
  assert.equal(result.language, 'en');
  assert.deepEqual(result.segments.map((segment) => [segment.startMs, segment.endMs, segment.sourceText]), [
    [200, 900, 'Hello'],
    [1100, 1800, 'world'],
  ]);
});

test('atempo chains ratios outside a single filter range', () => {
  assert.equal(buildAtempoFilter(4), 'atempo=2.000000,atempo=2.000000');
  assert.equal(buildAtempoFilter(0.25), 'atempo=0.500000,atempo=0.500000');
});

test('workspace cleanup removes only validated job directories', async (t) => {
  const fixture = await createTempFixture(t);
  const manager = new TempWorkspaceManager({ root: fixture.root, staleHours: 1, logger: silentLogger });
  await manager.initialize();
  const workspace = await manager.create('video-1');
  await fs.writeFile(path.join(workspace, 'large.tmp'), 'temporary');
  await manager.cleanup(workspace);
  await assert.rejects(fs.stat(workspace), { code: 'ENOENT' });
  await assert.rejects(() => manager.cleanup(fixture.base), { code: 'UNSAFE_CLEANUP_TARGET' });
});

test('startup sweep deletes stale job directories but preserves unrelated directories', async (t) => {
  const fixture = await createTempFixture(t);
  await fs.mkdir(fixture.root, { recursive: true });
  const stale = path.join(fixture.root, 'dub-old-job');
  const unrelated = path.join(fixture.root, 'keep-me');
  await Promise.all([fs.mkdir(stale), fs.mkdir(unrelated)]);
  const oldDate = new Date(Date.now() - 3 * 60 * 60 * 1000);
  await fs.utimes(stale, oldDate, oldDate);

  const manager = new TempWorkspaceManager({ root: fixture.root, staleHours: 1, logger: silentLogger });
  await manager.initialize();
  await assert.rejects(fs.stat(stale), { code: 'ENOENT' });
  assert.equal((await fs.stat(unrelated)).isDirectory(), true);
});

test('channel runner skips cached/missing videos and runs selected videos sequentially', async () => {
  const videos = [
    { _id: '1', videoName: 'cached', duration: 20, canonicalMp4Key: 'a.mp4', dubbedUrls: { hi: 'https://cached' } },
    { _id: '2', videoName: 'missing', duration: 20, dubbedUrls: {} },
    { _id: '3', videoName: 'first', duration: 20, canonicalMp4Key: 'c.mp4', dubbedUrls: {} },
    { _id: '4', videoName: 'second', duration: 20, canonicalMp4Key: 'd.mp4', dubbedUrls: {} },
  ];
  let active = 0;
  let maxActive = 0;
  const pipeline = {
    async runVideo(video) {
      active += 1;
      maxActive = Math.max(maxActive, active);
      await new Promise((resolve) => setTimeout(resolve, 5));
      active -= 1;
      return { status: 'completed', audioSeconds: 20, azureSourceCharacters: 100 };
    },
  };
  const runner = new ChannelDubbingRunner({
    repository: {
      async resolveChannel() { return { _id: 'channel', name: 'Channel' }; },
      async listChannelVideos() { return videos; },
    },
    pipeline,
    logger: silentLogger,
  });
  const preflight = await runner.preflight({ channelName: 'Channel', targetLanguage: 'hi' });
  assert.equal(preflight.cached.length, 1);
  assert.equal(preflight.missingCanonical.length, 1);
  assert.equal(preflight.selected.length, 2);
  const summary = await runner.run(preflight, { runId: 'run' });
  assert.equal(summary.completed, 2);
  assert.equal(maxActive, 1);
});

function createPipelineMocks(workspaceManager, failureStage = null) {
  const repository = {
    writes: [],
    async setDubbedUrl(videoId, language, url) {
      this.writes.push({ videoId, language, url });
    },
  };
  const storage = {
    async downloadSource(video, localPath) {
      await fs.writeFile(localPath, 'source');
      return { key: video.canonicalMp4Key, localPath };
    },
    async uploadDubbed(localPath, key) {
      await fs.stat(localPath);
      return { url: `https://cdn.example/${key}`, key };
    },
  };
  const mediaTools = {
    async probe() { return { hasVideo: true, hasAudio: true, durationSeconds: 5 }; },
    async extractSpeechAudio(input, output) { await fs.writeFile(output, 'audio'); },
    async buildDubbedTimeline({ workspace }) {
      const timelinePath = path.join(workspace, 'timeline.wav');
      await fs.writeFile(timelinePath, 'timeline');
      return { timelinePath, clippedSegmentCount: 0 };
    },
    async muxDubbedVideo(input, timeline, output) { await fs.writeFile(output, 'dubbed'); },
    async validateDubbedVideo() {},
  };
  const sttProvider = {
    async transcribe() {
      return {
        language: 'en',
        segments: [{ id: 0, startMs: 0, endMs: 1000, sourceText: 'hello' }],
      };
    },
  };
  const translationProvider = {
    async translateSegments(segments) {
      if (failureStage === 'translation') throw new Error('translation failed');
      return {
        sourceCharacters: 5,
        segments: segments.map((segment) => ({ ...segment, translatedText: 'namaste' })),
      };
    },
  };
  const pipeline = new DubbingPipeline({
    config: { maxVideoSeconds: 600, pipelineVersion: 'v1' },
    workspaceManager,
    storage,
    repository,
    sttProvider,
    translationProvider,
    ttsProvider: {},
    mediaTools,
    logger: silentLogger,
  });
  return { pipeline, repository };
}

test('pipeline persists URL and cleans workspace after success', async (t) => {
  const fixture = await createTempFixture(t);
  const manager = new TempWorkspaceManager({ root: fixture.root, logger: silentLogger });
  await manager.initialize();
  const { pipeline, repository } = createPipelineMocks(manager);
  const result = await pipeline.runVideo({
    _id: 'video1',
    canonicalMp4Key: 'videos/video1.mp4',
    dubbedUrls: {},
  }, { targetLanguage: 'hi', runId: 'run1' });
  assert.equal(result.status, 'completed');
  assert.equal(repository.writes.length, 1);
  assert.deepEqual(await fs.readdir(fixture.root), []);
});

test('pipeline cleans workspace when a provider fails', async (t) => {
  const fixture = await createTempFixture(t);
  const manager = new TempWorkspaceManager({ root: fixture.root, logger: silentLogger });
  await manager.initialize();
  const { pipeline, repository } = createPipelineMocks(manager, 'translation');
  await assert.rejects(
    pipeline.runVideo({
      _id: 'video2',
      canonicalMp4Key: 'videos/video2.mp4',
      dubbedUrls: {},
    }, { targetLanguage: 'hi', runId: 'run2' }),
    { code: 'DUBBING_FAILED' },
  );
  assert.equal(repository.writes.length, 0);
  assert.deepEqual(await fs.readdir(fixture.root), []);
});

test('R2 source URL resolution only accepts configured origins and safe keys', () => {
  const storage = new R2DubbingStorage({
    r2Service: {},
    accountId: 'account',
    bucketName: 'bucket',
    publicDomain: 'https://cdn.example.com',
  });
  assert.equal(
    storage.sourceKey({ canonicalMp4Url: 'https://cdn.example.com/videos/source.mp4' }),
    'videos/source.mp4',
  );
  assert.throws(
    () => storage.sourceKey({ canonicalMp4Url: 'https://evil.example/source.mp4' }),
    { code: 'UNTRUSTED_VIDEO_ORIGIN' },
  );
  assert.throws(() => validateKey('../source.mp4'), { code: 'INVALID_R2_KEY' });
});

test('real FFmpeg path builds, muxes, and validates a short dubbed MP4', async (t) => {
  const fixture = await createTempFixture(t);
  const workspace = path.join(fixture.base, 'media');
  await fs.mkdir(workspace);
  const mediaTools = new MediaTools({ timeoutMs: 120000, ttsConcurrency: 1, logger: silentLogger });
  const sourcePath = path.join(workspace, 'source.mp4');
  await mediaTools.runFfmpeg([
    '-f', 'lavfi',
    '-i', 'color=c=black:s=320x240:r=25',
    '-f', 'lavfi',
    '-i', 'sine=frequency=220:sample_rate=48000',
    '-t', '2',
    '-c:v', 'libx264',
    '-pix_fmt', 'yuv420p',
    '-c:a', 'aac',
    sourcePath,
  ]);

  const ttsProvider = {
    async synthesize({ outputPath }) {
      await mediaTools.runFfmpeg([
        '-f', 'lavfi',
        '-i', 'sine=frequency=440:sample_rate=48000',
        '-t', '0.4',
        '-c:a', 'libmp3lame',
        outputPath,
      ]);
    },
  };
  const timeline = await mediaTools.buildDubbedTimeline({
    segments: [
      { id: 0, startMs: 200, endMs: 800, translatedText: 'hello' },
      { id: 1, startMs: 1200, endMs: 1700, translatedText: 'world' },
    ],
    videoDurationMs: 2000,
    workspace,
    language: { voice: 'en-US-AriaNeural', estimatedCharactersPerSecond: 13 },
    ttsProvider,
  });
  const outputPath = path.join(workspace, 'output.mp4');
  await mediaTools.muxDubbedVideo(sourcePath, timeline.timelinePath, outputPath, 2);
  const metadata = await mediaTools.validateDubbedVideo(outputPath, 2);
  assert.equal(metadata.hasVideo, true);
  assert.equal(metadata.hasAudio, true);
});

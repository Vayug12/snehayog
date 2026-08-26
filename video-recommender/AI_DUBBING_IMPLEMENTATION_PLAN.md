# AI Dubbing Implementation Plan

Status: implementation-ready design  
Target: Vayug backend channel-backfill script (API and Flutter integration later)\
Constraint: no AI model inference on the developer or user device (8 GB RAM friendly)  
Primary providers: Groq cloud STT + Microsoft Azure Translator + Microsoft Edge online TTS

## 1. Goal

Add Hindi/English dubbing for videos that already exist in MongoDB/R2, without downloading or running Whisper, translation, or TTS models locally.

The current prototype is a standalone channel backfill command. It must not be connected to the existing video-upload pipeline, upload controllers, R2 upload events, Flutter requests, or an automatic post-upload hook. API/queue integration remains a later production phase.

The current finished flow must:

1. Accept a creator channel name and target language.
2. Resolve the channel through `User.name`, then fetch its existing videos through `Video.uploader`.
3. Skip videos that already have a valid `dubbedUrls.<language>` value unless `--force` is explicitly supplied.
4. Reuse each video's canonical MP4 from Cloudflare R2.
5. Extract and compress speech audio with FFmpeg.
6. Transcribe speech remotely with Groq Whisper and retain segment timestamps.
7. Translate timestamped segments through Microsoft Azure Translator.
8. Generate one Edge TTS clip per translated segment.
9. Align the clips to the original timeline.
10. Mux the dubbed track with the original video.
11. Upload the result to R2 and save its URL in MongoDB.
12. Remove every local source copy, chunk, transcript artifact, TTS clip, and output file after each video, on both success and failure.

## 2. Key architecture decision

The current implementation is a standalone Node script in the existing backend. It reuses backend models, R2 storage, provider adapters, and media services, but it is not called by the upload pipeline or Flutter.

If public dubbing is added later, its API and job orchestration should also be implemented in the existing Node/Express backend, not duplicated inside the Python recommendation service.

Reasons:

- The backend already owns authentication, MongoDB `Video` records, R2 storage, Redis/BullMQ, and Flutter API routes.
- Existing Flutter code already calls `/dubbing/request` and `/dubbing/status/:taskId`.
- The backend already has partial transcription, translation, Edge TTS, and `dubbedUrls` support.
- Adding a second public dubbing API to `video-recommender` would create duplicate provider, authentication, storage, and job-state logic.

This file lives in `video-recommender` as the implementation specification. The recommendation service can consume transcript metadata later, but it should not own the first production dubbing pipeline.

## 3. Current-state audit

### Already present

- `../backend/routes/dubbingRoutes.js` exposes low-level `/transcribe`, `/translate`, `/synthesize`, and engine endpoints.
- `../backend/controllers/video/dubbingController.js` implements those low-level calls.
- `../backend/services/aiService.js` provides a pluggable AI facade.
- `../backend/services/aiService/HuggingFaceAIEngine.js` already invokes Edge TTS.
- `../backend/services/videoProcessing/steps/GeminiSummarizationStep.js` already contains a Groq Whisper example.
- `../backend/services/uploadServices/cloudflareR2Service.js` uploads generic files to R2.
- `../backend/models/Video.js` contains `dubbedUrls: Map<String, String>`.
- `../frontend/lib/features/video/dubbing/data/services/dubbing_service.dart` already implements server-side request and status polling.
- The Docker image already installs FFmpeg, Python 3, and `edge-tts`.

### Gaps and risks to fix

- Flutter expects `POST /dubbing/request` and `GET /dubbing/status/:taskId`, but the backend does not implement them.
- `backend/package.json` references `workers/dubbingWorker.js`, but that file does not exist.
- `fly.toml` has no separate dubbing process group.
- Groq STT logic is embedded in a summarization step instead of a reusable provider.
- Current transcription returns one large string and discards segment timestamps.
- Current translation translates the full transcript in one call, losing timing and context boundaries.
- Current TTS generates one large audio file, so speech cannot align reliably with the video.
- Edge TTS is launched through a shell-interpolated command. This creates quoting and command-injection risk.
- The current TTS output path ends in `.wav`, although Edge TTS normally emits compressed audio. The container and extension must match.
- The current Flutter "on-device" implementation downloads and processes the video with mobile FFmpeg. This is unsuitable for low-end phones and duplicates backend work.
- Expensive low-level routes use passive authentication. Dubbing must require a valid user and quota checks.
- The current provider switch mutates a process-global engine at runtime. In a multi-process deployment it will be inconsistent.
- Current in-memory provider quotas do not coordinate between app and worker processes.
- Existing Groq quota comments are stale. Limits must be configurable and provider `429` responses must be authoritative.

## 4. Target architecture

```text
npm run dub:channel -- --channel="Channel Name" --target=hi
    |
    v
Resolve User.name -> query Video.uploader -> preflight summary/confirmation
    |
    v
Process one existing video at a time (concurrency 1)
    |
    +--> valid Video.dubbedUrls.hi exists -> skip/cache hit
    |
    +--> R2 canonical MP4 -> isolated local temp workspace
                               |
             +-----------------+------------------+
             |                 |                  |
             v                 v                  v
      Groq Whisper STT   Azure Translator     Edge TTS
             +-----------------+------------------+
                               |
                               v
                     FFmpeg alignment/mux
                               |
                               v
              validate -> R2 upload -> Video.dubbedUrls.hi
                               |
                               v
               finally: delete the complete local workspace
```

Provider boundaries must be explicit. Swapping STT or translation later should not change the batch runner, media, or database code.

## 5. Scope

### MVP

- Standalone channel backfill script only; no upload-pipeline integration.
- Command: `npm run dub:channel -- --channel="<creator name>" --target=<hi|en>`.
- Resolve the creator using an exact, case-insensitive `User.name` match.
- Query all existing videos with `Video.uploader = creator._id`.
- Process videos sequentially with concurrency `1` to bound local disk and memory usage.
- Source languages: automatic detection, optimized for Hindi and English.
- Target languages: Hindi and English.
- STT: `whisper-large-v3-turbo` through Groq.
- Translation: Microsoft Azure Translator Text API (`en` <-> `hi`).
- TTS voices:
  - Hindi: `hi-IN-SwaraNeural`
  - English: `en-US-AriaNeural`
- Segment-level synchronization.
- One dubbed MP4 per `(videoId, targetLanguage)`.
- Console progress, interrupt-safe cleanup, resumable cache skipping, and R2 persistence.
- Maximum video duration configured for the free-tier budget; begin with 10 minutes.

### Not in MVP

- Automatic dubbing during or after video upload.
- Changes to the existing upload pipeline/controllers or R2 upload events.
- Flutter-triggered dubbing, public dubbing request/status APIs, BullMQ, or a dedicated dubbing worker.
- Voice cloning or impersonation.
- Speaker-specific voices.
- Lip synchronization.
- Real-time/live dubbing.
- Local Whisper/NLLB/other model execution.
- Reliable separation of dialogue from background music.
- Arbitrary URLs supplied directly by clients.
- Unlimited free usage.

### Channel batch command

Add this backend script entry:

```json
{
  "scripts": {
    "dub:channel": "node scripts/dub-channel.js"
  }
}
```

Primary usage:

```bash
npm run dub:channel -- --channel="Snehayog" --target=hi
```

On Windows PowerShell use `npm.cmd run dub:channel -- ...`; the `npm.ps1` wrapper can consume arguments after `--` instead of forwarding them to the Node script.

Useful operational options:

```bash
# Show the channel, selected videos, cache hits, and estimated minutes; do not dub
npm run dub:channel -- --channel="Snehayog" --target=hi --dry-run

# Regenerate even when the same-language dubbed URL already exists
npm run dub:channel -- --channel="Snehayog" --target=hi --force

# Non-interactive execution after preflight validation
npm run dub:channel -- --channel="Snehayog" --target=hi --yes

# Safe partial rollout
npm run dub:channel -- --channel="Snehayog" --target=hi --limit=5
```

Command behavior:

1. Require `--channel` and allow only target codes from the configured allowlist (`hi`, `en`).
2. Match `User.name` exactly after trimming, case-insensitively. Do not use a loose substring match.
3. If more than one user has the same name, abort without processing and print their IDs. Support `--channel-id=<userId>` as the unambiguous fallback.
4. Fetch the channel's videos in one database query, sorted by `_id` or `uploadedAt` for deterministic reruns. Do not query the database once per video.
5. Print total videos, cache hits, eligible videos, missing canonical MP4s, total duration, and the target language.
6. Prompt `Start dubbing? (y/N)` unless `--yes` or `--dry-run` is present.
7. Process eligible videos one at a time. A failure is recorded in the final summary and the next video continues unless `--fail-fast` is supplied.
8. Treat `Video.dubbedUrls.<target>` as the resume checkpoint. Rerunning the same command skips completed videos without provider calls.
9. Exit non-zero if channel resolution/preflight fails, and print a final completed/skipped/failed/not-suitable summary.

### Local workspace and cleanup contract

The batch may process many videos, but it must keep artifacts for only one video at a time.

1. Create one random isolated directory per video under `DUBBING_TEMP_ROOT`, for example `/tmp/vayug-dubbing/dub-<random>`.
2. Use an outer `try/finally` around the complete per-video pipeline. The `finally` block recursively deletes that exact validated workspace on success, provider failure, media failure, upload failure, DB failure, or skip after download.
3. Delete large intermediates as soon as their next stage no longer needs them:
   - audio chunks immediately after STT normalization;
   - individual TTS MP3 files after the full dubbed timeline is created;
   - extracted audio after transcription;
   - muxed output only after R2 upload, media validation, and MongoDB update complete.
4. Register `SIGINT`, `SIGTERM`, `uncaughtException`, and `unhandledRejection` handlers that stop accepting new videos, clean the active workspace, close MongoDB, and exit. Signal cleanup must be idempotent.
5. On startup, remove only stale job directories older than `DUBBING_STALE_TEMP_HOURS` under the resolved temp root. Validate that every target is a direct child of that root; never delete the temp root, workspace root, home directory, or an arbitrary computed path.
6. Default concurrency remains `1`. Do not begin the next download until the previous video's workspace is removed.
7. Optionally fail preflight when available local disk is below `DUBBING_MIN_FREE_DISK_MB`.
8. Cleanup applies only to local temporary artifacts. Never delete the source R2 object, an existing dubbed R2 object, or the newly published object.
9. If a new dub replaces an old URL under `--force`, upload to a new versioned R2 key and update MongoDB only after validation. Remote orphan cleanup is a separate controlled task.

## 6. Provider strategy

| Capability | MVP provider | Local model | Fallback |
|---|---|---:|---|
| Speech-to-text | Groq Whisper API | No | Existing Hugging Face adapter, feature-flagged |
| Translation | Microsoft Azure Translator Text API | No | Feature-flagged provider adapter later |
| Text-to-speech | `edge-tts` online service | No | Azure Speech for production SLA |
| Media processing | FFmpeg | No AI model | None |
| Storage | Cloudflare R2 | No | Existing storage abstraction |
| Batch orchestration | Standalone Node channel script, concurrency 1 | No | BullMQ worker later |

Free tiers are quotas, not guarantees. Do not encode provider limits as product promises. Read limits from environment configuration, record provider `429`/`Retry-After` headers, and provide an admin kill switch.

Useful current references:

- Groq speech-to-text: <https://console.groq.com/docs/speech-to-text>
- Groq rate limits: <https://console.groq.com/docs/rate-limits>
- Azure Translator pricing: <https://azure.microsoft.com/pricing/details/cognitive-services/translator/>
- Azure Translator limits: <https://learn.microsoft.com/azure/ai-services/translator/service-limits>
- Edge TTS project: <https://github.com/rany2/edge-tts>

## 7. New backend module layout

```text
backend/
  services/dubbing/
    DubbingPipeline.js
    languageConfig.js
    tempWorkspace.js
    providers/
      ISttProvider.js
      ITranslationProvider.js
      ITtsProvider.js
      GroqSttProvider.js
      AzureTranslationProvider.js
      EdgeTtsProvider.js
    media/
      audioExtractor.js
      audioChunker.js
      segmentAligner.js
      videoMuxer.js
    validation/
      segmentSchemas.js
  scripts/
    dub-channel.js
    edge_tts_synthesize.py
  tests/
    dubbing/
```

`DubbingJob`, request/status routes, BullMQ queue, and `dubbingWorker.js` belong to the later public API phase, not the current channel-backfill MVP.

Do not add Groq-specific code to controllers. Controllers validate requests and delegate to the queue/service only.

## 8. Canonical segment contract

All stages must exchange structured segments instead of plain transcript strings.

```js
{
  id: 12,
  startMs: 18420,
  endMs: 21980,
  sourceLanguage: "en",
  sourceText: "Today we will learn how this works.",
  translatedText: "आज हम समझेंगे कि यह कैसे काम करता है।",
  voice: "hi-IN-SwaraNeural",
  generatedAudioPath: null,
  generatedDurationMs: null,
  finalDurationMs: 3560
}
```

Validation rules:

- `id` is unique and monotonically increasing.
- `0 <= startMs < endMs <= videoDurationMs`.
- Source text must be non-empty after trimming.
- Translation must preserve every input segment ID exactly once.
- Provider output may not change timestamps.
- Text and provider payload sizes have explicit limits.
- Unknown fields from providers are discarded.

## 9. Database design

This `DubbingJob` model is deferred until the later API/queue phase. The current channel script uses `Video.dubbedUrls.<target>` as its durable completion checkpoint and prints a per-run summary.

Create `backend/models/DubbingJob.js`.

Recommended fields:

```js
{
  _id,
  videoId,
  requestedBy,
  sourceLanguage,
  targetLanguage,
  voice,
  status,
  progress,
  currentStage,
  attempts,
  bullJobId,
  sourceVideoKey,
  outputR2Key,
  dubbedUrl,
  fromCache,
  transcriptSegmentCount,
  providerUsage: {
    sttAudioSeconds,
    translationInputTokens,
    translationOutputTokens,
    ttsCharacters
  },
  error: {
    code,
    safeMessage,
    retryable
  },
  startedAt,
  completedAt,
  expiresAt,
  createdAt,
  updatedAt
}
```

Indexes:

- Unique partial index for active/completed `(videoId, targetLanguage)` jobs.
- Index on `requestedBy, createdAt` for quota enforcement.
- TTL index on `expiresAt` for old failed/cancelled job records; completed records may be retained for audit.

Allowed states:

```text
queued
downloading
extracting_audio
transcribing
translating
synthesizing
aligning
muxing
uploading
completed
not_suitable
failed
cancelled
```

State changes must be monotonic except an explicit retry returning a failed job to `queued`.

## 10. API contract

This entire API section is deferred. The current MVP is invoked only through `npm run dub:channel` and does not expose a Flutter/public request endpoint.

### Request a dub

`POST /api/dubbing/request`

Authentication: required.

```json
{
  "videoId": "MongoObjectId",
  "targetLanguage": "hindi",
  "voice": "hi-IN-SwaraNeural"
}
```

Behavior:

- Validate `videoId`, language, voice, ownership/access, duration, and feature flag.
- Never accept a source file path or arbitrary remote URL from the client.
- If `Video.dubbedUrls[targetLanguage]` exists, return `200 completed` with `fromCache: true`.
- If an equivalent job is active, return that task ID instead of creating a duplicate.
- Otherwise create a `DubbingJob`, enqueue it with deterministic ID `dub:<videoId>:<targetLanguage>`, and return `202`.

```json
{
  "taskId": "...",
  "status": "queued",
  "progress": 2,
  "language": "hindi"
}
```

### Read status

`GET /api/dubbing/status/:taskId`

- Require authentication and verify that the caller can access the video/job.
- Return only safe errors; never expose API keys, command strings, provider response bodies, or local paths.

```json
{
  "taskId": "...",
  "videoId": "...",
  "status": "translating",
  "progress": 45,
  "language": "hindi",
  "dubbedUrl": null,
  "error": null
}
```

### Cancel a job (recommended)

`DELETE /api/dubbing/jobs/:taskId`

- Mark cancellation intent.
- Remove a waiting job when possible.
- An active worker must check cancellation between pipeline stages.
- Always clean its temporary workspace.

### Low-level routes

Keep `/transcribe`, `/translate`, and `/synthesize` only for authenticated admin/testing use, or remove them after end-to-end jobs work. Do not expose them as unrestricted free provider proxies.

The engine mutation endpoint must be admin-only. Prefer environment variables and deployment restart over process-local runtime switching.

## 11. Pipeline details

### Stage A: resolve and download source

1. Read `Video` by ID.
2. Prefer `canonicalMp4Key`/`canonicalMp4Url`; do not try to dub an HLS playlist if a canonical MP4 exists.
3. Download only from the configured R2/CDN origin.
4. Reject redirects to unapproved hosts to prevent SSRF.
5. Write into an isolated temporary directory created for the job.
6. Use `ffprobe` to verify duration, audio stream presence, and expected container.

If there is no audio stream or speech is empty, finish as `not_suitable` rather than `failed`.

### Stage B: extract and chunk audio

Recommended FFmpeg target:

```text
mono, 16 kHz, FLAC, audio only
```

Conceptual command:

```bash
ffmpeg -i input.mp4 -vn -map 0:a:0 -ac 1 -ar 16000 -c:a flac speech.flac
```

Rules:

- Invoke FFmpeg with argument arrays (`spawn`/`execFile`), never shell-built strings.
- Set a timeout and capture bounded stderr.
- Keep each Groq free-tier upload below a configurable safe threshold, default 24 MB.
- Chunk large audio into overlapping windows. Start with 8-10 minute chunks and 500 ms overlap.
- Add each chunk's absolute offset to returned segment timestamps.
- Deduplicate overlapping boundary text.

### Stage C: Groq transcription

Provider request:

- Endpoint: Groq OpenAI-compatible audio transcription endpoint.
- Model: environment-configured, default `whisper-large-v3-turbo`.
- Response format: `verbose_json`.
- Timestamp granularity: `segment`.
- Language: omit for automatic detection unless the video already has trusted language metadata.

Do not repeat the current summarization behavior that forces `language=hi`; that will harm English/source-language detection.

Normalize every provider response into the canonical segment contract. Reject a successful HTTP response that has malformed or empty segments.

### Stage D: Microsoft Azure Translator

Use Azure Translator Text API v3 with `from=en&to=hi` or `from=hi&to=en`. If the source language is not trusted, omit `from` and record Azure's detected language.

Send multiple segments as the request JSON array instead of making one request per segment. Keep every request below both Azure limits: at most 1,000 array elements and 50,000 total characters; use a lower configurable safety threshold such as 45,000 characters.

Segment/timestamp rules:

1. Keep segment IDs and timestamps locally; send only each segment's `sourceText` in the corresponding request-array position.
2. Require exactly one returned translation for every input array item and map it back by array position.
3. Reject empty, missing, extra, or malformed results. Never allow Azure output to modify timestamps.
4. Retry `429`, transient network errors, and `5xx` responses at most three times using `Retry-After` when present. Do not retry `400`, `401`, or `403`.
5. Count source characters sent and record them in the run summary so the Azure F0 monthly allowance can be monitored.
6. Translating the same source into multiple target languages multiplies billable characters; this command processes only the explicitly requested target.

Azure standard translation is not prompt-driven, so it cannot reliably obey a request such as "make this shorter." Duration fitting must be handled conservatively during TTS/alignment. An optional LLM concise-retranslation fallback is a later feature, not part of the zero-cost MVP.

### Stage E: Edge TTS synthesis

Implement a small Python wrapper around the `edge_tts` library rather than interpolating text into a shell command.

Node should invoke it with `spawn` or `execFile` and safe argument boundaries. Prefer a temporary UTF-8 JSON/text input file for long text.

Rules:

- Generate one MP3 per translated segment.
- Use a language-to-voice allowlist; never accept an arbitrary command-line voice value.
- Start with TTS concurrency `2` to avoid bursts.
- Retry transient network failures at most three times with exponential backoff and jitter.
- Do not retry authentication/input errors.
- Record generated clip duration using `ffprobe`.

Edge TTS is suitable for an MVP but is a community client for an online service without a production SLA. Keep `ITtsProvider` so Azure Speech can replace it later without changing the pipeline.

### Stage F: duration matching and timeline construction

For each segment:

1. Calculate `targetDuration = endMs - startMs`.
2. Ask Edge TTS for a reasonable initial speech rate based on text length and target duration.
3. Measure the generated clip.
4. Use FFmpeg `atempo` filters for final correction.
5. Chain `atempo` filters when the ratio falls outside one filter's supported range.
6. If a translation cannot fit within the configured intelligible rate limit, record a duration-mismatch warning and apply the deterministic MVP fallback; do not silently call another paid/LLM provider.
7. Pad short clips with silence; do not stretch them unnaturally to fill the whole window.

Create a full-duration dubbed audio timeline matching the source video duration. Handle gaps as silence. For MVP, resolve overlapping speech segments deterministically by trimming or shifting the lower-confidence segment and emit a metric.

### Stage G: mux

MVP audio modes:

- Default: replace the original audio track with the dubbed track.
- Optional experiment: mix original audio at a low volume beneath the dub.

Replacing is safer for MVP because the original track contains dialogue; simply lowering it can produce two simultaneous voices. True background preservation requires source separation and belongs in a later phase.

Requirements:

- Copy the video stream when codec/container compatibility allows.
- Encode dubbed audio as AAC.
- Preserve the full video duration; do not let `-shortest` truncate a video when TTS is shorter.
- Produce a standard MP4 with fast-start metadata.
- Verify output duration, video stream, audio stream, and non-zero file size before upload.

### Stage H: R2 upload and persistence

1. Upload to a versioned immutable key such as `dubbed/<videoId>/<language>/<sourceFingerprint>/<pipelineVersion>-<runId>.mp4`; never overwrite an existing R2 object in place.
2. Reuse `cloudflareR2Service.uploadFileToR2`.
3. Set `Video.dubbedUrls.<language>` only after upload and media validation succeed.
4. Count the video as completed only after the MongoDB update succeeds.
5. If upload succeeds but DB update fails, retry the DB operation before treating the job as failed.
6. Delete the local workspace in `finally`.

## 12. Queue and worker behavior

Deferred until the later public API phase. The current MVP uses the standalone channel script with sequential concurrency `1`.

Create a dedicated BullMQ queue called `video-dubbing`.

Recommended job options:

```js
{
  jobId: `dub:${videoId}:${targetLanguage}`,
  attempts: 3,
  backoff: { type: "exponential", delay: 10000 },
  removeOnComplete: { age: 86400, count: 100 },
  removeOnFail: { age: 604800, count: 500 }
}
```

Worker defaults:

- Concurrency: `1` on the current 2 GB shared worker.
- One isolated temp workspace per job.
- Progress update after every stage.
- Heartbeat during FFmpeg and provider waits.
- Graceful shutdown: finish or safely release the current job.
- Cancellation check between every provider/media stage.

Simplest deployment is to let the existing `worker` process consume both video-processing and video-dubbing queues. Only add a separate Fly process group after measurements show contention. A separate dubbing process requires explicit `fly.toml` process and VM entries; the existing `worker:dubbing` package script alone does not create a running machine.

## 13. Rate limiting and quota control

The current script has only one operator and runs one video at a time, so Redis quota counters are not required for the MVP.

Minimum controls:

- Preflight total eligible video count and audio duration before confirmation.
- Maximum source duration per video.
- Channel batch `--limit` for staged runs.
- One-video concurrency cap.
- Groq request/audio quota handling.
- Azure source-character accounting and monthly usage visibility.
- Edge TTS concurrency cap within a video.
- Provider backoff, bounded retries, and an emergency environment kill switch.

Treat provider `429`, `Retry-After`, and rate-limit headers as authoritative. Never retry forever or create a retry storm. Redis-backed per-user quotas are deferred with the public API.

## 14. Configuration

Add configuration validation at startup:

```dotenv
DUBBING_BATCH_ENABLED=true

GROQ_API_KEY=
DUBBING_STT_PROVIDER=groq
DUBBING_STT_MODEL=whisper-large-v3-turbo
DUBBING_TRANSLATION_PROVIDER=azure
AZURE_TRANSLATOR_KEY=
AZURE_TRANSLATOR_REGION=
AZURE_TRANSLATOR_ENDPOINT=https://api.cognitive.microsofttranslator.com
DUBBING_TTS_PROVIDER=edge

DUBBING_MAX_VIDEO_SECONDS=600
DUBBING_MAX_AUDIO_UPLOAD_MB=24
DUBBING_SCRIPT_CONCURRENCY=1
DUBBING_TTS_CONCURRENCY=2
DUBBING_TEMP_ROOT=/tmp/vayug-dubbing
DUBBING_STALE_TEMP_HOURS=24
DUBBING_MIN_FREE_DISK_MB=2048
DUBBING_PIPELINE_VERSION=v1
DUBBING_OUTPUT_MODE=replace
```

Provider model names and quotas must remain configurable because availability and free-tier limits can change.

Do not log secrets. Redact provider response text if it could contain credentials, local paths, or user content.

## 15. Security and privacy checklist

- [ ] Require `verifyToken` for job creation, status, and cancellation.
- [ ] Check caller access to the `Video` record.
- [ ] Resolve media from trusted database/R2 fields, never an arbitrary client URL.
- [ ] Validate object IDs, language, voice, file size, duration, MIME type, and actual media streams.
- [ ] Use `spawn`/`execFile` argument arrays for FFmpeg, ffprobe, and Python.
- [ ] Never put transcript text directly into a shell command.
- [ ] Use randomly created job directories under one validated temp root.
- [ ] Prevent path traversal in video IDs, language codes, filenames, and R2 keys.
- [ ] Delete source copies, chunks, transcripts, and TTS clips after completion/failure.
- [ ] Do not log complete transcripts by default.
- [ ] Rate-limit low-level provider routes or restrict them to admins.
- [ ] Document that audio leaves Vayug infrastructure for Groq/Edge processing.
- [ ] Add user/content consent rules before supporting voice cloning in any later version.

## 16. Error policy

Map internal failures to stable codes:

| Code | Retryable | Meaning |
|---|---:|---|
| `VIDEO_NOT_FOUND` | No | Database video is absent |
| `VIDEO_ACCESS_DENIED` | No | User cannot access/request dubbing |
| `NO_AUDIO_STREAM` | No | Video has no audio |
| `NO_SPEECH` | No | STT returned no usable speech |
| `VIDEO_TOO_LONG` | No | Product limit exceeded |
| `PROVIDER_RATE_LIMITED` | Yes | Provider returned 429 |
| `PROVIDER_UNAVAILABLE` | Yes | Timeout or provider 5xx |
| `INVALID_STT_RESPONSE` | Maybe | STT schema was invalid |
| `INVALID_TRANSLATION_RESPONSE` | Maybe | IDs/schema were invalid |
| `TTS_FAILED` | Yes | Edge TTS network/synthesis failure |
| `MEDIA_PROCESSING_FAILED` | Maybe | FFmpeg/ffprobe failure |
| `UPLOAD_FAILED` | Yes | R2 upload failure |
| `CANCELLED` | No | User/system cancelled job |

Never retry `400`, `401`, `403`, invalid media, unsupported language, or access errors. Retry `429` according to `Retry-After` and retry transient `5xx`/network failures at most three times.

## 17. Testing plan

### Unit tests

- Segment normalization and timestamp offsetting.
- Chunk overlap deduplication.
- Translation batch construction and strict ID validation.
- Invalid/missing/duplicate translation IDs.
- Voice and language allowlists.
- Duration ratio and `atempo` chain generation.
- State-transition validation.
- Safe R2 key construction.
- Error classification and retry decisions.
- Temp workspace cleanup on success, failure, and cancellation.

### Provider contract tests

Mock HTTP/TTS processes and cover:

- Success.
- Empty body.
- Malformed JSON.
- `401`, `429` with `Retry-After`, `500`, timeout, and connection reset.
- Partial segment output.
- Edge TTS clip not created or zero-byte clip.

Live provider tests must be opt-in and skipped unless dedicated test keys are present.

### Integration tests

- Exact channel name resolves the correct `User` and queries videos by `Video.uploader`.
- Duplicate channel names abort and require `--channel-id`.
- `--dry-run` makes no provider, R2-write, or MongoDB-write calls.
- Existing same-language `dubbedUrls` values are skipped unless `--force` is set.
- Completed processing updates `Video.dubbedUrls.<target>` only after validation and R2 upload.
- Failed job does not publish a partial URL.
- Success, provider failure, FFmpeg failure, DB failure, `SIGINT`, and `SIGTERM` clean the active local workspace.
- The next video does not start until cleanup for the previous video finishes.
- Two target languages can coexist for one video.
- A rerun resumes by skipping already completed videos.

### Media tests

Use small checked-in/generated fixtures:

- English speech with silence gaps.
- Hindi speech.
- No-audio video.
- Music-only/empty-speech video.
- Long-enough fixture to trigger chunking.
- Overlapping speech fixture.

Assertions:

- Output MP4 is playable.
- Video duration differs by no more than an agreed tolerance.
- Audio begins near expected segment timestamps.
- Output contains exactly one video stream and at least one audio stream.
- No output is truncated when dub audio is shorter than video.

### End-to-end test

Run `dub:channel` with `--limit=1` for one short existing video through real Groq, Azure Translator, and Edge TTS. Upload to a staging R2 prefix, verify `Video.dubbedUrls.<target>`, verify the local temp root is empty, play the URL, and rerun to confirm a cache skip without provider calls.

## 18. Observability

Log structured metadata only:

```text
runId, channelId, videoId, stage, progress, durationMs,
provider, model, attempt, audioSeconds, segmentCount,
azureSourceCharacters, inputBytes, outputBytes, errorCode, cleanupStatus
```

Metrics:

- Videos selected/completed/skipped/failed/not-suitable/interrupted.
- Total batch time and per-video completion time.
- Duration per pipeline stage.
- Provider `429`, timeout, and error counts.
- Audio minutes and translation/TTS usage.
- Cache-hit ratio.
- Segment duration mismatch percentiles.
- Temp/R2 cleanup failures.

Never place API keys, full transcript text, translated text, signed URLs, or raw provider error payloads in logs/APM attributes.

## 19. Implementation phases

### Phase 0: channel runner and cleanup foundation

- [ ] Add `backend/scripts/dub-channel.js` and the `npm run dub:channel` package script.
- [ ] Implement exact channel-name resolution with duplicate-name failure and `--channel-id` fallback.
- [ ] Query all selected videos once and implement `--dry-run`, confirmation, `--limit`, `--yes`, `--force`, and final summary.
- [ ] Implement per-video random temp workspaces, guarded recursive cleanup, startup stale-workspace sweep, and signal cleanup.
- [ ] Enforce concurrency `1`, disk-space preflight, cache skips, and deterministic ordering.

Exit criterion: a mocked channel batch selects the expected videos, skips cached entries, never holds two workspaces, and leaves the temp root empty after success, failure, and interruption.

### Phase 1: Groq STT provider

- [ ] Extract Groq code from `GeminiSummarizationStep` into `GroqSttProvider`.
- [ ] Add audio extraction, size validation, and chunking.
- [ ] Request verbose segment timestamps.
- [ ] Remove forced Hindi language.
- [ ] Add normalization and boundary deduplication.
- [ ] Reuse this provider from video summarization to remove duplicate Groq logic.

Exit criterion: English and Hindi fixtures return valid absolute timestamped segments without local model inference.

### Phase 2: Azure Translator provider

- [ ] Add `AzureTranslationProvider` using Translator Text API v3.
- [ ] Batch segment texts within the 1,000-element and 50,000-character request limits.
- [ ] Map responses back to local segment IDs by array position and preserve timestamps.
- [ ] Validate response cardinality and handle `401`, `429`, `5xx`, timeout, and malformed responses.
- [ ] Record Azure source-character usage per video and per batch run.

Exit criterion: all source segments have one valid target segment and unchanged timestamps.

### Phase 3: TTS alignment and mux

- [ ] Add safe Edge TTS Python wrapper.
- [ ] Generate per-segment MP3 clips.
- [ ] Measure and fit clips to their time windows.
- [ ] Construct a video-length dubbed timeline.
- [ ] Mux, validate, and preserve full duration.
- [ ] Upload to staging R2.

Exit criterion: a short test video plays with understandable, approximately synchronized Hindi/English speech.

### Phase 4: channel backfill validation

- [ ] Run one video using `--limit=1`, inspect sync/playback, and verify cleanup.
- [ ] Rerun the same command and confirm it skips the cached dub without provider calls.
- [ ] Run a small multi-video batch and confirm sequential processing and final summary counts.
- [ ] Verify a failed video is cleaned and does not block subsequent videos.
- [ ] Confirm existing valid URLs are never overwritten without `--force`.

Exit criterion: the requested channel's eligible existing videos can be safely backfilled and the local temp root returns to its pre-run state after every video.

### Phase 5: later public API/worker integration (out of current scope)

- [ ] Add `DubbingJob`, BullMQ, request/status/cancel routes, and Flutter polling only when requested later.
- [ ] Redis-backed quota tracking.
- [ ] Per-user daily minute limit.
- [ ] Global concurrency and queue-pressure controls.
- [ ] Provider backoff/circuit breaker.
- [ ] Feature flag and kill switch.
- [ ] Structured metrics and alerts.
- [ ] Temp-file/R2 orphan cleanup job.
- [ ] Load, abuse, privacy, and cost review.
- [ ] Decide separately whether automatic upload-pipeline integration is ever desirable; do not add it implicitly.

Exit criterion: error rates, queue time, provider consumption, and storage growth remain within agreed thresholds.

## 20. MVP acceptance criteria

- [ ] No Whisper, translation, or TTS model is downloaded to the PC, phone, API machine, or worker.
- [ ] A 5-minute English or Hindi video can be dubbed into the other language.
- [ ] Segment timestamps survive STT, translation, and TTS stages.
- [ ] Output video duration is preserved and not truncated.
- [ ] Existing `dubbedUrls.<target>` values prevent repeat provider calls unless `--force` is supplied.
- [ ] Rerunning a channel command resumes through persisted `dubbedUrls` cache entries.
- [ ] Provider/network failures yield safe, retryable job errors.
- [ ] Temporary media is removed in every terminal state.
- [ ] The script resolves one unambiguous creator and never processes another channel accidentally.
- [ ] The output URL is persisted and returned in normal video serialization.
- [ ] Only one video workspace exists at a time, and all local artifacts are deleted after success, failure, or interruption.
- [ ] No changes are made to the existing video-upload pipeline.

## 21. Later improvements

- Add more Edge/Azure voices and languages through configuration.
- Detect speakers and assign multiple stock voices.
- Add cloud-based dialogue/background separation.
- Publish separate audio tracks/HLS renditions instead of separate MP4 files.
- Add WebSocket/SSE progress to replace polling.
- Add authenticated request/status APIs and a BullMQ worker if user-triggered dubbing is needed.
- Consider upload-pipeline integration only as a separately approved future feature.
- Cache transcripts so recommendation, captions, search, and dubbing share one STT result.
- Store transcript/translation artifacts in private R2 with retention rules.
- Evaluate Azure Speech when uptime/SLA matters more than zero-cost prototyping.
- Add human review/editing of subtitles before TTS for creator-controlled releases.

## 22. Recommended first implementation slice

Implement one vertical slice before generalizing:

1. Run `npm run dub:channel -- --channel="<name>" --target=hi --limit=1` for one existing English MP4 shorter than two minutes.
2. Resolve the creator and video from MongoDB without touching the upload pipeline.
3. Create one isolated temp workspace.
4. Run Groq timestamped STT and Azure English-to-Hindi segment translation.
5. Generate `hi-IN-SwaraNeural` segment TTS and replacement-audio MP4 mux.
6. Validate and upload to a versioned staging R2 key.
7. Update `Video.dubbedUrls.hi` only after successful upload/validation.
8. Delete the complete local workspace in `finally` and confirm the temp root is empty.
9. Rerun the same command and confirm it skips the cached video.

Once that path is reliable and covered by tests, remove `--limit=1`, process a small channel batch sequentially, then add chunking, Hindi-to-English, more voices, and longer videos.

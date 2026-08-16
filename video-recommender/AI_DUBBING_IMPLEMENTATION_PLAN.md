# AI Dubbing Implementation Plan

Status: implementation-ready design  
Target: Vayug backend and Flutter client  
Constraint: no AI model inference on the developer or user device (8 GB RAM friendly)  
Primary providers: Groq cloud STT + Groq cloud translation + Microsoft Edge online TTS

## 1. Goal

Add asynchronous Hindi/English video dubbing without downloading or running Whisper, translation, or TTS models locally.

The finished flow must:

1. Accept a `videoId` and target language.
2. Reuse the video's canonical MP4 from Cloudflare R2.
3. Extract and compress speech audio with FFmpeg.
4. Transcribe speech remotely with Groq Whisper and retain segment timestamps.
5. Translate timestamped segments remotely with a Groq-hosted LLM.
6. Generate one Edge TTS clip per translated segment.
7. Align the clips to the original timeline.
8. Mux the dubbed track with the original video.
9. Upload the result to R2 and save its URL in MongoDB.
10. Expose job progress to the existing Flutter polling client.

## 2. Key architecture decision

The public dubbing API and job orchestration should be implemented in the existing Node/Express backend, not duplicated inside the Python recommendation service.

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
Flutter client
    |
    | POST /api/dubbing/request
    v
Express API -- MongoDB DubbingJob -- Redis/BullMQ queue
                                      |
                                      v
                               Dubbing worker
                                      |
              +-----------------------+-----------------------+
              |                       |                       |
              v                       v                       v
       Groq Whisper STT       Groq LLM translation       Edge TTS
              |                       |                       |
              +---------- timestamped segments --------------+
                                      |
                                      v
                              FFmpeg alignment/mux
                                      |
                                      v
                           Cloudflare R2 + Video.dubbedUrls
```

Provider boundaries must be explicit. Swapping STT or translation later should not change controller, queue, media, or database code.

## 5. Scope

### MVP

- Source languages: automatic detection, optimized for Hindi and English.
- Target languages: Hindi and English.
- STT: `whisper-large-v3-turbo` through Groq.
- Translation: configurable Groq chat model.
- TTS voices:
  - Hindi: `hi-IN-SwaraNeural`
  - English: `en-US-AriaNeural`
- Segment-level synchronization.
- One dubbed MP4 per `(videoId, targetLanguage)`.
- Background processing, progress polling, cancellation-safe cleanup, and R2 persistence.
- Maximum video duration configured for the free-tier budget; begin with 10 minutes.

### Not in MVP

- Voice cloning or impersonation.
- Speaker-specific voices.
- Lip synchronization.
- Real-time/live dubbing.
- Local Whisper/NLLB/other model execution.
- Reliable separation of dialogue from background music.
- Arbitrary URLs supplied directly by clients.
- Unlimited free usage.

## 6. Provider strategy

| Capability | MVP provider | Local model | Fallback |
|---|---|---:|---|
| Speech-to-text | Groq Whisper API | No | Existing Hugging Face adapter, feature-flagged |
| Translation | Groq chat completion | No | Existing OpenAI adapter if configured |
| Text-to-speech | `edge-tts` online service | No | Azure Speech for production SLA |
| Media processing | FFmpeg | No AI model | None |
| Storage | Cloudflare R2 | No | Existing storage abstraction |
| Jobs | BullMQ + Redis | No | None |

Free tiers are quotas, not guarantees. Do not encode provider limits as product promises. Read limits from environment configuration, record provider `429`/`Retry-After` headers, and provide an admin kill switch.

Useful current references:

- Groq speech-to-text: <https://console.groq.com/docs/speech-to-text>
- Groq rate limits: <https://console.groq.com/docs/rate-limits>
- Edge TTS project: <https://github.com/rany2/edge-tts>

## 7. New backend module layout

```text
backend/
  models/
    DubbingJob.js
  routes/
    dubbingRoutes.js
  controllers/video/
    dubbingController.js
  services/dubbing/
    DubbingPipeline.js
    dubbingQueue.js
    languageConfig.js
    tempWorkspace.js
    providers/
      ISttProvider.js
      ITranslationProvider.js
      ITtsProvider.js
      GroqSttProvider.js
      GroqTranslationProvider.js
      EdgeTtsProvider.js
    media/
      audioExtractor.js
      audioChunker.js
      segmentAligner.js
      videoMuxer.js
    validation/
      segmentSchemas.js
  scripts/
    edge_tts_synthesize.py
  workers/
    dubbingWorker.js
  tests/
    dubbing/
```

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

### Stage D: Groq translation

Translate batches of approximately 15-30 segments. Do not send one request per segment, and do not translate the entire video as one unstructured string.

Translation prompt requirements:

- Return JSON only.
- Preserve each `id` exactly once.
- Do not return or alter timestamps.
- Use natural spoken target language.
- Preserve names, brands, URLs, and technical vocabulary.
- Keep the translation concise enough for the original segment duration.
- Avoid commentary, markdown, transliteration unless requested, and added facts.

After each response:

1. Parse JSON strictly.
2. Compare output IDs with input IDs.
3. Reject missing, duplicate, or unknown IDs.
4. Retry malformed output once with a repair prompt.
5. Fail safely if the second response is invalid.

Pass a small glossary and one neighboring segment on each side when useful, but only write translations for the requested batch IDs.

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
6. If a translation still cannot fit intelligibly, mark the segment for concise retranslation once.
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

1. Upload to a deterministic immutable key such as `dubbed/<videoId>/<language>/<pipelineVersion>.mp4`.
2. Reuse `cloudflareR2Service.uploadFileToR2`.
3. Set `Video.dubbedUrls.<language>` only after upload and media validation succeed.
4. Mark the job `completed` only after the MongoDB update succeeds.
5. If upload succeeds but DB update fails, retry the DB operation before treating the job as failed.
6. Delete the local workspace in `finally`.

## 12. Queue and worker behavior

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

Use two layers:

1. User/product quota: protects the feature from abuse.
2. Provider quota: protects Groq/Edge limits and handles `429` responses.

Minimum controls:

- Daily dubbing minutes per user.
- Maximum source duration.
- Maximum active jobs per user.
- Global active job cap.
- Per-provider concurrency cap.
- Feature flag and emergency kill switch.

Provider quota counters must live in Redis, not process memory, because API and worker run in separate processes. Treat response headers and `Retry-After` as authoritative. Never retry forever or create a retry storm.

## 14. Configuration

Add configuration validation at startup:

```dotenv
DUBBING_FEATURE_ENABLED=false

GROQ_API_KEY=
DUBBING_STT_PROVIDER=groq
DUBBING_STT_MODEL=whisper-large-v3-turbo
DUBBING_TRANSLATION_PROVIDER=groq
DUBBING_TRANSLATION_MODEL=llama-3.1-8b-instant
DUBBING_TTS_PROVIDER=edge

DUBBING_MAX_VIDEO_SECONDS=600
DUBBING_MAX_AUDIO_UPLOAD_MB=24
DUBBING_WORKER_CONCURRENCY=1
DUBBING_TTS_CONCURRENCY=2
DUBBING_USER_DAILY_MINUTES=20
DUBBING_TEMP_ROOT=/tmp/vayug-dubbing
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

- Request creates one job.
- Duplicate request returns the active/cached job.
- Unauthorized user cannot request or inspect a job.
- Worker transitions through all stages.
- Completed job updates both `DubbingJob` and `Video.dubbedUrls`.
- Failed job does not publish a partial URL.
- Cancellation cleans local files.
- Two target languages can coexist for one video.
- App and worker share Redis-based quota state.

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

Run one short authorized video through real Groq + Edge TTS in staging, upload to a staging R2 prefix, play it in Flutter, and verify cached replay does not create another provider job.

## 18. Observability

Log structured metadata only:

```text
taskId, videoId, userIdHash, stage, progress, durationMs,
provider, model, attempt, audioSeconds, segmentCount,
inputBytes, outputBytes, errorCode
```

Metrics:

- Jobs requested/completed/failed/not-suitable/cancelled.
- Queue wait time and total completion time.
- Duration per pipeline stage.
- Provider `429`, timeout, and error counts.
- Audio minutes and translation/TTS usage.
- Cache-hit ratio.
- Segment duration mismatch percentiles.
- Temp/R2 cleanup failures.

Never place API keys, full transcript text, translated text, signed URLs, or raw provider error payloads in logs/APM attributes.

## 19. Implementation phases

### Phase 0: repair foundations

- [ ] Add this plan to the project documentation index if one exists.
- [ ] Confirm the existing frontend uses `ServerSideDubbingServiceImpl` for production builds.
- [ ] Add the missing `DubbingJob` model.
- [ ] Add the `video-dubbing` queue.
- [ ] Implement missing request/status routes expected by Flutter.
- [ ] Make engine/provider selection environment-based.
- [ ] Restrict low-level and engine administration routes.
- [ ] Replace shell-interpolated Edge TTS execution with a safe wrapper.
- [ ] Correct output extensions and media content types.

Exit criterion: a mocked job can move from `queued` to `completed`, and Flutter polling receives every state.

### Phase 1: Groq STT provider

- [ ] Extract Groq code from `GeminiSummarizationStep` into `GroqSttProvider`.
- [ ] Add audio extraction, size validation, and chunking.
- [ ] Request verbose segment timestamps.
- [ ] Remove forced Hindi language.
- [ ] Add normalization and boundary deduplication.
- [ ] Reuse this provider from video summarization to remove duplicate Groq logic.

Exit criterion: English and Hindi fixtures return valid absolute timestamped segments without local model inference.

### Phase 2: Groq translation provider

- [ ] Add Groq chat client with configured model.
- [ ] Batch segments and demand strict JSON.
- [ ] Validate exact ID preservation.
- [ ] Add glossary/context support and concise retranslation.
- [ ] Record token usage when provider returns it.

Exit criterion: all source segments have one valid target segment and unchanged timestamps.

### Phase 3: TTS alignment and mux

- [ ] Add safe Edge TTS Python wrapper.
- [ ] Generate per-segment MP3 clips.
- [ ] Measure and fit clips to their time windows.
- [ ] Construct a video-length dubbed timeline.
- [ ] Mux, validate, and preserve full duration.
- [ ] Upload to staging R2.

Exit criterion: a short test video plays with understandable, approximately synchronized Hindi/English speech.

### Phase 4: worker, persistence, and frontend

- [ ] Implement `dubbingWorker.js` and progress updates.
- [ ] Add idempotency and cache reuse.
- [ ] Persist output URL in `Video.dubbedUrls`.
- [ ] Confirm feed/player serializers return dubbed URLs.
- [ ] Switch production Flutter DI to server-side dubbing.
- [ ] Keep on-device flow disabled or development-only.
- [ ] Add cancel/retry UI states if missing.

Exit criterion: a signed-in user requests a dub, leaves/reopens the screen, observes progress, and plays the cached R2 result.

### Phase 5: production hardening

- [ ] Redis-backed quota tracking.
- [ ] Per-user daily minute limit.
- [ ] Global concurrency and queue-pressure controls.
- [ ] Provider backoff/circuit breaker.
- [ ] Feature flag and kill switch.
- [ ] Structured metrics and alerts.
- [ ] Temp-file/R2 orphan cleanup job.
- [ ] Load, abuse, privacy, and cost review.
- [ ] Staged rollout: admins -> 1% -> 10% -> 100%.

Exit criterion: error rates, queue time, provider consumption, and storage growth remain within agreed thresholds.

## 20. MVP acceptance criteria

- [ ] No Whisper, translation, or TTS model is downloaded to the PC, phone, API machine, or worker.
- [ ] A 5-minute English or Hindi video can be dubbed into the other language.
- [ ] Segment timestamps survive STT, translation, and TTS stages.
- [ ] Output video duration is preserved and not truncated.
- [ ] Duplicate requests do not repeat provider calls.
- [ ] Job state survives API restarts.
- [ ] Provider/network failures yield safe, retryable job errors.
- [ ] Temporary media is removed in every terminal state.
- [ ] Only authorized users can start or inspect jobs.
- [ ] The output URL is persisted and returned in normal video serialization.
- [ ] The feature can be disabled remotely without a client release.

## 21. Later improvements

- Add more Edge/Azure voices and languages through configuration.
- Detect speakers and assign multiple stock voices.
- Add cloud-based dialogue/background separation.
- Publish separate audio tracks/HLS renditions instead of separate MP4 files.
- Add WebSocket/SSE progress to replace polling.
- Cache transcripts so recommendation, captions, search, and dubbing share one STT result.
- Store transcript/translation artifacts in private R2 with retention rules.
- Evaluate Azure Speech when uptime/SLA matters more than zero-cost prototyping.
- Add human review/editing of subtitles before TTS for creator-controlled releases.

## 22. Recommended first implementation slice

Implement one vertical slice before generalizing:

1. Authenticated `POST /dubbing/request` for an English MP4 shorter than two minutes.
2. One BullMQ job with persisted status.
3. Groq timestamped STT.
4. Groq English-to-Hindi segment translation.
5. `hi-IN-SwaraNeural` segment TTS.
6. Replacement-audio MP4 mux.
7. Staging R2 upload and `Video.dubbedUrls.hindi` update.
8. Existing Flutter polling and playback.

Once that path is reliable and covered by tests, add chunking, Hindi-to-English, more voices, quotas, fallbacks, and longer videos.

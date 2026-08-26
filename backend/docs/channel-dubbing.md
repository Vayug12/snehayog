# Existing-channel dubbing command

This command dubs videos that already exist in MongoDB and Cloudflare R2. It does not hook into the upload pipeline, upload controllers, Flutter, or R2 upload events.

## Providers

- STT: Groq `whisper-large-v3-turbo`
- Translation: Microsoft Azure Translator Text API v3
- TTS: Microsoft Edge online TTS through the `edge-tts` Python package
- Media processing: FFmpeg/ffprobe
- Output: versioned MP4 in Cloudflare R2 and `Video.dubbedUrls.<target>` in MongoDB

## Required environment

```dotenv
MONGO_URI=

GROQ_API_KEY=
DUBBING_STT_MODEL=whisper-large-v3-turbo

AZURE_TRANSLATOR_KEY=
AZURE_TRANSLATOR_REGION=
AZURE_TRANSLATOR_ENDPOINT=https://api.cognitive.microsofttranslator.com

CLOUDFLARE_ACCOUNT_ID=
CLOUDFLARE_R2_BUCKET_NAME=
CLOUDFLARE_R2_ACCESS_KEY_ID=
CLOUDFLARE_R2_SECRET_ACCESS_KEY=
CLOUDFLARE_R2_PUBLIC_DOMAIN=

DUBBING_BATCH_ENABLED=true
DUBBING_MAX_VIDEO_SECONDS=600
DUBBING_TEMP_ROOT=
DUBBING_MIN_FREE_DISK_MB=2048
```

`DUBBING_TEMP_ROOT` is optional. When omitted, the script uses an OS temp directory named `vayug-dubbing`. The Docker image already installs Python 3, FFmpeg, and `edge-tts`. A local non-Docker run needs Python 3 with `edge-tts` installed, or `DUBBING_PYTHON_BIN` pointing to that Python executable.

## Run safely

Start with a read-only preflight:

```bash
cd backend
npm run dub:channel -- --channel="Snehayog" --target=hi --dry-run
```

On Windows PowerShell, invoke `npm.cmd` so arguments after `--` are forwarded instead of being consumed by the `npm.ps1` wrapper:

```powershell
npm.cmd run dub:channel -- --channel="Snehayog" --target=hi --dry-run
```

Then process one eligible video:

```bash
npm run dub:channel -- --channel="Snehayog" --target=hi --limit=1
```

Process every eligible existing video after preflight confirmation:

```bash
npm run dub:channel -- --channel="Snehayog" --target=hi
```

For a non-interactive environment:

```bash
npm run dub:channel -- --channel="Snehayog" --target=hi --yes
```

Use `--force` only when the existing same-language dub should be regenerated. It uploads a new versioned R2 object and changes the MongoDB pointer only after media validation and upload succeed.

## Selection and resume behavior

The command resolves an exact, case-insensitive `User.name` and queries videos through `Video.uploader`. Duplicate creator names abort safely and print IDs; retry with `--channel-id=<id>`.

Videos with an existing non-empty `dubbedUrls.<target>` are cache hits and are skipped unless `--force` is present. This makes reruns resumable without a separate job database.

## Cleanup behavior

Videos are processed sequentially. Each video gets a random direct child directory under the configured temp root. The complete workspace is removed in `finally` after success, provider failure, FFmpeg failure, upload failure, MongoDB failure, or interruption.

Large intermediates are removed earlier when possible. Startup removes only stale `dub-*` directories under the validated temp root. It never removes source R2 objects, existing dubbed objects, the temp root itself, the workspace root, or the user's home directory.

## Verification

Run the isolated test suite:

```bash
npm run test:dubbing
```

The suite covers CLI validation, Azure batching, cache selection, sequential execution, cleanup on success/failure, safe R2 keys, and a real local FFmpeg timeline/mux/validation path. Provider calls are mocked; use `--limit=1` for the first live provider test.

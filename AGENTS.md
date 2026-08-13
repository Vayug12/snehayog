# Vayug - Video Sharing Platform

## Project Overview

Vayug is a creator-first, open-source short-form video sharing platform built with Flutter (frontend) and Node.js/Express (backend). Features TikTok-style video feeds, creator monetization (80% revenue share), ad management, AI-powered video generation, dubbing, and backend-driven architecture for zero-Play-Store-deploy updates.

**Tech Stack:**
- **Frontend**: Flutter 3.6+ (SDK >=3.5.0 <4.0.0), Riverpod, Provider
- **Backend**: Node.js, Express, MongoDB, Redis (Upstash)
- **Video Storage**: Cloudflare R2 + HLS streaming
- **Edge**: Cloudflare Workers (API caching, R2 uploads, KV)
- **Payments**: Revenue Cat
- **AI**: DeepSeek, Google Gemini, HuggingFace, OpenAI
- **Notifications**: Firebase Cloud Messaging + Brevo (email)
- **Deployment**: Fly.io (backend + worker), Cloudflare Workers (edge)
- **IaC**: Terraform (MongoDB Atlas, Cloudflare R2, Upstash Redis, Fly.io)
- **CI/CD**: GitHub Actions (6 workflows)
- **Monitoring**: New Relic APM

## Project Structure

```
snehayog/
├── backend/                 # Node.js/Express backend
│   ├── config/              # Configuration modules
│   ├── constants/           # Global constants
│   ├── controllers/         # Route controllers
│   │   ├── agent/           # AI agent upload
│   │   ├── video/           # Video sub-controllers (feed, upload, analytics, etc.)
│   │   └── videoGen/        # AI video generation
│   ├── loaders/             # App bootstrap (Express, MongoDB, Redis, cron jobs)
│   ├── middleware/          # Express middleware (rate limit, validation, tracing, RBAC)
│   ├── models/              # 27 Mongoose models
│   ├── routes/              # 19+ route files
│   │   ├── adRoutes/        # Modular ad system routes
│   │   ├── billing/         # Creator payout routes
│   │   ├── e2ee/            # End-to-end encryption routes
│   │   ├── feedback/        # User feedback routes
│   │   ├── notification/    # Notification routes
│   │   ├── report/          # Content report routes
│   │   └── uploadRoutes/    # File upload routes
│   ├── services/            # Business logic (18 service dirs/files)
│   │   ├── adServices/      # Ad system + pluggable AdEngine
│   │   ├── aiService/       # Pluggable AI engines (HuggingFace, OpenAI)
│   │   ├── auth/            # Google verification
│   │   ├── caching/         # Redis cache layer
│   │   ├── notificationServices/ # Push + email
│   │   ├── payoutServices/  # Automated payouts
│   │   ├── rateLimiting/    # API rate limiter
│   │   ├── searchServices/  # Pluggable search (MongoDB)
│   │   ├── storageSystem/   # Pluggable storage (Local, R2)
│   │   ├── uploadServices/  # Video processing pipeline
│   │   ├── videoGen/        # AI video generation agent
│   │   ├── videoProcessing/ # Step-based pipeline (VideoPipeline + 6 steps)
│   │   └── yugFeedServices/ # Feed & recommendation engine
│   ├── workers/             # BullMQ background workers
│   ├── utils/               # Utility functions
│   ├── scripts/             # Migration, seeding, test scripts
│   ├── tests/               # Jest tests
│   ├── docs/                # Backend documentation
│   ├── admin/               # Static admin dashboards (HTML)
│   └── server.js            # Entry point (DISABLE_INTEGRATED_WORKER env flag)
│
├── frontend/                # Flutter app
│   └── lib/
│       ├── core/            # Core design system
│       │   ├── design/      # Design tokens (colors, typography, spacing, radius, elevation, theme)
│       │   ├── interfaces/  # 12 abstract service interfaces
│       │   └── providers/   # 12 global Riverpod providers
│       ├── features/        # Feature modules (clean architecture)
│       │   ├── ads/         # data/domain/presentation
│       │   ├── auth/        # data/domain/presentation
│       │   ├── onboarding/  # data/presentation
│       │   ├── profile/     # 6 sub-features: analytics, content, core, notices, payouts, search
│       │   └── video/       # 8 sub-features: core, dubbing, edit, feed, quiz, subscriptions, upload, vayu
│       └── shared/          # 14 shared utility directories
│           ├── config/      # app_config, feature_flags, google_sign_in_config
│           ├── constants/   # App, video, profile, interests constants
│           ├── di/          # Dependency injection
│           ├── enums/       # Video state
│           ├── exceptions/  # App exceptions
│           ├── factories/   # Video controller factory
│           ├── managers/    # 5 singleton state managers
│           ├── mixins/      # Hot UI, video screen lifecycle
│           ├── models/      # App activity, remote config, feedback
│           ├── navigation/  # Route observer
│           ├── providers/   # User provider
│           ├── services/    # 28 service files
│           ├── utils/       # 13 utility files
│           └── widgets/     # 18 reusable widgets
│
├
│  
│
├── workers/                 # Cloudflare Workers (edge)
│   ├── index.js             # Consolidated worker (upload + API cache + R2 events)
│   ├── api_gateway_worker.js # Standalone API edge caching
│   ├── upload_worker.js     # Standalone R2 signed URL uploads
│   ├── wrangler.toml        # Wrangler config (vayug-edge)
│   └── r2-cors.json         # R2 CORS policy
│
├── mcp-servers/             # Model Context Protocol servers
│   └── vayu-ai-service/     # MCP server with 8 AI tool definitions
│       ├── index.js
│       └── tools/           # admin, ads, analysis, dubbing, embeddings, search, users, videos
│
├── terraform/               # Infrastructure as Code
│   ├── main.tf              # Terraform backend (R2 state)
│   ├── cloudflare.tf        # R2 buckets
│   ├── fly.tf               # Fly.io app + IPs + secrets
│   ├── mongodb.tf           # MongoDB Atlas (M0, AP_SOUTH_1)
│   ├── upstash.tf           # Upstash Redis
│   └── import_resources.*   # Import existing resources
│
├── .github/workflows/       # CI/CD
│   ├── build-android.yml    # Android build
│   ├── ci.yml               # General CI
│   ├── code-quality.yml     # Linting
│   ├── flutter_ci.yml       # Flutter CI
│   ├── fly_deploy.yml       # Fly.io deployment
│   └── release.yml          # Release automation
│
├── fly.toml                 # Fly.io deployment (app + worker processes)
├── Dockerfile               # Docker build (node:18-slim + ffmpeg + edge-tts)
├── nixpacks.toml            # Nixpacks build config
└── CLAUDE.md / GEMINI.md / AGENTS.md  # AI agent instructions
```

## Backend Architecture

### Entry Point

**`server.js`** - Express app bootstrap
- Registers API versioning middleware on all routes
- Conditionally starts integrated video worker based on `DISABLE_INTEGRATED_WORKER` env var
- Loader orchestrator (`loaders/`) handles Express, MongoDB, Redis, and cron jobs initialization

### Core Services

**Caching Layer** (`services/caching/redisService.js`)
- Upstash Redis with cache-aside pattern
- Connection pooling and graceful shutdown handling

**Upload Services** (`services/uploadServices/`)
- `videoProcessingService.js` - Upload orchestrator
- `hlsEncodingService.js` - FFmpeg HLS encoding
- `cloudflareR2Service.js` - R2 direct upload
- `hybridVideoService.js` - Hybrid storage
- `localModerationService.js` - Content moderation
- `exclusiveVideoCleanupService.js` - Cleanup orphaned files

**Feed & Recommendation System** (`services/yugFeedServices/`)
- `recommendationService.js` - AI-powered video recommendations
- `feedQueueService.js` / `queueService.js` - Queue-based feed generation
- `recommendationScoreCron.js` - Periodic score updates
- `aiSemanticService.js` - Semantic analysis for recommendations
- `videoMetadataService.js` - Feed metadata enrichment
- `recommendationEngine/` - Pluggable engine with `BaseScorer` + individual scorer implementations

**Pluggable Ad Engine** (`services/adServices/adEngine/`)
- `IAdSource.js` / `IAdTargeter.js` - Interface contracts
- `AdEngine.js` - Pluggable orchestrator
- `sources/` / `targeters/` - Implementations

**Pluggable AI Service** (`services/aiService/`)
- `IAIEngine.js` - Interface
- `HuggingFaceAIEngine.js` / `OpenAIAIEngine.js` - Providers

**Pluggable Search** (`services/searchServices/`)
- `ISearchProvider.js` - Interface
- `MongoSearchProvider.js` - MongoDB text search implementation

**Pluggable Storage** (`services/storageSystem/`)
- `IStorageProvider.js` - Interface
- `StorageManager.js` - Manager
- `LocalStorageProvider.js` / `R2StorageProvider.js` - Implementations

**AI Services** (top-level)
- `aiService.js` - AI orchestration
- `deepseekService.js` - DeepSeek integration
- `geminiService.js` - Google Gemini integration

**Other Services:**
- `services/payoutServices/` - Automated payout processing
- `services/rateLimiting/apiRateLimiter.js` - API rate limiting
- `services/auth/phoneVerificationService.js` - Phone OTP verification
- `services/notificationServices/` - Push + email (Brevo)
- `socialQueue.js` - Social sharing queue

### Background Workers

- `workers/videoWorker.js` - BullMQ video processing worker
- `workers/autoResume.js` - Cron: resets AI quotas daily
- Scripts: `npm run worker`, `npm run worker:dubbing`, `npm run worker:social`

### Middleware

| Middleware | Purpose |
|-----------|---------|
| `accessControl.js` | RBAC / role checks |
| `apiVersioning.js` | Date-based API version routing |
| `cacheMiddleware.js` | Response caching |
| `errorHandler.js` | Global error handler |
| `rateLimiter.js` | Rate limiting |
| `traceMiddleware.js` | Request tracing |
| `validation.js` | Joi request validation |
| `verifyWebhookSecret.js` | Webhook signature verification |
| `versionTracking.js` | Version tracking |
| `videoMiddleware.js` | Video-specific middleware |

### API Routes (19+ route groups)

| Route File | Path | Purpose |
|-----------|------|---------|
| `authRoutes.js` | `/api/auth` | Google Sign-In, JWT, phone OTP |
| `videoRoutes.js` | `/api/videos` | Video CRUD |
| `userRoutes.js` | `/api/users` | User management |
| `adminRoutes.js` | `/api/admin` | Admin dashboard |
| `agentRoutes.js` | `/api/agent` | AI agent endpoints |
| `appConfigRoutes.js` | `/api/app-config` | Remote config (version check, texts, kill switch) |
| `dubbingRoutes.js` | `/api/dubbing` | Multi-language dubbing |
| `referralRoutes.js` | `/api/referrals` | Referral system |
| `searchRoutes.js` | `/api/search` | Content search |
| `systemRoutes.js` | `/api/system` | Health check, system info |
| `videoGenRoutes.js` | `/api/video-gen` | AI video generation |
| `youtubeAuthRoutes.js` | `/api/youtube` | YouTube integration |
| `adRoutes/` | `/api/ads` | Ad system (10 sub-routes: campaigns, creatives, impressions, targeting, analytics, payments, validation, comments) |
| `billing/creatorPayoutRoutes.js` | `/api/billing` | Creator payouts |
| `e2ee/e2eeRoutes.js` | `/api/e2ee` | End-to-end encryption |
| `feedback/feedbackRoutes.js` | `/api/feedback` | User feedback |
| `notification/notificationRoutes.js` | `/api/notifications` | Push notifications |
| `report/reportRoutes.js` | `/api/reports` | Content reports |
| `uploadRoutes/uploadRoutes.js` | `/api/uploads` | File uploads |

### Database Models (27 models)

**Core Models:**
- `User.js` - User accounts, profiles, preferences
- `Video.js` - Video metadata, analytics, HLS URLs
- `View.js` - Video view tracking
- `Follower.js` - Social graph (follow relationships)
- `SavedVideo.js` - Bookmarked videos
- `WatchHistory.js` - Watch history tracking
- `FeedHistory.js` - Feed scroll position history

**Monetization Models:**
- `AdCampaign.js` - Ad campaign definitions
- `AdCreative.js` - Ad creative assets
- `AdImpression.js` - Ad impression tracking
- `CreatorPayout.js` - Creator payout records
- `CreatorDailyStats.js` - Daily creator analytics
- `CreatorMonthlyStat.js` - Monthly creator analytics
- `PlatformRevenue.js` - Platform revenue tracking
- `Invoice.js` - Billing invoices

**System Models:**
- `AppConfig.js` - Remote configuration (feature flags, business rules, UI texts, kill switch)
- `Notice.js` - System notices/announcements
- `CreatorNotification.js` - Creator notifications
- `RefreshToken.js` - JWT refresh tokens
- `PhoneOtpChallenge.js` - Phone OTP challenges
- `EncryptedVideoKey.js` - E2EE video keys
- `Feedback.js` - User feedback
- `Referral.js` - Referral tracking
- `Report.js` - Content reports
- `RemovedVideoRecord.js` - Deleted video audit log
- `VideoGenJob.js` - AI video generation jobs

## Frontend Architecture

### Design System (`core/design/`)

- `colors.dart` - Color tokens
- `typography.dart` - Typography scale
- `spacing.dart` - Spacing constants
- `radius.dart` - Border radius
- `elevation.dart` - Shadow/elevation
- `theme.dart` - Theme assembly

### Flutter UI Spacing Rules

- Do not hard-code layout spacing values such as `8`, `12`, `16`, or `24` in Flutter widgets.
- Import `core/design/spacing.dart` and use the responsive `AppSpacing` tokens (`spacing1`, `spacing2`, `spacing3`, `spacing4`, etc.) or the `hSpace*`/`vSpace*` helpers.
- Use the same `AppSpacing` token for shared gutters so titles, action buttons, avatars, and related rows stay aligned.
- Component-specific dimensions such as icon sizes may remain explicit when they are part of the component’s visual specification; spacing and padding should still use `AppSpacing`.
- Before finishing a UI change, check that new spacing values have not bypassed the design system.

### Abstract Interfaces (`core/interfaces/`)

12 service interfaces for dependency inversion:
- `i_auth_service.dart`, `i_video_service.dart`, `i_user_service.dart`
- `i_search_service.dart`, `i_dubbing_service.dart`, `i_e2ee_service.dart`
- `i_notice_service.dart`, `i_notification_service.dart`, `i_subscription_service.dart`
- `i_payment_setup_service.dart`, `i_quiz_engine.dart`, `i_video_upload_service.dart`

### Global Providers (`core/providers/`)

12 Riverpod providers:
- `auth_providers.dart`, `video_providers.dart`, `navigation_providers.dart`
- `user_data_providers.dart`, `user_service_providers.dart`
- `payment_providers.dart`, `subscription_providers.dart`
- `notice_providers.dart`, `notification_providers.dart`
- `video_upload_providers.dart`, `ai_video_generation_providers.dart`

### Feature Modules

| Feature | Sub-features | Layers |
|---------|-------------|--------|
| `ads/` | - | data/ domain/ presentation/ |
| `auth/` | - | data/ domain/ presentation/ |
| `onboarding/` | - | data/ presentation/ |
| `profile/` | analytics, content, core, notices, payouts, search | data/ domain/ presentation/ (varies) |
| `video/` | core, dubbing, edit, feed, quiz, subscriptions, upload, vayu | data/ domain/ presentation/ (varies) |

### State Management

**Riverpod** is used for state management:
- `core/providers/` - Global providers
- `shared/managers/` - Singleton managers for complex state
- `shared/providers/` - Feature-specific providers

**Key Managers:**
- `HotUIStateManager` - UI state preservation
- `SmartCacheManager` - Intelligent caching
- `VideoPositionCacheManager` - Video position tracking
- `CarouselAdManager` - Ad carousel lifecycle
- `ActivityRecoveryManager` - Activity recovery

### Video Player Architecture

**Vayu Player** (`features/video/vayu/presentation/widgets/vayu_player/`)
- Custom video player with HLS support
- Optimized for low-RAM devices (100MB image cache limit)
- Intelligent controller pooling and disposal
- Background playback support

### Shared Services (28 services)

**Network:**
- `http_client_service.dart` - HTTP client with retry logic
- `signed_url_service.dart` - Signed URL generation for R2 uploads
- `http_migration_helper.dart` - HTTP migration utilities

**Video & Playback:**
- `video_player_config_service.dart` - Player configuration
- `playback_coordinator.dart` - Playback coordination
- `deep_link_playback_gate.dart` - Deep link playback gating
- `hls_warmup_service.dart` - HLS pre-warming
- `auto_scroll_settings.dart` - Auto-scroll configuration

**Platform:**
- `app_remote_config_service.dart` - Backend-driven config fetch + local cache
- `connectivity_service.dart` - Network connectivity monitoring
- `location_service.dart` - Location services
- `city_search_service.dart` - City search
- `platform_id_service.dart` - Platform identification
- `file_picker_service.dart` - File picker
- `local_gallery_service.dart` - Local gallery access
- `cloudflare_r2_service.dart` - R2 upload integration

**User & Social:**
- `account_switcher_service.dart` - Multi-account switching
- `feedback_service.dart` - Feedback submission
- `report_service.dart` - Content reporting
- `search_service.dart` - Content search
- `share_service.dart` - Social sharing

**Utilities:**
- `error_logging_service.dart` - Error tracking
- `notification_service.dart` - Push notifications
- `performance_manager.dart` - Performance monitoring
- `memory_management_service.dart` - Memory optimization
- `profile_screen_logger.dart` / `video_screen_logger.dart` - Logging

### Shared Utilities (13 utilities)

- `app_logger.dart` - Centralized logging
- `app_text.dart` - Backend-driven text management (no hard-coded strings)
- `feature_flags.dart` - Feature flag checks
- `responsive_helper.dart` - Responsive layout
- `format_utils.dart` - Formatting
- `url_utils.dart` - URL utilities
- `banner_image_processor.dart` - Banner processing
- `enhanced_controller_disposal.dart` - Controller disposal
- `video_disposal_utils.dart` - Video disposal
- `video_engagement_ranker.dart` - Engagement ranking
- `video_screen_utils.dart` / `video_url_checker.dart` - Video utilities
- `debug_helper.dart` - Debug utilities

### Reusable Widgets (18 widgets)

- `app_button.dart`, `loading_button.dart`, `interactive_scale_button.dart`
- `unified_video_card.dart`, `vayu_video_card.dart`, `episode_grid_widget.dart`
- `follow_button_widget.dart`, `action_buttons_widget.dart`
- `share_options_sheet.dart`, `vayu_bottom_sheet.dart`
- `forced_update_widget.dart` - Forced update blocking
- `report_dialog_widget.dart`, `feedback/` - Reporting & feedback
- `in_app_browser.dart`, `external_link_button.dart`
- `payment_status_indicator.dart`
- `vayu_logo.dart`, `vayu_snackbar.dart`

## Backend-Driven Architecture

### AppConfig System

Remote config via `GET /api/app-config` with Redis caching (5-min TTL):
- **Version Control**: Forced updates (min version), soft updates
- **Feature Flags**: Enable/disable features remotely
- **Business Rules**: Pricing, limits, thresholds
- **Algorithm Parameters**: Recommendation tuning
- **UI Texts**: Backend-managed strings (i18n-ready)
- **Kill Switch**: Emergency app shutdown

**Frontend Integration:**
- `AppRemoteConfigService` - Fetches config, caches locally (SharedPreferences), graceful fallback
- `ForcedUpdateWidget` - Blocks app if version < minimum, shows banner if < latest
- `AppText` - Centralized text management with backend fallbacks

### API Versioning

Date-based versioning via `middleware/apiVersioning.js`:
- Multiple active versions simultaneously
- Deprecation and end-of-life support
- Header-based version detection (`X-API-Version`)

## Cloudflare Workers (Edge)

**Consolidated Worker** (`workers/index.js`):
- **Phase 1** - `/upload-url`: JWT-authenticated R2 signed PUT URL generation
- **Phase 2** - `/api/*`: Edge KV caching for app-config, video metadata, user profiles, creator analytics
- **Phase 3** - R2 event handler: webhook notification to backend on new file uploads

**Bindings:**
- R2 Bucket: `snehayog-videos`
- KV Namespace: `VAYUG_CACHE`
- Backend Origin: `https://vayug.fly.dev`

## MCP Server

**`mcp-servers/vayu-ai-service/`** - Model Context Protocol server with 8 AI tool definitions:
- `admin.js`, `ads.js`, `analysis.js`, `dubbing.js`
- `embeddings.js`, `search.js`, `users.js`, `videos.js`

## Infrastructure (Terraform)

Managed resources:
- **MongoDB Atlas**: M0 free tier, AP_SOUTH_1 region
- **Cloudflare R2**: `snehayog-videos` bucket + Terraform state bucket
- **Upstash Redis**: Serverless Redis
- **Fly.io**: App + dedicated worker machine + IPs + secrets

## Configuration

### Environment Variables

**Backend (.env):**
```
MONGO_URI=mongodb://...
REDIS_URL=redis://...
JWT_SECRET=...
GOOGLE_CLIENT_ID=...
CLOUD_NAME=...
CLOUD_KEY=...
CLOUD_SECRET=...
DISABLE_INTEGRATED_WORKER=true  # Run worker as separate Fly machine
```

**Frontend (`lib/shared/config/`):**
- `app_config.dart` - API endpoints, mode switching, Cloudflare Workers URL
- `feature_flags.dart` - Feature flag checks
- `google_sign_in_config.dart` - Google auth config

### Deployment

**Fly.io (2 process groups):**
| Process | Command | RAM | CPU | Notes |
|---------|---------|-----|-----|-------|
| `app` | `npm start` | 512MB | shared | HTTP via Fly Proxy, auto-stop/start |
| `worker` | `npm run worker` | 2GB | shared | Outside HTTP proxy, never killed mid-encode |

- Health check: `GET /health` every 30s
- Concurrency: soft 150, hard 200
- Region: `sin` (Singapore)

**Docker:** `node:18-slim` + `ffmpeg` + `python3` + `edge-tts`

**CI/CD:** 6 GitHub Actions workflows (build-android, ci, code-quality, flutter-ci, fly-deploy, release)

## Common Tasks

### Adding a New API Endpoint
1. Create route in `backend/routes/`
2. Add controller in `backend/controllers/`
3. Add service in `backend/services/` (business logic)
4. Add model in `backend/models/` if needed
5. Add frontend interface in `core/interfaces/`
6. Add frontend service in `features/*/data/services/`
7. Add provider in `core/providers/` or `shared/providers/`

### Adding a New Feature
1. Create feature directory in `lib/features/`
2. Follow clean architecture: domain -> data -> presentation
3. Add abstract interface in `core/interfaces/`
4. Add Riverpod providers for state management
5. Update navigation if needed
6. Use `AppText.get()` for all UI strings (no hard-coded text)

### Adding a New Background Worker
1. Create worker file in `backend/workers/`
2. Add npm script in `package.json` (`npm run worker:xxx`)
3. Use BullMQ for job queue management
4. Add Fly.io process group in `fly.toml` if needed

### Debugging Video Issues
- Check `VideoControllerManager` logs
- Verify Redis cache keys
- Review HLS stream URLs
- Check `VideoPipeline` step logs
- Verify R2 upload URLs

### Performance Profiling
- Use New Relic APM (backend)
- Check `performance_manager.dart` logs (frontend)
- Monitor Redis memory usage
- Review video controller pool size
- Check Fly.io metrics

## Testing

**Backend:**
```bash
cd backend
npm test              # Jest tests
```

**Frontend:**
```bash
cd frontend
flutter test              # Standard testing
./scripts/fast_test.bat   # Centralized fast testing (Windows)
```

## Contributing

Follow the existing code structure and patterns:
- Use Riverpod for state management
- Follow clean architecture principles (Controller -> Service -> Model)
- Use abstract interfaces for dependency inversion
- Add error handling for all API calls
- Log important events with `AppLogger`
- Use `AppText.get()` for all UI strings
- Test on low-end devices for performance
- Never hard-code values - use AppConfig for business rules

# AI Engineering Guide

## Goal
Write production-grade, scalable, and modular code.
Avoid hacks, duplication, and fragile logic.

## Architecture Principles

- Follow clean architecture (Controller -> Service -> Model)
- No business logic in controllers
- Keep functions small and composable
- Prefer composition over inheritance
- Use pluggable interfaces (IAdSource, IAIEngine, ISearchProvider, IStorageProvider)

## Modular Design Rules

- Each module should have clear responsibility, no tight coupling
- Never import across unrelated modules
- Use dependency injection where possible
- Abstract interfaces for all external dependencies

## Performance Rules

- Never call DB inside loops
- Use caching (Redis) for repeated reads
- Batch operations using Promise.all
- Avoid unnecessary API calls
- Use step-based video processing pipeline for complex flows

## API & Network Rules

- Retry max 3 times only
- Do NOT retry on 404 or 401
- Add timeout to every request
- Debounce repeated calls
- Use API versioning for backward compatibility

## Edge Cases (MANDATORY)

Always handle:
- null / undefined inputs
- empty arrays
- network failures
- partial responses
- duplicate requests
- race conditions

## Error Handling

- Use try/catch everywhere async is used
- Return meaningful error messages
- Never expose internal errors to client
- Log all failures

## Caching Rules (Redis)

- Cache only read-heavy data
- Always set TTL (positive value only)
- Never overwrite cache blindly
- Use cache-aside pattern

## Auth Rules

- Always validate userId
- Never trust frontend blindly
- Check permissions before action
- Verify webhook signatures

## Code Quality

- Use async/await (no callbacks)
- No duplicate logic
- Write reusable functions
- Avoid magic numbers
- Write code in deep modules

## Anti-Patterns (STRICTLY AVOID)

- Infinite loops
- Retry storms
- Nested API calls
- DB calls in UI layer
- Blocking operations

## Thinking Instructions (IMPORTANT)

Before writing code, ALWAYS:
1. Identify bottlenecks
2. Check for edge cases
3. Think about scale (even if small)
4. Avoid over-fetching
5. Optimize for fewer network calls

## Output Format

- Explain reasoning briefly
- Then provide clean code
- Avoid unnecessary comments

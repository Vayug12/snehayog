# Vayug

Vayug is the product-facing name of the Snehayog project. It is a creator-first video platform for discovering, watching, publishing, and monetizing short-form and long-form video.

The project is currently built around a Flutter client, a Node.js/Express backend, asynchronous video processing, and Cloudflare-backed media delivery.

## Implemented capabilities

### Viewers and communities

- Public short-form and long-form video feeds.
- Anonymous/device-based feed access with optional personalized recommendations for signed-in users.
- Video and creator search.
- Creator profiles, follows/subscriptions, likes, comments, shares, saves, and watch history.
- Playback-position recovery, notifications, content reporting, and creator suggestions.
- Series and episode navigation.
- Interactive quizzes attached to supported videos.
- Public share pages for eligible videos at `/video/{id}/{slug}` and embeddable players at `/embed/{id}`.

### Creator publishing

- Google Sign-In and JWT-based account authentication.
- Video upload from the Flutter client.
- Video metadata, thumbnails, descriptions, categories, tags, keywords, visibility, and editing.
- Background processing with FFmpeg, HLS playlists, quality variants, thumbnails, and processing progress.
- Series/episode organization and video quizzes.
- Creator analytics, views, watch time, engagement, and revenue-related views.
- Subscriber-only video selection with encrypted delivery support.
- Cross-post status tracking for configured external platforms.

### AI and language workflows

- Video analysis and metadata enrichment.
- Transcription, summaries, language/region detection, and semantic embeddings.
- Recommendation scoring and content-aware search.
- AI-assisted dubbing workflows for transcription, translation, and speech synthesis.
- Authenticated AI video-generation jobs with progress streaming and gallery download support.

AI features depend on configured providers, credentials, quotas, and deployment settings. They are not guaranteed to be available in every environment.

### Monetization and advertising

- Creator advertising-revenue workflow with a configured 80% creator / 20% platform split for eligible advertising revenue.
- Advertiser campaign creation, creative uploads, targeting, ad credits, impressions, views, clicks, and campaign reporting.
- Creator rewards, billing setup, payout-related records, and revenue analytics where the required payment configuration is enabled.

The 80% figure is a configured eligible-revenue split, not guaranteed income. Ads are not guaranteed on every video, and eligibility, inventory, region, billing, payout minimums, and platform configuration apply.

### Privacy and delivery

- Subscriber-only content uses encrypted video/key flows in the client and backend.
- Public videos are accessible without authentication; subscriber-only content is filtered from public feeds and public SEO indexing.
- Public video pages include canonical metadata and `VideoObject` structured data.
- The production sitemap includes completed public video pages and excludes subscriber-only videos.
- Media delivery uses Cloudflare R2-compatible storage, public CDN URLs for public media, HLS playback, and Cloudflare Worker edge caching.
- Android App Links, APK distribution, `robots.txt`, public documentation, and machine-readable product resources are included in the backend.

## Technology stack

| Area | Technology |
|---|---|
| Client | Flutter / Dart |
| API | Node.js + Express |
| Database | MongoDB + Mongoose |
| Jobs and caching | BullMQ, Redis/Upstash, Cloudflare Worker cache |
| Media processing | FFmpeg, HLS |
| Object storage | Cloudflare R2 |
| Authentication | Google Sign-In, JWT |
| AI | Configurable OpenAI, Gemini, Hugging Face, and dubbing providers |
| Deployment | Fly.io backend, Cloudflare Workers/R2 where configured |

## Local development

### Prerequisites

- Flutter SDK compatible with the version in `frontend/pubspec.yaml`.
- Node.js 18 or newer.
- MongoDB, local or hosted.
- Redis/Upstash for queues and caching.
- FFmpeg for local video processing.
- Cloudflare R2 and AI credentials for the workflows that use them.

### Backend

```powershell
cd backend
npm install
Copy-Item env.example .env
# Configure .env with MongoDB, Redis, authentication, storage, and AI values.
npm start
```

The backend serves the API and public web resources. Important public resources include `/`, `/docs`, `/llms.txt`, `/robots.txt`, `/sitemap.xml`, and public video share pages.

### Flutter client

```powershell
cd frontend
flutter pub get
flutter run
```

Configure the API environment in the Flutter project before running on a device or emulator.

### Workers

The `workers` directory contains the Cloudflare edge gateway and upload worker configuration. Use Wrangler with the project bindings and secrets configured for your environment.

```powershell
cd workers
npm install
npx wrangler dev
```

## Project structure

```text
snehayog/
├── backend/       # Express API, workers, models, processing, public SEO pages
├── frontend/      # Flutter application
├── workers/       # Cloudflare Worker edge and upload services
├── terraform/     # Infrastructure configuration
└── README.md
```

## Public web and indexing

Public videos can be opened without an authenticated session through their canonical share page. Subscriber-only videos are not included in the public sitemap and their web routes require access.

Google indexing still depends on the production domain being reachable, the video being completed and public, the sitemap being discoverable, and normal crawler decisions. A public page being indexable does not guarantee a search-result placement.

## Current limitations

- Feature availability depends on deployment configuration and enabled credentials.
- AI generation, dubbing, payments, payouts, ads, push notifications, and Cloudflare services require their respective secrets and external services.
- Public indexing is for public video pages, not authenticated API responses.
- Production credentials, user data, private media, and third-party accounts are not included in this repository.

Vayug is the product-facing name; Snehayog is the repository and internal project identity.

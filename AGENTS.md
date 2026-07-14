# Vayug (Snehayog) - Video Sharing Platform

## Project Overview

Vayug is a short-form video sharing platform built with Flutter (frontend) and Node.js/Express (backend). The platform features TikTok-style video feeds, creator monetization, ad management, and advanced video processing capabilities.

**Tech Stack:**
- **Frontend**: Flutter 3.5+, Riverpod, Provider
- **Backend**: Node.js, Express, MongoDB, Redis
- **Video Storage**: Cloudinary (HLS streaming)
- **Payments**: Razorpay
- **Notifications**: Firebase Cloud Messaging
- **Deployment**: Fly.io (backend), Cloudflare Workers (edge caching)

## Project Structure

```
snehayog/
├── backend/                 # Node.js/Express backend
│   ├── config/            # Configuration files
│   ├── controllers/       # Route controllers
│   ├── models/            # Mongoose models
│   ├── routes/            # API routes
│   ├── services/          # Business logic
│   ├── middleware/        # Express middleware
│   ├── loaders/           # App initialization
│   ├── workers/           # Background jobs
│   └── server.js          # Entry point
│
├── frontend/              # Flutter app
│   ├── lib/
│   │   ├── core/          # Core design system
│   │   ├── features/      # Feature modules
│   │   ├── shared/        # Shared utilities/services
│   │   └── main.dart      # Entry point
│   └── pubspec.yaml       # Dependencies
│
└── packages/              # Local packages
    └── snehayog_monetization/  # Monetization package
```

## Backend Architecture

### Core Services

**Caching Layer** (`backend/services/caching/redisService.js`)
- Redis-based caching for feeds, user data, and video metadata
- Currently using Upstash Redis (considering migration to Redis Cloud for unlimited requests)
- Connection pooling and graceful shutdown handling

**Video Processing** (`backend/services/uploadServices/`)
- `videoProcessingService.js` - Video upload and processing
- `hlsEncodingService.js` - HLS stream generation
- `videoClippingService.js` - Video clipping/trimming
- `cloudflareR2Service.js` - Alternative storage option

**Feed Services** (`backend/services/yugFeedServices/`)
- `recommendationService.js` - AI-powered video recommendations
- `feedQueueService.js` - Queue-based feed generation
- `recommendationScoreCron.js` - Periodic score updates
- `aiSemanticService.js` - Semantic analysis for recommendations

**Ad Services** (`backend/services/adServices/`)
- `adService.js` - Ad campaign management
- `revenueService.js` - Revenue calculation and tracking
- `adTargetingService.js` - Audience targeting logic

**Notification Services** (`backend/services/notificationServices/`)
- `notificationService.js` - Push notification management
- `monthlyNotificationCron.js` - Scheduled notifications
- `brevoService.js` - Email notifications

### API Routes

- `/api/auth` - Authentication (Google Sign-In, JWT)
- `/api/videos` - Video CRUD operations
- `/api/users` - User management
- `/api/ads` - Ad campaign management
- `/api/admin` - Admin dashboard
- `/api/search` - Search functionality
- `/api/youtube` - YouTube integration

### Database Models

**Core Models:**
- `User.js` - User accounts and profiles
- `Video.js` - Video metadata and analytics
- `View.js` - Video view tracking
- `Follower.js` - Social graph
- `SavedVideo.js` - Bookmarked videos

**Monetization Models:**
- `AdCampaign.js` - Ad campaigns
- `AdCreative.js` - Ad creatives
- `AdImpression.js` - Ad impression tracking
- `CreatorPayout.js` - Creator payouts
- `PlatformRevenue.js` - Platform revenue

**System Models:**
- `AppConfig.js` - Remote configuration
- `Notice.js` - System notices
- `RefreshToken.js` - Token management

## Frontend Architecture

### Feature-Based Organization

The frontend follows a clean architecture with feature-based modules:

```
lib/features/
├── auth/              # Authentication
├── video/             # Video playback and feed
├── profile/           # User profiles
├── ads/               # Ad management
├── onboarding/        # User onboarding
└── subscriptions/     # Subscription management
```

### State Management

**Riverpod** is used for state management:
- `core/providers/` - Global providers (auth, navigation, video)
- `shared/managers/` - Singleton managers for complex state
- `shared/providers/` - Feature-specific providers

**Key Managers:**
- `VideoControllerManager` - Video player lifecycle
- `SharedVideoControllerPool` - Video controller pooling
- `HotUIStateManager` - UI state preservation
- `SmartCacheManager` - Intelligent caching

### Video Player Architecture

**Vayu Player** (`lib/features/video/vayu/presentation/widgets/vayu_player/`)
- Custom video player with HLS support
- Optimized for low-RAM devices (100MB image cache limit)
- Intelligent controller pooling and disposal
- Background playback support

**Feed Screens:**
- `homescreen.dart` - Main feed (Yug feed)
- `video_feed_advanced/` - Advanced feed with caching
- `video_screen.dart` - Individual video playback

### Services

**Network Layer:**
- `http_client_service.dart` - HTTP client with retry logic
- `signed_url_service.dart` - Signed URL generation for uploads

**Data Services:**
- `video_service.dart` - Video API calls
- `authservices.dart` - Authentication
- `analytics_service.dart` - Analytics tracking

**Utility Services:**
- `error_logging_service.dart` - Error tracking
- `notification_service.dart` - Push notifications
- `performance_manager.dart` - Performance monitoring

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
RAZORPAY_KEY_ID=...
RAZORPAY_KEY_SECRET=...
```

**Frontend (lib/shared/config/app_config.dart):**
- API endpoints configuration
- Development/production mode switching
- Cloudflare Workers URL
- Ad serving parameters

### Development Setup

**Backend:**
```bash
cd backend
npm install
npm run dev  # Development server
```

**Frontend:**
```bash
cd frontend
flutter pub get
flutter run  # Run on device/emulator
```

## Key Features

### Video Upload & Processing
- Max file size: 700MB
- Supported formats: MP4, AVI, MOV, WMV, FLV, WEBM
- Automatic HLS encoding with adaptive bitrate
- Thumbnail generation
- Video compression

### Feed Algorithm
- AI-powered recommendations using semantic analysis
- Engagement-based ranking
- Location-based content
- Creator preference tracking

### Monetization
- Ad campaigns with targeting
- Creator revenue sharing (80% to creators)
- Automated payouts
- Analytics dashboard

### Performance Optimizations
- Redis caching for feeds
- Video controller pooling
- Aggressive memory management
- Background preloading
- Edge caching via Cloudflare Workers

## Deployment

**Backend (Fly.io):**
- Docker-based deployment
- Environment variables via Fly secrets
- Integrated video worker in same process

**Frontend:**
- Android/iOS builds via Flutter
- Firebase for crash reporting (Crashlytics)
- Remote config for feature flags

## Common Tasks

### Adding a New API Endpoint
1. Create route in `backend/routes/`
2. Add controller in `backend/controllers/`
3. Update service layer if needed
4. Add frontend service in `lib/features/*/data/services/`

### Adding a New Feature
1. Create feature directory in `lib/features/`
2. Follow clean architecture: domain → data → presentation
3. Add Riverpod providers for state management
4. Update navigation if needed

### Debugging Video Issues
- Check `VideoControllerManager` logs
- Verify Redis cache keys
- Review HLS stream URLs

### Performance Profiling
- Use Firebase Performance Monitoring
- Check `performance_manager.dart` logs
- Monitor Redis memory usage
- Review video controller pool size

## Known Issues & Considerations

### Redis Migration
Currently using Upstash Redis with 10,000 daily request limit. 

### Memory Management
- Video controllers are aggressively disposed on background
- Image cache limited to 100MB for low-RAM devices
- Consider device-specific cache sizing

### Video Player
- Custom Vayu player for better control
- Chewie library as fallback
- HLS streaming via video_player

## Testing

**Backend:**
```bash
cd backend
npm test
```

**Frontend:**
```bash
cd frontend
flutter test              # Standard testing
./scripts/fast_test.bat   # Centralized fast testing (Windows)
```

## Documentation

- API docs: Available via Swagger/Postman collections
- Component docs: Inline Dart documentation
- Architecture docs: This file

## Contributing

Follow the existing code structure and patterns:
- Use Riverpod for state management
- Follow clean architecture principles
- Add error handling for all API calls
- Log important events with `AppLogger`
- Test on low-end devices for performance

# 🧠 Vayug AI Engineering Guide

## 🎯 Goal
Write production-grade, scalable, and modular code.
Avoid hacks, duplication, and fragile logic.

---

# 🏗️ Architecture Principles

- Follow clean architecture (Controller → Service → Repository)
- No business logic in controllers
- Keep functions small and composable
- Prefer composition over inheritance

---

# 📦 Modular Design Rules

- Each module should have:
  - clear responsibility
  - no tight coupling
- Never import across unrelated modules
- Use dependency injection where possible

---

# ⚡ Performance Rules

- Never call DB inside loops
- Use caching (Redis) for repeated reads
- Batch operations using Promise.all
- Avoid unnecessary API calls

---

# 🔁 API & Network Rules

- Retry max 3 times only
- Do NOT retry on 404 or 401
- Add timeout to every request
- Debounce repeated calls

---

# 🧠 Edge Cases (MANDATORY)

Always handle:

- null / undefined inputs
- empty arrays
- network failures
- partial responses
- duplicate requests
- race conditions

---

# 🧯 Error Handling

- Use try/catch everywhere async is used
- Return meaningful error messages
- Never expose internal errors to client
- Log all failures

---

# 💾 Caching Rules (Redis)

- Cache only read-heavy data
- Always set TTL (positive value only)
- Never overwrite cache blindly
- Use cache-aside pattern

---

# 🔐 Auth Rules

- Always validate userId
- Never trust frontend blindly
- Check permissions before action

---

# 🧪 Code Quality

- Use async/await (no callbacks)
- No duplicate logic
- Write reusable functions
- Avoid magic numbers
- write code in deep module

---

# 📉 Anti-Patterns (STRICTLY AVOID)

- Infinite loops
- Retry storms
- Nested API calls
- DB calls in UI layer
- Blocking operations

---

# 🧠 Thinking Instructions (IMPORTANT)

Before writing code, ALWAYS:

1. Identify bottlenecks
2. Check for edge cases
3. Think about scale (even if small)
4. Avoid over-fetching
5. Optimize for fewer network calls

---

# 🧾 Output Format

- Explain reasoning briefly
- Then provide clean code
- Avoid unnecessary comments



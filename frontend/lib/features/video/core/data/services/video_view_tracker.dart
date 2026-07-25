import 'dart:async';
import 'dart:convert';
import 'package:flutter/widgets.dart';
import 'package:vayug/shared/config/app_config.dart';
import 'package:vayug/features/auth/data/services/authservices.dart';
import 'package:vayug/shared/services/platform_id_service.dart';
import 'package:vayug/shared/utils/app_logger.dart';
import 'package:vayug/shared/services/http_client_service.dart';
import 'package:vayug/shared/constants/app_constants.dart';

/// Handles 2-second view threshold for videos, repeat views (max 10 per user), self-view prevention, and API integration
class VideoViewTracker with WidgetsBindingObserver {
  static String get _baseUrl => AppConfig.baseUrl;
  final AuthService _authService = AuthService();

  VideoViewTracker() {
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // If the app is minimized, sent to background, or about to be terminated,
    // IMMEDIATELY flush the queue so no views are lost.
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      AppLogger.log('⚠️ VideoViewTracker: App went to background. Flushing views!');
      syncWatchEvents();
    }
  }

  // Track timers for each video
  final Map<String, Timer> _viewTimers = <String, Timer>{};
  final Map<String, DateTime> _playbackStartTimes = <String, DateTime>{};
  final Map<String, int> _userViewCounts = <String, int>{};

  // **NEW: Track recent views to prevent rapid repeat spam**
  final Map<String, DateTime> _recentViews = <String, DateTime>{};
  static final Map<String, DateTime> _recentSkips = <String, DateTime>{};
  // **RELAXED**: Allow repeat views after a short cooldown instead of 1 minute
  static const Duration _minViewInterval =
      Duration(seconds: 10); // Minimum 10 seconds between views
  static const Duration _minSkipInterval = Duration(seconds: 30);

  // **NEW: Batching for watch events**
  final List<Map<String, dynamic>> _pendingWatchEvents = [];
  Timer? _batchSyncTimer;
  static const Duration _batchSyncInterval = Duration(seconds: 30);
  static const int _maxBatchSize = 20;

  /// Increment view count for a video after 2 seconds of playback
  /// Returns true if view was counted, false if already at max or error
  Future<bool> incrementView(
    String videoId, {
    int? duration,
    String? videoUploaderId,
    String? videoHash, // **NEW: Accept videoHash**
  }) async {
    try {
      final effectiveDuration =
          duration ?? AppConstants.videoViewCountThreshold.inSeconds;

      AppLogger.log(
          '🎯 VideoViewTracker: Attempting to increment view for video $videoId (hash: $videoHash)');

      // **CRITICAL FIX: Watch tracking should work for BOTH authenticated AND anonymous users**
      // Get platformId first (always available, even for anonymous users)
      final platformIdService = PlatformIdService();
      final platformId = await platformIdService.getPlatformId();

      // Get auth token (may be null for anonymous users)
      final token = await AuthService.getToken();
      Map<String, String> headers = {
        'Content-Type': 'application/json',
      };
      
      // **FIX: Always add device ID header for consistent tracking**
      if (platformId.isNotEmpty) {
        headers['x-device-id'] = platformId;
      }

      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }

      // **NEW: BATCHED WATCH TRACKING**
      _queueWatchEvent(videoId, effectiveDuration, false, platformId, videoHash);

      // **FIXED: View increment requires authenticated user, but watch tracking already happened above**
      // **FIXED: Allow anonymous view increments using platformId**
      // Get current user data for view increment (prefer authenticated users)
      final userData = await _authService.getUserData();
      final userId = userData?['id'] ?? userData?['googleId'] ?? platformId;
      
      if (userId == null || userId.isEmpty) {
        AppLogger.log('ℹ️ VideoViewTracker: No identifier found - skipping view increment');
        return true;
      }
      
      AppLogger.log('🎯 VideoViewTracker: User/Device ID for increment: $userId');

      // **RELAXED RULE**: Allow creators to test their own videos
      // Self-views will now be counted like normal views so creators
      // can verify that view counts are updating correctly.

      // **NEW: Check for rapid repeat spam**
      final viewKey = '${videoId}_$userId';
      final lastViewTime = _recentViews[viewKey];
      if (lastViewTime != null) {
        final timeSinceLastView = DateTime.now().difference(lastViewTime);
        if (timeSinceLastView < _minViewInterval) {
          AppLogger.log(
              '🚫 VideoViewTracker: Rapid repeat view detected - too soon since last view');
          AppLogger.log(
              '🚫 VideoViewTracker: Time since last view: ${timeSinceLastView.inSeconds}s, minimum: ${_minViewInterval.inSeconds}s');
          return false;
        }
      }

      // Check if user has already reached max views for this video
      final userViewCount = _userViewCounts['${videoId}_$userId'] ?? 0;
      if (userViewCount >= 10) {
        AppLogger.log(
            '⚠️ VideoViewTracker: User has reached max view count (10) for video $videoId');
        return false;
      }

      // **IMPROVED: Fully Batched Architecture**
      // We no longer send an immediate API call to /increment-view.
      // The view has already been queued via _queueWatchEvent above, 
      // which will be synced to the backend in bulk every 5 seconds.
      // This eliminates rapid Redis rate-limiter counts while preserving data integrity.

      // Update local view count tracking immediately
      _userViewCounts[viewKey] = userViewCount + 1;

      // Update recent view time to prevent rapid repeat spam
      _recentViews[viewKey] = DateTime.now();

      AppLogger.log('✅ VideoViewTracker: View queued successfully for batch sync');
      AppLogger.log('   Local User view count: ${userViewCount + 1}');

      return true;
    } catch (e) {
      AppLogger.log('❌ VideoViewTracker: Error queueing view: $e');
      return false;
    }
  }

  /// Start tracking view for a video - will increment after 2 seconds
  void startViewTracking(String videoId, {String? videoUploaderId, String? videoHash}) {
    AppLogger.log(
        '🎯 VideoViewTracker: Starting view tracking for video $videoId');

    // Cancel any existing timer for this video
    _viewTimers[videoId]?.cancel();
    _playbackStartTimes[videoId] = DateTime.now();

    // Start new timer
    _viewTimers[videoId] =
        Timer(AppConstants.videoViewCountThreshold, () async {
      AppLogger.log(
        '⏰ VideoViewTracker: ${AppConstants.videoViewCountThreshold.inSeconds} seconds elapsed for video $videoId, incrementing view',
      );

      final success =
          await incrementView(videoId, videoUploaderId: videoUploaderId, videoHash: videoHash);
      
      if (success) {
        AppLogger.log('✅ VideoViewTracker: View counted for video $videoId');
      } else {
        AppLogger.log(
            '⚠️ VideoViewTracker: View not counted for video $videoId (self-view, max reached or error)');
      }

      // Clean up timer
      _viewTimers.remove(videoId);
    });
  }

  /// Stop tracking view for a video (e.g., when user scrolls away)
  void stopViewTracking(String videoId) {
    AppLogger.log(
        '🎯 VideoViewTracker: Stopping view tracking for video $videoId');

    final startTime = _playbackStartTimes.remove(videoId);
    if (startTime != null) {
      final elapsed = DateTime.now().difference(startTime);
      const threshold = AppConstants.videoViewCountThreshold;

      if (elapsed < threshold && elapsed.inMilliseconds > 500) {
        AppLogger.log(
            '⏭️ VideoViewTracker: Video $videoId skipped (watched for ${elapsed.inMilliseconds}ms < ${threshold.inMilliseconds}ms)');
        _trackSkip(videoId);
      }
    }

    _viewTimers[videoId]?.cancel();
    _viewTimers.remove(videoId);
  }

  /// Reset view tracking for a video (allows re-counting)
  void resetViewTracking(String videoId) {
    AppLogger.log(
        '🎯 VideoViewTracker: Resetting view tracking for video $videoId');

    stopViewTracking(videoId);
  }

  /// Get user's view count for a specific video
  int getUserViewCount(String videoId, String userId) {
    return _userViewCounts['${videoId}_$userId'] ?? 0;
  }

  /// Check if user has reached max views for a video
  bool hasReachedMaxViews(String videoId, String userId) {
    return getUserViewCount(videoId, userId) >= 10;
  }

  /// **NEW: Check if user is viewing their own video**
  bool isViewingOwnVideo(String videoUploaderId, String userId) {
    return videoUploaderId == userId;
  }

  /// **NEW: Check if view is too soon (rapid repeat spam)**
  bool isViewTooSoon(String videoId, String userId) {
    final viewKey = '${videoId}_$userId';
    final lastViewTime = _recentViews[viewKey];
    if (lastViewTime == null) return false;

    final timeSinceLastView = DateTime.now().difference(lastViewTime);
    return timeSinceLastView < _minViewInterval;
  }

  /// Clear all view tracking data
  void clearViewTracking() {
    AppLogger.log('🎯 VideoViewTracker: Clearing all view tracking data');

    // Cancel all active timers
    for (final timer in _viewTimers.values) {
      timer.cancel();
    }

    _viewTimers.clear();
    _userViewCounts.clear();
    _recentViews.clear(); // **NEW: Clear recent views tracking**
  }

  /// **NEW: Track video completion for watch history**
  /// This should work for BOTH authenticated and anonymous users.
  Future<void> trackVideoCompletion(String videoId, {int? duration, String? videoHash}) async {
    try {
      AppLogger.log('📊 VideoViewTracker: Tracking video completion for $videoId');

      final platformIdService = PlatformIdService();
      final platformId = await platformIdService.getPlatformId();

      // **NEW: BATCHED COMPLETION TRACKING**
      _queueWatchEvent(videoId, duration ?? 0, true, platformId, videoHash);
    } catch (e) {
      AppLogger.log('❌ VideoViewTracker: Error tracking video completion: $e');
    }
  }

  /// **NEW: Queue watch event for batching**
  void _queueWatchEvent(String videoId, int duration, bool completed, String platformId, String? videoHash) {
    _pendingWatchEvents.add({
      'videoId': videoId,
      'duration': duration,
      'completed': completed,
      'platformId': platformId,
      'videoHash': videoHash,
      'timestamp': DateTime.now().toIso8601String(),
    });

    AppLogger.log('📊 VideoViewTracker: Queued watch event for $videoId (Total queued: ${_pendingWatchEvents.length})');

    if (_pendingWatchEvents.length >= _maxBatchSize) {
      syncWatchEvents();
    } else {
      _startBatchTimer();
    }
  }

  /// **NEW: Start timer for periodic batch sync**
  void _startBatchTimer() {
    _batchSyncTimer?.cancel();
    _batchSyncTimer = Timer(_batchSyncInterval, () {
      syncWatchEvents();
    });
  }

  /// **NEW: Sync queued watch events in a single batch**
  Future<void> syncWatchEvents() async {
    if (_pendingWatchEvents.isEmpty) return;

    _batchSyncTimer?.cancel();
    final eventsToSync = List<Map<String, dynamic>>.from(_pendingWatchEvents);
    _pendingWatchEvents.clear();

    try {
      AppLogger.log('🔄 VideoViewTracker: Syncing ${eventsToSync.length} watch events via BATCH...');

      final token = await AuthService.getToken();
      final headers = <String, String>{
        'Content-Type': 'application/json',
      };
      
      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }

      // **BACKEND: POST /api/videos/watch/batch**
      final url = Uri.parse('$_baseUrl/api/videos/watch/batch');
      final response = await httpClientService.withRequestContext(
        feature: 'video_feed',
        uiAction: 'watch_batch',
        request: () => httpClientService.post(
          url,
          headers: headers,
          body: json.encode({'events': eventsToSync}),
        ),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        AppLogger.log('✅ VideoViewTracker: Batch sync of watch events successful');
      } else {
        AppLogger.log('❌ VideoViewTracker: Batch sync failed (${response.statusCode}): ${response.body}');
        // Re-queue if server error
        if (response.statusCode >= 500 || response.statusCode == 429) {
          _pendingWatchEvents.insertAll(0, eventsToSync);
        }
      }
    } catch (e) {
      AppLogger.log('❌ VideoViewTracker: Error syncing watch events batch: $e');
      // Re-queue on network error
      _pendingWatchEvents.insertAll(0, eventsToSync);
    }
  }

  /// **NEW: Track video skip via API**
  Future<void> _trackSkip(String videoId) async {
    try {
      final now = DateTime.now();
      final lastSkip = _recentSkips[videoId];
      if (lastSkip != null && now.difference(lastSkip) < _minSkipInterval) {
        AppLogger.log('VideoViewTracker: Duplicate skip ignored for $videoId');
        return;
      }
      _recentSkips[videoId] = now;
      if (_recentSkips.length > 100) {
        _recentSkips.removeWhere(
          (_, timestamp) => now.difference(timestamp) >= _minSkipInterval,
        );
      }

      final token = await AuthService.getToken();
      final platformId = await PlatformIdService().getPlatformId();
      
      final headers = <String, String>{
        'Content-Type': 'application/json',
      };
      
      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }
      
      if (platformId.isNotEmpty) {
        headers['x-device-id'] = platformId;
      }

      final url = Uri.parse('$_baseUrl/api/videos/$videoId/skip');
      
      // Fire and forget
      httpClientService.withRequestContext(
        feature: 'video_feed',
        uiAction: 'skip',
        request: () => httpClientService.post(
          url,
          headers: headers,
          body: json.encode({}),
        ),
      ).then((response) {
        if (response.statusCode == 200) {
          AppLogger.log('✅ VideoViewTracker: Skip tracked for $videoId');
        } else {
          AppLogger.log('⚠️ VideoViewTracker: Skip tracking failed (${response.statusCode})');
        }
      }).catchError((e) {
        AppLogger.log('❌ VideoViewTracker: Error tracking skip: $e');
      });
      
      // Also queue as a watch event with completed: false
      _queueWatchEvent(videoId, 0, false, platformId, null);
    } catch (e) {
       AppLogger.log('❌ VideoViewTracker: Exception in _trackSkip: $e');
    }
  }

  /// Dispose of the service and clean up resources
  void dispose() {
    AppLogger.log('🎯 VideoViewTracker: Disposing service');
    WidgetsBinding.instance.removeObserver(this);
    clearViewTracking();
  }
}

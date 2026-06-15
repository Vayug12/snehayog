import 'package:flutter/material.dart';
import 'package:vayug/shared/utils/app_logger.dart';

import 'package:vayug/features/video/core/data/models/video_model.dart';
import 'package:vayug/shared/managers/smart_cache_manager.dart';

import 'package:vayug/shared/services/app_remote_config_service.dart';

import 'package:firebase_core/firebase_core.dart';
import 'package:vayug/shared/services/notification_service.dart';
import 'package:vayug/features/video/core/data/services/video_service.dart';
import 'package:vayug/shared/services/hls_warmup_service.dart';
import 'package:vayug/features/video/core/data/services/video_cache_proxy_service.dart';
import 'dart:async'; // For unawaited;
/// **AppInitializationManager**
/// 
/// Centralizes and sequences app startup logic to prevent "thundering herd"
/// lag issues. It prioritizes vital UI content (First 10 Videos) over
/// background tasks (Ads, Firebase, etc.).
class AppInitializationManager {
  // Singleton instance
  static final AppInitializationManager instance =
      AppInitializationManager._internal();

  AppInitializationManager._internal();

  // State
  bool _isStage1Complete = false;
  bool _isStage2Complete = false;
  bool _isStage3Complete = false;
  
  // Progress tracking
  final ValueNotifier<double> initializationProgress = ValueNotifier(0.0);
  final ValueNotifier<String> initializationStatus = ValueNotifier('Initializing...');

  bool get isStage2Complete => _isStage2Complete;

  // Track the vital first page of videos
  List<VideoModel>? initialVideos;
  DateTime? _initialVideosTimestamp;
  bool hasInitialVideosMore = false;
  
  // **NEW: Completer for background fetch synchronization**
  final Completer<List<VideoModel>?> _backgroundFetchCompleter = Completer<List<VideoModel>?>();
  Future<List<VideoModel>?> get backgroundFetchFuture => _backgroundFetchCompleter.future;

  // **NEW: Track if a forced update is required**
  final ValueNotifier<bool> isUpdateRequired = ValueNotifier(false);

  /// **NEW: Check if initialVideos are still fresh (within 3 minutes)**
  bool get isInitialVideosFresh {
    if (initialVideos == null || _initialVideosTimestamp == null) return false;
    final age = DateTime.now().difference(_initialVideosTimestamp!);
    return age < const Duration(minutes: 3);
  }
  
  /// **NEW: Clear cached initial videos on auth change**
  void clearCache() {
    initialVideos = null;
    _initialVideosTimestamp = null;
    AppLogger.log('🧹 InitManager: Cache cleared (Auth Change)');
    
  }

  // --- STAGE 1: AVAILABLE IMMEDIATELY (Before UI) ---
  /// Called before `runApp`. Setup basic config.
  Future<void> initializeStage1() async {
    if (_isStage1Complete) return;

    try {
      AppLogger.log('🚀 InitManager: Stage 1 (Config) Started');
      initializationProgress.value = 0.1;
      initializationStatus.value = 'Starting...';
      
      // 1. Firebase (Critical for Network Interceptors)
      try {
        await Firebase.initializeApp();
        initializationProgress.value = 0.5;
        AppLogger.log('✅ InitManager: Firebase initialized');
      } catch (e) {
        AppLogger.log('⚠️ InitManager: Firebase Init Error: $e');
      }

      // **OPTIMIZATION: Server URL check and SmartCache are now deferred**
      // Use last known working URL from AppConfig (no-ping)
      
      _isStage1Complete = true;
    } catch (e) {
      AppLogger.log('❌ InitManager: Stage 1 Failed: $e');
      _isStage1Complete = true;
    }
  }

  // --- STAGE 2: VITAL CONTENT (While Splash Visible) ---
  /// Called by SplashScreen. Fetches First Video & Profile.
  /// Goal: Ensure VideoFeed has content READY when it mounts.
  Future<void> initializeStage2(BuildContext context) async {
    if (_isStage2Complete) {
      return;
    }

    try {
      AppLogger.log('🚀 InitManager: Stage 2 (Insta-Switch) Started');
      
      // Reset progress immediately to trigger transition
      initializationProgress.value = 0.0;
      
      // **PARALLELISM: Start Stage 1 and background tasks**
      final stage1Future = initializeStage1();
      final videoService = VideoService();

      // Ensure Stage 1 (Firebase) completes quickly
      await stage1Future;

      // Task A: Video fetching - Start in background immediately (unawaited)
      unawaited(_fetchAndPreloadFirstVideos(videoService));

      // **INSTANT BOOT: Stage 2 completes immediately after Stage 1**
      // We no longer block on _fastAuthGate (Google Silent Auth) or Server Pings
      initializationProgress.value = 1.0;
      initializationStatus.value = 'Ready!';
      _isStage2Complete = true;
      
      AppLogger.log('✅ InitManager: Stage 2 Logic Unlocked (Optimistic Boot)');
    } catch (e) {
      AppLogger.log('❌ InitManager: Stage 2 Failed: $e');
      initializationProgress.value = 1.0;
      _isStage2Complete = true;
    }
  }

  /// Helper: Fetch videos and pre-initialize the first one
  Future<void> _fetchAndPreloadFirstVideos(VideoService videoService) async {
    try {
      AppLogger.log('📥 InitManager: Fetching Page 1 Videos (Yug) in background...');
      
      // 1. Network Call
      final result = await videoService.getVideos(
        page: 1, 
        limit: 15, 
        videoType: 'yog'
      );
      
      final List<dynamic> rawList = result['videos'];
      final videos = rawList.cast<VideoModel>();

      if (videos.isNotEmpty) {
        initialVideos = videos;
        hasInitialVideosMore = result['hasMore'] ?? false;
        _initialVideosTimestamp = DateTime.now();
        AppLogger.log('✅ InitManager: Background fetch complete (${videos.length} videos).');
        
        // Complete the future for listeners
        if (!_backgroundFetchCompleter.isCompleted) {
          _backgroundFetchCompleter.complete(videos);
        }

        // 2. Warm up HLS for next few in background
        unawaited(_warmUpNextVideos(videos));
      } else {
        if (!_backgroundFetchCompleter.isCompleted) {
          _backgroundFetchCompleter.complete(null);
        }
      }
    } catch (e) {
       AppLogger.log('❌ InitManager: Background Video Fetch Failed: $e');
       
       // Complete the future even on error
       if (!_backgroundFetchCompleter.isCompleted) {
         _backgroundFetchCompleter.complete(null);
       }
       
       // **NEW: Check for Version Error (Force Update)**
       final errorStr = e.toString();
       if (errorStr.contains('Unsupported API Version') || 
           errorStr.contains('410') || 
           (errorStr.contains('400') && errorStr.contains('API Version'))) {
          AppLogger.log('🚨 InitManager: CRITICAL VERSION ERROR DETECTED. Forcing update dialog.');
          isUpdateRequired.value = true;
          initializationStatus.value = 'Update Required';
       }
    }
  }

  Future<void> _warmUpNextVideos(List<VideoModel> videos) async {
      // Warm up HLS connection for video 2 and 3
      for (var i = 1; i < videos.length && i < 3; i++) {
        final video = videos[i];
        final url = video.hlsPlaylistUrl ?? video.videoUrl;
        if (url.contains('.m3u8')) {
          HlsWarmupService().warmUp(url);
        }
      }
  }


  /// **REMOVED: _fastAuthGate is now deferred to mid-session token refresh/interceptors**


  // --- STAGE 3: DEFERRED SERVICES (After Home Mount) ---
  /// Called by MainScreen after 3-5 seconds.
  /// Goal: Load heavy SDKs without stuttering the scrolling.
  Future<void> initializeStage3() async {
    if (_isStage3Complete) return;

    try {
       AppLogger.log('🚀 InitManager: Stage 3 (Deferred Services) Started');

       // 1. Initialize Smart Cache (Memory Only)
       // Now in Stage 3 to avoid blocking cold start
       try {
         await SmartCacheManager().initialize();
         AppLogger.log('✅ InitManager: SmartCache initialized');
         
         // Initialize Video Cache Proxy Server for E2EE decryption & caching
         await videoCacheProxy.initialize();
         AppLogger.log('✅ InitManager: VideoCacheProxyService initialized');
       } catch (e) {
         AppLogger.log('⚠️ InitManager: SmartCache/Proxy Init Error: $e');
       }

       // 2. Notifications (Firebase already initialized in Stage 1)
       try {
         final notificationService = NotificationService();
         await notificationService.initialize();
         AppLogger.log('✅ InitManager: Notifications initialized');
       } catch (e) {
         AppLogger.log('Notification Init Error: $e');
       }

       // 3. Remote Config
       try {
         await AppRemoteConfigService.instance.initialize();
       } catch(_) {}

       _isStage3Complete = true;
       AppLogger.log('✅ InitManager: Stage 3 Complete');

    } catch (e) {
       AppLogger.log('❌ InitManager: Stage 3 Failed: $e');
    }
  }
}


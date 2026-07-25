import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vayug/shared/config/app_config.dart';
import 'package:vayug/features/auth/data/services/authservices.dart';
import 'package:vayug/shared/utils/app_logger.dart';
import 'package:vayug/shared/services/http_client_service.dart';

class AdImpressionService {
  static final AdImpressionService _instance = AdImpressionService._internal();
  factory AdImpressionService() => _instance;
  AdImpressionService._internal();

  final AuthService _authService = AuthService();
  static const String _kOfflineImpressionsKey = 'offline_ad_impressions';

  // **NEW: Deduplication Cache to prevent spamming the server**
  final Map<String, DateTime> _dedupeCache = {};
  static const Duration _dedupeThreshold = Duration(seconds: 5);

  bool _isDuplicate(String key) {
    final now = DateTime.now();
    final lastTracked = _dedupeCache[key];
    
    if (lastTracked != null && now.difference(lastTracked) < _dedupeThreshold) {
      return true;
    }
    
    _dedupeCache[key] = now;
    
    // Cleanup old entries periodically
    if (_dedupeCache.length > 50) {
      _dedupeCache.removeWhere((_, time) => now.difference(time) > _dedupeThreshold);
    }
    return false;
  }

  /// **NEW: Remove from cache to allow retry on failure**
  void _removeFromDedupe(String key) {
    _dedupeCache.remove(key);
  }

  /// **OPTIMIZED: Read JWT token directly from SharedPreferences**
  /// Avoids calling getUserData() (which may trigger a network request) just for the token.
  Future<String?> _getToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('jwt_token');
    } catch (_) {
      return null;
    }
  }

  /// **NEW: Initialize service to listen for connectivity changes**
  void initialize() {
    Connectivity().onConnectivityChanged.listen((results) {
        final isOnline = results.any((result) =>
            result == ConnectivityResult.mobile ||
            result == ConnectivityResult.wifi);
            
      if (isOnline) {
        AppLogger.log('🌐 AdImpressionService: Back online, syncing offline impressions...');
        syncOfflineImpressions();
      }
    });
    
    // Also try to sync on app start
    syncOfflineImpressions();
  }

  /// Track banner ad impression for a video
  Future<void> trackBannerAdImpression({
    required String videoId,
    required String adId,
    required String userId,
  }) async {
    final dedupeKey = 'banner:$videoId:$adId:$userId';
    if (_isDuplicate(dedupeKey)) return;

    try {
      AppLogger.log('📊 AdImpressionService: Tracking banner ad impression:');
      AppLogger.log('   Video ID: $videoId');
      AppLogger.log('   Ad ID: $adId');
      AppLogger.log('   User ID: $userId');

      final url = '${NetworkHelper.adsEndpoint}/impressions/banner';
      AppLogger.log('📊 AdImpressionService: Tracking API URL: $url');

      final response = await httpClientService.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${await _getToken()}',
        },
        body: json.encode({
          'videoId': videoId,
          'adId': adId,
          'userId': userId,
          // NOTE: creatorId is NOT sent - backend fetches it from Video document
          // This avoids ID type confusion (googleId vs MongoDB ObjectId)
          'adType': 'banner',
          'timestamp': DateTime.now().toIso8601String(),
          'impressionType': 'view',
        }),
      );

      AppLogger.log(
          '📊 AdImpressionService: Tracking API response status: ${response.statusCode}');
      AppLogger.log(
          '📊 AdImpressionService: Tracking API response body: ${response.body}');

      if (response.statusCode == 201 || response.statusCode == 200) {
        AppLogger.log(
            '✅ AdImpressionService: Banner ad impression tracked successfully: Video $videoId, Ad $adId');
      } else {
        AppLogger.log(
            '❌ AdImpressionService: Failed to track banner ad impression: ${response.body}');
        
        // **NEW: Clear dedupe on failure to allow retry**
        _removeFromDedupe(dedupeKey);

        // **NEW: Queue offline**
        _queueOfflineImpression({
          'videoId': videoId,
          'adId': adId,
          'userId': userId,
          'adType': 'banner',
          'timestamp': DateTime.now().toIso8601String(),
          'impressionType': 'view',
        });
      }
    } catch (e) {
      AppLogger.log(
          '❌ AdImpressionService: Error tracking banner ad impression: $e');
      
      // **NEW: Clear dedupe on error to allow retry**
      _removeFromDedupe(dedupeKey);

      // **NEW: Queue offline**
      _queueOfflineImpression({
        'videoId': videoId,
        'adId': adId,
        'userId': userId,
        'adType': 'banner',
        'timestamp': DateTime.now().toIso8601String(),
        'impressionType': 'view',
      });
    }
  }

  /// Track carousel ad impression when user scrolls
  Future<void> trackCarouselAdImpression({
    required String videoId,
    required String adId,
    required String userId,
    required int scrollPosition,
  }) async {
    final dedupeKey = 'carousel:$videoId:$adId:$userId:$scrollPosition';
    if (_isDuplicate(dedupeKey)) return;

    try {
      final response = await httpClientService.post(
        Uri.parse('${NetworkHelper.adsEndpoint}/impressions/carousel'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${await _getToken()}',
        },
        body: json.encode({
          'videoId': videoId,
          'adId': adId,
          'userId': userId,
          'adType': 'carousel',
          'scrollPosition': scrollPosition,
          'timestamp': DateTime.now().toIso8601String(),
          'impressionType': 'scroll_view',
        }),
      );

      if (response.statusCode == 201 || response.statusCode == 200) {
        AppLogger.log(
            '📊 Carousel ad impression tracked: Video $videoId, Ad $adId, Position: $scrollPosition');
      } else {
        AppLogger.log(
            '❌ Failed to track carousel ad impression: ${response.body}');
        
        // **NEW: Clear dedupe on failure to allow retry**
        _removeFromDedupe(dedupeKey);

        // **NEW: Queue offline**
        _queueOfflineImpression({
          'videoId': videoId,
          'adId': adId,
          'userId': userId,
          'adType': 'carousel',
          'scrollPosition': scrollPosition,
          'timestamp': DateTime.now().toIso8601String(),
          'impressionType': 'scroll_view',
        });
      }
    } catch (e) {
      AppLogger.log('❌ Error tracking carousel ad impression: $e');
      
      // **NEW: Clear dedupe on error to allow retry**
      _removeFromDedupe(dedupeKey);

      // **NEW: Queue offline**
        _queueOfflineImpression({
          'videoId': videoId,
          'adId': adId,
          'userId': userId,
          'adType': 'carousel',
          'scrollPosition': scrollPosition,
          'timestamp': DateTime.now().toIso8601String(),
          'impressionType': 'scroll_view',
        });
    }
  }

  /// **NEW: Track carousel ad click**
  Future<void> trackCarouselAdClick({
    required String videoId,
    required String adId,
    required String userId,
  }) async {
    try {
      AppLogger.log('🖱️ AdImpressionService: Tracking carousel ad click:');
      AppLogger.log('   Video ID: $videoId');
      AppLogger.log('   Ad ID: $adId');
      AppLogger.log('   User ID: $userId');

      final url = '${NetworkHelper.adsEndpoint}/track-click/$adId';
      final response = await httpClientService.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${await _getToken()}',
        },
        body: json.encode({
          'videoId': videoId,
          'adId': adId,
          'userId': userId,
          'adType': 'carousel',
          'timestamp': DateTime.now().toIso8601String(),
        }),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        AppLogger.log('✅ AdImpressionService: Carousel ad click tracked successfully');
      } else {
        AppLogger.log('❌ AdImpressionService: Failed to track carousel ad click: ${response.body}');
        _queueOfflineImpression({
          'videoId': videoId,
          'adId': adId,
          'userId': userId,
          'adType': 'carousel',
          'timestamp': DateTime.now().toIso8601String(),
          'impressionType': 'click',
        });
      }
    } catch (e) {
      AppLogger.log('❌ AdImpressionService: Error tracking carousel ad click: $e');
      _queueOfflineImpression({
        'videoId': videoId,
        'adId': adId,
        'userId': userId,
        'adType': 'carousel',
        'timestamp': DateTime.now().toIso8601String(),
        'impressionType': 'click',
      });
    }
  }

  /// **NEW: Track general ad click (for banner/popup)**
  Future<void> trackAdClick({
    required String videoId,
    required String adId,
    required String userId,
    required String adType,
  }) async {
    try {
      AppLogger.log('🖱️ AdImpressionService: Tracking $adType ad click:');
      AppLogger.log('   Video ID: $videoId');
      AppLogger.log('   Ad ID: $adId');
      AppLogger.log('   User ID: $userId');

      final url = '${NetworkHelper.adsEndpoint}/track-click/$adId';
      final response = await httpClientService.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${await _getToken()}',
        },
        body: json.encode({
          'videoId': videoId,
          'adId': adId,
          'userId': userId,
          'adType': adType,
          'timestamp': DateTime.now().toIso8601String(),
        }),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        AppLogger.log('✅ AdImpressionService: $adType ad click tracked successfully');
      } else {
        AppLogger.log('❌ AdImpressionService: Failed to track $adType ad click: ${response.body}');
        _queueOfflineImpression({
          'videoId': videoId,
          'adId': adId,
          'userId': userId,
          'adType': adType,
          'timestamp': DateTime.now().toIso8601String(),
          'impressionType': 'click',
        });
      }
    } catch (e) {
      AppLogger.log('❌ AdImpressionService: Error tracking $adType ad click: $e');
      _queueOfflineImpression({
        'videoId': videoId,
        'adId': adId,
        'userId': userId,
        'adType': adType,
        'timestamp': DateTime.now().toIso8601String(),
        'impressionType': 'click',
      });
    }
  }

  /// Get total ad impressions for a video
  Future<Map<String, int>> getVideoAdImpressions(String videoId) async {
    try {
      final userData = await _authService.getUserData();
      if (userData == null) return {'banner': 0, 'carousel': 0, 'total': 0};

      final response = await httpClientService.get(
        Uri.parse('${NetworkHelper.adsEndpoint}/impressions/video/$videoId'),
        headers: {
          'Authorization': 'Bearer ${userData['token']}',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return {
          'banner': data['bannerImpressions'] ?? 0,
          'carousel': data['carouselImpressions'] ?? 0,
          'total': data['totalImpressions'] ?? 0,
        };
      }

      return {'banner': 0, 'carousel': 0, 'total': 0};
    } catch (e) {
      AppLogger.log('❌ Error getting ad impressions: $e');
      return {'banner': 0, 'carousel': 0, 'total': 0};
    }
  }

  /// Get banner ad impressions for a video (real API call)
  Future<int> getBannerAdImpressions(String videoId) async {
    try {
      AppLogger.log(
          '📊 AdImpressionService: Getting banner ad impressions for video: $videoId');

      final userData = await _authService.getUserData();
      if (userData == null) {
        AppLogger.log('❌ AdImpressionService: No authenticated user found');
        return 0;
      }

      final url =
          '${NetworkHelper.adsEndpoint}/impressions/video/$videoId/banner';
      AppLogger.log('📊 AdImpressionService: API URL: $url');

      final response = await httpClientService.get(
        Uri.parse(url),
        headers: {
          'Authorization': 'Bearer ${userData['token']}',
        },
      );

      AppLogger.log(
          '📊 AdImpressionService: API response status: ${response.statusCode}');
      AppLogger.log(
          '📊 AdImpressionService: API response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final count = data['count'] ?? 0;
        AppLogger.log(
            '📊 AdImpressionService: Banner impressions count: $count');
        return count;
      } else {
        AppLogger.log(
            '❌ AdImpressionService: Failed to get banner impressions - Status: ${response.statusCode}');
        return 0;
      }
    } catch (e) {
      AppLogger.log(
          '❌ AdImpressionService: Error getting banner ad impressions: $e');
      return 0;
    }
  }

  /// Get carousel ad impressions for a video (real API call)
  Future<int> getCarouselAdImpressions(String videoId) async {
    try {
      final userData = await _authService.getUserData();
      if (userData == null) return 0;

      final response = await httpClientService.get(
        Uri.parse(
            '${NetworkHelper.adsEndpoint}/impressions/video/$videoId/carousel'),
        headers: {
          'Authorization': 'Bearer ${userData['token']}',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['count'] ?? 0;
      }

      return 0;
    } catch (e) {
      AppLogger.log('❌ Error getting carousel ad impressions: $e');
      return 0;
    }
  }

  /// **NEW: Track banner ad VIEW (minimum 2-3 seconds visible) - for revenue calculation**
  Future<void> trackBannerAdView({
    required String videoId,
    required String adId,
    required String userId,
    required double viewDuration, // Duration in seconds
  }) async {
    final dedupeKey = 'banner-view:$videoId:$adId:$userId';
    if (_isDuplicate(dedupeKey)) return;

    try {
      AppLogger.log('👁️ AdImpressionService: Tracking banner ad VIEW:');
      AppLogger.log('   Video ID: $videoId');
      AppLogger.log('   Ad ID: $adId');
      AppLogger.log('   User ID: $userId');
      AppLogger.log('   View Duration: ${viewDuration}s');

      final url = '${NetworkHelper.adsEndpoint}/impressions/banner/view';
      final response = await httpClientService.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${await _getToken()}',
        },
        body: json.encode({
          'videoId': videoId,
          'adId': adId,
          'userId': userId,
          'viewDuration': viewDuration,
        }),
      );

      if (response.statusCode == 200) {
        AppLogger.log(
            '✅ AdImpressionService: Banner ad VIEW tracked successfully: Video $videoId, Ad $adId, Duration: ${viewDuration}s');
      } else {
        AppLogger.log(
            '❌ AdImpressionService: Failed to track banner ad view: ${response.body}');
      }
    } catch (e) {
      AppLogger.log('❌ AdImpressionService: Error tracking banner ad view: $e');
    }
  }

  /// **NEW: Track carousel ad VIEW (minimum 2-3 seconds visible) - for revenue calculation**
  Future<void> trackCarouselAdView({
    required String videoId,
    required String adId,
    required String userId,
    required double viewDuration, // Duration in seconds
  }) async {
    final dedupeKey = 'carousel-view:$videoId:$adId:$userId';
    if (_isDuplicate(dedupeKey)) return;

    try {
      AppLogger.log('👁️ AdImpressionService: Tracking carousel ad VIEW:');
      AppLogger.log('   Video ID: $videoId');
      AppLogger.log('   Ad ID: $adId');
      AppLogger.log('   User ID: $userId');
      AppLogger.log('   View Duration: ${viewDuration}s');

      final url = '${NetworkHelper.adsEndpoint}/impressions/carousel/view';
      final response = await httpClientService.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${await _getToken()}',
        },
        body: json.encode({
          'videoId': videoId,
          'adId': adId,
          'userId': userId,
          'viewDuration': viewDuration,
        }),
      );

      if (response.statusCode == 200) {
        AppLogger.log(
            '✅ AdImpressionService: Carousel ad VIEW tracked successfully: Video $videoId, Ad $adId, Duration: ${viewDuration}s');
      } else {
        AppLogger.log(
            '❌ AdImpressionService: Failed to track carousel ad view: ${response.body}');
      }
    } catch (e) {
      AppLogger.log(
          '❌ AdImpressionService: Error tracking carousel ad view: $e');
    }
  }

  /// **NEW: Get banner ad VIEWS (not impressions) for revenue calculation**
  Future<int> getBannerAdViews(String videoId) async {
    try {
      AppLogger.log(
          '👁️ AdImpressionService: Getting banner ad VIEWS for video: $videoId');

      final userData = await _authService.getUserData();
      if (userData == null) {
        AppLogger.log('❌ AdImpressionService: No authenticated user found');
        return 0;
      }

      final url = '${NetworkHelper.adsEndpoint}/views/video/$videoId/banner';
      AppLogger.log('👁️ AdImpressionService: API URL: $url');

      final response = await httpClientService.get(
        Uri.parse(url),
        headers: {
          'Authorization': 'Bearer ${userData['token']}',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final count = data['count'] ?? 0;
        AppLogger.log('👁️ AdImpressionService: Banner VIEWS count: $count');
        return count;
      } else {
        AppLogger.log(
            '❌ AdImpressionService: Failed to get banner views - Status: ${response.statusCode}');
        return 0;
      }
    } catch (e) {
      AppLogger.log('❌ AdImpressionService: Error getting banner ad views: $e');
      return 0;
    }
  }

  /// **NEW: Get carousel ad VIEWS (not impressions) for revenue calculation**
  Future<int> getCarouselAdViews(String videoId) async {
    try {
      AppLogger.log(
          '👁️ AdImpressionService: Getting carousel ad VIEWS for video: $videoId');

      final userData = await _authService.getUserData();
      if (userData == null) return 0;

      final url = '${NetworkHelper.adsEndpoint}/views/video/$videoId/carousel';
      final response = await httpClientService.get(
        Uri.parse(url),
        headers: {
          'Authorization': 'Bearer ${userData['token']}',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final count = data['count'] ?? 0;
        AppLogger.log('👁️ AdImpressionService: Carousel VIEWS count: $count');
        return count;
      }

      return 0;
    } catch (e) {
      AppLogger.log('❌ Error getting carousel ad views: $e');
      return 0;
    }
  }

  /// **NEW: Get banner ad VIEWS for current month only**
  Future<int> getBannerAdViewsForMonth(
      String videoId, int month, int year) async {
    try {
      AppLogger.log(
          '👁️ AdImpressionService: Getting banner ad VIEWS for current month ($month/$year) for video: $videoId');

      final userData = await _authService.getUserData();
      if (userData == null) {
        AppLogger.log('❌ AdImpressionService: No authenticated user found');
        return 0;
      }

      final url =
          '${NetworkHelper.adsEndpoint}/views/video/$videoId/banner?month=$month&year=$year';
      AppLogger.log('👁️ AdImpressionService: API URL: $url');

      final response = await httpClientService.get(
        Uri.parse(url),
        headers: {
          'Authorization': 'Bearer ${userData['token']}',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final count = data['count'] ?? 0;
        AppLogger.log(
            '👁️ AdImpressionService: Banner VIEWS count for $month/$year: $count');
        return count;
      } else {
        AppLogger.log(
            '❌ AdImpressionService: Failed to get banner views - Status: ${response.statusCode}');
        return 0;
      }
    } catch (e) {
      AppLogger.log(
          '❌ AdImpressionService: Error getting banner ad views for month: $e');
      return 0;
    }
  }

  /// **NEW: Get carousel ad VIEWS for current month only**
  Future<int> getCarouselAdViewsForMonth(
      String videoId, int month, int year) async {
    try {
      AppLogger.log(
          '👁️ AdImpressionService: Getting carousel ad VIEWS for current month ($month/$year) for video: $videoId');

      final userData = await _authService.getUserData();
      if (userData == null) return 0;

      final url =
          '${NetworkHelper.adsEndpoint}/views/video/$videoId/carousel?month=$month&year=$year';
      final response = await httpClientService.get(
        Uri.parse(url),
        headers: {
          'Authorization': 'Bearer ${userData['token']}',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final count = data['count'] ?? 0;
        AppLogger.log(
            '👁️ AdImpressionService: Carousel VIEWS count for $month/$year: $count');
        return count;
      }

      return 0;
    } catch (e) {
      AppLogger.log('❌ Error getting carousel ad views for month: $e');
      return 0;
    }
  }

  /// **NEW: Queue offline impression**
  Future<void> _queueOfflineImpression(Map<String, dynamic> impressionData) async {
    try {
      AppLogger.log('💾 AdImpressionService: Queuing offline impression...');
      final prefs = await SharedPreferences.getInstance();
      final List<String> queued = prefs.getStringList(_kOfflineImpressionsKey) ?? [];
      
      queued.add(json.encode(impressionData));
      await prefs.setStringList(_kOfflineImpressionsKey, queued);
      
      AppLogger.log('✅ AdImpressionService: Impression queued offline (Total queued: ${queued.length})');
    } catch (e) {
      AppLogger.log('❌ AdImpressionService: Error queuing offline impression: $e');
    }
  }

  /// **NEW: Sync offline impressions when back online**
  Future<void> syncOfflineImpressions() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final List<String> queued = prefs.getStringList(_kOfflineImpressionsKey) ?? [];
      
      if (queued.isEmpty) return;

      AppLogger.log('🔄 AdImpressionService: Syncing ${queued.length} offline impressions via BATCH...');
      
      final List<Map<String, dynamic>> impressions = [];
      for (final jsonStr in queued) {
        try {
          impressions.add(json.decode(jsonStr) as Map<String, dynamic>);
        } catch (e) {
          AppLogger.log('⚠️ AdImpressionService: Error decoding queued impression: $e');
        }
      }

      if (impressions.isEmpty) {
        await prefs.setStringList(_kOfflineImpressionsKey, []);
        return;
      }

      final userData = await _authService.getUserData();
      final token = userData?['token'];
      
      if (token == null) {
         AppLogger.log('⚠️ AdImpressionService: Cannot sync - No auth token');
         return;
      }

      final url = '${NetworkHelper.adsEndpoint}/impressions/batch';
      final response = await httpClientService.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode({'impressions': impressions}),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        AppLogger.log('✅ AdImpressionService: All ${impressions.length} offline impressions synced successfully');
        await prefs.setStringList(_kOfflineImpressionsKey, []);
      } else {
        AppLogger.log('❌ AdImpressionService: Batch sync failed (${response.statusCode}): ${response.body}');
        // Optional: Implement retry logic or partial failure handling here
        // For now, we keep them in the queue if it's a server error
        if (response.statusCode >= 500 || response.statusCode == 429) {
          // Keep in queue
        } else {
          // Clear if it's a permanent error (4xx) to avoid poison messages
          await prefs.setStringList(_kOfflineImpressionsKey, []);
        }
      }
    } catch (e) {
      AppLogger.log('❌ AdImpressionService: Error during offline sync: $e');
    }
  }

  /// **NEW: Get granular breakdown of ad performance per video**
  Future<List<Map<String, dynamic>>> getAdVideoBreakdown(String adId) async {
    try {
      AppLogger.log('📊 AdImpressionService: Getting video breakdown for ad: $adId');

      final userData = await _authService.getUserData();
      if (userData == null) return [];

      final url = '${NetworkHelper.adsEndpoint}/analytics/$adId/video-breakdown';
      final response = await httpClientService.get(
        Uri.parse(url),
        headers: {
          'Authorization': 'Bearer ${userData['token']}',
        },
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return List<Map<String, dynamic>>.from(data);
      } else {
        AppLogger.log('❌ AdImpressionService: Failed to get ad breakdown - Status: ${response.statusCode}');
        return [];
      }
    } catch (e) {
      AppLogger.log('❌ AdImpressionService: Error getting ad video breakdown: $e');
      return [];
    }
  }
}

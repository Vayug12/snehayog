import 'dart:convert';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vayug/features/ads/data/ad_model.dart';
import 'package:vayug/features/ads/data/wallet_model.dart';
import 'package:vayug/features/auth/data/services/authservices.dart';
import 'package:vayug/shared/services/cloudflare_r2_service.dart';
import 'package:vayug/shared/config/app_config.dart';
import 'package:vayug/shared/managers/smart_cache_manager.dart';
import 'package:vayug/features/ads/data/services/active_ads_service.dart';
import 'package:vayug/features/ads/domain/i_ad_service.dart';
import 'package:vayug/features/ads/data/services/ad_refresh_notifier.dart';
import 'package:vayug/shared/utils/app_logger.dart';
import 'package:vayug/shared/services/http_client_service.dart';

class AdService {
  static final AdService _instance = AdService._internal();
  factory AdService() => _instance;
  AdService._internal();

  static String get baseUrl => AppConfig.baseUrl;
  final AuthService _authService = AuthService();
  final CloudflareR2Service _cloudflareService = CloudflareR2Service();
  final SmartCacheManager _cacheManager = SmartCacheManager();
  final IAdService _activeAdsService = ActiveAdsService();
  final AdRefreshNotifier _adRefreshNotifier = AdRefreshNotifier();

  // Create a new ad
  Future<AdModel> createAd({
    required String title,
    required String description,
    String? imageUrl,
    String? videoUrl,
    String? link,
    required String adType,
    required int budget,
    required String targetAudience,
    required List<String> targetKeywords,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      final userData = await _authService.getUserData();
      if (userData == null) {
        throw Exception('User not authenticated');
      }

      // **NEW: Calculate impressions based on ad type CPM**
      final cpm = adType == 'banner' ? AppConfig.bannerCpm : AppConfig.fixedCpm;
      final impressions = AppConfig.calculateImpressionsFromBudgetWithCpm(
        budget / 100.0,
        cpm,
      );

      final response = await httpClientService.post(
        Uri.parse('$baseUrl/api/ads'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${userData['token']}',
        },
        body: json.encode({
          'title': title,
          'description': description,
          'imageUrl': imageUrl,
          'videoUrl': videoUrl,
          'link': link,
          'adType': adType == 'carousel'
              ? 'carousel'
              : adType == 'video feed'
                  ? 'video feed ad'
                  : adType, // **FIX: Correct adType format**
          'budget': budget,
          'targetAudience': targetAudience,
          'targetKeywords': targetKeywords,
          'startDate': startDate?.toIso8601String(),
          'endDate': endDate?.toIso8601String(),
          'uploaderId': userData['googleId'] ?? userData['id'],
          'uploaderName': userData['name'],
          'uploaderProfilePic': userData['profilePic'],
          'estimatedImpressions': impressions,
          'fixedCpm': cpm,
        }),
      );

      if (response.statusCode == 201 || response.statusCode == 200) {
        final data = json.decode(response.body);
        return AdModel.fromJson(data);
      } else {
        throw Exception('Failed to create ad: ${response.body}');
      }
    } catch (e) {
      throw Exception('Error creating ad: $e');
    }
  }

  /// Create an ad funded by the advertiser's prepaid credit balance.
  ///
  /// Gated behind [AppConfig.adCreationEnabled] — the backend endpoint lands
  /// with the ad credit wallet.
  Future<Map<String, dynamic>> createAdWithCredits({
    required String idempotencyKey,
    required String title,
    required String description,
    String? imageUrl,
    String? videoUrl,
    String? link,
    required String adType,
    required double budget,
    required String targetAudience,
    required List<String> targetKeywords,
    DateTime? startDate,
    DateTime? endDate,
    int? minAge,
    int? maxAge,
    String? gender,
    List<String>? locations,
    List<String>? interests,
    List<String>? platforms,
    String? deviceType,
    String? optimizationGoal,
    int? frequencyCap,
    String? timeZone,
    Map<String, bool>? dayParting,
    // **NEW: Advanced KPI parameters**
    String? bidType,
    double? bidAmount,
    String? pacing,
    Map<String, String>? hourParting,
    double? targetCPA,
    double? targetROAS,
    int? attributionWindow,
    // **NEW: Support multiple image URLs for carousel ads**
    List<String>? imageUrls,
  }) async {
    try {
      final userData = await _authService.getUserData();
      if (userData == null) {
        throw Exception('User not authenticated');
      }

      final cpm = adType == 'banner' ? AppConfig.bannerCpm : AppConfig.fixedCpm;
      final impressions = AppConfig.calculateImpressionsFromBudgetWithCpm(
        budget,
        cpm,
      );

      AppLogger.log('🔍 AdService: Creating ad with payment...');
      AppLogger.log(
        '🔍 AdService: Budget: ₹$budget, Ad Type: $adType, CPM: ₹$cpm, Estimated impressions: $impressions',
      );

      String backendAdType = adType;
      if (adType == 'carousel') {
        backendAdType = 'carousel';
      } else if (adType == 'video feed') {
        backendAdType = 'video feed ad';
      }

      final requestData = {
        'idempotencyKey': idempotencyKey,
        'title': title,
        'description': description,
        'imageUrl': imageUrl,
        'videoUrl': videoUrl,
        'link': link,
        'adType': backendAdType, // **FIX: Use corrected adType**
        'budget': budget.toDouble(),
        'targetAudience': targetAudience,
        'uploaderId': userData['googleId'] ?? userData['id'],
        'uploaderName': userData['name'],
        'uploaderProfilePic': userData['profilePic'],
        'estimatedImpressions': impressions,
        'fixedCpm': cpm,
        'duration': startDate != null && endDate != null
            ? endDate.difference(startDate).inDays + 1
            : 1,
      };

      // **NEW: Add imageUrls for carousel ads**
      if (imageUrls != null && imageUrls.isNotEmpty && adType == 'carousel') {
        requestData['imageUrls'] = imageUrls;
        AppLogger.log(
            '🔍 AdService: Sending ${imageUrls.length} carousel image URLs');
      }

      // **NEW: Validate required fields before sending**
      if (title.isEmpty ||
          description.isEmpty ||
          adType.isEmpty ||
          budget <= 0) {
        throw Exception(
            'Required fields validation failed: title=$title, description=$description, adType=$adType, budget=$budget');
      }

      final uploaderId = userData['googleId'] ?? userData['id'];
      if (uploaderId == null || uploaderId.toString().isEmpty) {
        throw Exception('Uploader ID is missing or empty: $uploaderId');
      }

      // **NEW: Add uploaderId to request data**
      requestData['uploaderId'] = uploaderId;
      requestData['targetKeywords'] = targetKeywords;
      requestData['startDate'] = startDate?.toIso8601String();
      requestData['endDate'] = endDate?.toIso8601String();

      // **NEW: Add advanced targeting data as individual parameters**
      if (minAge != null) requestData['minAge'] = minAge;
      if (maxAge != null) requestData['maxAge'] = maxAge;
      if (gender != null) requestData['gender'] = gender;
      if (locations != null && locations.isNotEmpty) {
        requestData['locations'] = locations;
      }
      if (interests != null && interests.isNotEmpty) {
        requestData['interests'] = interests;
      }
      if (platforms != null && platforms.isNotEmpty) {
        requestData['platforms'] = platforms;
      }
      requestData['deviceType'] = deviceType ?? 'all';

      // **NEW: Add additional campaign settings**
      if (optimizationGoal != null) {
        requestData['optimizationGoal'] = optimizationGoal;
      }
      if (frequencyCap != null) {
        requestData['frequencyCap'] = frequencyCap;
      }
      if (timeZone != null) {
        requestData['timeZone'] = timeZone;
      }
      if (dayParting != null && dayParting.isNotEmpty) {
        requestData['dayParting'] = dayParting;
      }

      // **NEW: Add advanced KPI parameters**
      if (bidType != null) {
        requestData['bidType'] = bidType;
      }
      if (bidAmount != null) {
        requestData['bidAmount'] = bidAmount;
        requestData['cpmINR'] =
            bidAmount; // Also set cpmINR for backend compatibility
      }
      if (pacing != null) {
        requestData['pacing'] = pacing;
      }
      if (hourParting != null && hourParting.isNotEmpty) {
        requestData['hourParting'] = hourParting;
      }
      if (targetCPA != null) {
        requestData['targetCPA'] = targetCPA;
      }
      if (targetROAS != null) {
        requestData['targetROAS'] = targetROAS;
      }
      if (attributionWindow != null) {
        requestData['attributionWindow'] = attributionWindow;
      }

      final response = await httpClientService.post(
        Uri.parse('$baseUrl/api/ads/create-with-credits'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${userData['token']}',
        },
        body: json.encode(requestData),
      );

      if (response.statusCode == 201) {
        final data = json.decode(response.body);
        AppLogger.log('✅ AdService: Ad created successfully');

        return {
          'success': true,
          'ad': data['ad'],
          'message': data['message'],
          // The server returns the post-debit balance, so the wallet chip can
          // update without a second round trip.
          'balance': data['wallet']?['balance'],
        };
      }

      AppLogger.log(
          '❌ AdService: Backend returned error status: ${response.statusCode}');
      AppLogger.log('❌ AdService: Response body: ${response.body}');

      Map<String, dynamic> error;
      try {
        error = json.decode(response.body) as Map<String, dynamic>;
      } catch (_) {
        error = const {};
      }

      // 402 is not a generic failure. It is the one ad-creation error the user
      // can act on, and acting on it needs the shortfall — so it is surfaced
      // as its own type instead of a red banner with a stringified body.
      if (response.statusCode == 402 ||
          error['code'] == 'INSUFFICIENT_CREDITS') {
        throw InsufficientCreditsException.fromJson(error);
      }

      if (response.statusCode == 409 &&
          (error['code'] == 'AD_CREATION_IN_PROGRESS' ||
              error['code'] == 'AD_CREATION_RETRY_REQUIRED')) {
        throw AdCreationConflictException(
          error['code'] as String,
          error['error'] as String? ?? 'Campaign creation is still processing.',
        );
      }

      throw Exception(error['error'] ?? 'Failed to create ad');
    } on InsufficientCreditsException {
      // Must escape the catch-all below, which would flatten it into a string.
      rethrow;
    } on AdCreationConflictException {
      rethrow;
    } catch (e) {
      AppLogger.log('❌ AdService: Error creating ad: $e');
      throw Exception('Error creating ad: $e');
    }
  }

  // Get user's ads
  Future<List<AdModel>> getUserAds() async {
    try {
      final userData = await _authService.getUserData();
      if (userData == null) {
        throw Exception('User not authenticated');
      }

      // **FIXED: Use the correct user ID format that matches backend expectations**
      // The backend expects req.user.id from JWT token, so we need to use the same ID format
      String userId;
      if (userData['id'] != null) {
        userId = userData['id'].toString();
      } else if (userData['googleId'] != null) {
        userId = userData['googleId'].toString();
      } else {
        throw Exception('User ID not found in user data');
      }

      AppLogger.log('🔍 AdService: Fetching ads for user ID: $userId');
      AppLogger.log('🔍 AdService: User data keys: ${userData.keys.toList()}');

      final response = await httpClientService.get(
        Uri.parse('$baseUrl/api/ads/user/$userId'),
        headers: {'Authorization': 'Bearer ${userData['token']}'},
      );

      AppLogger.log('🔍 AdService: Response status: ${response.statusCode}');
      AppLogger.log('🔍 AdService: Response body: ${response.body}');

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        final ads = data.map((json) => AdModel.fromJson(json)).toList();
        AppLogger.log('✅ AdService: Successfully fetched ${ads.length} ads');
        return ads;
      } else {
        AppLogger.log(
          '❌ AdService: Failed to fetch ads - Status: ${response.statusCode}, Body: ${response.body}',
        );
        throw Exception('Failed to fetch ads: ${response.body}');
      }
    } catch (e) {
      AppLogger.log('❌ AdService: Error in getUserAds: $e');
      throw Exception('Error fetching ads: $e');
    }
  }

  // Get all active ads (for display)
  Future<List<AdModel>> getActiveAds() async {
    try {
      final response =
          await httpClientService.get(Uri.parse('$baseUrl/api/ads/active'));

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.map((json) => AdModel.fromJson(json)).toList();
      } else {
        throw Exception('Failed to fetch active ads: ${response.body}');
      }
    } catch (e) {
      throw Exception('Error fetching active ads: $e');
    }
  }

  // **NEW: Get ads for video feed (with insertion logic)**
  Future<List<AdModel>> getAdsForVideoFeed({
    required int currentIndex,
    required int totalVideos,
  }) async {
    try {
      final activeAds = await getActiveAds();
      final adsForFeed = <AdModel>[];

      // **NEW: Insert ads every alternate screen as per requirements**
      for (int i = 0; i < totalVideos; i++) {
        if ((i + 1) % AppConfig.adInsertionFrequency == 0) {
          // Insert ad at this position
          final adIndex =
              (i ~/ AppConfig.adInsertionFrequency) % activeAds.length;
          if (adIndex < activeAds.length) {
            adsForFeed.add(activeAds[adIndex]);
          }
        }
      }

      return adsForFeed;
    } catch (e) {
      throw Exception('Error getting ads for video feed: $e');
    }
  }

  // Update ad status
  Future<AdModel> updateAdStatus(String adId, String status) async {
    try {
      final userData = await _authService.getUserData();
      if (userData == null) {
        throw Exception('User not authenticated');
      }

      final response = await httpClientService.patch(
        Uri.parse('$baseUrl/api/ads/$adId/status'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${userData['token']}',
        },
        body: json.encode({'status': status}),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return AdModel.fromJson(data);
      } else {
        throw Exception('Failed to update ad status: ${response.body}');
      }
    } catch (e) {
      throw Exception('Error updating ad status: $e');
    }
  }

  // Delete ad
  Future<bool> deleteAd(String adId) async {
    try {
      AppLogger.log('🗑️ AdService: Starting delete for ad ID: $adId');

      final userData = await _authService.getUserData();
      if (userData == null) {
        throw Exception('User not authenticated');
      }

      AppLogger.log(
          '🔍 AdService: User authenticated, making delete request...');
      AppLogger.log('🔍 AdService: Delete URL: $baseUrl/api/ads/$adId');

      final response = await httpClientService.delete(
        Uri.parse('$baseUrl/api/ads/$adId'),
        headers: {'Authorization': 'Bearer ${userData['token']}'},
      );

      AppLogger.log(
          '🔍 AdService: Delete response status: ${response.statusCode}');
      AppLogger.log('🔍 AdService: Delete response body: ${response.body}');

      if (response.statusCode == 200 || response.statusCode == 204) {
        AppLogger.log('✅ AdService: Ad deleted successfully');

        // **NEW: Clear ad cache after successful deletion**
        await _clearAdCache();
        AppLogger.log('🧹 AdService: Cleared ad cache after deletion');

        // **NEW: Clear ActiveAdsService cache**
        await _activeAdsService.clearAdsCache();
        AppLogger.log('🧹 AdService: Cleared ActiveAdsService cache');

        // **NEW: Notify video feed to refresh ads**
        await _notifyVideoFeedRefresh();
        AppLogger.log('📢 AdService: Notified video feed to refresh ads');

        return true;
      } else {
        AppLogger.log(
            '❌ AdService: Delete failed with status ${response.statusCode}');
        throw Exception('Delete failed: ${response.body}');
      }
    } catch (e) {
      AppLogger.log('❌ AdService: Delete error: $e');
      throw Exception('Error deleting ad: $e');
    }
  }

  // **NEW: Get ad analytics**
  Future<Map<String, dynamic>> getAdAnalytics(String adId) async {
    try {
      final userData = await _authService.getUserData();
      if (userData == null) {
        throw Exception('User not authenticated');
      }

      final response = await httpClientService.get(
        Uri.parse(
          '$baseUrl/api/ads/analytics/$adId?userId=${userData['googleId'] ?? userData['id']}',
        ),
        headers: {'Authorization': 'Bearer ${userData['token']}'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data;
      } else {
        final error = json.decode(response.body);
        throw Exception(error['error'] ?? 'Failed to get analytics');
      }
    } catch (e) {
      throw Exception('Error getting analytics: $e');
    }
  }

  // **NEW: Track ad impression**
  Future<void> trackAdImpression(
    String adId,
    String userId,
    String platform,
    String location,
  ) async {
    try {
      final userData = await _authService.getUserData();
      if (userData == null) return;

      await httpClientService.post(
        Uri.parse('$baseUrl/api/ads/track-impression/$adId'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${userData['token']}',
        },
        body: json.encode({
          'userId': userId,
          'platform': platform,
          'location': location,
        }),
      );
    } catch (e) {
      AppLogger.log('Error tracking impression: $e');
    }
  }

  // **NEW: Track ad click**
  Future<void> trackAdClick(
    String adId,
    String userId,
    String platform,
    String location,
  ) async {
    try {
      final userData = await _authService.getUserData();
      if (userData == null) return;

      await httpClientService.post(
        Uri.parse('$baseUrl/api/ads/track-click/$adId'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${userData['token']}',
        },
        body: json.encode({
          'userId': userId,
          'platform': platform,
          'location': location,
        }),
      );
    } catch (e) {
      AppLogger.log('Error tracking click: $e');
    }
  }

  // **NEW: Upload ad media using Cloudinary**
  Future<String> uploadAdMedia(File file, String mediaType) async {
    try {
      if (mediaType == 'image') {
        return await _cloudflareService.uploadImage(
          file,
          folder: 'snehayog/ads/images',
        );
      } else if (mediaType == 'video') {
        final result = await _cloudflareService.uploadVideo(
          file,
          folder: 'snehayog/ads/videos',
        );
        // Extract URL from the result map
        return result['url'] ?? result['hls_urls']?['hls_stream'] ?? '';
      } else {
        throw Exception('Unsupported media type: $mediaType');
      }
    } catch (e) {
      throw Exception('Error uploading media: $e');
    }
  }

  // **NEW: Delete ad media from Cloudinary**
  Future<bool> deleteAdMedia(String mediaUrl, String mediaType) async {
    try {
      // Extract public ID from Cloudinary URL
      final uri = Uri.parse(mediaUrl);
      final pathSegments = uri.pathSegments;

      if (pathSegments.length >= 3 && pathSegments[1] == 'upload') {
        // NOTE: Media deletion now happens server-side for Cloudflare R2.
        // This method is kept for API compatibility but simply returns true.
        return true;
      }

      return false;
    } catch (e) {
      AppLogger.log('Error deleting media: $e');
      return false;
    }
  }

  // Get ad performance metrics
  Future<Map<String, dynamic>> getAdPerformance(String adId) async {
    try {
      final userData = await _authService.getUserData();
      if (userData == null) {
        throw Exception('User not authenticated');
      }

      final response = await httpClientService.get(
        Uri.parse('$baseUrl/api/ads/$adId/performance'),
        headers: {'Authorization': 'Bearer ${userData['token']}'},
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception('Failed to fetch ad performance: ${response.body}');
      }
    } catch (e) {
      throw Exception('Error fetching ad performance: $e');
    }
  }

  // **NEW: Get creator revenue summary - FAST & SIMPLE**
  // **UPDATED: Supports optional userId to fetch revenue for ANY user (e.g. other creators)**

  // **OPTIMIZED: In-memory cache for revenue data (5-min TTL)**
  static Map<String, dynamic>? _cachedRevenue;
  static DateTime? _lastRevenueFetch;
  static const Duration _revenueCacheTtl = Duration(minutes: 5);

  Future<Map<String, dynamic>> getCreatorRevenueSummary(
      {String? userId, bool forceRefresh = false}) async {
    try {
      final userData = await _authService.getUserData();
      if (userData == null) {
        throw Exception('User not authenticated');
      }

      // **CRITICAL FIX: Always get token using AuthService.getToken() (most reliable source)**
      String? token = await AuthService.getToken();

      // Fallback to userData token if AuthService doesn't have it
      if (token == null || token.isEmpty) {
        AppLogger.log(
            '⚠️ AdService: Token not found via AuthService, checking userData...');
        token = userData['token'];
      }

      // Final check - if still no token, throw error
      if (token == null || token.isEmpty) {
        AppLogger.log(
            '❌ AdService: No token found via AuthService or userData');
        AppLogger.log('❌ AdService: UserData keys: ${userData.keys.toList()}');
        throw Exception(
            'Authentication token not found. Please sign in again.');
      }

      // Determine target user ID
      final targetUserId = userId ?? (userData['googleId'] ?? userData['id']);

      if (targetUserId == null) {
        throw Exception('Target user ID not found');
      }

      // **OPTIMIZED: Return cached data if valid (5-min TTL) and not force-refreshing**
      if (!forceRefresh &&
          _cachedRevenue != null &&
          _lastRevenueFetch != null) {
        final age = DateTime.now().difference(_lastRevenueFetch!);
        if (age < _revenueCacheTtl) {
          AppLogger.log(
              '♻️ AdService: Returning cached revenue data (${age.inSeconds}s old)');
          return _cachedRevenue!;
        }
      }

      AppLogger.log(
          '🔍 AdService: Fetching fresh revenue from API for user: $targetUserId');

      // **FIX: Use async base URL resolver for proper server detection**
      final baseUrl = await AppConfig.getBaseUrlWithFallback();

      // **FIX: Add timeout to prevent hanging (8 seconds)**
      final response = await httpClientService.get(
        Uri.parse('$baseUrl/api/ads/creator/revenue/$targetUserId'),
        headers: {'Authorization': 'Bearer $token'},
        timeout: const Duration(seconds: 8),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;

        AppLogger.log(
            '🔍 AdService: thisMonth: ${data['thisMonth']}, lastMonth: ${data['lastMonth']}, totalRevenue: ${data['totalRevenue']}');

        // **OPTIMIZED: Cache in memory**
        _cachedRevenue = data;
        _lastRevenueFetch = DateTime.now();

        // **OPTIMIZED: Also persist to SharedPreferences with timestamp for bottom sheet**
        try {
          final prefs = await SharedPreferences.getInstance();
          final myId = userData['googleId'] ?? userData['id'];
          if (myId != null) {
            await prefs.setString('earnings_cache_$myId', json.encode(data));
            await prefs.setInt('earnings_cache_ts_$myId',
                DateTime.now().millisecondsSinceEpoch);
          }
        } catch (_) {}

        return data;
      } else {
        AppLogger.log(
            '❌ AdService: Revenue API failed with status ${response.statusCode}: ${response.body}');
        throw Exception('Failed to fetch creator revenue: ${response.body}');
      }
    } catch (e) {
      throw Exception('Error fetching creator revenue: $e');
    }
  }

  /// **NEW: Clear ad cache to ensure deleted ads are removed from video feed**
  Future<void> _clearAdCache() async {
    try {
      AppLogger.log('🧹 AdService: Clearing ad cache...');

      // Clear active ads cache
      await _clearCacheForKey('active_ads');
      await _clearCacheForKey('user_ads');

      // Clear any ad-related cache entries
      final cacheKeys = [
        'active_ads',
        'user_ads',
        'banner_ads',
        'video_feed_ads',
        'ads_page_1',
        'ads_page_2',
        'ads_page_3',
      ];

      for (final key in cacheKeys) {
        await _clearCacheForKey(key);
      }

      AppLogger.log('✅ AdService: Ad cache cleared successfully');
    } catch (e) {
      AppLogger.log('⚠️ AdService: Error clearing ad cache: $e');
      // Don't throw error - cache clearing failure shouldn't break ad deletion
    }
  }

  /// **NEW: Clear specific cache key**
  Future<void> _clearCacheForKey(String key) async {
    try {
      AppLogger.log('🧹 AdService: Clearing cache for key: $key');

      // Clear from SmartCacheManager by forcing refresh with null data
      // This will effectively clear the cache entry
      await _cacheManager.get(
        key,
        fetchFn: () async => null as dynamic,
        cacheType: 'ads',
        maxAge: Duration.zero, // Force immediate expiration
        forceRefresh: true,
      );
      AppLogger.log('✅ AdService: Cleared cache for key: $key');
    } catch (e) {
      AppLogger.log('⚠️ AdService: Error clearing cache for key $key: $e');
    }
  }

  /// **NEW: Notify video feed to refresh ads**
  Future<void> _notifyVideoFeedRefresh() async {
    try {
      AppLogger.log('📢 AdService: Notifying video feed to refresh ads...');

      // Clear video feed specific cache keys
      final videoFeedCacheKeys = [
        'video_feed_ads',
        'active_ads_video_feed',
        'banner_ads_video_feed',
        'ads_serve_response',
      ];

      for (final key in videoFeedCacheKeys) {
        await _clearCacheForKey(key);
      }

      // Also clear any cached video feed data that includes ads
      await _clearCacheForKey('video_feed_page_1');
      await _clearCacheForKey('video_feed_page_2');
      await _clearCacheForKey('video_feed_page_3');

      // **NEW: Notify video feed listeners to refresh ads**
      try {
        _adRefreshNotifier.notifyRefresh();
        AppLogger.log(
            '📢 AdService: Sent refresh notification to video feed listeners');
      } catch (e) {
        AppLogger.log('⚠️ AdService: Could not send refresh notification: $e');
      }

      AppLogger.log(
          '✅ AdService: Video feed cache cleared, ads will refresh on next load');
    } catch (e) {
      AppLogger.log('⚠️ AdService: Error notifying video feed refresh: $e');
    }
  }
}

// **NEW: Riverpod Provider for AdService**
final adServiceProvider = Provider<AdService>((ref) => AdService());

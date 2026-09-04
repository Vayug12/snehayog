import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';
import 'dart:io';
import 'package:video_compress/video_compress.dart';
import 'package:path_provider/path_provider.dart';
import 'package:vayug/features/video/core/data/models/video_model.dart';
import 'package:vayug/features/ads/data/ad_model.dart';
import 'package:vayug/features/auth/data/services/authservices.dart';
import 'package:vayug/features/ads/data/services/ad_service.dart';
import 'package:vayug/shared/services/platform_id_service.dart';
import 'package:vayug/shared/config/app_config.dart';
import 'package:vayug/shared/utils/app_logger.dart';
import 'package:vayug/shared/services/connectivity_service.dart';
import 'package:vayug/shared/services/http_client_service.dart';
import 'package:vayug/core/interfaces/i_video_service.dart';
import 'package:vayug/core/interfaces/i_e2ee_service.dart';
import 'package:vayug/shared/di/dependency_injection.dart';

/// Creators a user must subscribe to before the Vayu feed unlocks.
/// Mirrors `MIN_SUBSCRIPTIONS` in backend/controllers/video/videoFeedController.js
const int kMinSubscriptions = 5;

/// Eliminates code duplication and provides consistent API
class VideoService implements IVideoService {
  final AuthService _authService = AuthService();
  final AdService _adService = AdService();
  final HttpClientService httpClientService = HttpClientService.instance;

  // Using httpClientService for connection pooling and better performance

  // **VIDEO TRACKING: State management for video playback**
  int _currentVisibleVideoIndex = 0;
  bool _isVideoScreenActive = true;
  bool _isAppInForeground = true;
  final List<Function(int)> _videoIndexChangeListeners = [];
  final List<Function(bool)> _videoScreenStateListeners = [];

  // **CONSTANTS: Optimized values for better performance**
  static String get baseUrl => NetworkHelper.getBaseUrl();

  // **NEW: Get base URL with Railway first, local fallback**
  Future<String> getBaseUrlWithFallback() =>
      NetworkHelper.getBaseUrlWithFallback();
  static const int maxRetries = 2;
  static const int retryDelay = 1;
  static const int maxFileSize = 700 * 1024 * 1024; // 700MB

  // **GETTERS: Video tracking state**
  int get currentVisibleVideoIndex => _currentVisibleVideoIndex;
  bool get isVideoScreenActive => _isVideoScreenActive;
  bool get isAppInForeground => _isAppInForeground;
  bool get shouldPlayVideos => _isVideoScreenActive && _isAppInForeground;

  // **VIDEO TRACKING METHODS**
  void updateCurrentVideoIndex(int newIndex) {
    if (_currentVisibleVideoIndex != newIndex) {
      _currentVisibleVideoIndex = newIndex;
      /* AppLogger.log(
          '🎬 VideoService: Video index changed from $oldIndex to $newIndex'); */

      for (final listener in _videoIndexChangeListeners) {
        try {
          listener(newIndex);
        } catch (e) {
          AppLogger.log(
              '❌ VideoService: Error in video index change listener: $e');
        }
      }
    }
  }

  void updateVideoScreenState(bool isActive) {
    if (_isVideoScreenActive != isActive) {
      _isVideoScreenActive = isActive;
      /* AppLogger.log(
        '🔄 VideoService: Video screen state changed to ${isActive ? "ACTIVE" : "INACTIVE"}',
      ); */

      for (final listener in _videoScreenStateListeners) {
        try {
          listener(isActive);
        } catch (e) {
          AppLogger.log(
              '❌ VideoService: Error in video screen state listener: $e');
        }
      }
    }
  }

  void updateAppForegroundState(bool inForeground) {
    if (_isAppInForeground != inForeground) {
      _isAppInForeground = inForeground;
    }
  }

  void addVideoIndexChangeListener(Function(int) listener) {
    if (!_videoIndexChangeListeners.contains(listener)) {
      _videoIndexChangeListeners.add(listener);
    }
  }

  void removeVideoIndexChangeListener(Function(int) listener) {
    _videoIndexChangeListeners.remove(listener);
  }

  void addVideoScreenStateListener(Function(bool) listener) {
    if (!_videoScreenStateListeners.contains(listener)) {
      _videoScreenStateListeners.add(listener);
    }
  }

  void removeVideoScreenStateListener(Function(bool) listener) {
    _videoScreenStateListeners.remove(listener);
  }

  Map<String, dynamic> getVideoTrackingInfo() {
    return {
      'currentVisibleVideoIndex': _currentVisibleVideoIndex,
      'isVideoScreenActive': _isVideoScreenActive,
      'isAppInForeground': _isAppInForeground,
      'shouldPlayVideos': shouldPlayVideos,
      'timestamp': DateTime.now().toIso8601String(),
    };
  }

  // **CORE VIDEO METHODS - Merged from all services**

  /// **Get videos with pagination and HLS support**
  /// **NEW: Optional authentication for personalized feed**
  /// **NEW: Optional clearSession parameter to clear backend session state for fresh videos**
  Future<Map<String, dynamic>> getVideos({
    int page = 1,
    int limit = 15,
    String? videoType,
    bool clearSession = false,
    String? cursor,
    bool random = false,
  }) async {
    try {
      String url = '${NetworkHelper.apiBaseUrl}/videos?page=$page&limit=$limit';
      if (random) url += '&random=true';
      final normalizedType = videoType?.toLowerCase();
      String? apiVideoType = normalizedType;
      if (normalizedType == 'yog' || normalizedType == 'vayu') {
        url += '&videoType=$apiVideoType';
      }

      final platformIdService = PlatformIdService();
      final platformId = await platformIdService.getPlatformId();
      if (platformId.isNotEmpty) {
        url += '&platformId=$platformId';
      }

      if (clearSession) {
        url += '&clearSession=true';
        AppLogger.log(
            '🧹 VideoService: Clearing session state for fresh videos');
      }

      if (cursor != null && cursor.isNotEmpty) {
        url += '&cursor=${Uri.encodeComponent(cursor)}';
      }

      Map<String, String> headers = {
        'Content-Type': 'application/json',
      };

      if (platformId.isNotEmpty) {
        headers['x-device-id'] = platformId;
      }

      try {
        final token = await AuthService.getToken();
        if (token != null && token.isNotEmpty) {
          headers['Authorization'] = 'Bearer $token';
        }
      } catch (e) {
        AppLogger.log('⚠️ VideoService: Error getting auth token: $e');
      }

      final response = await httpClientService.get(
        Uri.parse(url),
        headers: headers,
        timeout: const Duration(seconds: 45), // Increased timeout
      );

      if (response.statusCode == 200) {
        // **COMPUTE: Use background isolate for heavy JSON parsing and mapping**
        final parseParams = {
          'body': response.body,
          'apiBaseUrl': NetworkHelper.apiBaseUrl,
          'page': page,
        };

        final result = await compute(_parseVideosCompute, parseParams);
        return result;
      } else {
        AppLogger.log(
            '❌ VideoService: API returned status ${response.statusCode}');
        String errorMessage = 'Failed to load videos: ${response.statusCode}';
        try {
          final errorData = json.decode(response.body);
          if (errorData['error'] != null) {
            errorMessage = errorData['error'].toString();
          } else if (errorData['message'] != null) {
            errorMessage = errorData['message'].toString();
          }
        } catch (_) {}
        throw Exception(errorMessage);
      }
    } catch (e) {
      AppLogger.log('❌ VideoService: Error in getVideos: $e');
      rethrow;
    }
  }
  
  /// **Feed built only from creators the user subscribes to**
  ///
  /// The response always carries a `gate` map
  /// (`unlocked`, `required`, `followingCount`) so the caller never has to make
  /// a second call to learn whether the feed is still locked.
  Future<Map<String, dynamic>> getFollowingVideos({
    int limit = 10,
    String? cursor,
    String videoType = 'vayu',
    bool refresh = false,
  }) async {
    Map<String, dynamic> lockedResult({bool requiresSignIn = false}) => {
          'videos': <VideoModel>[],
          'hasMore': false,
          'nextCursor': null,
          'gate': {
            'unlocked': false,
            'required': kMinSubscriptions,
            'followingCount': 0,
            'requiresSignIn': requiresSignIn,
          },
        };

    try {
      final token = await AuthService.getToken();
      if (token == null || token.isEmpty) {
        return lockedResult(requiresSignIn: true);
      }

      String url =
          '${NetworkHelper.apiBaseUrl}/videos/following?limit=$limit&videoType=$videoType';
      if (cursor != null && cursor.isNotEmpty) {
        url += '&cursor=${Uri.encodeComponent(cursor)}';
      }
      if (refresh) url += '&refresh=true';

      final response = await httpClientService.get(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        timeout: const Duration(seconds: 30),
      );

      if (response.statusCode == 200) {
        return await compute(_parseVideosCompute, {
          'body': response.body,
          'apiBaseUrl': NetworkHelper.apiBaseUrl,
          'page': 1,
        });
      }

      if (response.statusCode == 401) {
        AppLogger.log('⚠️ VideoService: Following feed needs a valid session');
        return lockedResult(requiresSignIn: true);
      }

      throw Exception('Failed to load subscribed videos: ${response.statusCode}');
    } catch (e) {
      AppLogger.log('❌ VideoService: Error in getFollowingVideos: $e');
      rethrow;
    }
  }

  /// **Get video by ID - Enhanced with better error handling**
  Future<VideoModel> getVideoById(String id) async {
    try {
      // **VALIDATION: Ensure video ID is not empty**
      if (id.trim().isEmpty) {
        throw Exception('Video ID cannot be empty');
      }

      final videoId = id.trim();
      final url = '${NetworkHelper.apiBaseUrl}/videos/$videoId';

      // AppLogger.log('📡 VideoService: Fetching video by ID: $videoId');

      final res = await httpClientService
          .get(Uri.parse(url), timeout: const Duration(seconds: 15));

      if (res.statusCode == 200) {
        final videoData = json.decode(res.body);
        final video = VideoModel.fromJson(videoData);
        /* AppLogger.log(
          '✅ VideoService: Successfully fetched video: ${video.videoName} (ID: ${video.id})',
        ); */
        return video;
      } else if (res.statusCode == 404) {
        AppLogger.log('❌ VideoService: Video not found (404): $videoId');
        throw Exception('Video not found. It may have been deleted.');
      } else {
        final error = json.decode(res.body);
        final errorMessage = error['error'] ?? 'Failed to load video';
        AppLogger.log(
          '❌ VideoService: Error fetching video (${res.statusCode}): $errorMessage',
        );
        throw Exception(errorMessage);
      }
    } catch (e) {
      AppLogger.log('❌ VideoService: Exception fetching video by ID: $e');
      if (e is Exception) rethrow;
      throw Exception('Network error: $e');
    }
  }

  /// **Toggle like for a video (like/unlike)**
  @override
  Future<VideoModel> toggleLike(String videoId) async {
    // **CONNECTIVITY CHECK: Verify internet before like operation**
    final hasInternet = await ConnectivityService.hasInternetConnection();
    if (!hasInternet) {
      throw Exception(
        ConnectivityService.getNetworkErrorMessage(
          Exception('No internet connection'),
        ),
      );
    }

    try {
      AppLogger.log('🔄 VideoService: Toggling like for video: $videoId');

      // **FIX: Get user data and validate token before making request**
      final userData = await _authService.getUserData();
      if (userData == null) {
        AppLogger.log('❌ VideoService: User not authenticated for like');
        throw Exception('Please sign in to like videos');
      }

      // **FIX: Check if token exists and is valid**
      final token = userData['token'];
      if (token == null || token.toString().isEmpty) {
        AppLogger.log('❌ VideoService: No token found for like');
        throw Exception('Please sign in again to like videos');
      }

      // **FIX: Check if token is a fallback token (won't work with backend)**
      if (token.toString().startsWith('temp_')) {
        AppLogger.log(
            '❌ VideoService: Fallback token detected - cannot like videos');
        throw Exception(
            'Please sign in with your Google account to like videos. Fallback session does not support this feature.');
      }

      // **FIX: Validate token format (should be JWT) - wrap in try-catch**
      bool isTokenValid = false;
      try {
        isTokenValid = _authService.isTokenValid(token);
      } catch (e) {
        AppLogger.log(
            '❌ VideoService: Error validating token (may not be JWT): $e');
        isTokenValid = false;
      }

      if (!isTokenValid) {
        AppLogger.log('❌ VideoService: Token is invalid or expired');
        // Try to refresh
        try {
          final refreshedToken = await _authService.refreshTokenIfNeeded();
          if (refreshedToken == null) {
            throw Exception('Please sign in again to like videos');
          }
          AppLogger.log('✅ VideoService: Token refreshed before like request');
        } catch (e) {
          AppLogger.log('❌ VideoService: Token refresh failed: $e');
          throw Exception('Please sign in again to like videos');
        }
      } else {
        // **FIX: Try to refresh token if it might be expiring soon**
        try {
          final refreshedToken = await _authService.refreshTokenIfNeeded();
          if (refreshedToken != null && refreshedToken != token) {
            AppLogger.log(
                '✅ VideoService: Token refreshed before like request');
          }
        } catch (e) {
          AppLogger.log(
              '⚠️ VideoService: Token refresh failed (non-critical): $e');
        }
      }

      // **FIX: Log user data for debugging**
      AppLogger.log(
          '🔍 VideoService: User data - googleId: ${userData['googleId']}');
      AppLogger.log('🔍 VideoService: User data - id: ${userData['id']}');
      AppLogger.log('🔍 VideoService: User data - email: ${userData['email']}');
      AppLogger.log(
          '🔍 VideoService: Like request URL: ${NetworkHelper.apiBaseUrl}/videos/$videoId/like');

      final res = await httpClientService
          .post(
            Uri.parse('${NetworkHelper.apiBaseUrl}/videos/$videoId/like'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({}),
            timeout: const Duration(seconds: 15),
          );

      AppLogger.log('📡 VideoService: Like response status: ${res.statusCode}');
      AppLogger.log('📡 VideoService: Like response body: ${res.body}');

      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        AppLogger.log('✅ VideoService: Like toggled successfully');
        return VideoModel.fromJson(data);
      } else {
        final errorBody = res.body;
        AppLogger.log(
            '❌ VideoService: Like failed - Status: ${res.statusCode}, Body: $errorBody');
        try {
          final error = json.decode(errorBody);
          final errorMsg =
              error['error'] ?? error['message'] ?? 'Failed to like video';
          throw Exception(errorMsg.toString());
        } catch (e) {
          if (e is FormatException) {
            throw Exception(
                'Failed to like video: ${errorBody.length > 100 ? errorBody.substring(0, 100) : errorBody}');
          }
          throw Exception('Failed to like video (Status: ${res.statusCode})');
        }
      }
    } catch (e) {
      AppLogger.log('❌ VideoService: Error toggling like: $e');
      if (e is TimeoutException) {
        throw Exception('Request timed out. Please try again.');
      } else if (e.toString().contains('sign in') ||
          e.toString().contains('authenticated')) {
        rethrow;
      }
      throw Exception('Failed to like video: ${e.toString()}');
    }
  }

  /// **Track video skip**
  Future<void> trackSkip(String videoId) async {
    try {
      final url = '${NetworkHelper.apiBaseUrl}/videos/$videoId/skip';
      
      // Use fire-and-forget or background tracking for skips to avoid blocking UI
      unawaited(httpClientService.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({}),
      ).then((res) {
        if (res.statusCode != 200) {
          AppLogger.log('⚠️ VideoService: Skip tracking failed for $videoId: ${res.statusCode}');
        }
      }).catchError((e) {
        AppLogger.log('⚠️ VideoService: Error tracking skip for $videoId: $e');
      }));
    } catch (e) {
      AppLogger.log('⚠️ VideoService: Exception preparing skip tracking: $e');
    }
  }

  /// **Toggle save (bookmark) for a video**
  @override
  Future<bool> toggleSave(String videoId) async {
    final hasInternet = await ConnectivityService.hasInternetConnection();
    if (!hasInternet) {
      throw Exception('No internet connection');
    }

    try {
      AppLogger.log('🔄 VideoService: Toggling save for video: $videoId');

      // **FIX: Robust URL construction to avoid double slashes or missing /api**
      final baseUrl = NetworkHelper.apiBaseUrl.endsWith('/')
          ? NetworkHelper.apiBaseUrl
              .substring(0, NetworkHelper.apiBaseUrl.length - 1)
          : NetworkHelper.apiBaseUrl;

      final url = '$baseUrl/videos/$videoId/save';
      AppLogger.log('🚀 VideoService: Save request URL: $url');

      final res = await httpClientService
          .post(
            Uri.parse(url),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({}),
            timeout: const Duration(seconds: 15),
          );

      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        return data['isSaved'] == true;
      } else if (res.statusCode == 401 || res.statusCode == 403) {
        throw Exception('Please sign in again to save videos');
      } else {
        final error = json.decode(res.body);
        throw Exception(error['error'] ?? 'Failed to save video');
      }
    } catch (e) {
      AppLogger.log('❌ VideoService: Error toggling save: $e');
      rethrow;
    }
  }

  /// **Get all saved videos for the current user**
  Future<List<VideoModel>> getSavedVideos() async {
    final hasInternet = await ConnectivityService.hasInternetConnection();
    if (!hasInternet) {
      throw Exception('No internet connection');
    }

    try {
      AppLogger.log('📡 VideoService: Fetching saved videos...');

      // Session validation happens automatically in HttpClientService
      final baseUrl = NetworkHelper.apiBaseUrl.endsWith('/')
          ? NetworkHelper.apiBaseUrl
              .substring(0, NetworkHelper.apiBaseUrl.length - 1)
          : NetworkHelper.apiBaseUrl;

      final url = '$baseUrl/videos/saved';

      final res = await httpClientService
          .get(
            Uri.parse(url),
          )
          .timeout(const Duration(seconds: 15));

      if (res.statusCode == 200) {
        final List<dynamic> data = json.decode(res.body);
        return data.map((json) => VideoModel.fromJson(json)).toList();
      } else if (res.statusCode == 401 || res.statusCode == 403) {
        throw Exception('Please sign in again to view saved videos');
      } else {
        final error = json.decode(res.body);
        throw Exception(error['error'] ?? 'Failed to fetch saved videos');
      }
    } catch (e) {
      AppLogger.log('❌ VideoService: Error fetching saved videos: $e');
      rethrow;
    }
  }

  // **CACHE: Simple memory cache for subscriber videos**
  List<VideoModel>? _subscriberVideosCache;
  DateTime? _lastSubscriberFetchTime;
  static const Duration _cacheDuration = Duration(minutes: 5);

  /// **Get subscriber-only videos for the current user**
  Future<List<VideoModel>> getSubscriberVideos({bool forceRefresh = false}) async {
    // **NEW: Return cached data if available and not expired**
    if (!forceRefresh && 
        _subscriberVideosCache != null && 
        _lastSubscriberFetchTime != null &&
        DateTime.now().difference(_lastSubscriberFetchTime!) < _cacheDuration) {
      AppLogger.log('🎬 VideoService: Returning cached subscriber videos');
      return _subscriberVideosCache!;
    }

    final hasInternet = await ConnectivityService.hasInternetConnection();
    if (!hasInternet) {
      throw Exception('No internet connection');
    }

    try {
      AppLogger.log('📡 VideoService: Fetching subscriber videos from network...');

      final resolvedBaseUrl = await getBaseUrlWithFallback();
      final url = '$resolvedBaseUrl/api/users/subscriber-videos';

      final res = await httpClientService
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 15));

      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        final List<dynamic> videoList = data['videos'] ?? [];
        AppLogger.log(
            '✅ VideoService: Fetched ${videoList.length} subscriber videos');
        
        final List<VideoModel> videos = videoList
            .map((json) => VideoModel.fromJson(Map<String, dynamic>.from(json)))
            .toList();
        
        // **NEW: Update cache**
        _subscriberVideosCache = videos;
        _lastSubscriberFetchTime = DateTime.now();
        
        return videos;
      } else if (res.statusCode == 401 || res.statusCode == 403) {
        throw Exception('Please sign in to view subscriber content');
      } else {
        final error = json.decode(res.body);
        throw Exception(
            error['error'] ?? 'Failed to fetch subscriber videos');
      }
    } catch (e) {
      AppLogger.log('❌ VideoService: Error fetching subscriber videos: $e');
      rethrow;
    }
  }

  /// **Like a video (for backward compatibility)**
  Future<VideoModel> likeVideo(String videoId) async {
    return await toggleLike(videoId);
  }

  /// **Unlike a video (for backward compatibility)**
  Future<VideoModel> unlikeVideo(String videoId) async {
    return await toggleLike(videoId);
  }

  /// **Get user videos**
  @override
  Future<List<VideoModel>> getUserVideos(String userId,
      {bool forceRefresh = false,
      int page = 1,
      int limit = 9,
      String? videoType,
      String? mediaType}) async {
    try {
      // **FIXED: Validate userId before making request**
      if (userId.isEmpty) {
        throw Exception('User ID is empty. Please sign in again.');
      }

      final resolvedBaseUrl = await getBaseUrlWithFallback();
      String url =
          '$resolvedBaseUrl/api/videos/user/$userId?page=$page&limit=$limit';

      if (videoType != null && videoType.isNotEmpty) {
        url += '&videoType=$videoType';
      }
      if (mediaType != null && mediaType.isNotEmpty) {
        url += '&mediaType=$mediaType';
      }

      // **NEW: Append refresh=true if forceRefresh is requested**
      if (forceRefresh) {
        url += '&refresh=true';
      }

      AppLogger.log('📡 VideoService: Fetching videos for userId: $userId');
      AppLogger.log('📡 VideoService: URL: $url');

      final hasToken = await AuthService.getToken() != null;
      AppLogger.log('📡 VideoService: Auth token present: $hasToken');

      final response = await httpClientService
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 30));

      AppLogger.log('📡 VideoService: Response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final List<dynamic> videoList = json.decode(response.body);

        final videos = videoList.map((json) {
          // **HLS URL Priority**: Use HLS for better streaming
          if (json['hlsPlaylistUrl'] != null &&
              json['hlsPlaylistUrl'].toString().isNotEmpty) {
            String hlsUrl = json['hlsPlaylistUrl'].toString();
            if (!hlsUrl.startsWith('http')) {
              if (hlsUrl.startsWith('/')) {
                hlsUrl = hlsUrl.substring(1);
              }
              json['videoUrl'] = '$resolvedBaseUrl/$hlsUrl';
            } else {
              json['videoUrl'] = hlsUrl;
            }
            AppLogger.log(
                '🔗 VideoService: Using HLS Playlist URL: ${json['videoUrl']}');
          } else if (json['hlsMasterPlaylistUrl'] != null &&
              json['hlsMasterPlaylistUrl'].toString().isNotEmpty) {
            String masterUrl = json['hlsMasterPlaylistUrl'].toString();
            if (!masterUrl.startsWith('http')) {
              if (masterUrl.startsWith('/')) {
                masterUrl = masterUrl.substring(1);
              }
              json['videoUrl'] = '$resolvedBaseUrl/$masterUrl';
            } else {
              json['videoUrl'] = masterUrl;
            }
            AppLogger.log(
                '🔗 VideoService: Using HLS Master URL: ${json['videoUrl']}');
          } else {
            // **Fallback**: Ensure relative URLs are complete
            if (json['videoUrl'] != null &&
                !json['videoUrl'].toString().startsWith('http')) {
              String videoUrl = json['videoUrl'].toString();
              if (videoUrl.startsWith('/')) {
                videoUrl = videoUrl.substring(1);
              }
              json['videoUrl'] = '$resolvedBaseUrl/$videoUrl';
            }
          }

          // **Ensure other URLs are complete**
          if (json['originalVideoUrl'] != null &&
              !json['originalVideoUrl'].toString().startsWith('http')) {
            String originalUrl = json['originalVideoUrl'].toString();
            if (originalUrl.startsWith('/')) {
              originalUrl = originalUrl.substring(1);
            }
            json['originalVideoUrl'] = '$resolvedBaseUrl/$originalUrl';
          }
          if (json['thumbnailUrl'] != null &&
              !json['thumbnailUrl'].toString().startsWith('http')) {
            String thumbnailUrl = json['thumbnailUrl'].toString();
            if (thumbnailUrl.startsWith('/')) {
              thumbnailUrl = thumbnailUrl.substring(1);
            }
            json['thumbnailUrl'] = '$resolvedBaseUrl/$thumbnailUrl';
          }

          return VideoModel.fromJson(json);
        }).toList();

        return videos;
      } else if (response.statusCode == 404) {
        return [];
      } else if (response.statusCode == 401) {
        AppLogger.log(
            '❌ VideoService: 401 Unauthorized - Token may be expired or invalid');
        throw Exception(
            'Failed to fetch user videos: 401 - Please sign in again');
      } else {
        AppLogger.log(
            '❌ VideoService: Failed to fetch user videos - Status: ${response.statusCode}, Body: ${response.body}');
        throw Exception('Failed to fetch user videos: ${response.statusCode}');
      }
    } catch (e) {
      if (e is TimeoutException) {
        throw Exception(
          'Request timed out. Please check your internet connection and try again.',
        );
      }
      rethrow;
    }
  }

  /// **Upload video with compression and validation**
  @override
  Future<Map<String, dynamic>> uploadVideo({
    required File videoFile,
    required String title,
    String? description,
    String? link,
    String? category,
    List<String>? tags,
    String? videoType,
    Function(double)? onProgress,
    CancelToken? cancelToken,
    List<String>? crossPostPlatforms,
    String? seriesId,
    int? episodeNumber,
    List<QuizModel>? quizzes,
    List<String>? allowedSubscribers,
    List<String>? targetProfessionIds,
    File? thumbnailFile,
  }) async {
    try {
      AppLogger.log('🚀 VideoService: Starting video upload...');

      final isHealthy = await checkServerHealth();
      if (!isHealthy) {
        throw Exception(
          'Server is not responding. Please check your connection and try again.',
        );
      }

      final fileSize = await videoFile.length();
      if (fileSize > maxFileSize) {
        throw Exception('File too large. Maximum size is 700MB');
      }

      // **REMOVED: duration-based categorization logic**

      final userData = await _authService.getUserData();
      if (userData == null) {
        throw Exception(
          'User not authenticated. Please sign in to upload videos.',
        );
      }

      File finalVideoFile = videoFile;
      // **DEPRECATED: Client-side compression removed in favor of Direct R2 Upload**
      // if (fileSize > 15 * 1024 * 1024) { ... }

      final resolvedBaseUrl = await getBaseUrlWithFallback();

      // **NEW: Direct R2 Upload Flow**
      return await _uploadVideoDirect(
        baseUrl: resolvedBaseUrl,
        videoFile: finalVideoFile,
        title: title,
        description: description,
        link: link,
        category: category,
        tags: tags,
        videoType: videoType,
        onProgress: onProgress,
        cancelToken: cancelToken,
        crossPostPlatforms: crossPostPlatforms,
        seriesId: seriesId,
        episodeNumber: episodeNumber,
        quizzes: quizzes,
        allowedSubscribers: allowedSubscribers,
        targetProfessionIds: targetProfessionIds,
        thumbnailFile: thumbnailFile,
      );
    } catch (e) {
      if (e is DioException && e.type == DioExceptionType.cancel) {
        AppLogger.log('?? VideoService: Upload cancelled by user');
        rethrow;
      }
      AppLogger.log('? VideoService: Error uploading video: $e');
      rethrow;
    }
  }

  // **NEW: Direct Upload Implementation (Phone -> R2 -> Backend)**
  Future<Map<String, dynamic>> _uploadVideoDirect({
    required String baseUrl,
    required File videoFile,
    required String title,
    String? description,
    String? link,
    String? category,
    List<String>? tags,
    String? videoType,
    Function(double)? onProgress,
    CancelToken? cancelToken,
    List<String>? crossPostPlatforms,
    String? seriesId,
    int? episodeNumber,
    List<QuizModel>? quizzes,
    List<String>? allowedSubscribers,
    List<String>? targetProfessionIds,
    File? thumbnailFile,
  }) async {
    File? encryptedTempFile;
    try {
      AppLogger.log('🚀 VideoService: Starting Direct R2 Upload...');

      final bool isE2ee = allowedSubscribers != null && allowedSubscribers.isNotEmpty;
      Uint8List? symmetricKey;

      if (isE2ee) {
        symmetricKey = serviceLocator.e2eeService.generateSymmetricKey();
        encryptedTempFile = await _encryptVideoFile(videoFile, symmetricKey);
        videoFile = encryptedTempFile;
      }

      // 1. Get Presigned URL
      AppLogger.log('🔑 Requesting presigned URL...');
      final fileSize = await videoFile.length();
      final mimeType =
          'video/${videoFile.path.split('.').last}'; // Simple mime guess

      // **FIX: Use shared httpClientService.dioClient to ensure interceptors and validateStatus work**
      final dio = httpClientService.dioClient;

      final presignedResponse = await dio.post(
        '$baseUrl/api/upload/video/presigned',
        data: {
          'fileName': videoFile.path.split('/').last,
          'fileType': mimeType,
          'fileSize': fileSize,
        },
        options: Options(
          headers: {
            'Content-Type': 'application/json',
          },
        ),
      );

      final uploadUrl = presignedResponse.data['uploadUrl'];
      final key = presignedResponse.data['key'];

      if (uploadUrl == null || key == null) {
        throw Exception('Failed to get upload URL');
      }

      AppLogger.log('✅ Got presigned URL. Uploading ${isE2ee ? "ENCRYPTED" : "raw"} file to R2...');

      // 2. Upload to R2 (Directly)
      // Note: We use a separate Dio instance to avoid default interceptors/headers causing issues with R2
      final r2Dio = Dio();

      await r2Dio.put(
        uploadUrl,
        data: videoFile.openRead(), // Stream the file
        options: Options(
          headers: {
            'Content-Type': mimeType,
            'Content-Length': fileSize,
            'Cache-Control': 'public, max-age=31536000, immutable, stale-while-revalidate=604800',
          },
        ),
        cancelToken: cancelToken,
        onSendProgress: (sent, total) {
          if (total != -1 && onProgress != null) {
            // Map 0.0 - 0.95 to upload progress
            // Leave last 5% for backend processing trigger
            final progress = (sent / total) * 0.95;
            onProgress(progress);
          }
        },
      );

      if (onProgress != null) onProgress(0.98); // Almost done

      // 3. Handle Thumbnail Upload if provided
      String? thumbnailKey;
      if (thumbnailFile != null) {
        AppLogger.log('🖼️ VideoService: Uploading custom thumbnail...');
        final thumbMimeType = 'image/${thumbnailFile.path.split('.').last}';
        final thumbPresignedResponse = await dio.post(
          '$baseUrl/api/upload/video/presigned',
          data: {
            'fileName': thumbnailFile.path.split('/').last,
            'fileType': thumbMimeType,
            'fileSize': await thumbnailFile.length(),
          },
        );
        
        final thumbUploadUrl = thumbPresignedResponse.data['uploadUrl'];
        thumbnailKey = thumbPresignedResponse.data['key'];

        if (thumbUploadUrl != null) {
          await r2Dio.put(
            thumbUploadUrl,
            data: thumbnailFile.openRead(),
            options: Options(
              headers: {
                'Content-Type': thumbMimeType,
                'Content-Length': await thumbnailFile.length(),
                'Cache-Control': 'public, max-age=31536000, immutable, stale-while-revalidate=604800',
              },
            ),
          );
          AppLogger.log('✅ Custom thumbnail uploaded successfully');
        }
      }

      // 4. Notify Backend to Start Processing
      final completeResponse = await dio.post(
        '$baseUrl/api/upload/video/direct-complete',
        data: {
          'key': key,
          'videoName': title,
          'description': description,
          'link': link,
          'size': fileSize,
          'category': category,
          'tags': tags,
          'videoType': videoType,
          'crossPostPlatforms': crossPostPlatforms,
          'seriesId': seriesId,
          'episodeNumber': episodeNumber,
          'thumbnailKey': thumbnailKey,
          'quizzes': quizzes?.map((q) => q.toJson()).toList(),
          'allowedSubscribers': allowedSubscribers,
          'targetProfessionIds': targetProfessionIds ?? const <String>[],
        },
      );

      // **NEW: Key Distribution (if E2EE)**
      if (isE2ee && symmetricKey != null) {
        final videoData = completeResponse.data['video'] ?? completeResponse.data;
        final videoId = videoData['_id']?.toString() ?? videoData['id']?.toString();
        if (videoId != null) {
          AppLogger.log('🔐 E2EE: Distributing keys for video $videoId...');
          final e2ee = serviceLocator.e2eeService;
          final subKeys = await e2ee.fetchSubscriberPublicKeys();
          
          final List<EncryptedKeyEntry> entries = [];
          for (final sub in subKeys) {
            if (allowedSubscribers.contains(sub.subscriberId)) {
              final encKey = await e2ee.encryptSymmetricKeyForSubscriber(symmetricKey, sub.publicKey);
              entries.add(EncryptedKeyEntry(
                subscriberId: sub.subscriberId,
                encryptedSymmetricKey: encKey,
              ));
            }
          }

          // Also encrypt the key for the creator (uploader) themselves so they can decrypt and watch it
          final userData = await _authService.getUserData();
          final creatorId = userData?['_id']?.toString() ?? userData?['id']?.toString();
          final creatorIdentity = userData?['googleId']?.toString() ?? creatorId;
          final creatorPublicKey = await e2ee.getPublicKey(userId: creatorIdentity);
          if (creatorId != null && creatorPublicKey != null) {
            AppLogger.log('🔐 E2EE: Encrypting symmetric key for creator $creatorId...');
            final creatorEncKey = await e2ee.encryptSymmetricKeyForSubscriber(symmetricKey, creatorPublicKey);
            entries.add(EncryptedKeyEntry(
              subscriberId: creatorId,
              encryptedSymmetricKey: creatorEncKey,
            ));
          }
          
          if (entries.isNotEmpty) {
            await e2ee.uploadEncryptedVideoKeys(videoId: videoId, encryptedKeys: entries);
          } else {
            AppLogger.log('⚠️ E2EE: No active subscribers found with public keys for key distribution.');
          }
        }
      }

      if (onProgress != null) onProgress(1.0);

      return completeResponse.data;
    } catch (e) {
      rethrow;
    } finally {
      if (encryptedTempFile != null && await encryptedTempFile.exists()) {
        try {
          await encryptedTempFile.delete();
          AppLogger.log('🧹 E2EE: Deleted temporary encrypted video file.');
        } catch (e) {
          AppLogger.log('⚠️ E2EE: Failed to delete temporary file: $e');
        }
      }
    }
  }

  Future<File> _encryptVideoFile(File rawFile, Uint8List symmetricKey) async {
    AppLogger.log('🔐 E2EE: Encrypting video file locally...');
    final tempDir = await getTemporaryDirectory();
    final tempFile = File('${tempDir.path}/enc_${DateTime.now().millisecondsSinceEpoch}.tmp');
    
    final e2ee = serviceLocator.e2eeService;
    final raf = await tempFile.open(mode: FileMode.write);
    final inputStream = rawFile.openRead();
    
    const int chunkSize = 2 * 1024 * 1024;
    List<int> buffer = [];

    await for (final chunk in inputStream) {
      buffer.addAll(chunk);
      while (buffer.length >= chunkSize) {
        final toEncrypt = Uint8List.fromList(buffer.sublist(0, chunkSize));
        buffer = buffer.sublist(chunkSize);
        
        final encryptedChunk = await e2ee.encryptChunk(toEncrypt, symmetricKey);
        await raf.writeFrom(encryptedChunk);
      }
    }

    if (buffer.isNotEmpty) {
      final toEncrypt = Uint8List.fromList(buffer);
      final encryptedChunk = await e2ee.encryptChunk(toEncrypt, symmetricKey);
      await raf.writeFrom(encryptedChunk);
    }

    await raf.close();
    AppLogger.log('🔐 E2EE: Encryption complete. Encrypted file size: ${await tempFile.length()} bytes');
    return tempFile;
  }

  Future<VideoModel> updateVideoMetadata(String videoId, String videoName,
      {String? link,
      List<String>? tags,
      String? seriesId,
      int? episodeNumber,
      List<QuizModel>? quizzes,
      File? thumbnailFile}) async {
    try {
      AppLogger.log('🔄 VideoService: Updating metadata for video: $videoId');

      final resolvedBaseUrl = await getBaseUrlWithFallback();
      final url = '$resolvedBaseUrl/api/videos/$videoId';

      final Map<String, dynamic> updateData = {
        'videoName': videoName,
      };

      if (link != null) updateData['link'] = link;
      if (tags != null) updateData['tags'] = tags;
      if (seriesId != null) updateData['seriesId'] = seriesId;
      if (episodeNumber != null) updateData['episodeNumber'] = episodeNumber;
      if (quizzes != null) {
        updateData['quizzes'] = quizzes.map((q) => q.toJson()).toList();
      }

      // Handle Thumbnail Update if provided
      if (thumbnailFile != null) {
        AppLogger.log('🖼️ VideoService: Uploading new thumbnail for existing video...');
        final thumbMimeType = 'image/${thumbnailFile.path.split('.').last}';
        
        // 1. Get Presigned URL
        final thumbPresignedResponse = await httpClientService.dioClient.post(
          '$resolvedBaseUrl/api/upload/video/presigned',
          data: {
            'fileName': thumbnailFile.path.split('/').last,
            'fileType': thumbMimeType,
            'fileSize': await thumbnailFile.length(),
          },
        );
        
        final thumbUploadUrl = thumbPresignedResponse.data['uploadUrl'];
        final thumbnailKey = thumbPresignedResponse.data['key'];

        if (thumbUploadUrl != null) {
          // 2. Upload to R2
          await Dio().put(
            thumbUploadUrl,
            data: thumbnailFile.openRead(),
            options: Options(
              headers: {
                'Content-Type': thumbMimeType,
                'Content-Length': await thumbnailFile.length(),
                'Cache-Control': 'public, max-age=31536000, immutable, stale-while-revalidate=604800',
              },
            ),
          );
          
          updateData['thumbnailKey'] = thumbnailKey;
          AppLogger.log('✅ New thumbnail uploaded and key added to update data');
        }
      }

      final res = await httpClientService.patch(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(updateData),
        timeout: const Duration(seconds: 15),
      );

      if (res.statusCode == 200) {
        final traceId = res.headers['x-trace-id'] ?? 'unknown';
        AppLogger.log('✅ VideoService: Video updated successfully (Trace ID: $traceId)');
        final data = json.decode(res.body);
        // The backend now returns the full video object in data['video']
        return VideoModel.fromJson(data['video']);
      } else if (res.statusCode == 401) {
        throw Exception('Please sign in again to update video');
      } else if (res.statusCode == 403) {
        throw Exception('You do not have permission to update this video');
      } else {
        final error = json.decode(res.body);
        throw Exception(error['error'] ?? 'Failed to update video');
      }
    } catch (e) {
      AppLogger.log('❌ VideoService: Error updating video metadata: $e');
      if (e is TimeoutException) {
        throw Exception('Request timed out. Please try again.');
      }
      rethrow;
    }
  }

  /// **Update series metadata for multiple videos**
  /// Links a list of episode IDs to a series (bulk update)
  Future<Map<String, dynamic>> updateVideoSeries(
    String videoId,
    List<String> episodeIds, {
    String? seriesId,
  }) async {
    try {
      AppLogger.log(
          '🔄 VideoService: Updating series for ${episodeIds.length} videos');

      final resolvedBaseUrl = await NetworkHelper.getBaseUrlWithFallback();
      final url = '$resolvedBaseUrl/api/videos/$videoId/series';

      final Map<String, dynamic> updateData = {
        'episodeIds': episodeIds,
      };
      if (seriesId != null) updateData['seriesId'] = seriesId;

      final res = await httpClientService.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(updateData),
        timeout: const Duration(seconds: 30),
      );

      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        AppLogger.log('✅ VideoService: Series updated successfully');
        return data;
      } else {
        final error = json.decode(res.body);
        throw Exception(error['error'] ?? 'Failed to update series');
      }
    } catch (e) {
      AppLogger.log('❌ VideoService: Error updating series: $e');
      rethrow;
    }
  }

  /// **Delete video**
  @override
  Future<bool> deleteVideo(String videoId) async {
    try {
      AppLogger.log('🗑️ VideoService: Attempting to delete video: $videoId');

      final resolvedBaseUrl = await getBaseUrlWithFallback();
      final res = await httpClientService
          .delete(Uri.parse('$resolvedBaseUrl/api/videos/$videoId'))
          .timeout(const Duration(seconds: 10));

      if (res.statusCode == 200 || res.statusCode == 204) {
        AppLogger.log('✅ VideoService: Video deleted successfully');
        return true;
      } else if (res.statusCode == 401) {
        throw Exception('Please sign in again to delete videos');
      } else if (res.statusCode == 403) {
        throw Exception('You do not have permission to delete this video');
      } else if (res.statusCode == 404) {
        throw Exception('Video not found');
      } else {
        // **FIX: Robust parsing for non-JSON error responses**
        try {
          final error = json.decode(res.body);
          throw Exception(error['error'] ?? 'Failed to delete video');
        } catch (e) {
          AppLogger.log('⚠️ VideoService: Could not parse error JSON: ${res.body}');
          throw Exception('Server error (${res.statusCode}): Failed to delete video');
        }
      }
    } catch (e) {
      AppLogger.log('❌ VideoService: Error deleting video: $e');
      if (e is TimeoutException) {
        throw Exception('Request timed out. Please try again.');
      }
      rethrow;
    }
  }

  /// **Delete multiple videos (Bulk Deletion)**
  @override
  Future<int> deleteVideos(List<String> videoIds) async {
    if (videoIds.isEmpty) return 0;

    try {
      AppLogger.log('🗑️ VideoService: Attempting bulk delete for ${videoIds.length} videos');

      final resolvedBaseUrl = await getBaseUrlWithFallback();
      final res = await httpClientService.post(
        Uri.parse('$resolvedBaseUrl/api/videos/bulk-delete'),
        body: json.encode({'videoIds': videoIds}),
      ).timeout(const Duration(seconds: 20));

      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        final deletedCount = data['deletedCount'] ?? videoIds.length;
        AppLogger.log('✅ VideoService: Bulk delete successful. Deleted $deletedCount videos');
        return deletedCount;
      } else {
        // Handle error response
        try {
          final error = json.decode(res.body);
          throw Exception(error['error'] ?? 'Failed to delete videos');
        } catch (e) {
          throw Exception('Server error (${res.statusCode}): Bulk deletion failed');
        }
      }
    } catch (e) {
      AppLogger.log('❌ VideoService: Error in bulk delete: $e');
      if (e is TimeoutException) {
        throw Exception('Bulk deletion timed out. Some videos may have been deleted.');
      }
      rethrow;
    }
  }

  /// **Increment share count** (without showing share dialog)
  Future<void> incrementShares(String videoId) async {
    try {
      final resolvedBaseUrl = await getBaseUrlWithFallback();
      final res = await httpClientService.post(
        Uri.parse('$resolvedBaseUrl/api/videos/$videoId/share'),
      );

      if (res.statusCode != 200) {
        AppLogger.log('⚠️ Failed to increment share count: ${res.statusCode}');
      }
    } catch (e) {
      AppLogger.log('⚠️ Error incrementing shares: $e');
      // Don't throw - sharing should work even if server tracking fails
    }
  }

  /// **Get video processing status**
  @override
  Future<Map<String, dynamic>?> getVideoProcessingStatus(String videoId) async {
    try {
      AppLogger.log(
          '🔄 VideoService: Getting processing status for video: $videoId');

      final resolvedBaseUrl = await getBaseUrlWithFallback();
      final res = await httpClientService
          .get(Uri.parse('$resolvedBaseUrl/api/upload/video/$videoId/status'))
          .timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        final responseData = json.decode(res.body);
        AppLogger.log(
            '✅ VideoService: Processing status retrieved successfully');
        return responseData;
      } else if (res.statusCode == 404) {
        AppLogger.log('⚠️ VideoService: Video not found for status check');
        return null;
      } else {
        AppLogger.log(
            '❌ VideoService: Failed to get processing status: ${res.statusCode}');
        return null;
      }
    } catch (e) {
      AppLogger.log('❌ VideoService: Error getting processing status: $e');
      return null;
    }
  }

  /// **Check server health**
  Future<bool> checkServerHealth() async {
    try {
      // Resolve base URL with local-first fallback
      final resolvedBaseUrl = await getBaseUrlWithFallback();
      final response = await httpClientService
          .get(Uri.parse('$resolvedBaseUrl/api/health'))
          .timeout(const Duration(seconds: 15));
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  /// **Compress video while preserving display (resolution/aspect) as much as possible**
  /// Uses DefaultQuality so encoder mainly reduces bitrate, not dimensions.
  Future<File?> compressVideo(File videoFile) async {
    try {
      AppLogger.log(
          '🔄 VideoService: Compressing video (preserve resolution)...');

      final MediaInfo? mediaInfo = await VideoCompress.compressVideo(
        videoFile.path,
        quality: VideoQuality
            .Res640x480Quality, // 480p is perfect for mobile consumption & size
        deleteOrigin: false,
      );

      if (mediaInfo?.file != null) {
        AppLogger.log(
          '✅ VideoService: Video compressed successfully. '
          'Original display (orientation/aspect ratio) should remain the same.',
        );
        return mediaInfo!.file;
      } else {
        AppLogger.log('❌ VideoService: Video compression failed');
        return null;
      }
    } catch (e) {
      AppLogger.log('❌ VideoService: Error compressing video: $e');
      return null;
    }
  }



  // **AD INTEGRATION METHODS - From original VideoService**

  /// **Get videos with integrated ads**
  Future<Map<String, dynamic>> getVideosWithAds({
    int page = 1,
    int limit = 15,
    int adInsertionFrequency = 3,
  }) async {
    try {
      AppLogger.log('🔍 VideoService: Fetching videos with ads...');

      final videosResult = await getVideos(page: page, limit: limit);
      final videos =
          (videosResult['videos'] as List<dynamic>).cast<VideoModel>();

      List<AdModel> ads = const [];
      try {
        ads = await _adService.getActiveAds();
      } catch (adError) {
        AppLogger.log(
            '⚠️ VideoService: Failed to fetch ads, continuing without ads: $adError');
      }

      List<dynamic> integratedFeed = videos;
      try {
        if (ads.isNotEmpty) {
          integratedFeed = _integrateAdsIntoFeed(
            videos,
            ads,
            adInsertionFrequency,
          );
        }
      } catch (integrationError) {
        AppLogger.log(
          '⚠️ VideoService: Failed to integrate ads, using videos only: $integrationError',
        );
        integratedFeed = videos;
      }

      return {
        'videos': integratedFeed,
        'hasMore': videosResult['hasMore'] ?? false,
        'total': videosResult['total'] ?? 0,
        'currentPage': page,
        'totalPages': videosResult['totalPages'] ?? 1,
        'adCount': ads.length,
        'integratedCount': integratedFeed.length,
      };
    } catch (e) {
      AppLogger.log('❌ VideoService: Error fetching videos with ads: $e');
      rethrow;
    }
  }

  /// **Integrate ads into video feed**
  List<dynamic> _integrateAdsIntoFeed(
    List<VideoModel> videos,
    List<AdModel> ads,
    int frequency,
  ) {
    if (ads.isEmpty) return videos;

    final integratedFeed = <dynamic>[];
    int adIndex = 0;

    for (int i = 0; i < videos.length; i++) {
      integratedFeed.add(videos[i]);

      if ((i + 1) % frequency == 0 && i < videos.length - 1) {
        if (adIndex < ads.length) {
          final adAsVideo = _convertAdToVideoFormat(ads[adIndex]);
          integratedFeed.add(adAsVideo);
          adIndex++;
        }
      }
    }

    AppLogger.log('🔍 VideoService: Integrated $adIndex ads into feed');
    return integratedFeed;
  }

  /// **Convert AdModel to VideoModel-like structure**
  Map<String, dynamic> _convertAdToVideoFormat(AdModel ad) {
    return {
      'id': 'ad_${ad.id}',
      'videoName': ad.title,
      'videoUrl': ad.videoUrl ?? ad.imageUrl ?? '',
      'thumbnailUrl': ad.imageUrl ?? ad.videoUrl ?? '',
      'description': ad.description,
      'likes': 0,
      'views': 0,
      'shares': 0,
      'uploader': {
        'id': ad.uploaderId,
        'name': 'Sponsored',
        'profilePic': ad.uploaderProfilePic ?? '',
      },
      'uploadedAt': DateTime.now(),
      'likedBy': <String>[],
      'videoType': 'ad',
      'link': ad.link,
      'isAd': true,
      'adData': ad.toJson(),
      'adType': ad.adType,
      'targetAudience': ad.targetAudience,
      'targetKeywords': ad.targetKeywords,
    };
  }

  // **DISPOSE METHOD**
  void dispose() {
    _videoIndexChangeListeners.clear();
    _videoScreenStateListeners.clear();
    AppLogger.log('🗑️ VideoService: Disposed all listeners');
  }

  /// **Helper: Parse videos in background isolate**
  static Map<String, dynamic> _parseVideosCompute(Map<String, dynamic> params) {
    final String body = params['body'];
    final String apiBaseUrl = params['apiBaseUrl'];
    final int page = params['page'];

    final Map<String, dynamic> responseData = json.decode(body);
    final List<dynamic> videoList = responseData['videos'] ?? [];

    final videos = videoList.map((json) {
      // **HLS URL Priority**: Use HLS for better streaming
      if (json['hlsPlaylistUrl'] != null &&
          json['hlsPlaylistUrl'].toString().isNotEmpty) {
        String hlsUrl = json['hlsPlaylistUrl'].toString();
        if (!hlsUrl.startsWith('http')) {
          if (hlsUrl.startsWith('/')) hlsUrl = hlsUrl.substring(1);
          json['videoUrl'] = '$apiBaseUrl/$hlsUrl';
        } else {
          json['videoUrl'] = hlsUrl;
        }
      } else if (json['hlsMasterPlaylistUrl'] != null &&
          json['hlsMasterPlaylistUrl'].toString().isNotEmpty) {
        String masterUrl = json['hlsMasterPlaylistUrl'].toString();
        if (!masterUrl.startsWith('http')) {
          if (masterUrl.startsWith('/')) masterUrl = masterUrl.substring(1);
          json['videoUrl'] = '$apiBaseUrl/$masterUrl';
        } else {
          json['videoUrl'] = masterUrl;
        }
      } else {
        if (json['videoUrl'] != null &&
            !json['videoUrl'].toString().startsWith('http')) {
          String videoUrl = json['videoUrl'].toString();
          if (videoUrl.startsWith('/')) videoUrl = videoUrl.substring(1);
          json['videoUrl'] = '$apiBaseUrl/$videoUrl';
        }
      }

      final video = VideoModel.fromJson(json);
      if (video.id.isEmpty) {
        return video.copyWith(
            id: 'temp_${DateTime.now().microsecondsSinceEpoch}');
      }
      return video;
    }).toList();

    return {
      'videos': List<VideoModel>.from(videos),
      'hasMore': responseData['hasMore'] ?? false,
      'total': responseData['total'] ?? videos.length,
      'currentPage': responseData['currentPage'] ?? page,
      'totalPages': responseData['totalPages'] ?? 1,
      'nextCursor': responseData['nextCursor'], // **NEW: Cursor for next page**
      // Only the following feed sends this; null everywhere else.
      'gate': responseData['gate'],
    };
  }
}


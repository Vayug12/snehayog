import 'dart:convert';
import 'package:vayug/features/auth/data/services/authservices.dart';
import 'package:vayug/features/auth/data/usermodel.dart';
import 'package:vayug/shared/utils/app_logger.dart';
import 'package:dio/dio.dart';
import 'package:vayug/shared/config/app_config.dart';
import 'package:vayug/shared/services/http_client_service.dart';
import 'package:vayug/core/interfaces/i_user_service.dart';

class UserService implements IUserService {
  final AuthService _authService = AuthService();

  // **REQUEST DEDUPLICATION: Track in-flight requests to prevent duplicate API calls**
  static final Map<String, Future<Map<String, dynamic>>> _pendingRequests = {};

  @override
  Future<Map<String, dynamic>> getUserById(String id) async {
    // **OPTIMIZATION: If a request for this user ID is already in-flight, reuse it**
    if (_pendingRequests.containsKey(id)) {
      AppLogger.log('♻️ UserService: Reusing in-flight request for user: $id');
      try {
        return await _pendingRequests[id]!;
      } catch (e) {
        // If the request failed, remove it so we can retry
        _pendingRequests.remove(id);
        rethrow;
      }
    }

    // **FIXED: Make authentication optional for creator profiles**
    // Backend /api/users/:id endpoint doesn't require authentication
    final token = (await _authService.getUserData())?['token'];

    // **FIXED: Only include Authorization header if token exists**
    final headers = <String, String>{
      'Content-Type': 'application/json',
    };
    if (token != null) {
      headers['Authorization'] = 'Bearer $token';
    }

    // **DEDUPLICATION: Create and store the future before making the request**
    final requestFuture = _fetchUserById(id, headers);
    _pendingRequests[id] = requestFuture;

    try {
      final result = await requestFuture;
      // **CLEANUP: Remove from pending requests after successful completion**
      _pendingRequests.remove(id);
      return result;
    } catch (e) {
      // **CLEANUP: Remove from pending requests on error so it can be retried**
      _pendingRequests.remove(id);
      rethrow;
    }
  }

  /// **PRIVATE: Internal method to actually fetch user data from backend**
  Future<Map<String, dynamic>> _fetchUserById(
      String id, Map<String, String> headers) async {
    final response = await httpClientService.get(
      Uri.parse('${NetworkHelper.usersEndpoint}/$id'),
      headers: headers,
    );

    if (response.statusCode == 200) {
      AppLogger.log('✅ UserService: Successfully loaded user: $id');
      return jsonDecode(response.body);
    } else if (response.statusCode == 404) {
      AppLogger.log('❌ UserService: User not found: $id');
      throw Exception('User not found');
    } else {
      AppLogger.log(
          'Failed to load user. Status code: ${response.statusCode}, Body: ${response.body}');
      throw Exception('Failed to load user (Status: ${response.statusCode})');
    }
  }

  /// Follow a user
  @override
  Future<bool> followUser(String userIdToFollow) async {
    final trimmedUserId = userIdToFollow.trim();
    if (trimmedUserId.isEmpty || trimmedUserId == 'unknown') {
      AppLogger.log('❌ Follow API Error: Invalid user ID provided');
      throw Exception('Invalid user ID');
    }

    try {
      final token = (await _authService.getUserData())?['token'];
      AppLogger.log(
          '🔍 Follow API Debug: Token retrieved: ${token != null ? 'Yes' : 'No'}');

      if (token == null) {
        AppLogger.log('❌ Follow API Error: No authentication token found');
        throw Exception('Not authenticated');
      }

      AppLogger.log(
          '🔍 Follow API Debug: Making request to follow user: $trimmedUserId');
      AppLogger.log(
          '🔍 Follow API Debug: Using token: ${token.substring(0, 10)}...');

      final response = await httpClientService.post(
        Uri.parse('${NetworkHelper.usersEndpoint}/follow'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'userIdToFollow': trimmedUserId}),
      );

      AppLogger.log(
          '🔍 Follow API Debug: Response status: ${response.statusCode}');
      AppLogger.log('🔍 Follow API Debug: Response body: ${response.body}');

      if (response.statusCode == 200) {
        AppLogger.log('✅ Follow API Success: User followed successfully');
        return true;
      } else if (response.statusCode == 400) {
        // Some backends return 400 with "Already following this user" if the
        // relationship already exists. Treat that as a logical success so the
        // UI can still move to the "Subscribed" state instead of failing.
        try {
          final body = jsonDecode(response.body);
          final errorMessage = body['error']?.toString() ?? '';
          if (errorMessage.toLowerCase().contains('already following')) {
            AppLogger.log(
                '✅ Follow API Logical Success: Already following $trimmedUserId');
            return true;
          }
        } catch (_) {
          // If parsing fails, fall through to generic error handling below.
        }

        AppLogger.log(
            '❌ Follow API Error: Status code ${response.statusCode}, Body: ${response.body}');
        throw Exception('Failed to follow user: ${response.statusCode}');
      } else {
        AppLogger.log(
            '❌ Follow API Error: Status code ${response.statusCode}, Body: ${response.body}');
        throw Exception('Failed to follow user: ${response.statusCode}');
      }
    } catch (e) {
      AppLogger.log('❌ Follow API Exception: $e');
      throw Exception('Failed to follow user: $e');
    }
  }

  /// Unfollow a user
  @override
  Future<bool> unfollowUser(String userIdToUnfollow) async {
    final trimmedUserId = userIdToUnfollow.trim();
    if (trimmedUserId.isEmpty || trimmedUserId == 'unknown') {
      AppLogger.log('❌ Unfollow API Error: Invalid user ID provided');
      throw Exception('Invalid user ID');
    }

    try {
      final token = (await _authService.getUserData())?['token'];
      AppLogger.log(
          '🔍 Unfollow API Debug: Token retrieved: ${token != null ? 'Yes' : 'No'}');

      if (token == null) {
        AppLogger.log('❌ Unfollow API Error: No authentication token found');
        throw Exception('Not authenticated');
      }

      AppLogger.log(
          '🔍 Unfollow API Debug: Making request to unfollow user: $trimmedUserId');

      final response = await httpClientService.post(
        Uri.parse('${NetworkHelper.usersEndpoint}/unfollow'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'userIdToUnfollow': trimmedUserId}),
      );

      AppLogger.log(
          '🔍 Unfollow API Debug: Response status: ${response.statusCode}');
      AppLogger.log('🔍 Unfollow API Debug: Response body: ${response.body}');

      if (response.statusCode == 200) {
        AppLogger.log('✅ Unfollow API Success: User unfollowed successfully');
        return true;
      } else {
        AppLogger.log(
            '❌ Unfollow API Error: Status code ${response.statusCode}, Body: ${response.body}');
        throw Exception('Failed to unfollow user: ${response.statusCode}');
      }
    } catch (e) {
      AppLogger.log('❌ Unfollow API Exception: $e');
      throw Exception('Failed to unfollow user: $e');
    }
  }

  /// Check if current user is following another user
  @override
  Future<bool> isFollowingUser(String userIdToCheck) async {
    final trimmedUserId = userIdToCheck.trim();
    if (trimmedUserId.isEmpty || trimmedUserId == 'unknown') {
      return false;
    }

    try {
      final token = (await _authService.getUserData())?['token'];
      if (token == null) {
        throw Exception('Not authenticated');
      }

      final response = await httpClientService.get(
        Uri.parse('${NetworkHelper.usersEndpoint}/isfollowing/$trimmedUserId'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['isFollowing'] ?? false;
      } else {
        AppLogger.log(
            'Failed to check follow status. Status: ${response.statusCode}');
        return false;
      }
    } catch (e) {
      AppLogger.log('Error checking follow status: $e');
      return false;
    }
  }

  /// **OPTIMIZED: Batch check follow status for multiple users in 1 API call**
  @override
  Future<Map<String, bool>> batchCheckFollowStatus(List<String> userIds) async {
    if (userIds.isEmpty) return {};

    try {
      final token = (await _authService.getUserData())?['token'];
      if (token == null) return {};

      final response = await httpClientService.post(
        Uri.parse('${NetworkHelper.usersEndpoint}/isfollowing/batch'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'userIds': userIds}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final statuses = data['statuses'] as Map<String, dynamic>? ?? {};
        return statuses.map((key, value) => MapEntry(key, value as bool));
      }

      return {};
    } catch (e) {
      AppLogger.log('❌ Error batch checking follow status: $e');
      return {};
    }
  }

  /// Update user profile information
  @override
  Future<bool> updateProfile({
    required String googleId,
    required String name,
    String? profilePic,
    String? websiteUrl,
  }) async {
    final response = await httpClientService.post(
      Uri.parse('${NetworkHelper.usersEndpoint}/update-profile'),
      headers: {
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'googleId': googleId,
        'name': name,
        if (profilePic != null) 'profilePic': profilePic,
        if (websiteUrl != null) 'websiteUrl': websiteUrl,
      }),
    );

    if (response.statusCode == 200) {
      return true;
    } else {
      AppLogger.log(
          'Failed to update profile. Status code: ${response.statusCode}, Body: ${response.body}');
      throw Exception('Failed to update profile on server');
    }
  }

  @override
  Future<String?> updateProfilePhoto(String googleId, String photoPath) async {
    final token = (await _authService.getUserData())?['token'];
    if (token == null) throw Exception('Not authenticated');

    final response = await httpClientService.postMultipart(
      '${NetworkHelper.usersEndpoint}/update-photo',
      fields: {'googleId': googleId},
      files: [
        MapEntry(
          'profilePic',
          await MultipartFile.fromFile(photoPath,
              filename: 'profile_photo.jpg'),
        ),
      ],
      headers: {'Authorization': 'Bearer $token'},
    );

    if (response.statusCode == 200) {
      final data =
          response.data is String ? jsonDecode(response.data) : response.data;
      return data['profilePic'];
    }
    return null;
  }

  /// Get user data including follower counts
  @override
  Future<UserModel?> getUserData(String userId) async {
    try {
      AppLogger.log('🔍 UserService: Getting user data for userId: $userId');
      AppLogger.log('🔍 UserService: userId type: ${userId.runtimeType}');
      AppLogger.log('🔍 UserService: userId length: ${userId.length}');

      final token = (await _authService.getUserData())?['token'];
      AppLogger.log(
          '🔍 UserService: Token retrieved: ${token != null ? 'Yes' : 'No'}');
      if (token != null) {
        AppLogger.log(
            '🔍 UserService: Token (first 20 chars): ${token.substring(0, 20)}...');
        AppLogger.log('🔍 UserService: Token length: ${token.length}');
      }

      if (token == null) {
        throw Exception('Not authenticated');
      }

      final url = '${NetworkHelper.usersEndpoint}/$userId';
      AppLogger.log('🔍 UserService: Making request to: $url');
      AppLogger.log(
          '🔍 UserService: Headers: Authorization: Bearer ${token.substring(0, 20)}...');

      final response = await httpClientService.get(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      AppLogger.log('🔍 UserService: Response status: ${response.statusCode}');
      AppLogger.log('🔍 UserService: Response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        // Also check follow status for current user
        bool isFollowing = false;
        try {
          isFollowing = await isFollowingUser(userId);
        } catch (e) {
          AppLogger.log('Error checking follow status: $e');
        }

        // Create UserModel with all available data
        return UserModel(
          id: data['googleId'] ?? data['id'] ?? data['_id'] ?? '',
          name: data['name'] ?? '',
          email: data['email'] ?? '',
          profilePic: data['profilePic'] ?? '',
          videos: List<String>.from(data['videos'] ?? []),
          followersCount: data['followersCount'] ?? data['followers'] ?? 0,
          followingCount: data['followingCount'] ?? data['following'] ?? 0,
          isFollowing: isFollowing,
          createdAt: data['createdAt'] != null
              ? DateTime.parse(data['createdAt'])
              : null,
          bio: data['bio'],
          location: data['location'],
          websiteUrl: data['websiteUrl']?.toString(),
        );
      } else {
        AppLogger.log(
            'Failed to load user data. Status: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      AppLogger.log('Error getting user data: $e');
      return null;
    }
  }

  /// Get YouTube auth URL
  Future<String?> getYouTubeAuthUrl() async {
    try {
      final userData = await _authService.getUserData();
      final token = userData?['token'];
      if (token == null) {
        throw Exception('Not authenticated');
      }

      final response = await httpClientService.get(
        Uri.parse('${NetworkHelper.apiBaseUrl}/auth/youtube'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['authUrl'];
      } else {
        AppLogger.log(
            'Failed to get YouTube auth URL. Status: ${response.statusCode}, Body: ${response.body}');
        throw Exception('Failed to get YouTube auth URL');
      }
    } catch (e) {
      AppLogger.log('Error getting YouTube auth URL: $e');
      rethrow;
    }
  }

  /// Get every subscriber of the creator (walks pagination).
  /// Used where the full audience is needed, e.g. subscriber notifications.
  Future<List<Subscriber>> getSubscribers({int maxSubscribers = 2000}) async {
    final subscribers = <Subscriber>[];
    String? cursor;

    // Bounded loop: stops on hasMore == false, on a repeated cursor, or at the cap
    while (subscribers.length < maxSubscribers) {
      final page = await getSubscribersPage(limit: 100, cursor: cursor);
      subscribers.addAll(page.subscribers);

      if (!page.hasMore ||
          page.nextCursor == null ||
          page.nextCursor == cursor) {
        break;
      }
      cursor = page.nextCursor;
    }

    AppLogger.log('✅ UserService: Fetched ${subscribers.length} subscribers');
    return subscribers;
  }

  /// One page of the creator's subscribers, newest first.
  /// Pass the returned cursor back unchanged to load the next page.
  Future<SubscribersPage> getSubscribersPage({
    int limit = 30,
    String? cursor,
  }) async {
    try {
      final token = (await _authService.getUserData())?['token'];
      if (token == null) {
        throw Exception('Not authenticated');
      }

      final query = <String, String>{
        'limit': '$limit',
        if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
      };

      final response = await httpClientService.get(
        Uri.parse('${NetworkHelper.usersEndpoint}/subscribers')
            .replace(queryParameters: query),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        return SubscribersPage.fromJson(
          Map<String, dynamic>.from(jsonDecode(response.body)),
        );
      }

      AppLogger.log(
          'Failed to fetch subscribers. Status: ${response.statusCode}');
      throw Exception('Failed to fetch subscribers');
    } catch (e) {
      AppLogger.log('Error fetching subscribers: $e');
      rethrow;
    }
  }

  /// Subscribers gained since the creator last opened their subscriber list.
  /// Drives the red dot on the profile Subscribers stat.
  Future<int> getNewSubscribersCount() async {
    try {
      final token = (await _authService.getUserData())?['token'];
      if (token == null) return 0;

      final response = await httpClientService.get(
        Uri.parse('${NetworkHelper.usersEndpoint}/subscribers/new-count'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return int.tryParse(data['newCount']?.toString() ?? '') ?? 0;
      }

      AppLogger.log(
          '⚠️ UserService: New subscribers count failed (${response.statusCode})');
      throw Exception('Failed to fetch new subscribers count');
    } catch (e) {
      AppLogger.log('❌ UserService: Error fetching new subscribers count: $e');
      rethrow;
    }
  }

  /// Clear the new-subscriber badge. [seenAt] should be the newest
  /// subscription timestamp actually shown, so anything that arrives
  /// mid-request stays unseen. Returns the remaining unseen count.
  Future<int> markSubscribersSeen({DateTime? seenAt}) async {
    try {
      final token = (await _authService.getUserData())?['token'];
      if (token == null) return 0;

      final response = await httpClientService.post(
        Uri.parse('${NetworkHelper.usersEndpoint}/subscribers/seen'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: {
          if (seenAt != null) 'seenAt': seenAt.toUtc().toIso8601String(),
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return int.tryParse(data['newCount']?.toString() ?? '') ?? 0;
      }

      AppLogger.log(
          '⚠️ UserService: Mark subscribers seen failed (${response.statusCode})');
      throw Exception('Failed to mark subscribers as seen');
    } catch (e) {
      AppLogger.log('❌ UserService: Error marking subscribers seen: $e');
      rethrow;
    }
  }

  /// Creators the user can subscribe to in order to unlock the Vayu feed.
  /// The backend already excludes the user and everyone they follow.
  Future<List<SuggestedCreator>> getSuggestedCreators({
    int limit = 20,
    String videoType = 'vayu',
  }) async {
    final page = await getSuggestedCreatorsPage(
      limit: limit,
      videoType: videoType,
    );
    return page.creators;
  }

  /// Fetches one page of suggestions. Pass the returned cursor back unchanged.
  Future<SuggestedCreatorsPage> getSuggestedCreatorsPage({
    int limit = 20,
    String videoType = 'vayu',
    String? cursor,
  }) async {
    try {
      final token = (await _authService.getUserData())?['token'];
      if (token == null) throw Exception('Not authenticated');

      final query = <String, String>{
        'limit': '$limit',
        'videoType': videoType,
        if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
      };
      final response = await httpClientService.get(
        Uri.parse('${NetworkHelper.usersEndpoint}/suggested-creators')
            .replace(queryParameters: query),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List<dynamic> creators = data['creators'] ?? [];
        final parsedCreators = creators
            .map((json) =>
                SuggestedCreator.fromJson(Map<String, dynamic>.from(json)))
            .where((c) => c.id.isNotEmpty)
            .toList();
        return SuggestedCreatorsPage(
          creators: parsedCreators,
          nextCursor: data['nextCursor']?.toString(),
          hasMore: data['hasMore'] == true,
        );
      }

      throw Exception(
          'Failed to fetch suggested creators: ${response.statusCode}');
    } catch (e) {
      AppLogger.log('❌ UserService: Error fetching suggested creators: $e');
      rethrow;
    }
  }

  /// Get list of creators the user is following
  Future<List<Map<String, dynamic>>> getFollowingList() async {
    try {
      final token = (await _authService.getUserData())?['token'];
      if (token == null) throw Exception('Not authenticated');

      final response = await httpClientService.get(
        Uri.parse('${NetworkHelper.usersEndpoint}/following/list'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return List<Map<String, dynamic>>.from(data['following'] ?? []);
      } else {
        throw Exception('Failed to fetch following list');
      }
    } catch (e) {
      AppLogger.log('❌ UserService: Error fetching following list: $e');
      rethrow;
    }
  }
}

class SuggestedCreatorsPage {
  final List<SuggestedCreator> creators;
  final String? nextCursor;
  final bool hasMore;

  const SuggestedCreatorsPage({
    required this.creators,
    required this.nextCursor,
    required this.hasMore,
  });
}

/// Creator suggested to a user who has not yet unlocked the Vayu feed
class SuggestedCreator {
  final String id; // googleId — accepted by the follow/unfollow endpoints
  final String name;
  final String profilePic;
  final int followerCount;

  const SuggestedCreator({
    required this.id,
    required this.name,
    required this.profilePic,
    required this.followerCount,
  });

  factory SuggestedCreator.fromJson(Map<String, dynamic> json) {
    return SuggestedCreator(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Creator',
      profilePic: json['profilePic']?.toString() ?? '',
      followerCount: int.tryParse(json['followerCount']?.toString() ?? '') ?? 0,
    );
  }
}

/// One page of subscribers plus the badge state that came with it
class SubscribersPage {
  final List<Subscriber> subscribers;
  final String? nextCursor;
  final bool hasMore;
  final int total;
  final int newCount;

  const SubscribersPage({
    required this.subscribers,
    required this.nextCursor,
    required this.hasMore,
    required this.total,
    required this.newCount,
  });

  factory SubscribersPage.fromJson(Map<String, dynamic> json) {
    final List<dynamic> rawSubscribers = json['subscribers'] ?? const [];
    final subscribers = rawSubscribers
        .whereType<Map>()
        .map((item) => Subscriber.fromJson(Map<String, dynamic>.from(item)))
        .where((subscriber) => subscriber.id.isNotEmpty)
        .toList();

    return SubscribersPage(
      subscribers: subscribers,
      nextCursor: json['nextCursor']?.toString(),
      hasMore: json['hasMore'] == true,
      total: int.tryParse(json['total']?.toString() ?? '') ?? subscribers.length,
      newCount: int.tryParse(json['newCount']?.toString() ?? '') ?? 0,
    );
  }

  /// Newest subscription timestamp in this page — the watermark to mark as seen
  DateTime? get newestSubscribedAt {
    DateTime? newest;
    for (final subscriber in subscribers) {
      final subscribedAt = subscriber.subscribedAt;
      if (subscribedAt == null) continue;
      if (newest == null || subscribedAt.isAfter(newest)) newest = subscribedAt;
    }
    return newest;
  }
}

/// Subscriber model for subscriber-only content
class Subscriber {
  final String id;
  final String name;
  final String email;
  final String? profilePic;
  final DateTime? subscribedAt;

  /// Subscribed after the creator last opened their subscriber list
  final bool isNew;

  Subscriber({
    required this.id,
    required this.name,
    required this.email,
    this.profilePic,
    this.subscribedAt,
    this.isNew = false,
  });

  factory Subscriber.fromJson(Map<String, dynamic> json) {
    return Subscriber(
      id: json['id']?.toString() ?? json['_id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      profilePic: json['profilePic']?.toString(),
      subscribedAt:
          DateTime.tryParse(json['subscribedAt']?.toString() ?? '')?.toLocal(),
      isNew: json['isNew'] == true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'email': email,
      'profilePic': profilePic,
      'subscribedAt': subscribedAt?.toIso8601String(),
      'isNew': isNew,
    };
  }
}

/// **NEW: FollowManager for better follow state management**
class FollowManager {
  static final Map<String, bool> _followCache = {};
  static final Map<String, int> _followerCountCache = {};

  /// Check if user is following another user (with caching)
  static Future<bool> isFollowing(String userIdToCheck) async {
    // Return cached value if available
    if (_followCache.containsKey(userIdToCheck)) {
      return _followCache[userIdToCheck]!;
    }

    // Fetch from service and cache
    try {
      final userService = UserService();
      final isFollowing = await userService.isFollowingUser(userIdToCheck);
      _followCache[userIdToCheck] = isFollowing;
      return isFollowing;
    } catch (e) {
      AppLogger.log('Error checking follow status: $e');
      return false;
    }
  }

  /// Update follow status in cache
  static void updateFollowStatus(String userId, bool isFollowing) {
    _followCache[userId] = isFollowing;
  }

  /// Update follower count in cache
  static void updateFollowerCount(String userId, int count) {
    _followerCountCache[userId] = count;
  }

  /// Get cached follower count
  static int getFollowerCount(String userId) {
    return _followerCountCache[userId] ?? 0;
  }

  /// Clear cache for a specific user
  static void clearUserCache(String userId) {
    _followCache.remove(userId);
    _followerCountCache.remove(userId);
  }

  /// Clear all cache
  static void clearAllCache() {
    _followCache.clear();
    _followerCountCache.clear();
  }
}

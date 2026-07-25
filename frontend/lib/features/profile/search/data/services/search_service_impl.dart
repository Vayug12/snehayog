import 'dart:convert';

import 'package:vayug/core/interfaces/i_search_service.dart';
import 'package:vayug/features/auth/data/usermodel.dart';
import 'package:vayug/features/profile/search/data/models/search_suggestions.dart';
import 'package:vayug/features/video/core/data/models/video_model.dart';
import 'package:vayug/shared/config/app_config.dart';
import 'package:vayug/shared/services/http_client_service.dart';
import 'package:vayug/shared/utils/app_logger.dart';

/// **PLUGIN LAYER — HTTP implementation of [ISearchService].**
///
/// This is the "default codec" — the one the app ships with.
/// Tomorrow i can create [AiSearchServiceImpl] or [CachedSearchServiceImpl]
/// and inject it into [SearchDiscoveryScreen] without touching ANY screen code.
class SearchServiceImpl implements ISearchService {
  // Cache base URL to avoid repeated network checks on every keystroke.
  String? _cachedBaseUrl;

  SearchServiceImpl();

  Future<String> _getBaseUrl() async {
    _cachedBaseUrl ??= await AppConfig.getBaseUrlWithFallback();
    return _cachedBaseUrl!;
  }

  // ---------------------------------------------------------------------------
  // ISearchService implementation
  // ---------------------------------------------------------------------------

  @override
  Future<List<VideoModel>> searchVideos(String query, {int limit = 20}) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return [];

    final baseUrl = await _getBaseUrl();
    final uri = Uri.parse('$baseUrl/api/search/videos').replace(
      queryParameters: <String, String>{
        'q': trimmed,
        'limit': '$limit',
      },
    );

    AppLogger.log('🔍 SearchServiceImpl: searchVideos q="$trimmed"');

    try {
      final res = await httpClientService.withRequestContext(
        feature: 'search',
        uiAction: 'submit',
        screen: 'search',
        request: () => httpClientService.get(
          uri,
          headers: const {'Content-Type': 'application/json'},
          timeout: const Duration(seconds: 10),
        ),
      );

      if (res.statusCode != 200) {
        AppLogger.log('❌ SearchServiceImpl: searchVideos status=${res.statusCode}');
        return [];
      }

      final data = json.decode(res.body) as Map<String, dynamic>;
      final list = data['videos'] as List<dynamic>? ?? [];
      AppLogger.log('✅ SearchServiceImpl: searchVideos found ${list.length} videos');

      return list
          .map((e) => VideoModel.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(growable: false);
    } catch (e) {
      AppLogger.log('❌ SearchServiceImpl: searchVideos exception: $e');
      return [];
    }
  }

  @override
  Future<List<UserModel>> searchCreators(String query, {int limit = 20}) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return [];

    final baseUrl = await _getBaseUrl();
    final uri = Uri.parse('$baseUrl/api/search/creators').replace(
      queryParameters: <String, String>{
        'q': trimmed,
        'limit': '$limit',
      },
    );

    AppLogger.log('🔍 SearchServiceImpl: searchCreators q="$trimmed"');

    try {
      final res = await httpClientService.withRequestContext(
        feature: 'search',
        uiAction: 'submit',
        screen: 'search',
        request: () => httpClientService.get(
          uri,
          headers: const {'Content-Type': 'application/json'},
          timeout: const Duration(seconds: 10),
        ),
      );

      if (res.statusCode != 200) {
        AppLogger.log('❌ SearchServiceImpl: searchCreators status=${res.statusCode}');
        return [];
      }

      final data = json.decode(res.body) as Map<String, dynamic>;
      final list = data['creators'] as List<dynamic>? ?? [];
      AppLogger.log('✅ SearchServiceImpl: searchCreators found ${list.length} creators');

      if (list.isNotEmpty) {
        AppLogger.log('📡 SearchServiceImpl: First creator: ${list[0]['name']}');
      }

      return list
          .map((e) => UserModel.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(growable: false);
    } catch (e) {
      AppLogger.log('❌ SearchServiceImpl: searchCreators exception: $e');
      return [];
    }
  }

  @override
  Future<SearchSuggestions> getSuggestions(String query) async {
    final trimmed = query.trim();
    if (trimmed.length < 2) return SearchSuggestions.empty;

    final baseUrl = await _getBaseUrl();

    // Fetch creators and videos in parallel for fastest autocomplete.
    final creatorsUri = Uri.parse('$baseUrl/api/search/creators').replace(
      queryParameters: <String, String>{'q': trimmed, 'limit': '5'},
    );
    final videosUri = Uri.parse('$baseUrl/api/search/videos').replace(
      queryParameters: <String, String>{'q': trimmed, 'limit': '3'},
    );

    try {
      final results = await httpClientService.withRequestContext(
        feature: 'search',
        uiAction: 'suggestions',
        screen: 'search',
        request: () => Future.wait([
          httpClientService.get(
            creatorsUri,
            headers: const {'Content-Type': 'application/json'},
            timeout: const Duration(seconds: 5),
          ),
          httpClientService.get(
            videosUri,
            headers: const {'Content-Type': 'application/json'},
            timeout: const Duration(seconds: 5),
          ),
        ]),
      );

      final creatorsRes = results[0];
      final videosRes = results[1];

      List<UserModel> creators = [];
      if (creatorsRes.statusCode == 200) {
        final data = json.decode(creatorsRes.body) as Map<String, dynamic>;
        final list = data['creators'] as List<dynamic>? ?? [];
        creators = list
            .map((e) => UserModel.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(growable: false);
      }

      List<VideoModel> videos = [];
      if (videosRes.statusCode == 200) {
        final data = json.decode(videosRes.body) as Map<String, dynamic>;
        final list = data['videos'] as List<dynamic>? ?? [];
        videos = list
            .map((e) => VideoModel.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(growable: false);
      }

      return SearchSuggestions(creators: creators, videos: videos);
    } catch (e) {
      AppLogger.log('❌ SearchServiceImpl: getSuggestions exception: $e');
      return SearchSuggestions.empty;
    }
  }
}

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:vayug/shared/config/app_config.dart';
import 'package:vayug/shared/models/profession.dart';
import 'package:vayug/shared/services/http_client_service.dart';

class ProfessionCatalogService {
  ProfessionCatalogService._();

  static final ProfessionCatalogService instance = ProfessionCatalogService._();
  static const _cacheKey = 'profession_catalog_v1';
  static const _cacheTimestampKey = 'profession_catalog_v1_cached_at';
  static const _cacheLifetime = Duration(hours: 24);

  List<Profession>? _memoryCache;

  Future<List<Profession>> getProfessions({bool forceRefresh = false}) async {
    if (!forceRefresh && _memoryCache != null) return _memoryCache!;

    final preferences = await SharedPreferences.getInstance();
    final cached = _readCached(preferences);
    final cachedAt = DateTime.tryParse(
      preferences.getString(_cacheTimestampKey) ?? '',
    );
    if (!forceRefresh &&
        cached.isNotEmpty &&
        cachedAt != null &&
        DateTime.now().difference(cachedAt) < _cacheLifetime) {
      _memoryCache = cached;
      return cached;
    }

    try {
      final response = await httpClientService.get(
        Uri.parse('${NetworkHelper.apiBaseUrl}/professions'),
        timeout: NetworkHelper.shortTimeout,
      );
      if (response.statusCode != 200) {
        throw Exception('Profession catalogue unavailable');
      }

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final professions = (body['professions'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(Profession.fromJson)
          .where((profession) =>
              profession.id.isNotEmpty && profession.label.isNotEmpty)
          .toList(growable: false);
      if (professions.isEmpty) throw Exception('Profession catalogue is empty');

      await preferences.setString(
        _cacheKey,
        jsonEncode(professions.map((profession) => profession.toJson()).toList()),
      );
      await preferences.setString(
        _cacheTimestampKey,
        DateTime.now().toIso8601String(),
      );
      _memoryCache = professions;
      return professions;
    } catch (_) {
      if (cached.isNotEmpty) {
        _memoryCache = cached;
        return cached;
      }
      rethrow;
    }
  }

  List<Profession> _readCached(SharedPreferences preferences) {
    final raw = preferences.getString(_cacheKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      return (jsonDecode(raw) as List<dynamic>)
          .whereType<Map<String, dynamic>>()
          .map(Profession.fromJson)
          .where((profession) =>
              profession.id.isNotEmpty && profession.label.isNotEmpty)
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }
}


import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vayug/shared/config/app_config.dart';
import 'package:vayug/shared/services/platform_id_service.dart';
import 'package:vayug/shared/utils/app_logger.dart';

class InstallAttributionService {
  InstallAttributionService._();

  static final InstallAttributionService instance = InstallAttributionService._();
  static const MethodChannel _channel = MethodChannel('vayug/install_referrer');

  static const _initializedKey = 'install_attribution_initialized';
  static const _sourceKey = 'install_attribution_utm_source';
  static const _mediumKey = 'install_attribution_utm_medium';
  static const _campaignKey = 'install_attribution_utm_campaign';
  static const _contentKey = 'install_attribution_utm_content';
  static const _termKey = 'install_attribution_utm_term';
  static const _rawReferrerKey = 'install_attribution_raw_referrer';
  static const _backendSyncedKey = 'install_attribution_backend_synced';

  Future<Map<String, String>> getAttributionPayload() async {
    final prefs = await SharedPreferences.getInstance();
    await _captureInstallReferrerIfNeeded(prefs);

    final payload = <String, String>{};
    _putIfPresent(payload, 'source', prefs.getString(_sourceKey));
    _putIfPresent(payload, 'medium', prefs.getString(_mediumKey));
    _putIfPresent(payload, 'campaign', prefs.getString(_campaignKey));
    _putIfPresent(payload, 'content', prefs.getString(_contentKey));
    _putIfPresent(payload, 'term', prefs.getString(_termKey));
    _putIfPresent(payload, 'rawReferrer', prefs.getString(_rawReferrerKey));
    return payload;
  }

  /// Sends attribution to backend on first API call (fire-and-forget).
  /// Only syncs once per device to avoid redundant calls.
  Future<void> syncAttributionToBackend() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_backendSyncedKey) == true) return;

      final attribution = await getAttributionPayload();
      if (attribution.isEmpty) {
        await prefs.setBool(_backendSyncedKey, true);
        return;
      }

      final platformIdService = PlatformIdService();
      final deviceId = await platformIdService.getPlatformId();
      if (deviceId.isEmpty || deviceId == 'anon' || deviceId == 'anonymous') {
        return;
      }

      final packageInfo = await PackageInfo.fromPlatform();
      final appVersion = '${packageInfo.version}+${packageInfo.buildNumber}';

      final response = await http.post(
        Uri.parse('${NetworkHelper.apiBaseUrl}/attribution/capture'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'deviceId': deviceId,
          'attribution': attribution,
          'appVersion': appVersion,
        }),
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        await prefs.setBool(_backendSyncedKey, true);
        AppLogger.log('✅ InstallAttribution: Synced to backend');
      } else {
        AppLogger.log('⚠️ InstallAttribution: Backend sync failed: ${response.statusCode}');
      }
    } catch (e) {
      AppLogger.log('⚠️ InstallAttribution: Backend sync error: $e');
    }
  }

  Future<void> _captureInstallReferrerIfNeeded(SharedPreferences prefs) async {
    if (!Platform.isAndroid || prefs.getBool(_initializedKey) == true) return;

    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'getInstallReferrer',
      );
      final rawReferrer = result?['installReferrer']?.toString().trim();
      if (rawReferrer == null || rawReferrer.isEmpty) {
        await prefs.setBool(_initializedKey, true);
        return;
      }

      final params = _parseReferrer(rawReferrer);
      await prefs.setString(_rawReferrerKey, rawReferrer);
      await _saveIfPresent(prefs, _sourceKey, params['utm_source']);
      await _saveIfPresent(prefs, _mediumKey, params['utm_medium']);
      await _saveIfPresent(prefs, _campaignKey, params['utm_campaign']);
      await _saveIfPresent(prefs, _contentKey, params['utm_content']);
      await _saveIfPresent(prefs, _termKey, params['utm_term']);
      await prefs.setBool(_initializedKey, true);
    } catch (_) {
      // Retry on the next launch/feedback submit if the native channel is not ready.
    }
  }

  Map<String, String> _parseReferrer(String rawReferrer) {
    final normalized = rawReferrer.startsWith('?')
        ? rawReferrer.substring(1)
        : rawReferrer;

    var params = Uri.splitQueryString(normalized);
    if (!params.containsKey('utm_source') && normalized.contains('%3D')) {
      params = Uri.splitQueryString(Uri.decodeComponent(normalized));
    }

    return params.map((key, value) => MapEntry(
          key.trim().toLowerCase(),
          value.trim().toLowerCase(),
        ));
  }

  Future<void> _saveIfPresent(
    SharedPreferences prefs,
    String key,
    String? value,
  ) async {
    final cleaned = value?.trim();
    if (cleaned != null && cleaned.isNotEmpty) {
      await prefs.setString(key, cleaned);
    }
  }

  void _putIfPresent(Map<String, String> payload, String key, String? value) {
    final cleaned = value?.trim();
    if (cleaned != null && cleaned.isNotEmpty) {
      payload[key] = cleaned;
    }
  }
}

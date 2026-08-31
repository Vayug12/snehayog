import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vayug/shared/models/app_remote_config.dart';
import 'package:vayug/shared/config/app_config.dart';
import 'package:vayug/shared/services/http_client_service.dart';
import 'package:vayug/shared/utils/app_logger.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'dart:io';

/// AppRemoteConfigService
///
/// Service to fetch and manage backend-driven app configuration.
/// This service:
/// - Fetches config from /api/app-config on app launch
/// - Caches config locally for offline use
/// - Provides graceful fallback if API fails
/// - Handles version checking and forced updates
class AppRemoteConfigService {
  static AppRemoteConfigService? _instance;
  static AppRemoteConfigService get instance =>
      _instance ??= AppRemoteConfigService._internal();

  AppRemoteConfigService._internal();

  static const String _cacheKey = 'app_remote_config';
  static const String _cacheTimestampKey = 'app_remote_config_timestamp';
  static const String _apiVersionHeader = 'X-API-Version';
  static String get _defaultApiVersion => AppConfig.kApiVersion;

  AppRemoteConfig? _cachedConfig;
  bool _isInitialized = false;
  DateTime? _lastFetchTime;

  /// Initialize the service and fetch config
  Future<void> initialize() async {
    if (_isInitialized) {
      AppLogger.log('✅ AppRemoteConfigService: Already initialized');
      return;
    }

    AppLogger.log('🔍 AppRemoteConfigService: Initializing...');

    // Load cached config first (for immediate use)
    await _loadCachedConfig();

    // Fetch fresh config in background
    await fetchConfig(forceRefresh: false);

    _isInitialized = true;
    AppLogger.log('✅ AppRemoteConfigService: Initialized');
  }

  /// Get current config (cached or fresh)
  AppRemoteConfig? get config => _cachedConfig;

  /// Check if config is available
  bool get isConfigAvailable => _cachedConfig != null;

  /// Get last fetch time
  DateTime? get lastFetchTime => _lastFetchTime;

  /// Fetch config from backend
  ///
  /// [forceRefresh] - If true, bypasses cache and fetches fresh config
  /// [platform] - Platform identifier (android, ios, web)
  /// [environment] - Environment (development, staging, production)
  Future<AppRemoteConfig?> fetchConfig({
    bool forceRefresh = false,
    String? platform,
    String? environment,
  }) async {
    try {
      // Determine platform
      final detectedPlatform = platform ?? _detectPlatform();
      final env = environment ?? (AppConfig.isDevelopment ? 'development' : 'production');

      AppLogger.log(
          '🔍 AppRemoteConfigService: Fetching config for $detectedPlatform/$env');

      final baseUrl = await AppConfig.getBaseUrlWithFallback();
      final url =
          Uri.parse('$baseUrl/api/app-config').replace(queryParameters: {
        'platform': detectedPlatform,
        'environment': env,
      });

      AppLogger.log('🔍 AppRemoteConfigService: URL: $url');

      final response = await httpClientService.get(
        url,
        headers: {
          'Content-Type': 'application/json',
          _apiVersionHeader: _defaultApiVersion,
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final config = AppRemoteConfig.fromJson(json);

        // Cache the config
        await _saveConfig(config);
        _cachedConfig = config;
        _lastFetchTime = DateTime.now();

        AppLogger.log('✅ AppRemoteConfigService: Config fetched and cached');
        return config;
      } else {
        AppLogger.log(
            '❌ AppRemoteConfigService: Failed to fetch config: ${response.statusCode}');

        // Return cached config if available
        if (_cachedConfig != null) {
          AppLogger.log(
              '⚠️ AppRemoteConfigService: Using cached config as fallback');
          return _cachedConfig;
        }

        return null;
      }
    } catch (e) {
      AppLogger.log('❌ AppRemoteConfigService: Error fetching config: $e');

      // Return cached config if available
      if (_cachedConfig != null) {
        AppLogger.log(
            '⚠️ AppRemoteConfigService: Using cached config due to error');
        return _cachedConfig;
      }

      return null;
    }
  }

  /// Check app version and return update status
  Future<VersionCheckResult> checkAppVersion({bool refresh = false}) async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final appVersion = packageInfo.version;

      // Ensure config is loaded
      if (refresh || _cachedConfig == null) {
        await fetchConfig(forceRefresh: refresh);
      }

      if (_cachedConfig == null) {
        return VersionCheckResult(
          isSupported: true, // Assume supported if no config
          isLatest: true,
          updateRequired: false,
          updateRecommended: false,
        );
      }

      final config = _cachedConfig!;
      final isSupported = config.isAppVersionSupported(appVersion);
      final isLatest = config.isAppVersionLatest(appVersion);
      final updateRequired = !isSupported;
      final updateRecommended = !isLatest && isSupported;

      return VersionCheckResult(
        isSupported: isSupported,
        isLatest: isLatest,
        updateRequired: updateRequired,
        updateRecommended: updateRecommended,
        currentVersion: appVersion,
        minVersion: config.versionControl.minSupportedAppVersion,
        latestVersion: config.versionControl.latestAppVersion,
        updateMessage: updateRequired
            ? config.versionControl.forceUpdateMessage
            : (updateRecommended
                ? config.versionControl.softUpdateMessage
                : null),
        updateUrl: config.versionControl.getUpdateUrl(_detectPlatform()),
      );
    } catch (e) {
      AppLogger.log('❌ AppRemoteConfigService: Error checking version: $e');
      return VersionCheckResult(
        isSupported: true,
        isLatest: true,
        updateRequired: false,
        updateRecommended: false,
      );
    }
  }

  /// Check kill switch status
  Future<KillSwitchStatus> checkKillSwitch() async {
    try {
      final baseUrl = await AppConfig.getBaseUrlWithFallback();
      final platform = _detectPlatform();
      final url = Uri.parse('$baseUrl/api/app-config/kill-switch')
          .replace(queryParameters: {
        'platform': platform,
      });

      final response = await httpClientService.get(
        url,
        headers: {
          'Content-Type': 'application/json',
          _apiVersionHeader: _defaultApiVersion,
        },
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        return KillSwitchStatus.fromJson(json);
      }

      // If API fails, assume kill switch is off
      return KillSwitchStatus(
        enabled: false,
        maintenanceMode: false,
      );
    } catch (e) {
      AppLogger.log('❌ AppRemoteConfigService: Error checking kill switch: $e');
      // If API fails, assume kill switch is off
      return KillSwitchStatus(
        enabled: false,
        maintenanceMode: false,
      );
    }
  }

  /// Get UI text with fallback
  String getText(String key, {String? fallback}) {
    if (_cachedConfig != null) {
      return _cachedConfig!.getText(key, fallback: fallback);
    }
    return fallback ?? key;
  }

  /// Detect platform
  String _detectPlatform() {
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    return 'web';
  }

  /// Load cached config from SharedPreferences
  Future<void> _loadCachedConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final configJson = prefs.getString(_cacheKey);

      if (configJson != null) {
        final json = jsonDecode(configJson) as Map<String, dynamic>;
        _cachedConfig = AppRemoteConfig.fromJson(json);

        final timestampStr = prefs.getString(_cacheTimestampKey);
        if (timestampStr != null) {
          _lastFetchTime = DateTime.parse(timestampStr);
        }

        AppLogger.log('✅ AppRemoteConfigService: Loaded cached config');
      }
    } catch (e) {
      AppLogger.log(
          '❌ AppRemoteConfigService: Error loading cached config: $e');
    }
  }

  /// Save config to SharedPreferences
  Future<void> _saveConfig(AppRemoteConfig config) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final configJson = jsonEncode(config.toJson());

      await prefs.setString(_cacheKey, configJson);
      await prefs.setString(
          _cacheTimestampKey, DateTime.now().toIso8601String());

      AppLogger.log('✅ AppRemoteConfigService: Config saved to cache');
    } catch (e) {
      AppLogger.log('❌ AppRemoteConfigService: Error saving config: $e');
    }
  }

  /// Clear cached config
  Future<void> clearCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_cacheKey);
      await prefs.remove(_cacheTimestampKey);
      _cachedConfig = null;
      _lastFetchTime = null;
      AppLogger.log('✅ AppRemoteConfigService: Cache cleared');
    } catch (e) {
      AppLogger.log('❌ AppRemoteConfigService: Error clearing cache: $e');
    }
  }
}

/// Version Check Result
class VersionCheckResult {
  final bool isSupported;
  final bool isLatest;
  final bool updateRequired;
  final bool updateRecommended;
  final String? currentVersion;
  final String? minVersion;
  final String? latestVersion;
  final String? updateMessage;
  final String? updateUrl;

  VersionCheckResult({
    required this.isSupported,
    required this.isLatest,
    required this.updateRequired,
    required this.updateRecommended,
    this.currentVersion,
    this.minVersion,
    this.latestVersion,
    this.updateMessage,
    this.updateUrl,
  });
}

/// Kill Switch Status
class KillSwitchStatus {
  final bool enabled;
  final bool maintenanceMode;
  final String? message;
  final String? maintenanceMessage;

  KillSwitchStatus({
    required this.enabled,
    required this.maintenanceMode,
    this.message,
    this.maintenanceMessage,
  });

  factory KillSwitchStatus.fromJson(Map<String, dynamic> json) {
    return KillSwitchStatus(
      enabled: json['killSwitchEnabled'] as bool? ?? false,
      maintenanceMode: json['maintenanceMode'] as bool? ?? false,
      message: json['message'] as String?,
      maintenanceMessage: json['maintenanceMessage'] as String?,
    );
  }
}

/// Extension to add toJson for AppRemoteConfig (for caching)
extension AppRemoteConfigJson on AppRemoteConfig {
  Map<String, dynamic> toJson() {
    return {
      'platform': platform,
      'environment': environment,
      'apiVersion': apiVersion,
      'cached': cached,
      'timestamp': timestamp.toIso8601String(),
      'config': {
        'versionControl': {
          'minSupportedAppVersion': versionControl.minSupportedAppVersion,
          'latestAppVersion': versionControl.latestAppVersion,
          'forceUpdateMessage': versionControl.forceUpdateMessage,
          'softUpdateMessage': versionControl.softUpdateMessage,
          'updateUrl': versionControl.updateUrl,
        },
        'featureFlags': {
          'yugTabCarouselAds': featureFlags.yugTabCarouselAds,
          'imageUploadForCreators': featureFlags.imageUploadForCreators,
          'adCreationV2': featureFlags.adCreationV2,
          'videoFeedAds': featureFlags.videoFeedAds,
          'creatorPayouts': featureFlags.creatorPayouts,
          'referralSystem': featureFlags.referralSystem,
          'pushNotifications': featureFlags.pushNotifications,
            'analytics': featureFlags.analytics,
            'professionTargeting': featureFlags.professionTargeting,
        },
        'businessRules': {
          'adBudget': {
            'minDailyBudget': businessRules.adBudget.minDailyBudget,
            'maxDailyBudget': businessRules.adBudget.maxDailyBudget,
            'minTotalBudget': businessRules.adBudget.minTotalBudget,
          },
          'cpmRates': {
            'banner': businessRules.cpmRates.banner,
            'carousel': businessRules.cpmRates.carousel,
            'videoFeedAd': businessRules.cpmRates.videoFeedAd,
          },
          'revenueShare': {
            'creatorShare': businessRules.revenueShare.creatorShare,
            'platformShare': businessRules.revenueShare.platformShare,
          },
          'uploadLimits': {
            'maxVideoSize': businessRules.uploadLimits.maxVideoSize,
            'maxImageSize': businessRules.uploadLimits.maxImageSize,
            'maxVideoDuration': businessRules.uploadLimits.maxVideoDuration,
            'allowedVideoFormats':
                businessRules.uploadLimits.allowedVideoFormats,
            'allowedImageFormats':
                businessRules.uploadLimits.allowedImageFormats,
          },
          'payoutRules': {
            'minPayoutAmount': businessRules.payoutRules.minPayoutAmount,
            'payoutProcessingDays':
                businessRules.payoutRules.payoutProcessingDays,
          },
          'adServing': {
            'insertionFrequency': businessRules.adServing.insertionFrequency,
            'maxAdsPerSession': businessRules.adServing.maxAdsPerSession,
            'impressionFrequencyCap':
                businessRules.adServing.impressionFrequencyCap,
          },
        },
        'recommendationParams': {
          'weights': {
            'views': recommendationParams.weights.views,
            'likes': recommendationParams.weights.likes,
            'recency': recommendationParams.weights.recency,
            'userEngagement': recommendationParams.weights.userEngagement,
            'categoryMatch': recommendationParams.weights.categoryMatch,
          },
          'timeDecayFactor': recommendationParams.timeDecayFactor,
          'trendingThreshold': recommendationParams.trendingThreshold,
        },
        'uiTexts': uiTexts,
        'killSwitch': {
          'enabled': killSwitch.enabled,
          'message': killSwitch.message,
          'maintenanceMode': killSwitch.maintenanceMode,
          'maintenanceMessage': killSwitch.maintenanceMessage,
        },
        'cacheSettings': {
          'configCacheTTL': cacheSettings.configCacheTTL,
          'videoFeedCacheTTL': cacheSettings.videoFeedCacheTTL,
        },
      },
    };
  }
}

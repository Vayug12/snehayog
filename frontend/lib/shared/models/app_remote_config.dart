/// AppRemoteConfig Model
///
/// Represents the backend-driven configuration fetched from /api/app-config
/// This model contains all configurable aspects of the app:
/// - Version control (forced updates)
/// - Feature flags
/// - Business rules
/// - UI texts
/// - Kill switch
class AppRemoteConfig {
  final String platform;
  final String environment;
  final String apiVersion;
  final bool cached;
  final bool? fallback;
  final DateTime timestamp;

  // Version control
  final VersionControl versionControl;

  // Feature flags
  final FeatureFlags featureFlags;

  // Business rules
  final BusinessRules businessRules;

  // Recommendation parameters
  final RecommendationParams recommendationParams;

  // UI texts (i18n keys)
  final Map<String, String> uiTexts;

  // Kill switch
  final KillSwitch killSwitch;

  // Cache settings
  final CacheSettings cacheSettings;

  AppRemoteConfig({
    required this.platform,
    required this.environment,
    required this.apiVersion,
    required this.cached,
    this.fallback,
    required this.timestamp,
    required this.versionControl,
    required this.featureFlags,
    required this.businessRules,
    required this.recommendationParams,
    required this.uiTexts,
    required this.killSwitch,
    required this.cacheSettings,
  });

  factory AppRemoteConfig.fromJson(Map<String, dynamic> json) {
    final config = json['config'] as Map<String, dynamic>? ?? json;

    return AppRemoteConfig(
      platform: json['platform'] as String? ?? 'android',
      environment: json['environment'] as String? ?? 'production',
      apiVersion: json['apiVersion'] as String? ?? '2024-10-01',
      cached: json['cached'] as bool? ?? false,
      fallback: json['fallback'] as bool?,
      timestamp: json['timestamp'] != null
          ? DateTime.parse(json['timestamp'] as String)
          : DateTime.now(),
      versionControl: VersionControl.fromJson(
        config['versionControl'] as Map<String, dynamic>,
      ),
      featureFlags: FeatureFlags.fromJson(
        config['featureFlags'] as Map<String, dynamic>,
      ),
      businessRules: BusinessRules.fromJson(
        config['businessRules'] as Map<String, dynamic>,
      ),
      recommendationParams: RecommendationParams.fromJson(
        config['recommendationParams'] as Map<String, dynamic>,
      ),
      uiTexts: _parseUiTexts(config['uiTexts']),
      killSwitch: KillSwitch.fromJson(
        config['killSwitch'] as Map<String, dynamic>,
      ),
      cacheSettings: CacheSettings.fromJson(
        config['cacheSettings'] as Map<String, dynamic>? ?? {},
      ),
    );
  }

  static Map<String, String> _parseUiTexts(dynamic texts) {
    if (texts == null) return {};

    if (texts is Map) {
      return Map<String, String>.from(
        texts.map((key, value) => MapEntry(key.toString(), value.toString())),
      );
    }

    return {};
  }

  /// Get UI text with fallback
  String getText(String key, {String? fallback}) {
    return uiTexts[key] ?? fallback ?? key;
  }

  /// Check if app version is supported
  bool isAppVersionSupported(String appVersion) {
    return _compareVersions(
            appVersion, versionControl.minSupportedAppVersion) >=
        0;
  }

  /// Check if app version is latest
  bool isAppVersionLatest(String appVersion) {
    return _compareVersions(appVersion, versionControl.latestAppVersion) >= 0;
  }

  /// Compare semantic versions (e.g., "1.2.3")
  int _compareVersions(String version1, String version2) {
    final v1Parts =
        version1.split('.').map((v) => int.tryParse(v) ?? 0).toList();
    final v2Parts =
        version2.split('.').map((v) => int.tryParse(v) ?? 0).toList();

    for (int i = 0; i < v1Parts.length || i < v2Parts.length; i++) {
      final v1Part = i < v1Parts.length ? v1Parts[i] : 0;
      final v2Part = i < v2Parts.length ? v2Parts[i] : 0;

      if (v1Part > v2Part) return 1;
      if (v1Part < v2Part) return -1;
    }

    return 0;
  }
}

/// Version Control Configuration
class VersionControl {
  final String minSupportedAppVersion;
  final String latestAppVersion;
  final String forceUpdateMessage;
  final String softUpdateMessage;
  final Map<String, String> updateUrl;

  VersionControl({
    required this.minSupportedAppVersion,
    required this.latestAppVersion,
    required this.forceUpdateMessage,
    required this.softUpdateMessage,
    required this.updateUrl,
  });

  factory VersionControl.fromJson(Map<String, dynamic> json) {
    final updateUrlMap = json['updateUrl'] as Map<String, dynamic>? ?? {};
    final updateUrl = Map<String, String>.from(
      updateUrlMap.map((key, value) {
        if (value is Map) {
          // Handle nested structure (android/ios keys)
          return MapEntry(key.toString(), value.toString());
        }
        return MapEntry(key.toString(), value.toString());
      }),
    );

    // Extract android/ios URLs if nested
    if (updateUrlMap['android'] != null) {
      updateUrl['android'] = updateUrlMap['android'].toString();
    }
    if (updateUrlMap['ios'] != null) {
      updateUrl['ios'] = updateUrlMap['ios'].toString();
    }

    return VersionControl(
      minSupportedAppVersion:
          json['minSupportedAppVersion'] as String? ?? '1.0.0',
      latestAppVersion: json['latestAppVersion'] as String? ?? '1.0.0',
      forceUpdateMessage: json['forceUpdateMessage'] as String? ??
          'A new version of the app is available. Please update to continue.',
      softUpdateMessage: json['softUpdateMessage'] as String? ??
          'A new version is available with exciting features!',
      updateUrl: updateUrl,
    );
  }

  String getUpdateUrl(String platform) {
    return updateUrl[platform] ?? updateUrl['android'] ?? '';
  }
}

/// Feature Flags
class FeatureFlags {
  final bool yugTabCarouselAds;
  final bool imageUploadForCreators;
  final bool adCreationV2;
  final bool videoFeedAds;
  final bool creatorPayouts;
  final bool referralSystem;
  final bool pushNotifications;
  final bool analytics;
  final bool professionTargeting;

  FeatureFlags({
    required this.yugTabCarouselAds,
    required this.imageUploadForCreators,
    required this.adCreationV2,
    required this.videoFeedAds,
    required this.creatorPayouts,
    required this.referralSystem,
    required this.pushNotifications,
    required this.analytics,
    required this.professionTargeting,
  });

  factory FeatureFlags.fromJson(Map<String, dynamic> json) {
    return FeatureFlags(
      yugTabCarouselAds: json['yugTabCarouselAds'] as bool? ?? true,
      imageUploadForCreators: json['imageUploadForCreators'] as bool? ?? true,
      adCreationV2: json['adCreationV2'] as bool? ?? true,
      videoFeedAds: json['videoFeedAds'] as bool? ?? true,
      creatorPayouts: json['creatorPayouts'] as bool? ?? true,
      referralSystem: json['referralSystem'] as bool? ?? true,
      pushNotifications: json['pushNotifications'] as bool? ?? true,
      analytics: json['analytics'] as bool? ?? true,
      professionTargeting: json['professionTargeting'] as bool? ?? true,
    );
  }
}

/// Business Rules
class BusinessRules {
  final AdBudget adBudget;
  final CpmRates cpmRates;
  final RevenueShare revenueShare;
  final UploadLimits uploadLimits;
  final PayoutRules payoutRules;
  final AdServing adServing;

  BusinessRules({
    required this.adBudget,
    required this.cpmRates,
    required this.revenueShare,
    required this.uploadLimits,
    required this.payoutRules,
    required this.adServing,
  });

  factory BusinessRules.fromJson(Map<String, dynamic> json) {
    return BusinessRules(
      adBudget: AdBudget.fromJson(
        json['adBudget'] as Map<String, dynamic>? ?? {},
      ),
      cpmRates: CpmRates.fromJson(
        json['cpmRates'] as Map<String, dynamic>? ?? {},
      ),
      revenueShare: RevenueShare.fromJson(
        json['revenueShare'] as Map<String, dynamic>? ?? {},
      ),
      uploadLimits: UploadLimits.fromJson(
        json['uploadLimits'] as Map<String, dynamic>? ?? {},
      ),
      payoutRules: PayoutRules.fromJson(
        json['payoutRules'] as Map<String, dynamic>? ?? {},
      ),
      adServing: AdServing.fromJson(
        json['adServing'] as Map<String, dynamic>? ?? {},
      ),
    );
  }
}

class AdBudget {
  final double minDailyBudget;
  final double maxDailyBudget;
  final double minTotalBudget;

  AdBudget({
    required this.minDailyBudget,
    required this.maxDailyBudget,
    required this.minTotalBudget,
  });

  factory AdBudget.fromJson(Map<String, dynamic> json) {
    return AdBudget(
      minDailyBudget: (json['minDailyBudget'] as num?)?.toDouble() ?? 100.0,
      maxDailyBudget: (json['maxDailyBudget'] as num?)?.toDouble() ?? 10000.0,
      minTotalBudget: (json['minTotalBudget'] as num?)?.toDouble() ?? 1000.0,
    );
  }
}

class CpmRates {
  final double banner;
  final double carousel;
  final double videoFeedAd;

  CpmRates({
    required this.banner,
    required this.carousel,
    required this.videoFeedAd,
  });

  factory CpmRates.fromJson(Map<String, dynamic> json) {
    return CpmRates(
      banner: (json['banner'] as num?)?.toDouble() ?? 10.0,
      carousel: (json['carousel'] as num?)?.toDouble() ?? 30.0,
      videoFeedAd: (json['videoFeedAd'] as num?)?.toDouble() ?? 30.0,
    );
  }
}

class RevenueShare {
  final double creatorShare;
  final double platformShare;

  RevenueShare({
    required this.creatorShare,
    required this.platformShare,
  });

  factory RevenueShare.fromJson(Map<String, dynamic> json) {
    return RevenueShare(
      creatorShare: (json['creatorShare'] as num?)?.toDouble() ?? 0.80,
      platformShare: (json['platformShare'] as num?)?.toDouble() ?? 0.20,
    );
  }
}

class UploadLimits {
  final int maxVideoSize;
  final int maxImageSize;
  final int maxVideoDuration;
  final List<String> allowedVideoFormats;
  final List<String> allowedImageFormats;

  UploadLimits({
    required this.maxVideoSize,
    required this.maxImageSize,
    required this.maxVideoDuration,
    required this.allowedVideoFormats,
    required this.allowedImageFormats,
  });

  factory UploadLimits.fromJson(Map<String, dynamic> json) {
    return UploadLimits(
      maxVideoSize: json['maxVideoSize'] as int? ?? 100 * 1024 * 1024,
      maxImageSize: json['maxImageSize'] as int? ?? 5 * 1024 * 1024,
      maxVideoDuration: json['maxVideoDuration'] as int? ?? 600,
      allowedVideoFormats: (json['allowedVideoFormats'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          ['mp4', 'avi', 'mov', 'wmv', 'flv', 'webm'],
      allowedImageFormats: (json['allowedImageFormats'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          ['jpg', 'jpeg', 'png', 'gif', 'webp'],
    );
  }
}

class PayoutRules {
  final double minPayoutAmount;
  final int payoutProcessingDays;

  PayoutRules({
    required this.minPayoutAmount,
    required this.payoutProcessingDays,
  });

  factory PayoutRules.fromJson(Map<String, dynamic> json) {
    return PayoutRules(
      minPayoutAmount: (json['minPayoutAmount'] as num?)?.toDouble() ?? 500.0,
      payoutProcessingDays: json['payoutProcessingDays'] as int? ?? 7,
    );
  }
}

class AdServing {
  final int insertionFrequency;
  final int maxAdsPerSession;
  final int impressionFrequencyCap;

  AdServing({
    required this.insertionFrequency,
    required this.maxAdsPerSession,
    required this.impressionFrequencyCap,
  });

  factory AdServing.fromJson(Map<String, dynamic> json) {
    return AdServing(
      insertionFrequency: json['insertionFrequency'] as int? ?? 2,
      maxAdsPerSession: json['maxAdsPerSession'] as int? ?? 10,
      impressionFrequencyCap: json['impressionFrequencyCap'] as int? ?? 3,
    );
  }
}

/// Recommendation Parameters
class RecommendationParams {
  final RecommendationWeights weights;
  final double timeDecayFactor;
  final int trendingThreshold;

  RecommendationParams({
    required this.weights,
    required this.timeDecayFactor,
    required this.trendingThreshold,
  });

  factory RecommendationParams.fromJson(Map<String, dynamic> json) {
    return RecommendationParams(
      weights: RecommendationWeights.fromJson(
        json['weights'] as Map<String, dynamic>? ?? {},
      ),
      timeDecayFactor: (json['timeDecayFactor'] as num?)?.toDouble() ?? 0.95,
      trendingThreshold: json['trendingThreshold'] as int? ?? 1000,
    );
  }
}

class RecommendationWeights {
  final double views;
  final double likes;
  final double recency;
  final double userEngagement;
  final double categoryMatch;

  RecommendationWeights({
    required this.views,
    required this.likes,
    required this.recency,
    required this.userEngagement,
    required this.categoryMatch,
  });

  factory RecommendationWeights.fromJson(Map<String, dynamic> json) {
    return RecommendationWeights(
      views: (json['views'] as num?)?.toDouble() ?? 0.3,
      likes: (json['likes'] as num?)?.toDouble() ?? 0.25,
      recency: (json['recency'] as num?)?.toDouble() ?? 0.2,
      userEngagement: (json['userEngagement'] as num?)?.toDouble() ?? 0.15,
      categoryMatch: (json['categoryMatch'] as num?)?.toDouble() ?? 0.1,
    );
  }
}

/// Kill Switch
class KillSwitch {
  final bool enabled;
  final String message;
  final bool maintenanceMode;
  final String maintenanceMessage;

  KillSwitch({
    required this.enabled,
    required this.message,
    required this.maintenanceMode,
    required this.maintenanceMessage,
  });

  factory KillSwitch.fromJson(Map<String, dynamic> json) {
    return KillSwitch(
      enabled: json['enabled'] as bool? ?? false,
      message: json['message'] as String? ??
          'The app is temporarily unavailable. Please try again later.',
      maintenanceMode: json['maintenanceMode'] as bool? ?? false,
      maintenanceMessage: json['maintenanceMessage'] as String? ??
          'We are performing maintenance. Some features may be unavailable.',
    );
  }
}

/// Cache Settings
class CacheSettings {
  final int configCacheTTL;
  final int videoFeedCacheTTL;

  CacheSettings({
    required this.configCacheTTL,
    required this.videoFeedCacheTTL,
  });

  factory CacheSettings.fromJson(Map<String, dynamic> json) {
    return CacheSettings(
      configCacheTTL: json['configCacheTTL'] as int? ?? 300,
      videoFeedCacheTTL: json['videoFeedCacheTTL'] as int? ?? 180,
    );
  }
}

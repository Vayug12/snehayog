import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:vayug/shared/services/http_client_service.dart';

/// Optimized app configuration for better performance and smaller size
class AppConfig {
  // **NEW: API Version (Date-Based)**
  static const String kApiVersion = '2026-04-02';

  // Set to true to force local development server
  static const bool isDevelopment = false;
  
  // Set to true to use production Cloudflare worker even in development
  static const bool useProductionWorker = true;

  // Use the explicit flag instead of kReleaseMode
  static bool get _isDevelopment => isDevelopment;

  // Cache for the discovered base URL
  static String? _cachedBaseUrl;

  // Find your IP: Windows: ipconfig | Linux/Mac: ifconfig or ip address
  // Make sure your phone/emulator is on the same Wi‑Fi network
  static const String _currentMobileIp = 'http://192.168.0.190:5001';
  static const String _currentMobileIp2 = 'http://172.20.10.2:5001';
  static const String _localIpBaseUrl = _currentMobileIp;

  // Local development server (localhost) - for web
  static const String _localWebBaseUrl = 'http://localhost:5001';

  // Primary production endpoints
  static const String _customDomainUrl = 'https://api.snehayog.site';
  static const String _flyUrl = 'https://vayug.fly.dev';

  // **NEW: Cloudflare Workers configuration**
  static const String _workerProductionUrl =
      'https://vayug-edge.factshorts1.workers.dev';
  static const String _workerDevelopmentUrl = 'http://localhost:8787';

  static String get workerUrl {
    if (!_isDevelopment || useProductionWorker) return _workerProductionUrl;

    // For web development, localhost is the standard
    if (kIsWeb) return _workerDevelopmentUrl;

    try {
      final ipUri = Uri.parse(_localIpBaseUrl);
      return 'http://${ipUri.host}:8787';
    } catch (e) {
      // Fallback if parsing fails
      return _workerDevelopmentUrl;
    }
  }

  // Backend API configuration - Strict Mode
  static String get baseUrl {
    if (_isDevelopment) {
      return kIsWeb ? _localWebBaseUrl : _localIpBaseUrl;
    } else {
      // Production mode: Prioritize Custom Domain
      return _cachedBaseUrl ?? _customDomainUrl; 
    }
  }
  

  // **Helper Methods for Production Priority & Fallback**
  
  /// Asynchronous check that prioritizes Custom Domain -> Fly.io
  static Future<String> getBaseUrlWithFallback() async {
    if (_isDevelopment) return baseUrl;
    
    // Check if Custom Domain is healthy
    final String? healthyCustom = await _checkServer(_customDomainUrl);
    if (healthyCustom != null) {
      _cachedBaseUrl = _customDomainUrl;
      return _customDomainUrl;
    }
    
    // Otherwise fallback to Fly.io
    print('⚠️ AppConfig: Custom domain unreachable, falling back to Fly.io');
    _cachedBaseUrl = _flyUrl;
    return _flyUrl;
  }

  /// Simplified version of refresh check
  static Future<String> checkAndUpdateServerUrl() async {
    return await getBaseUrlWithFallback();
  }

  /// Reset cached URL - no-op in simplified version as there's no cache
  static void resetCachedUrl() {
    _cachedBaseUrl = null;
    print('🔄 AppConfig: Cached URL reset.');
  }

  /// **OPTIMIZED: Check server connectivity**
  static Future<String?> _checkServer(String url) async {
    try {
      final response = await httpClientService.get(
        Uri.parse('$url/api/health'),
        headers: {'Content-Type': 'application/json'},
        timeout: const Duration(seconds: 2),
      );

      if (response.statusCode == 200) {
        print('✅ AppConfig: Server accessible at $url');
        return url;
      }
    } catch (e) {
      print('❌ AppConfig: Server not accessible at $url: $e');
    }
    return null;
  }

  // **NEW: Fallback URLs - custom domain first for production**
  static const List<String> fallbackUrls = [
    _flyUrl,
    _customDomainUrl,
  ];

  // **NEW: Network timeout configurations**
  static const Duration authTimeout = Duration(seconds: 30);
  static const Duration apiTimeout = Duration(seconds: 20);
  static const Duration uploadTimeout = Duration(minutes: 30);

  static const int maxRetries = 3;
  static const Duration retryDelay = Duration(seconds: 2);

  // Ad configuration
  static const int minAdBudget = 1; // Minimum daily budget in dollars

  // **NEW: Fixed CPM for India market**
  // Must match AD_CONFIG.DEFAULT_CPM / BANNER_CPM on the server. The server
  // recomputes both CPM and impressions when an ad is created, so a mismatch
  // here does not change what is delivered — it just shows the advertiser an
  // impression estimate they will not get.
  static const double fixedCpm = 30.0;
  static const double bannerCpm = 20.0;

  static const double creatorRevenueShare = 0.80;
  static const double platformRevenueShare = 0.20;

  /// RevenueCat public SDK key, supplied at build time:
  ///
  ///   flutter build apk --dart-define=REVENUECAT_ANDROID_KEY=goog_xxx
  ///
  /// **Never hardcode it here.** The Razorpay keys that had to be revoked were
  /// leaked exactly this way — committed to a shipped client, so they live in
  /// git history and in every build already on a device. This one is a public
  /// SDK key rather than a secret, but the habit is what matters: the webhook
  /// secret and the REST key stay server-side and are never in this file.
  static const String revenueCatAndroidKey =
      String.fromEnvironment('REVENUECAT_ANDROID_KEY');

  /// In-app credit purchases are only offered when a key was built in.
  /// Without one the wallet still works — it is just topped up by an admin
  /// grant rather than by the store.
  static bool get adCreditPurchasesEnabled => revenueCatAndroidKey.isNotEmpty;

  /// Ads are funded from the prepaid ad-credit wallet via
  /// `POST /api/ads/create-with-credits`. Enabled now that the wallet ledger
  /// and that endpoint are live; in-app credit purchases land separately, so
  /// until then a balance is topped up by an admin grant.
  static const bool adCreationEnabled = true;

  // **NEW: Ad Serving Rules**
  static const int adInsertionFrequency =
      2; // Every alternate screen (2nd screen)
  static const int maxAdsPerSession = 10; // Maximum ads shown per user session

  // **NEW: Enhanced Ad Serving Logic**
  static const Map<String, Map<String, dynamic>> adTypeConfig = {
    'banner': {
      'cpm': 10.0, // ₹10 per 1000 impressions
      'maxFileSize': 5 * 1024 * 1024, // 5MB
      'supportedFormats': ['jpg', 'jpeg', 'png', 'gif', 'webp'],
      'displayFrequency': 2, // Every 2nd screen
      'priority': 1, // Lower priority than video ads
      'estimatedImpressionsPerDay': 50000, // Based on user base
    },
    'carousel': {
      'cpm': 30.0, // ₹30 per 1000 impressions
      'maxFileSize': 10 * 1024 * 1024, // 10MB
      'supportedFormats': ['jpg', 'jpeg', 'png', 'gif', 'webp'],
      'displayFrequency': 3, // Every 3rd screen
      'priority': 2, // Medium priority
      'estimatedImpressionsPerDay': 25000,
    },
  };

  // **NEW: Campaign Duration & Budget Logic**
  static const Map<String, int> campaignDurationLimits = {
    'min_days': 1,
    'max_days': 365,
    'recommended_min_days': 7,
    'recommended_max_days': 90,
  };

  // **NEW: Budget & Impression Management**
  static const Map<String, dynamic> budgetConfig = {
    'min_daily_budget': 100.0, // ₹100 minimum
    'max_daily_budget': 10000.0,
    'budget_multiplier': 1.0, // For campaign duration
    'impression_buffer': 0.1, // 10% buffer for over-delivery
  };

  // **NEW: Ad Serving Algorithm Parameters**
  static const Map<String, dynamic> servingConfig = {
    'impression_frequency_cap': 3, // Max impressions per user per day
    'session_frequency_cap': 5, // Max impressions per user session
    'quality_score_threshold': 0.7, // Minimum quality score for ad display
    'relevance_threshold': 0.6, // Minimum relevance score
    'competition_window': 300, // 5 minutes between competing ads
  };

  // **NEW: Calculate campaign metrics**
  static Map<String, dynamic> calculateCampaignMetrics({
    required double dailyBudget,
    required int campaignDays,
    required String adType,
  }) {
    final config = adTypeConfig[adType] ?? adTypeConfig['banner']!;
    final cpm = config['cpm'] as double;
    final estimatedDailyImpressions =
        config['estimatedImpressionsPerDay'] as int;

    // Calculate total budget
    final totalBudget = dailyBudget * campaignDays;

    // Calculate expected impressions
    final expectedImpressions = (totalBudget / cpm) * 1000;

    // Calculate daily impressions
    final dailyImpressions = (expectedImpressions / campaignDays).round();

    // Calculate actual campaign duration based on budget
    final actualDuration =
        (expectedImpressions / estimatedDailyImpressions).ceil();

    return {
      'totalBudget': totalBudget,
      'expectedImpressions': expectedImpressions,
      'dailyImpressions': dailyImpressions,
      'estimatedDuration': actualDuration,
      'cpm': cpm,
      'dailyBudget': dailyBudget,
      'campaignDays': campaignDays,
    };
  }

  // **NEW: Validate campaign parameters**
  static Map<String, dynamic> validateCampaign({
    required double dailyBudget,
    required int campaignDays,
    required String adType,
  }) {
    final errors = <String>[];
    final warnings = <String>[];

    // Budget validation
    if (dailyBudget < budgetConfig['min_daily_budget']) {
      errors.add(
          'Daily budget must be at least ₹${budgetConfig['min_daily_budget']}');
    }
    if (dailyBudget > budgetConfig['max_daily_budget']) {
      errors.add(
          'Daily budget cannot exceed ₹${budgetConfig['max_daily_budget']}');
    }

    // Duration validation
    if (campaignDays < campaignDurationLimits['min_days']!) {
      errors.add(
          'Campaign must run for at least ${campaignDurationLimits['min_days']} day');
    }
    if (campaignDays > campaignDurationLimits['max_days']!) {
      errors.add(
          'Campaign cannot exceed ${campaignDurationLimits['max_days']} days');
    }

    // Recommendations
    if (campaignDays < campaignDurationLimits['recommended_min_days']!) {
      warnings.add(
          'Consider running for at least ${campaignDurationLimits['recommended_min_days']} days for better results');
    }
    if (campaignDays > campaignDurationLimits['recommended_max_days']!) {
      warnings.add(
          'Long campaigns may have diminishing returns. Consider shorter, focused campaigns');
    }

    // Calculate metrics
    final metrics = calculateCampaignMetrics(
      dailyBudget: dailyBudget,
      campaignDays: campaignDays,
      adType: adType,
    );

    return {
      'isValid': errors.isEmpty,
      'errors': errors,
      'warnings': warnings,
      'metrics': metrics,
    };
  }

  // Media upload configuration
  static const int maxImageSize = 5 * 1024 * 1024;
  static const int maxVideoSize = 700 * 1024 * 1024; // 700MB

  // HLS streaming configuration
  static const Map<String, dynamic> hlsConfig = {
    'segment_duration': 2, // 2 seconds per segment
    'keyframe_interval': 60, // 2 seconds at 30fps
    'abr_enabled': true, // Adaptive Bitrate enabled
    'buffer_size': 10, // 10 seconds buffer
    'hls_version': '3',
    'compatibility': 'modern'
  };

  // Ad types supported
  static const List<String> supportedAdTypes = [
    'banner',
    'interstitial',
    'rewarded',
    'native'
  ];

  // Ad statuses
  static const List<String> adStatuses = [
    'draft',
    'active',
    'paused',
    'completed'
  ];

  // Target audience options
  static const List<String> targetAudienceOptions = [
    'all',
    'youth',
    'professionals',
    'students',
    'parents',
    'seniors'
  ];

  // **NEW: Helper methods for revenue calculations**
  static double calculateCreatorRevenue(double adSpend) {
    return adSpend * creatorRevenueShare;
  }

  static double calculatePlatformRevenue(double adSpend) {
    return adSpend * platformRevenueShare;
  }

  static double calculateCpmFromBudget(double budget, int impressions) {
    if (impressions <= 0) return 0.0;
    return (budget / impressions) * 1000;
  }

  static int calculateImpressionsFromBudget(double budget) {
    return (budget / fixedCpm * 1000).round();
  }

  static int calculateImpressionsFromBudgetWithCpm(double budget, double cpm) {
    return (budget / cpm * 1000).round();
  }

  // **NEW: AdMob Configuration**
  // Delegates to AdMobConfig for modular approach
  static String? get adMobBannerAdUnitId {
    // Import and use AdMobConfig
    // This getter provides backward compatibility
    try {
      // Dynamic import to avoid circular dependencies
      // AdMobConfig will be imported where needed
      return null; // Will be resolved by AdMobConfig
    } catch (e) {
      return null;
    }
  }
}

/// Optimized network helper for better performance
class NetworkHelper {
  /// Get the appropriate server URL based on the environment
  static String getServerUrl() => AppConfig.baseUrl;

  /// Get the appropriate base URL for the current environment
  static String getBaseUrl() => AppConfig.baseUrl;

  /// Get base URL with automatic Railway first, local fallback (async version)
  static Future<String> getBaseUrlAsync() => AppConfig.getBaseUrlWithFallback();

  /// Get base URL with fallback: Custom Domain → Railway → Local Server
  static Future<String> getBaseUrlWithFallback() =>
      AppConfig.getBaseUrlWithFallback();

  /// API endpoints
  static String get apiBaseUrl {
    // **FIX: Robustly handle redundant /api prefixes using regex**
    // This strips all occurrences of /api and appends it once
    final base = AppConfig.baseUrl.replaceAll(RegExp(r'(/+api)+$'), '');
    return '$base/api';
  }

  static String get healthEndpoint => '$apiBaseUrl/health';
  static String get videosEndpoint => '$apiBaseUrl/videos';
  static String get authEndpoint => '$apiBaseUrl/auth';
  static String get usersEndpoint => '$apiBaseUrl/users';
  static String get adsEndpoint => '$apiBaseUrl/ads';

  /// Cloudflare Workers endpoints
  static String get workerUrl => AppConfig.workerUrl;
  static String get uploadUrlEndpoint => '$workerUrl/upload-url';

  /// Network timeout configurations - Increased for better remote connectivity
  static const Duration defaultTimeout = Duration(seconds: 30);
  static const Duration uploadTimeout = Duration(minutes: 5);
  static const Duration shortTimeout = Duration(seconds: 30);

  /// Retry configurations - Enhanced for better reliability
  static const int defaultMaxRetries = 3;
  static const Duration defaultRetryDelay = Duration(seconds: 2);

  /// File size limits
  static const int maxVideoFileSize = 700 * 1024 * 1024; // 700MB
  static const int maxImageFileSize = 5 * 1024 * 1024; // 5MB

  /// Valid file extensions
  static const List<String> validVideoExtensions = [
    'mp4',
    'avi',
    'mov',
    'wmv',
    'flv',
    'webm'
  ];

  static const List<String> validImageExtensions = [
    'jpg',
    'jpeg',
    'png',
    'gif',
    'webp'
  ];

  /// Validation methods
  static bool isValidVideoExtension(String extension) {
    return validVideoExtensions.contains(extension.toLowerCase());
  }

  static bool isValidImageExtension(String extension) {
    return validImageExtensions.contains(extension.toLowerCase());
  }

  /// File size formatting
  static String formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  /// Check if file size is within limits
  static bool isFileSizeValid(int fileSize, {bool isVideo = true}) {
    final maxSize = isVideo ? maxVideoFileSize : maxImageFileSize;
    return fileSize <= maxSize;
  }

  /// **NEW: Check if custom domain is accessible**
  static Future<bool> isCustomDomainAccessible() async {
    try {
      print('🔍 NetworkHelper: Checking custom domain accessibility...');
      final response = await http.get(
        Uri.parse('${AppConfig._flyUrl}/api/health'), // Using Fly.io as it is more stable
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 30));

      final isAccessible = response.statusCode == 200;
      print('🔍 NetworkHelper: Custom domain accessible: $isAccessible');
      return isAccessible;
    } catch (e) {
      print('❌ NetworkHelper: Custom domain not accessible: $e');
      return false;
    }
  }

  /// **UPDATED: Get best available server URL - Custom Domain → Railway → Local Server**
  static Future<String> getBestServerUrl() async {
    // Now strictly based on AppConfig.baseUrl logic
    return AppConfig.baseUrl;
  }
}

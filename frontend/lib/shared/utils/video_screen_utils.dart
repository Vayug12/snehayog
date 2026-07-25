import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vayug/features/video/core/data/models/video_model.dart';
import 'package:vayug/shared/services/video_screen_logger.dart';
import 'package:vayug/shared/widgets/vayu_snackbar.dart';

/// Utility class for video screen helper methods
class VideoScreenUtils {
  /// Show refresh instructions for first-time users
  static Future<void> showRefreshInstructions(BuildContext context) async {
    try {
      if (context.mounted) {
        VayuSnackBar.showInfo(
          context,
          'Tip: Pull down to refresh or double-tap the Yog tab',
          duration: const Duration(seconds: 4),
          action: SnackBarAction(
            label: 'Got it',
            onPressed: () {
              VideoScreenLogger.logInfo(
                  'User acknowledged refresh instructions');
            },
          ),
        );
      }
      // }
    } catch (e) {
      VideoScreenLogger.logError('Error showing refresh instructions: $e');
    }
  }

  /// Handle double-tap refresh with haptic feedback
  static void handleDoubleTapRefresh({
    required bool isRefreshing,
    required VoidCallback refreshVideos,
    required BuildContext context,
  }) {
    if (isRefreshing) {
      // Already refreshing, show feedback
      _showAlreadyRefreshing(context);
      return;
    }

    VideoScreenLogger.logDoubleTapRefresh();

    // Add haptic feedback
    HapticFeedback.lightImpact();

    // Show visual feedback
    VayuSnackBar.showInfo(
      context,
      'Refreshing videos...',
      duration: const Duration(seconds: 1),
      action: SnackBarAction(
        label: 'Cancel',
        onPressed: () {
          // Could implement cancel refresh if needed
          VideoScreenLogger.logInfo('Refresh cancelled by user');
        },
      ),
    );

    // Start refresh
    refreshVideos();
  }

  /// Handle scroll-down refresh (Instagram Reels style)
  static void handleScrollDownRefresh({
    required bool isRefreshing,
    required BuildContext context,
  }) {
    if (isRefreshing) {
      // Already refreshing, show feedback
      _showAlreadyRefreshing(context);
      return;
    }

    VideoScreenLogger.logInfo('Scroll-down refresh triggered');

    // Add haptic feedback
    HapticFeedback.mediumImpact();

    // Show visual feedback
    VayuSnackBar.showInfo(
      context,
      'Pull down to refresh videos',
      duration: const Duration(seconds: 2),
    );
  }

  static void _showAlreadyRefreshing(BuildContext context) {
    VayuSnackBar.showInfo(
      context,
      'Already refreshing videos...',
      duration: const Duration(seconds: 1),
    );
  }

  /// Test HLS conversion for current video (DISABLED - VideoUrlService removed)
  static void testHlsConversion({
    required VideoModel video,
    required BuildContext context,
    required Function(Map<String, dynamic>) copyTestResultsToClipboard,
  }) {
    // HLS conversion testing disabled - VideoUrlService was removed
    VayuSnackBar.showWarning(
        context, 'HLS conversion testing is currently disabled');
  }

  /// Copy test results to clipboard for debugging
  static void copyTestResultsToClipboard(
      Map<String, dynamic> testResults, BuildContext context) {
    try {
      final resultsText = testResults.entries
          .map((entry) => '${entry.key}: ${entry.value}')
          .join('\n');

      Clipboard.setData(ClipboardData(text: resultsText));

      VayuSnackBar.showSuccess(context, 'Test results copied to clipboard',
          duration: const Duration(seconds: 2));
    } catch (e) {
      VideoScreenLogger.logError('Error copying to clipboard: $e');
    }
  }

  /// Show video error dialog with recovery options
  static void showVideoErrorDialog({
    required String errorMessage,
    required BuildContext context,
    required VoidCallback restartVideoSystem,
    required VoidCallback retryVideoInitialization,
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.error, color: Colors.red),
            SizedBox(width: 8),
            Text('Video Playback Error'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Failed to initialize video after 3 attempts:'),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                errorMessage,
                style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'This usually happens due to:\n'
              '• Memory pressure on device\n'
              '• Video decoder conflicts\n'
              '• App background/foreground transitions',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              restartVideoSystem();
            },
            child: const Text('Restart Video System'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              retryVideoInitialization();
            },
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  /// Show current video tracking info in debug dialog
  static void showCurrentVideoTrackingInfo({
    required Map<String, dynamic> trackingInfo,
    required Map<String, dynamic> cacheStats,
    required List<String> memoryCacheKeys,
    required String backendUrl,
    required String videoServiceUrl,
    required Map<String, bool> featureFlags,
    required Map<String, dynamic> controllerInfo,
    required Map<String, dynamic> cacheStatus,
    required BuildContext context,
    required VoidCallback onTestBackend,
    required VoidCallback onClearAllCaches,
    required VoidCallback onTestPreloading,
    required VoidCallback onTestControllers,
    required VoidCallback onTestCaching,
    required VoidCallback onShowVideoStateInfo,
    required VoidCallback onTestHlsConversion,
  }) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('🎬 Video Tracking Info'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                  'Current Video Index: ${trackingInfo['currentVisibleVideoIndex']}'),
              Text(
                  'Video Screen Active: ${trackingInfo['isVideoScreenActive']}'),
              Text('App In Foreground: ${trackingInfo['isAppInForeground']}'),
              Text('Should Play Videos: ${trackingInfo['shouldPlayVideos']}'),
              Text('Last Active Tab: ${trackingInfo['lastActiveTabIndex']}'),
              Text('Was On Video Tab: ${trackingInfo['wasOnVideoTab']}'),
              Text('Is Initialized: ${trackingInfo['isInitialized']}'),
              Text('Timestamp: ${trackingInfo['timestamp']}'),
              const SizedBox(height: 16),
              const Text('📊 Cache Info:',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              Text('Cache Size: ${cacheStats['cacheSize']}'),
              Text('Cached Pages: ${cacheStats['totalCachedPages']}'),
              Text('Cache Time: ${cacheStats['videosCacheTime']} minutes'),
              Text(
                  'Stale Time: ${cacheStats['staleWhileRevalidateTime']} minutes'),
              const SizedBox(height: 16),
              const Text('🌐 CDN Edge Cache:',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              Text(
                  'CDN Cache Time: ${cacheStats['cdnCacheTime'] ?? 'N/A'} minutes'),
              Text(
                  'Total ETags: ${cacheStats['cdnCacheStats']?['totalEtags'] ?? 'N/A'}'),
              Text(
                  'Total Last-Modified: ${cacheStats['cdnCacheStats']?['totalLastModified'] ?? 'N/A'}'),
              Text(
                  'CDN Optimized Requests: ${cacheStats['cdnCacheStats']?['cdnOptimizedRequests'] ?? 'N/A'}'),
              Text(
                  'Conditional Requests: ${cacheStats['cdnCacheStats']?['conditionalRequestsSupported'] == true ? 'Supported' : 'Not Supported'}'),
              const SizedBox(height: 16),
              const Text('💾 Disk Cache:',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              Text('Total Cached Videos: ${cacheStats['totalCachedVideos']}'),
              Text('Fully Downloaded: ${cacheStats['fullyDownloadedVideos']}'),
              Text('Preload Only: ${cacheStats['preloadOnlyVideos']}'),
              Text('Cache Size: ${cacheStats['diskCacheSizeMB']} MB'),
              const SizedBox(height: 16),
              const Text('🔍 Cache Status:',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              Text(
                  'Has Cached Videos (Page 1): ${cacheStatus['hasCachedVideos']}'),
              Text('Total Videos: ${cacheStatus['totalVideos']}'),
              Text('Current Page: ${cacheStatus['currentPage']}'),
              const SizedBox(height: 16),
              const Text('📋 Memory Cache Keys:',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              ...memoryCacheKeys.map((key) => Text('• $key')),
              const SizedBox(height: 16),
              const Text('🌐 Backend Info:',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              Text('Backend URL: $backendUrl'),
              Text('Video Service URL: $videoServiceUrl'),
              const SizedBox(height: 16),
              const Text('🚀 Preloading Status:',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              Text(
                  'Smart Video Caching: ${featureFlags['smart_video_caching'] == true ? 'Enabled' : 'Disabled'}'),
              Text(
                  'Background Preloading: ${featureFlags['background_video_preloading'] == true ? 'Enabled' : 'Disabled'}'),
              Text(
                  'Instant Playback: ${featureFlags['instant_video_playback'] == true ? 'Enabled' : 'Disabled'}'),
              const SizedBox(height: 16),
              const Text('🔒 Controller Management:',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              Text('Total Controllers: ${controllerInfo['totalControllers']}'),
              Text(
                  'Keep-Alive Controllers: ${controllerInfo['keepAliveControllers']}'),
              Text('Active Page: ${controllerInfo['activePage']}'),
              const SizedBox(height: 16),
              const Text('💾 Video Cache Status:',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              Text('Watched Videos: ${cacheStatus['watchedVideos']}'),
              Text('Recently Accessed: ${cacheStatus['recentlyAccessed']}'),
              Text('Cached Controllers: ${cacheStatus['cachedControllers']}'),
              Text(
                  'Total Cached: ${cacheStatus['totalCached']}/${cacheStatus['maxCacheSize']}'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              onTestBackend();
            },
            child: const Text('Test Backend'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              onClearAllCaches();
            },
            child: const Text('Clear All Caches'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              onTestPreloading();
            },
            child: const Text('Test Preloading'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              onTestControllers();
            },
            child: const Text('Test Controllers'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              onTestCaching();
            },
            child: const Text('Test Caching'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              onShowVideoStateInfo();
            },
            child: const Text('Video State Info'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              onTestHlsConversion();
            },
            child: const Text('Test HLS Conversion'),
          ),
        ],
      ),
    );
  }
}


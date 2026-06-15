import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:video_player/video_player.dart';
import 'package:vayug/features/video/core/data/models/video_model.dart';
import 'package:vayug/shared/services/video_player_config_service.dart';
import 'package:vayug/shared/managers/smart_cache_manager.dart';
import 'package:vayug/shared/services/hls_warmup_service.dart';
import 'package:vayug/features/video/core/data/services/video_cache_proxy_service.dart';
import 'package:vayug/shared/utils/app_logger.dart';
import 'package:vayug/shared/di/dependency_injection.dart';

/// Factory for creating VideoPlayerController instances with optimized configuration
class VideoControllerFactory {
  static Future<VideoPlayerController> createController(
      VideoModel video) async {
    AppLogger.log(
        '🎬 VideoControllerFactory: createController() called for video ID: ${video.id}, isSubscriberOnly: ${video.isSubscriberOnly}');
    // **NEW: Fetch and register E2EE symmetric key if video is subscriber-only**
    final bool isE2ee = video.isSubscriberOnly;
    if (isE2ee && !kIsWeb) {
      try {
        AppLogger.log(
            '🎬 VideoControllerFactory: E2EE video detected. Initializing proxy...');
        // Ensure proxy server is initialized and running for E2EE decryption
        await videoCacheProxy.initialize();

        final e2ee = serviceLocator.e2eeService;
        AppLogger.log(
            '🎬 VideoControllerFactory: Fetching E2EE key for video: ${video.id}');
        final encKey = await e2ee.fetchEncryptedVideoKey(video.id);
        if (encKey != null) {
          AppLogger.log(
              '🎬 VideoControllerFactory: Successfully fetched E2EE key. Decrypting...');
          final symmetricKey = await e2ee.decryptSymmetricKey(encKey);
          AppLogger.log(
              '🎬 VideoControllerFactory: Decrypted symmetric key (size: ${symmetricKey.length} bytes). Registering with proxy...');
          videoCacheProxy.registerSymmetricKey(video.id, symmetricKey);
          videoCacheProxy.markUrlAsPlayable(video.videoUrl);

          // **E2EE PRE-FETCH: Fire-and-forget background download.
          // ExoPlayer initializes immediately with chunked encoding.
          // If pre-fetch finishes first → cache hit (instant).
          // If ExoPlayer requests first → CDN stream (also works).**
          final isAlreadyCached = await videoCacheProxy.isCached(video.videoUrl);
          final isDecReady = await videoCacheProxy.isDecryptedReady(video.videoUrl);

          if (!isAlreadyCached) {
            AppLogger.log('🔐 VideoControllerFactory: Background pre-fetching E2EE video ${video.id}...');
            videoCacheProxy.prefetchFullFile(video.videoUrl, videoId: video.id);
          } else if (!isDecReady) {
            // Cache exists but .dec not ready — trigger background decrypt and wait briefly
            AppLogger.log(
              '🔐 VideoControllerFactory: Cache exists but .dec not ready for ${video.id}, '
              'triggering background decrypt...',
            );
            videoCacheProxy.prefetchFullFile(video.videoUrl, videoId: video.id);
          } else {
            AppLogger.log('🔐 VideoControllerFactory: E2EE fully ready for ${video.id}');
          }
        } else {
          AppLogger.log(
              '⚠️ VideoControllerFactory: No E2EE key available for video ${video.id}');
        }
      } catch (e, stack) {
        AppLogger.log(
            '❌ VideoControllerFactory: E2EE decryption setup failed: $e\n$stack');
        rethrow;
      }
    }

    // **FIXED: Use MP4 URLs for better ExoPlayer compatibility**
    final isHLS = video.videoUrl.contains('.m3u8') ||
        video.videoUrl.contains('/hls/') ||
        video.isHLSEncoded == true;

    // Use the best available URL for streaming
    String videoUrl = video.videoUrl;

    // **FIXED: Prefer MP4 URLs over HLS for better ExoPlayer compatibility**
    if (videoUrl.isNotEmpty && !videoUrl.contains('.m3u8')) {
    } else if (isHLS &&
        video.hlsPlaylistUrl != null &&
        video.hlsPlaylistUrl!.isNotEmpty) {
      videoUrl = video.hlsPlaylistUrl!;
    } else if (isHLS &&
        video.hlsMasterPlaylistUrl != null &&
        video.hlsMasterPlaylistUrl!.isNotEmpty) {
      videoUrl = video.hlsMasterPlaylistUrl!;
    }

    // Get standardized 480p quality preset
    final qualityPreset =
        VideoPlayerConfigService.getQualityPreset('standard_480p');

    // **CACHING INTEGRATION: Use SmartCacheManager for URL optimization**
    final smartCache = SmartCacheManager();

    // Ensure cache is initialized before use
    if (!smartCache.isInitialized) {
      await smartCache.initialize();
    }

    final cacheKey = 'video_url_${video.id}_${videoUrl.hashCode}';

    // Get optimized video URL with caching
    final optimizedUrl = await smartCache.get<String>(
          cacheKey,
          fetchFn: () async {
            return VideoPlayerConfigService.getOptimizedVideoUrl(
                videoUrl, qualityPreset);
          },
          cacheType: 'videos',
          maxAge: const Duration(minutes: 30),
        ) ??
        VideoPlayerConfigService.getOptimizedVideoUrl(videoUrl, qualityPreset);

    // **ROUTING: E2EE/subscriber-only → local proxy (decryption needed)
    //            Global/public feed → direct CDN URL (no proxy overhead)**
    final String proxiedUrl;
    if (isE2ee) {
      proxiedUrl = videoCacheProxy.proxyUrl(optimizedUrl, videoId: video.id);
      AppLogger.log(
          '🔐 VideoControllerFactory: E2EE video → proxy. original: $videoUrl, proxied: $proxiedUrl');
    } else {
      proxiedUrl = optimizedUrl;
      AppLogger.log(
          '🌐 VideoControllerFactory: Public video → direct CDN. url: $proxiedUrl');
    }

    // Get optimized HTTP headers with caching support
    final headers = VideoPlayerConfigService.getOptimizedHeaders(proxiedUrl);

    // **HLS CACHING: Add HLS-specific cache headers**
    if (isHLS) {
      headers['Cache-Control'] =
          'public, max-age=300'; // 5 minutes for HLS playlists
      headers['X-Cache-Strategy'] = 'HLS-Adaptive';
    }

    // Get buffering configuration

    // Best-effort warm-up for HLS (manifest + first segments)
    if (optimizedUrl.contains('.m3u8')) {
      // Fire-and-forget warm-up to avoid blocking UI
      HlsWarmupService().warmUp(optimizedUrl);
    }

    // **WEB FIX: Web video player needs different configuration**
    final videoPlayerOptions = VideoPlayerOptions(
      mixWithOthers: kIsWeb ? false : true, // Web doesn't support mixWithOthers
      allowBackgroundPlayback: false,
    );

    AppLogger.log(
      '🎬 VideoControllerFactory: Instantiating player controller. URL: $proxiedUrl, Headers: $headers',
    );

    try {
      // **NEW: Support for local gallery videos**
      if (video.videoType == 'local_gallery' && !kIsWeb) {
        AppLogger.log(
            '🎬 VideoControllerFactory: Creating File controller for: ${video.videoUrl}');
        return VideoPlayerController.file(
          File(video.videoUrl),
          videoPlayerOptions: videoPlayerOptions,
        );
      }

      // For E2EE videos the proxy handles all HTTP; do NOT send Accept-Encoding
      // to ExoPlayer because ExoPlayer would forward it to our local proxy which
      // then forwards it to the CDN. If the CDN compresses the encrypted binary
      // the Content-Length will be the compressed size but the stream body is the
      // decompressed size, causing the "Download truncated" error and a Source error.
      final Map<String, String> playerHeaders = {
        ...headers,
        'Connection': 'keep-alive',
        'Cache-Control': 'public, max-age=3600',
      };
      if (!isE2ee) {
        // Only allow compression for non-E2EE content where length mismatches are safe.
        playerHeaders['Accept-Encoding'] = 'gzip, deflate';
      }

      return VideoPlayerController.networkUrl(
        Uri.parse(proxiedUrl),
        videoPlayerOptions: videoPlayerOptions,
        httpHeaders: playerHeaders,
      );
    } catch (e, stack) {
      AppLogger.log(
        '🔴 EXO-DIAG: Error creating controller for video ${video.id}: '
        'errorType=${e.runtimeType}, error=$e',
        isError: true,
      );
      AppLogger.log('🔴 EXO-DIAG: Stack trace: $stack', isError: true);
      // Re-throw to let caller handle
      rethrow;
    }
  }

  /// Creates a VideoPlayerController with custom quality preset (ENHANCED HLS SUPPORT)
  static VideoPlayerController createControllerWithQuality(
      VideoModel video, String qualityUseCase) {
    // **ENHANCED: Use HLS-specific URLs when available**
    final isHLS = video.videoUrl.contains('.m3u8') ||
        video.videoUrl.contains('/hls/') ||
        video.isHLSEncoded == true;

    String videoUrl = video.videoUrl;

    // **ENHANCED HLS: Prioritize HLS-specific URLs for better streaming**
    if (isHLS &&
        video.hlsPlaylistUrl != null &&
        video.hlsPlaylistUrl!.isNotEmpty) {
      videoUrl = video.hlsPlaylistUrl!;
    } else if (isHLS &&
        video.hlsMasterPlaylistUrl != null &&
        video.hlsMasterPlaylistUrl!.isNotEmpty) {
      videoUrl = video.hlsMasterPlaylistUrl!;
    }

    final qualityPreset =
        VideoPlayerConfigService.getQualityPreset(qualityUseCase);
    final optimizedUrl =
        VideoPlayerConfigService.getOptimizedVideoUrl(videoUrl, qualityPreset);

    // **ROUTING: createControllerWithQuality is for public/non-E2EE content.
    //            Direct CDN URL — no proxy overhead needed.**
    final proxiedUrl = optimizedUrl;

    final headers = VideoPlayerConfigService.getOptimizedHeaders(proxiedUrl);

    return VideoPlayerController.networkUrl(
      Uri.parse(proxiedUrl),
      videoPlayerOptions: VideoPlayerOptions(
        mixWithOthers: true,
        allowBackgroundPlayback: false,
      ),
      httpHeaders: headers,
    );
  }

  /// Creates a VideoPlayerController optimized for mobile data usage
  static VideoPlayerController createDataSaverController(VideoModel video) {
    return createControllerWithQuality(video, 'data_saver');
  }

  /// Creates a VideoPlayerController optimized for high-quality playback
  static VideoPlayerController createHighQualityController(VideoModel video) {
    return createControllerWithQuality(video, 'high_quality');
  }
}

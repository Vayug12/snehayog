part of '../video_feed_advanced.dart';

extension _VideoFeedPreload on _VideoFeedAdvancedState {




  Future<void> _checkDeviceCapabilities() async {
    try {
      if (Platform.isAndroid) {
        final androidInfo = await DeviceInfoPlugin().androidInfo;
        // Consider devices with <= 4GB RAM as "Low End" for heavy video tasks
        // isLowRamDevice is a reliable flag from Android API
        // physicalRamSize is in MB (device_info_plus)
        final ramInMB = (androidInfo.physicalRamSize).toDouble();
        _isLowEndDevice = androidInfo.isLowRamDevice || (ramInMB <= 4096);

      }
      
      // **DYNAMIC POOL: Configure shared pool based on device power**
      SharedVideoControllerPool().configurePool(isLowEndDevice: _isLowEndDevice);
      
      // **DYNAMIC CACHE: Configure disk cache limit + Quality filtering**
      videoCacheProxy.configureService(isLowEndDevice: _isLowEndDevice);
      
    } catch (e) {
      AppLogger.log('⚠️ Error checking device capabilities: $e');
    }
  }

  void _preloadNearbyVideos() {
    if (_videos.isEmpty) return;

    // **PIN: covers first load and every page settle, not just swipes.**
    if (_currentIndex >= 0 && _currentIndex < _videos.length) {
      SharedVideoControllerPool()
          .pinVideo(_videos[_currentIndex].id, sessionId: _playbackSession.id);
    }

    // **CRITICAL BANDWIDTH FIX: Kill all previous background downloads except active window**
    final List<String> urlsToKeep = [];
    if (_currentIndex < _videos.length) {
      urlsToKeep.add(_getActingUrl(_videos[_currentIndex]));
    }
    if (_currentIndex + 1 < _videos.length) {
      urlsToKeep.add(_getActingUrl(_videos[_currentIndex + 1]));
    }
    if (_currentIndex - 1 >= 0) {
      urlsToKeep.add(_getActingUrl(_videos[_currentIndex - 1]));
    }
    videoCacheProxy.cancelAllPrefetchesExcept(urlsToKeep);

    final bool isScrollingDown = _currentIndex >= _previousIndex;
    
    // **PRIORITY 0: CURRENT VIDEO - SMART INITIAL CHUNK**
    // Prefetch only the first 500KB for instant playback (0.5 seconds)
    // The rest will be loaded by ExoPlayer in the background
    if (_currentIndex < _videos.length) {
      final currentVideo = _videos[_currentIndex];
      final currentUrl = currentVideo.hlsPlaylistUrl?.isNotEmpty == true
          ? currentVideo.hlsPlaylistUrl!
          : (currentVideo.hlsMasterPlaylistUrl?.isNotEmpty == true
              ? currentVideo.hlsMasterPlaylistUrl!
              : currentVideo.videoUrl);
      
      // Prefetch initial 150KB chunk for instant playback (approx 5s at 400kbps)
      videoCacheProxy.prefetchInitialChunk(currentUrl, kilobytes: 150).catchError((_){});

      // **PROACTIVE PROFILE PRELOAD: Target only the current creator to focus bandwidth**
      // By pre-fetching here, we ensure SmartCache is warm when user taps on profile.
      final creatorId = currentVideo.uploader.googleId?.isNotEmpty == true
          ? currentVideo.uploader.googleId!
          : currentVideo.uploader.id;
      
      if (creatorId.isNotEmpty && creatorId.toLowerCase() != 'unknown') {
        ProfilePreloader().preloadProfile(creatorId);
      }
    }

    
    // Still preload controller normally (initializes player)
    _preloadVideo(_currentIndex);
    
    // **STRICT DIRECTIONAL WINDOWS (User Request)**
    // Down: Focus on Current & Next (n+1). Clean everything else (past).
    // Up: Focus on Current & Prev (n-1). Clean everything else (future).
    
    // **SAFE WINDOW: Adjust window based on device power**
    // High-end: keep [Current-1, Current+1] (Total 3)
    // Low-end: keep [Current, Current+1] if down, [Current-1, Current] if up (Total 2)
    int keepStart, keepEnd;
    if (_isLowEndDevice) {
      if (isScrollingDown) {
        keepStart = _currentIndex;
        keepEnd = (_currentIndex + 1).clamp(0, _videos.length - 1);
      } else {
        keepStart = (_currentIndex - 1).clamp(0, _videos.length - 1);
        keepEnd = _currentIndex;
      }
    } else {
      keepStart = (_currentIndex - 1).clamp(0, _videos.length - 1);
      keepEnd = (_currentIndex + 1).clamp(0, _videos.length - 1);
    }
    
    // **STRICT DIRECTIONAL WINDOWS (Optimization)**
    // While we keep the safe buffer above, we prioritize preloading in the scroll direction.
    if (isScrollingDown) {
        // SCROLLING DOWN -> Priority Next Video (n+1)
        if (_currentIndex + 1 < _videos.length) {
            final nextVideo = _videos[_currentIndex + 1];
            final nextUrl = nextVideo.hlsPlaylistUrl?.isNotEmpty == true
                ? nextVideo.hlsPlaylistUrl!
                : (nextVideo.hlsMasterPlaylistUrl?.isNotEmpty == true
                    ? nextVideo.hlsMasterPlaylistUrl!
                    : nextVideo.videoUrl);
            
            if (_wasLastScrollFast) {
              _preloadDebounceTimers[nextVideo.id]?.cancel();
              _preloadDebounceTimers[nextVideo.id] = Timer(const Duration(milliseconds: 1500), () {
                if (mounted && _currentIndex == (keepStart + 1)) {
                  videoCacheProxy.prefetchInitialChunk(nextUrl, kilobytes: 50).catchError((_){});
                  _preloadVideo(_currentIndex + 1);
                }
              });
            } else {
              videoCacheProxy.prefetchInitialChunk(nextUrl, kilobytes: 50).catchError((_){});
              _preloadVideo(_currentIndex + 1);
            }
        }
    } else {
        // SCROLLING UP -> Priority Prev Video (n-1)
        if (_currentIndex - 1 >= 0) {
            final prevVideo = _videos[_currentIndex - 1];
            final prevUrl = prevVideo.hlsPlaylistUrl?.isNotEmpty == true
                ? prevVideo.hlsPlaylistUrl!
                : (prevVideo.hlsMasterPlaylistUrl?.isNotEmpty == true
                    ? prevVideo.hlsMasterPlaylistUrl!
                    : prevVideo.videoUrl);
            
            if (_wasLastScrollFast) {
              _preloadDebounceTimers[prevVideo.id]?.cancel();
              _preloadDebounceTimers[prevVideo.id] = Timer(const Duration(milliseconds: 1500), () {
                if (mounted && _currentIndex == keepEnd) {
                  videoCacheProxy.prefetchInitialChunk(prevUrl, kilobytes: 50).catchError((_){});
                  _preloadVideo(_currentIndex - 1);
                }
              });
            } else {
              videoCacheProxy.prefetchInitialChunk(prevUrl, kilobytes: 50).catchError((_){});
              _preloadVideo(_currentIndex - 1);
            }
        }
    }

    // **AGGRESSIVE CLEANUP**
    // Dispose everything outside the calculated window immediately
    _cleanupOldControllers(keepStart: keepStart, keepEnd: keepEnd);

    // **SHARED POOL CLEANUP**
    SharedVideoControllerPool()
        .retainOnly(_keepAliveVideoIds(keepStart, keepEnd));

    // **MANIFEST PREFETCH (Lightweight)**
    // Still useful to fetch manifests for HLS further down (no memory cost, just disk cache)
    // We keep this but reduce range to preventing network congestion
    if (isScrollingDown) {
        final int prefetchStart = _currentIndex + 2;
        final int prefetchEnd = _currentIndex + 3;
        for (int i = prefetchStart; i <= prefetchEnd && i < _videos.length; i++) {
           final video = _videos[i];
           final hlsUrl = video.hlsPlaylistUrl?.isNotEmpty == true
               ? video.hlsPlaylistUrl
               : video.hlsMasterPlaylistUrl;
           if (hlsUrl != null && hlsUrl.isNotEmpty) {
               videoCacheProxy.prefetchChunk(hlsUrl, megabytes: 1).catchError((_){});
           }
        }
    }

    // **NEW: Background preload of second page immediately after first page**
    if (!_hasStartedBackgroundPreload &&
        _videos.isNotEmpty &&
        _hasMore &&
        !_isLoadingMore) {
      _hasStartedBackgroundPreload = true;
      _loadMoreVideos();
    }

    // **FIXED: Dynamic loading trigger based on total videos**
    final distanceFromEnd = _videos.length - _currentIndex;
    if (_hasMore && !_isLoadingMore) {
      // **OPTIMIZATION: Smaller batch trigger for low-end devices**
      final int triggerDistance = _isLowEndDevice ? 5 : 20;
      if (distanceFromEnd <= triggerDistance) {
        _loadMoreVideos();
      }
    }
  }

  void _logPlayableControllerReady(
    VideoPlayerController controller, {
    required String videoId,
    required String label,
  }) {
    try {
      final value = controller.value;
      final duration = value.duration;
      final size = value.size;
      if (value.isInitialized &&
          duration > Duration.zero &&
          size.width > 0 &&
          size.height > 0) {
        AppLogger.log(
          '✅ VideoPreloader: PLAYABLE confirmed [$label] video=$videoId — '
          'duration=${duration.inMilliseconds}ms, '
          'size=${size.width.toStringAsFixed(0)}x${size.height.toStringAsFixed(0)}, '
          'aspect=${value.aspectRatio.toStringAsFixed(3)}',
        );
      } else {
        AppLogger.log(
          '⚠️ VideoPreloader: PLAYABLE-CHECK [$label] video=$videoId — '
          'initialized=${value.isInitialized}, duration=$duration, size=$size',
        );
      }
    } catch (e) {
      AppLogger.log('⚠️ VideoPreloader: PLAYABLE-CHECK failed for $videoId: $e');
    }
  }

  /// **PRELOAD SINGLE VIDEO**
  Future<void> _preloadVideo(int index, {bool bypassProxy = false}) async {
    final video = _videos[index];
    final String videoId = video.id;

    // **RACE CONDITION FIX: Don't double-load if already loading**
    if (_loadingVideos.contains(videoId)) {
      // Ensure we re-check smart autoplay even if skipping load
      if (mounted && index == _currentIndex) {

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && index == _currentIndex) {
             _tryAutoplayCurrentImmediate(index);
          }
        });
      }
      return;
    }

    // **NEW: Check if we're already at max concurrent initializations**
    // **VIP PASS: If it's the current video, BYPASS this check and load immediately!**
    if (index != _currentIndex &&
        _initializingVideos.length >= _maxConcurrentInitializations &&
        !_preloadedVideos.contains(videoId) &&
        !_loadingVideos.contains(videoId)) {
      // Queue this video for later initialization
      // **FIX: Use a unique timer for each videoId to prevent closure capturing issues**
      _preloadDebounceTimers[videoId]?.cancel();
      _preloadDebounceTimers[videoId] = Timer(const Duration(milliseconds: 200), () {
        if (mounted && !_preloadedVideos.contains(videoId)) {
          _preloadVideo(index, bypassProxy: bypassProxy);
        }
      });
      return;
    }

    // **OPTIMIZED: Removed "Buffer Gate" logic - HLS handles bandwidth adaptation automatically**
    // Preload normally and let the HLS player manage quality switching based on network conditions

    // **RELEVANCY CHECK: Abort if video is too far from current index (Zombie Load Check)**
    // This prevents "Ghost Loading" when user scrolls fast past this video.
    // **FIX: Tightened from 3 to 2 to prevent far-off videos from loading during fast scroll**
    if (mounted && (index - _currentIndex).abs() > 2) {

      _loadingVideos.remove(videoId); // Ensure we clear the loading flag
      _e2eeDecryptingVideos.remove(videoId);
      return;
    }

    // **CACHE STATUS CHECK ON PRELOAD**

    String? videoUrl;
    VideoPlayerController? controller;
    bool isReused = false;

    try { 
      // **CRITICAL FIX: Start tracking loading immediately inside TRY block to ensure cleanup in FINALLY**
      _loadingVideos.add(videoId);
      
      // **FIX: Clear any previous error state when starting a new load**
      if (mounted && _videoErrors.containsKey(videoId)) {
         _videoErrors.remove(videoId);
      }

      final video = _videos[index];

      // **E2EE SETUP: Fetch and register symmetric key if subscriber-only**
      if (video.isSubscriberOnly && !kIsWeb) {
        try {
          // Ensure proxy server is initialized and running for E2EE decryption
          await videoCacheProxy.initialize();
          
          final e2ee = serviceLocator.e2eeService;
          final encKey = await e2ee.fetchEncryptedVideoKey(video.id);
          if (encKey == null || encKey.isEmpty) {
            throw StateError('e2ee_error: key_unavailable');
          }

            final symmetricKey = await e2ee.decryptSymmetricKey(encKey);
          videoCacheProxy.registerSymmetricKey(video.id, symmetricKey);

          final originalUrl = _getActingUrl(video);
          videoCacheProxy.markUrlAsPlayable(originalUrl);
          final isAlreadyCached = await videoCacheProxy.isCached(originalUrl);
          final isDecryptedReady = await videoCacheProxy.isDecryptedReady(originalUrl);

          AppLogger.log(
            '🔐 VideoPreloader: Cache status for ${video.id}: '
            'cached=$isAlreadyCached, decrypted=$isDecryptedReady',
          );

          if (!isAlreadyCached) {
            AppLogger.log('🔐 VideoPreloader: Starting E2EE prefetch for ${video.id}...');
            unawaited(videoCacheProxy.prefetchFullFile(originalUrl, videoId: video.id));

            // **PREBUFFER GATE: Wait for enough encrypted bytes on disk
            // before creating ExoPlayer — prevents "Source error" on slow networks.**
            // **IMPORTANT: Don't remove _e2eeDecryptingVideos here — keep it alive
            // until the controller is fully initialized. This ensures the progress
            // bar stays visible throughout the entire download + init process.**
            if (mounted) {
              safeSetState(() {
                _e2eeDecryptingVideos.add(videoId);
              });
            }

            final ready = await videoCacheProxy.waitForE2eePrebuffer(
              originalUrl,
              minBytes: 2 * 1024 * 1024, // 2 MB ≈ 8-10 seconds of video — enough for ExoPlayer to start without Source error
              timeout: Duration(seconds: _isLowEndDevice ? 60 : 45),
            );

            // Don't remove _e2eeDecryptingVideos here — it stays until controller init completes

            if (!ready) {
              AppLogger.log('⚠️ VideoPreloader: E2EE prebuffer timed out for ${video.id}, proceeding anyway');
            } else {
              AppLogger.log('✅ VideoPreloader: E2EE prebuffer ready for ${video.id}');
            }
          } else if (!isDecryptedReady) {
            // **FIX: Cache exists but .dec not ready — wait for background decrypt**
            // Without this, ExoPlayer hits on-the-fly decrypt which is slow → Source error
            AppLogger.log(
              '🔐 VideoPreloader: E2EE cache exists but .dec not ready for ${video.id}, '
              'triggering and waiting for background decrypt...',
            );
            unawaited(videoCacheProxy.prefetchFullFile(originalUrl, videoId: video.id));
            // **IMPORTANT: Keep _e2eeDecryptingVideos alive until controller init completes**
            if (mounted) {
              safeSetState(() {
                _e2eeDecryptingVideos.add(videoId);
              });
            }

            // Wait for .dec to become ready (background decrypt)
            final decReady = await videoCacheProxy.waitForE2eePrebuffer(
              originalUrl,
              minBytes: 2 * 1024 * 1024, // 2MB of decrypted data
              timeout: Duration(seconds: _isLowEndDevice ? 60 : 45),
            );

            // Don't remove _e2eeDecryptingVideos here — it stays until controller init completes

            if (decReady) {
              AppLogger.log('✅ VideoPreloader: E2EE .dec ready for ${video.id}');
            } else {
              AppLogger.log(
                '⚠️ VideoPreloader: E2EE .dec not ready for ${video.id} after timeout, '
                'will use on-the-fly decrypt (may be slow)',
              );
            }
          } else {
            AppLogger.log('✅ VideoPreloader: E2EE fully cached and decrypted for ${video.id}');
          }
        } catch (e) {
          AppLogger.log('❌ VideoFeed: E2EE decryption setup failed for ${video.id}: $e');
          if (mounted) {
            safeSetState(() {
              _e2eeDecryptingVideos.remove(videoId);
              _loadingVideos.remove(videoId);
              _videoErrors[videoId] = 'e2ee_error: $e';
            });
          }
          return;
        }
      }

      // **NEW: Use effective URL (Original or Dubbed)**
      videoUrl = _getActingUrl(video);
      
      // **PROXY LOGIC: Only E2EE (subscriber-only) videos go through the local proxy.**
      // Public/global feed videos play directly from CDN — no proxy overhead needed,
      // and bypassing the proxy avoids any manifest-rewriting edge cases that can
      // trigger ExoPlayer Source errors on non-encrypted content.
      if (!bypassProxy && video.isSubscriberOnly) {
          videoUrl = videoCacheProxy.proxyUrl(videoUrl, videoId: video.id);
      } else if (!bypassProxy) {
          AppLogger.log('🌐 VideoPreloader: Direct CDN playback for public video $videoId (no proxy)');
      } else {
          AppLogger.log('🛡️ Fallback: Loading $videoId directly from CDN (Bypassing Proxy)');
      }
      if (videoUrl.isEmpty) {
        AppLogger.log('❌ Invalid video URL for $index: ${video.videoUrl}');
        _loadingVideos.remove(videoId);
        _e2eeDecryptingVideos.remove(videoId);
        return;
      }

      // **RELEVANCY CHECKPOINT #1: After URL resolution**
      if (mounted && (index - _currentIndex).abs() > 1 && index != _currentIndex) {
        _loadingVideos.remove(videoId);
        _e2eeDecryptingVideos.remove(videoId);
        return;
      }

      final sharedPool = SharedVideoControllerPool();

      // **INSTANT LOADING: Try to get controller from shared pool**
      final instantController = sharedPool.getControllerForInstantPlay(video.id);
      if (instantController != null && !sharedPool.isControllerDisposed(instantController)) {
        controller = instantController;
        isReused = true;
        _controllerPool[videoId] = controller;
        _lastAccessedLocal[videoId] = DateTime.now();
      } else if (sharedPool.isVideoLoaded(video.id)) {
        final fallbackController = sharedPool.getController(video.id);
        if (fallbackController != null && !sharedPool.isControllerDisposed(fallbackController)) {
          controller = fallbackController;
          isReused = true;
          _controllerPool[videoId] = controller;
          _lastAccessedLocal[videoId] = DateTime.now();
        }
      }

      if (controller != null && index != _currentIndex) {
        try {
          if (controller.value.isPlaying) {
            controller.pause();
          }
        } catch (_) {
          controller = null;
        }
      }

      if (controller == null) {
        // **ADMISSION CONTROL: acquire decoder headroom before allocating.**
        // A speculative neighbour preload that cannot get room is abandoned
        // rather than allowed to evict the video currently on screen.
        final bool isCurrent = index == _currentIndex;
        final bool hasRoom = await sharedPool.makeRoomForNewController(
          forVideoId: videoId,
          highPriority: isCurrent,
        );

        if (!hasRoom) {
          AppLogger.log(
              '⛔ VideoPreloader: No decoder headroom for $videoId (index $index) — skipping preload');
          _loadingVideos.remove(videoId);
          _e2eeDecryptingVideos.remove(videoId);
          return;
        }

        if (video.videoType == 'local_gallery') {
          // **NEW: Use File controller for local gallery videos**
          controller = VideoPlayerController.file(
            File(videoUrl),
            videoPlayerOptions: VideoPlayerOptions(
              mixWithOthers: true,
              allowBackgroundPlayback: false,
            ),
          );
        } else {
          final bool isE2eeProxy =
              video.isSubscriberOnly && videoUrl.contains('127.0.0.1');
          final Map<String, String> headers;
          if (videoUrl.contains('.m3u8')) {
            headers = const {'Accept': 'application/vnd.apple.mpegurl,application/x-mpegURL'};
          } else if (isE2eeProxy) {
            headers = const {
              'Connection': 'keep-alive',
              'Cache-Control': 'public, max-age=3600',
            };
          } else {
            headers = const {};
          }

          controller = VideoPlayerController.networkUrl(
            Uri.parse(videoUrl),
            videoPlayerOptions: VideoPlayerOptions(
              mixWithOthers: true,
              allowBackgroundPlayback: false,
            ),
            httpHeaders: headers,
          );
        }
      }

      // **RELEVANCY CHECKPOINT #2: Before initialization**
      if (!isReused && mounted && (index - _currentIndex).abs() > 1 && index != _currentIndex) {
        _loadingVideos.remove(videoId);
        _e2eeDecryptingVideos.remove(videoId);
        controller.dispose(); 
        return;
      }

      if (!isReused) {
        _initializingVideos.add(videoId);

        try {
          if (videoUrl.contains('.m3u8')) {
            // **VIP: Increase timeout for low-end hardware/network combinations**
            final timeoutSeconds = _isLowEndDevice ? 25 : 15;
            AppLogger.log('🎬 VideoPreloader: Starting controller.initialize() for HLS video. Timeout: $timeoutSeconds seconds. URL: $videoUrl');
            await controller.initialize().timeout(
              Duration(seconds: timeoutSeconds),
              onTimeout: () {
                AppLogger.log('🎬 VideoPreloader: HLS timeout reached for $videoUrl');
                throw Exception('HLS timeout');
              },
            );
            AppLogger.log('🎬 VideoPreloader: Finished controller.initialize() successfully for HLS video: $videoUrl');
            _logPlayableControllerReady(controller, videoId: videoId, label: 'hls');
          } else {
            final bool isE2eeProxy =
                video.isSubscriberOnly && videoUrl.contains('127.0.0.1');
            final timeoutSeconds = isE2eeProxy
                ? (_isLowEndDevice ? 90 : 75)
                : (_isLowEndDevice ? 15 : 10);
            AppLogger.log(
              '🎬 VideoPreloader: Starting controller.initialize() for binary video. '
              'Timeout: $timeoutSeconds seconds. E2EE proxy: $isE2eeProxy. URL: $videoUrl',
            );
            await controller.initialize().timeout(
              Duration(seconds: timeoutSeconds),
              onTimeout: () {
                AppLogger.log('🎬 VideoPreloader: Video timeout reached for $videoUrl');
                throw Exception('Video timeout');
              },
            );
            AppLogger.log('🎬 VideoPreloader: Finished controller.initialize() successfully for binary video: $videoUrl');
            _logPlayableControllerReady(controller, videoId: videoId, label: 'binary');
          }
          
          if (index != _currentIndex) {
            try {
              if (controller.value.isPlaying) {
                controller.pause();
              }
            } catch (_) {}
          }
        } catch (e, stack) {
          AppLogger.log('🎬 VideoPreloader: Error initializing controller for $videoUrl: $e\n$stack');
          rethrow;
        } finally {
          _initializingVideos.remove(videoId);
        }

        // **LIFECYCLE CHECK: Ensure controller is still valid after async initialization**
        if (!mounted || (index - _currentIndex).abs() > 1 && index != _currentIndex) {
          _loadingVideos.remove(videoId);
          _e2eeDecryptingVideos.remove(videoId);
          controller.dispose();
          return;
        }

        // **POST-INIT CHECK: Safe check for disposal**
        try {
          if (controller.value.isInitialized) {
            // Success
          }
        } catch (_) {
          // Controller might be disposed already
          _loadingVideos.remove(videoId);
          _e2eeDecryptingVideos.remove(videoId);
          return;
        }
      }

      if (mounted && _loadingVideos.contains(videoId)) {
        safeSetState(() {
          _controllerPool[videoId] = controller!;
          _controllerStates[videoId] = false;
          _preloadedVideos.add(videoId);
          _loadingVideos.remove(videoId);
          _lastAccessedLocal[videoId] = DateTime.now();
          // Clear retry count on successful preload
          _preloadRetryCount.remove(videoId);
          // **FIX: Remove E2EE decrypting state ONLY after controller is fully initialized.
          // This keeps the progress bar visible throughout download + init, preventing
          // premature "Source error" when ExoPlayer reads beyond prebuffered bytes.**
          _e2eeDecryptingVideos.remove(videoId);
        });

        sharedPool.addController(video.id, controller);
        
        if (mounted) {

          
          if (!_userPaused.containsKey(videoId)) {
            _userPaused[videoId] = false;
          }
          _getOrCreateNotifier<bool>(_userPausedVN, videoId, false);

          if (!_controllerStates.containsKey(videoId)) {
            _controllerStates[videoId] = false;
          }
        }

        _applyLoopingBehavior(controller);
        _attachEndListenerIfNeeded(controller, index);
        _attachBufferingListenerIfNeeded(controller, index);
        _attachQuizListenerIfNeeded(controller, index);
        _attachErrorListenerIfNeeded(controller, index);



      }

      if (mounted && index == _currentIndex) {
         // **FIX: When opened from profile, use forcePlayCurrent() which bypasses
         // all context checks (visibility, tab, lifecycle) and directly plays.
         // This ensures reliable autoplay regardless of timing/race conditions.**
         if (_openedFromProfile) {
           forcePlayCurrent();
         } else {
           _tryAutoplayCurrentImmediate(index);
         }
      }

    } catch (e) {
      if (mounted) {
        safeSetState(() {
           _loadingVideos.remove(videoId);
           _videoErrors[videoId] = e.toString();
           // **FIX: Also clean up E2EE decrypting state on failure**
           _e2eeDecryptingVideos.remove(videoId);
        });
      }
      
      // **CRITICAL: Dispose leaked controller on error**
      if (controller != null && !isReused) {
        try {
          controller.dispose();
        } catch (_) {}
      }
      
      final retryCount = _preloadRetryCount[videoId] ?? 0;
      if (retryCount < 2) { 
        _preloadRetryCount[videoId] = retryCount + 1;
        AppLogger.log('🔄 Video $index failed, retrying (attempt ${retryCount + 1}/2)... Error: $e');
        
        // Always retry WITH proxy — proxy is needed for HLS manifest rewriting.
        // Do NOT bypass proxy on retry; the root cause is usually a transient
        // network/CDN hiccup, not the proxy itself.
        Future.delayed(const Duration(milliseconds: 1500), () {
          if (mounted && !_preloadedVideos.contains(videoId) && (index - _currentIndex).abs() <= 1) {
            _preloadVideo(index);
          }
        });
      } else {
        AppLogger.log('❌ Video $index failed after retries: $e');
        _preloadRetryCount.remove(videoId);
      }
    }
  }

  String? _validateAndFixVideoUrl(String url, {String? videoId}) {
    if (url.isEmpty) return null;

    String finalUrl = url;

    // **IP REWRITE LOGIC: Correct any old/wrong local development IPs in absolute URLs to the current baseUrl**
    if (url.startsWith('http://192.168.') || 
        url.startsWith('http://10.') || 
        url.startsWith('http://172.') || 
        url.startsWith('http://localhost:5001') || 
        url.startsWith('http://127.0.0.1:5001')) {
      final currentBase = VideoService.baseUrl;
      try {
        final uri = Uri.parse(url);
        final currentBaseUri = Uri.parse(currentBase);
        finalUrl = uri.replace(
          scheme: currentBaseUri.scheme,
          host: currentBaseUri.host,
          port: currentBaseUri.port,
        ).toString();
        AppLogger.log('🔄 Proxy: Rewrote local development IP from ${uri.host} to ${currentBaseUri.host}');
      } catch (e) {
        AppLogger.log('⚠️ Proxy: Failed to rewrite local IP in URL: $e');
      }
    }

    if (!finalUrl.startsWith('http')) {
      // **NEW: Check if it's already a local file path**
      if (finalUrl.startsWith('/') || finalUrl.contains(':/') || finalUrl.contains(':\\')) {
        // Absolute local path, don't prefix with baseUrl
        return finalUrl;
      }
      
      String cleanUrl = finalUrl;
      if (cleanUrl.startsWith('/')) {
        cleanUrl = cleanUrl.substring(1);
      }
      finalUrl = '${VideoService.baseUrl}/$cleanUrl';
    } else {
      try {
        final uri = Uri.parse(finalUrl);
        if (uri.scheme == 'http' || uri.scheme == 'https') {
          // Valid URL
        }
      } catch (e) {
        AppLogger.log('❌ Invalid URL format: $finalUrl');
        return null;
      }
    }

    return finalUrl;
  }

  /// **NEW: Get acting URL representing original or dubbed state**
  String _getActingUrl(VideoModel video) {
    final String selectedLang = _selectedAudioLanguage[video.id] ?? 'default';
    String? targetUrl;

    if (selectedLang != 'default') {
      targetUrl = video.dubbedUrls?[selectedLang];
    }

    if (targetUrl == null || targetUrl.isEmpty) {
      // Standard logic (Source Audio)
      final hlsUrl = video.hlsPlaylistUrl?.isNotEmpty == true
          ? video.hlsPlaylistUrl
          : video.hlsMasterPlaylistUrl;
      
      targetUrl = (hlsUrl != null && hlsUrl.isNotEmpty) ? hlsUrl : video.videoUrl;
    }

    // **CRITICAL FIX: Bypass proxy for local gallery videos**
    if (video.videoType == 'local_gallery') {
      return targetUrl;
    }

    final fixedUrl = _validateAndFixVideoUrl(targetUrl, videoId: video.isSubscriberOnly ? video.id : null);
    
    return fixedUrl ?? targetUrl;
  }


  void _cleanupOldControllers({int? keepStart, int? keepEnd}) {
    final sharedPool = SharedVideoControllerPool();
    
    // Default to safe tight range if not specified
    final int start = keepStart ?? (_currentIndex - 1);
    final int end = keepEnd ?? (_currentIndex + 1);

    // Update Shared Pool too (redundancy check)
    sharedPool.retainOnly(_keepAliveVideoIds(start, end));

    final controllersToRemove = <String>[];

    // **SMART CLEANUP: Cancel pending/initializing videos if they are outside window**
    final initializingList = _initializingVideos.toList();
    for (final videoId in initializingList) {
        // Find index of this videoId
        int? index;
        try {
           index = _videos.indexWhere((v) => v.id == videoId);
        } catch (_) {}

        // Destroy anything outside the keep range
       if (index == null || index < start || index > end) { 

          
          // **FIX: Cancel Debounce Timer if it exists**
          if (_preloadDebounceTimers.containsKey(videoId)) {
             _preloadDebounceTimers[videoId]?.cancel();
             _preloadDebounceTimers.remove(videoId);
          }

          _initializingVideos.remove(videoId);
          _loadingVideos.remove(videoId);
          _e2eeDecryptingVideos.remove(videoId);
          
          if (_controllerPool.containsKey(videoId)) {
             try {
                _controllerPool[videoId]?.dispose();
                _controllerPool.remove(videoId);
             } catch (_) {}
          }
       }
    }

    // **NEW: Cleanup Debounce Timers specifically**
    // Sometimes timers exist even if not in _initializingVideos
    final timersToRemove = <String>[];
    for (final videoId in _preloadDebounceTimers.keys) {
      int? idx;
      try {
        idx = _videos.indexWhere((v) => v.id == videoId);
      } catch (_) {}

      if (idx == null || idx < start || idx > end) {
         timersToRemove.add(videoId);
      }
    }
    for (final videoId in timersToRemove) {
       _preloadDebounceTimers[videoId]?.cancel();
       _preloadDebounceTimers.remove(videoId);
    }

    // **LOCAL POOL CLEANUP**
    for (final videoId in _controllerPool.keys.toList()) {
      // Find ALL indices where this videoId appears
      final List<int> allIndices = [];
      for (int i = 0; i < _videos.length; i++) {
        if (_videos[i].id == videoId) {
          allIndices.add(i);
        }
      }

      // Keep if ANY index is within the safe range [start, end]
      final bool isAnyInRange = allIndices.any((idx) => idx >= start && idx <= end);
      
      if (allIndices.isEmpty || !isAnyInRange) {
        controllersToRemove.add(videoId);
      }
    }

    for (final videoId in controllersToRemove) {
      // **Never tear down the video being watched.** `retainOnly` protects the
      // pin, but this local list is built from list positions — and a refresh
      // that shrinks/reorders `_videos` can put the playing video outside the
      // computed range.
      if (videoId == sharedPool.pinnedVideoId) continue;

      // The pool owns every listener registered for this video, so one call
      // detaches all four (buffering / end / error / quiz).
      sharedPool.removeListener(videoId);
      _bufferingListeners.remove(videoId);
      _videoEndListeners.remove(videoId);
      _errorListeners.remove(videoId);
      _quizListeners.remove(videoId);

      // **SINGLE OWNER: the pool disposes pooled controllers, never the feed.**
      // Disposing here directly used to leave the pool holding a dangling
      // reference to a dead controller. The local map is just a view.
      if (sharedPool.isPooled(videoId)) {
        sharedPool.disposeController(videoId);
      } else {
        // Never handed to the pool (e.g. addController never ran) — the feed
        // is the only owner, so it must release it here.
        final ctrl = _controllerPool[videoId];
        if (ctrl != null) {
          try {
            if (ctrl.value.isInitialized) {
              ctrl.pause();
              ctrl.setVolume(0.0);
            }
            ctrl.dispose();
          } catch (e) {
            AppLogger.log('⚠️ Error disposing unpooled controller $videoId: $e');
          }
        }
      }

      _controllerPool.remove(videoId);
      _controllerStates.remove(videoId);
      _preloadedVideos.remove(videoId);
      _isBuffering.remove(videoId);
      _e2eeDecryptingVideos.remove(videoId);
      

      _bufferingListeners.remove(videoId);
      _videoEndListeners.remove(videoId);
      _lastAccessedLocal.remove(videoId);
      _initializingVideos.remove(videoId);
      _preloadRetryCount.remove(videoId);
      _videoErrors.remove(videoId);
        
      if (_errorListeners.containsKey(videoId)) {
            _errorListeners.remove(videoId);
      }
    }

    if (controllersToRemove.isNotEmpty) {
      // Cleanup complete
    }
  }


  void _applyLoopingBehavior(VideoPlayerController controller) {
    try {
      controller.setLooping(false);
    } catch (e) {
      AppLogger.log('⚠️ Error applying looping behavior: $e');
    }
  }

  void _attachEndListenerIfNeeded(VideoPlayerController controller, int index) {
    if (index >= _videos.length) return;
    final videoId = _videos[index].id;
    final existingListener = _videoEndListeners[videoId];
    if (existingListener != null) {
      SharedVideoControllerPool().detachListener(videoId, existingListener);
    }

    void handleVideoEnd() {
      if (!mounted) return;
      
      // **CRASH-PROOF: Safety check for disposal before accessing value**
      try {
        if (SharedVideoControllerPool().isControllerDisposed(controller)) return;
        
        final value = controller.value;
        if (!value.isInitialized) return;

        final duration = value.duration;
        if (duration == Duration.zero) return;

        final position = value.position;

        final sectionEnd = widget.endAtSeconds;
        final isSharedSection = sectionEnd != null &&
            widget.initialVideoId == videoId &&
            sectionEnd > 0;
        if (isSharedSection && position >= Duration(seconds: sectionEnd)) {
          controller.pause();
          _controllerStates[videoId] = false;
          _userPaused[videoId] = true;
          AppLogger.log('Shared Yug section reached its end at ${sectionEnd}s');
          return;
        }

        final remaining = duration - position;

        // **TRIGGER: 600ms before end for "Instant" feel**
        if (remaining <= const Duration(milliseconds: 600)) {
          if (_userPaused[videoId] == true) return;
          if (_autoAdvancedForIndex.contains(index)) return;
          
          AppLogger.log('✅ Video $index near completion. Auto-advancing...');
          _handleVideoCompleted(index);
        }
      } catch (e) {
        // Silently ignore disposal errors in listener
      }
    }
 
    _videoEndListeners[videoId] = handleVideoEnd;
    SharedVideoControllerPool().attachListener(videoId, handleVideoEnd);
  }

  void _attachBufferingListenerIfNeeded(
    VideoPlayerController controller,
    int index,
  ) {
    if (index >= _videos.length) return;
    final videoId = _videos[index].id;

    final existingListener = _bufferingListeners[videoId];
    if (existingListener != null) {
      SharedVideoControllerPool().detachListener(videoId, existingListener);
    }

    // **STALL DETECTOR STATE**
    Duration? lastPosition;
    DateTime? lastMoveTime;

    void handlePlaybackStatus() {
      if (!mounted) return;
      
      // **CRASH-PROOF: Safety check for disposal before accessing value**
      try {
        if (SharedVideoControllerPool().isControllerDisposed(controller)) return;
        
        final value = controller.value;
        if (!value.isInitialized) return;

        // **BUFFER WATCHDOG: Ensure we pause if the video is playing but it shouldn't be**
        if (value.isPlaying && _shouldPauseVideo(index, videoId)) {
          AppLogger.log('🛡️ Buffer Watchdog: Video $index ($videoId) is playing but should not be. Pausing.');
          try {
            controller.pause();
            _controllerStates[videoId] = false;
          } catch (e) {
            AppLogger.log('❌ Buffer Watchdog pause failed: $e');
          }
          return;
        }

        final bool isBuffering = value.isBuffering;
      
      // **1. BUFFERING LOGIC**
      if (_isBuffering[videoId] != isBuffering) {
          _isBuffering[videoId] = isBuffering;

          // **NEW: Handle Slow Connection feedback timer**
          if (isBuffering) {
            _bufferingTimers[videoId]?.cancel();
            
            // **ADAPTIVE: Immediate trigger for Low Bandwidth Mode**
            if (!_isLowBandwidthMode && mounted) {
               // Don't switch mode immediately, wait a bit to avoid false positives on seek
               // _isLowBandwidthMode = true; 
            }
            _consecutiveSmoothPlays = 0; // Reset recovery counter
    
            _bufferingTimers[videoId] = Timer(const Duration(seconds: 5), () {
              if (!mounted) return;
              
              if (_isBuffering[videoId] == true) {
                 // If still buffering after 5 seconds...
                 
                 // 1. Show Slow Internet UI
                 // **NEW: Throttle display frequency**
                 if (_slowConnectionShownCount < _maxSlowConnectionShows) {
                    _getOrCreateNotifier<bool>(_isSlowConnectionVN, videoId, true);
                    _slowConnectionShownCount++;
                    AppLogger.log('🐢 Slow Internet Banner shown: $_slowConnectionShownCount/$_maxSlowConnectionShows');
                 }
                _isLowBandwidthMode = true; // Now we confirm it's slow
                
                // 2. **KICKSTART LOGIC (Stale Connection Fix)**
                final controller = _controllerPool[videoId];
                if (controller != null && controller.value.isInitialized) {
                   AppLogger.log('🐢 Stale Buffering detected for video $videoId. Attempting Kickstart...');
                   try {
                      final position = controller.value.position;
                      controller.seekTo(position); // Re-trigger buffer fill
                   } catch (e) {
                      AppLogger.log('❌ Kickstart failed: $e');
                   }
                }
              }
            });
          } else {
            _bufferingTimers[videoId]?.cancel();
            _bufferingTimers.remove(videoId);
            final slowConnectionVN =
                _getOrCreateNotifier<bool>(_isSlowConnectionVN, videoId, false);
            if (slowConnectionVN.value != false) {
              slowConnectionVN.value = false;
            }
          }
    
          final bufferingVN =
              _getOrCreateNotifier<bool>(_isBufferingVN, videoId, isBuffering);
          if (bufferingVN.value != isBuffering) {
            bufferingVN.value = isBuffering;
          }
      }
      
      // **2. SILENT STALL DETECTION Watchdog**
      // Detects when video claims to be playing but position isn't moving
      if (value.isPlaying && !value.isBuffering) {
          // Playback is healthy; force-clear stale buffering UI state.
          if (_isBuffering[videoId] == true) {
            _isBuffering[videoId] = false;
          }
          if (_isBufferingVN[videoId]?.value == true) {
            _isBufferingVN[videoId]!.value = false;
          }
          if (_isSlowConnectionVN[videoId]?.value == true) {
            _isSlowConnectionVN[videoId]!.value = false;
          }
          _bufferingTimers[videoId]?.cancel();
          _bufferingTimers.remove(videoId);

          if (lastPosition == value.position) {
             // Position hasn't moved
             lastMoveTime ??= DateTime.now();
             
             if (DateTime.now().difference(lastMoveTime!) > const Duration(milliseconds: 3000)) {
                 // AppLogger.log('❄️ Silent Stall detected for video $videoId (Frozen for 3s). Kicking...');
                 
                 lastMoveTime = DateTime.now(); // Reset to prevent spamming
                 
                 // Force kickstart
                 try {
                    controller.seekTo(value.position);
                 } catch (_) {}
             }
          } else {
             // Moving fine
             lastPosition = value.position;
             lastMoveTime = null;
          }
        } else {
            // Not playing or legitimately buffering, reset stall timer
            lastMoveTime = null;
        }
      } catch (_) {
        // Silently ignore disposal errors in listener
      }
    }

    _bufferingListeners[videoId] = handlePlaybackStatus;
    SharedVideoControllerPool().attachListener(videoId, handlePlaybackStatus);
    handlePlaybackStatus();
  }

  // **NEW: Error Listener to catch runtime playback errors (Grey Screen Fix)**
  // **FIX: Track listener in map to allow cleanup (Prevent duplicate listeners on reuse)**
  void _attachErrorListenerIfNeeded(
    VideoPlayerController controller,
    int index,
  ) {
    if (index >= _videos.length) return;
    final videoId = _videos[index].id;

    final existingErrorListener = _errorListeners[videoId];
    if (existingErrorListener != null) {
      SharedVideoControllerPool().detachListener(videoId, existingErrorListener);
    }
    void handleError() {
      if (!mounted) return;
      try {
        if (SharedVideoControllerPool().isControllerDisposed(controller)) return;
        
        final value = controller.value;
        
        if (value.hasError) {
          final errorMessage = value.errorDescription ?? 'Unknown playback error';
          if (_videoErrors[videoId] != errorMessage) {
            AppLogger.log('❌ Runtime Video Error for video $videoId: $errorMessage');
            
            // **E2EE RETRY LOGIC: For subscriber-only videos, retry preload before showing error.**
            // ExoPlayer throws "Source error" when the encrypted download hasn't finished
            // and not enough bytes are available on disk. Retry with fresh controller.
            if (_videos[index].isSubscriberOnly) {
              final errorLower = errorMessage.toLowerCase();
              final isPreparingError = errorLower.contains('source') ||
                  errorLower.contains('timeout') ||
                  errorLower.contains('videoplayer') ||
                  errorLower.contains('videoerror') ||
                  errorLower.contains('exoplaybackexception') ||
                  errorLower.contains('platformexception') ||
                  errorLower.contains('still loading');
              final e2eeRetryCount = _preloadRetryCount[videoId] ?? 0;
              if (isPreparingError) {
                _preloadRetryCount[videoId] = e2eeRetryCount + 1;
                AppLogger.log(
                  '🔄 E2EE Prepare: Retrying video $videoId behind loading UI '
                  '(attempt ${e2eeRetryCount + 1}). '
                  'Error: $errorMessage',
                );

                // Keep showing the secure preparation state instead of a false error.
                safeSetState(() {
                  _videoErrors.remove(videoId);
                  _e2eeDecryptingVideos.add(videoId);
                  _loadingVideos.add(videoId);
                  _isBuffering[videoId] = false;
                  _isBufferingVN[videoId]?.value = false;
                });

                // Dispose failed controller
                try {
                  controller.pause();
                  controller.setVolume(0.0);
                  _controllerPool[videoId]?.dispose();
                  _controllerPool.remove(videoId);
                } catch (_) {}

                // Wait then retry preload. If the user stays nearby, this keeps polling
                // until the decrypted file is playable without flashing error UI.
                Future.delayed(const Duration(seconds: 3), () {
                  if (mounted && !_preloadedVideos.contains(videoId) &&
                      (index - _currentIndex).abs() <= 1) {
                    _preloadVideo(index).then((_) {
                      if (mounted && index == _currentIndex) {
                        _tryAutoplayCurrentImmediate(index);
                      }
                    });
                  } else {
                    safeSetState(() {
                      _e2eeDecryptingVideos.remove(videoId);
                    });
                  }
                });
                return;
              }

              // Non-preparation E2EE failures are real access/key errors.
              _preloadRetryCount.remove(videoId);
              safeSetState(() {
                 _videoErrors[videoId] = 'e2ee_error: $errorMessage';
                 _e2eeDecryptingVideos.remove(videoId);
                 _loadingVideos.remove(videoId);
                 _isBuffering[videoId] = false;
                 _isBufferingVN[videoId]?.value = false;
              });
              try {
                 controller.pause();
                 _controllerPool.remove(videoId);
              } catch (_) {}
              return;
            }

            // **VIP FALLBACK: If proxy fails on old phone, retry with Raw URL**
            bool handledByFallback = false;
            if (videoCacheProxy.isProxyUrl(controller.dataSource)) {
               AppLogger.log('🔄 Fallback: Proxy failed on $videoId. Retrying with Raw URL...');
               handledByFallback = true;
               
               safeSetState(() {
                  _videoErrors.remove(videoId);
                  _loadingVideos.add(videoId);
               });

               // Kill old controller and retry without proxy
               _controllerPool[videoId]?.dispose();
               _controllerPool.remove(videoId);
               
               // Trigger direct load (bypass proxy completely for normal videos)
               _preloadVideo(index, bypassProxy: !_videos[index].isSubscriberOnly).then((_) {
                   if (mounted && index == _currentIndex) {
                      _tryAutoplayCurrentImmediate(index);
                   }
               });
            }

            if (!handledByFallback) {
              safeSetState(() {
                _videoErrors[videoId] = errorMessage;
                _loadingVideos.remove(videoId);
                _isBuffering[videoId] = false;
                _isBufferingVN[videoId]?.value = false;
                
                try {
                   controller.pause();
                   controller.setVolume(0.0);
                   _controllerPool.remove(videoId);
                } catch (_) {}
              });
            }
          }
        }
      } catch (_) {
        // Silently ignore disposal errors in listener
      }
    }

    SharedVideoControllerPool().attachListener(videoId, handleError);
    _errorListeners[videoId] = handleError;
  }

  void _handleVideoCompleted(int index) {
    if (index >= _videos.length) return;
    final videoId = _videos[index].id;
    if (_userPaused[videoId] == true) return;
    if (_autoAdvancedForIndex.contains(index)) return;
    _autoAdvancedForIndex.add(index);

    if (index < _videos.length) {
      final video = _videos[index];
      _viewTracker.stopViewTracking(video.id);

      // **NEW: Track video completion for watch history**
      final controller = _controllerPool[videoId];
      if (controller != null && controller.value.isInitialized) {
        final duration = controller.value.duration.inSeconds;
        _viewTracker.trackVideoCompletion(
          video.id,
          duration: duration,
          videoHash: video.videoHash, // **NEW: Pass video hash**
        );
      }
      AppLogger.log('⏹️ Completed video playback for ${video.id}');

      // **ADAPTIVE RECOVERY: If video played smoothly, try to recover**
      if (_isLowBandwidthMode && mounted) {
        _consecutiveSmoothPlays++;
        if (_consecutiveSmoothPlays >= 3) {
           _isLowBandwidthMode = false;
           _consecutiveSmoothPlays = 0;
           // AppLogger.log('✅ Adaptive Network: Recovered to High Bandwidth Mode');
        }
      }
    }

    _resetControllerForReplay(index);

    if (_autoScrollEnabled) {
      _queueAutoAdvance(index);
    } else {
      _autoAdvancedForIndex.remove(index);
    }
  }

  void _queueAutoAdvance(int index) {
    final nextIndex = index + 1;
    if (nextIndex >= _videos.length) {
      AppLogger.log('ℹ️ Last video reached, auto-scroll skipped');
      _autoAdvancedForIndex.remove(index);
      return;
    }
    if (!_pageController.hasClients) return;
    if (_isAnimatingPage) return;

    _isAnimatingPage = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_pageController.hasClients) {
        _isAnimatingPage = false;
        return;
      }
      _pageController
          .animateToPage(
        nextIndex,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      )
          .whenComplete(() {
        _isAnimatingPage = false;
        _autoAdvancedForIndex.remove(index);
      });
    });
  }

  void _resetControllerForReplay(int index) {
    if (index >= _videos.length) return;
    final videoId = _videos[index].id;
    final controller = _controllerPool[videoId];
    if (controller == null || !controller.value.isInitialized) return;

    try {
      controller.pause();
      controller.seekTo(Duration.zero);
      controller.setVolume(1.0);
    } catch (e) {
      AppLogger.log('⚠️ Error resetting controller for video $videoId: $e');
    }

    _controllerStates[videoId] = false;
    _userPaused[videoId] = false;
    _isBuffering[videoId] = false;
    if (_isBufferingVN[videoId]?.value == true) {
      _isBufferingVN[videoId]?.value = false;
    }

    _ensureWakelockForVisibility();
  }

  // **NEW: Immediate autoplay helper that doesn't wait for full buffer**
  void _tryAutoplayCurrentImmediate(int index) {
    // **FIX: Removed _isLoading check so video plays even if feed is refreshing**
    if (_videos.isEmpty || index >= _videos.length) return;
    final video = _videos[index];
    final videoId = video.id;

    if (index != _currentIndex) return; // Make sure index hasn't changed
    // **CRITICAL FIX: Use _shouldAutoplayForContext instead of _allowAutoplay**
    // This ensures Yug tab visibility is checked before autoplay
    if (!_shouldAutoplayForContext('tryAutoplayCurrentImmediate')) return;

    final controller = _controllerPool[videoId];
    if (controller != null &&
        controller.value.isInitialized &&
        !controller.value.isPlaying) {
      if (_userPaused[videoId] == true) {
        AppLogger.log(
          '⏸️ Autoplay suppressed: user has manually paused video at index $index',
        );
        return;
      }

      try {
        controller.setVolume(1.0);
      } catch (_) {}

      // **CRITICAL FIX: Use _shouldAutoplayForContext instead of _allowAutoplay**
      if (!_shouldAutoplayForContext('autoplay immediate')) return;

      _pauseOtherLocalVideos(videoId);

      // **ENHANCED: Try to play immediately, with error handling**
      final controllerToPlay = controller;
      try {
        _maybeApplyInitialStartSeek(videoId, controllerToPlay);
        _playWithPolicy(controllerToPlay, 'feed immediate autoplay');
        _ensureWakelockForVisibility();
        _controllerStates[videoId] = true;
        _userPaused[videoId] = false;
        _pendingAutoplayAfterLogin = false;
        
        // **NEW: Start view tracking with videoHash for immediate play**
        if (index < _videos.length) {
          _viewTracker.startViewTracking(
            videoId, 
            videoUploaderId: video.uploader.id,
            videoHash: video.videoHash,
          );
        }

        AppLogger.log(
            '⚡ VideoFeedAdvanced: Immediate autoplay started for video $videoId (index $index)');

        // **NEW: Verify play actually started, retry if needed (use callback instead of delay)**
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted &&
              _currentIndex == index &&
              controllerToPlay.value.isInitialized &&
              !controllerToPlay.value.isPlaying &&
              _userPaused[videoId] != true) {
            
            // **CRITICAL FIX: strictly check lifecycle before retrying**
            if (!_shouldAutoplayForContext('retry immediate')) return;

            AppLogger.log(
                '⚠️ VideoFeedAdvanced: Play command didn\'t start for $videoId, retrying...');
            try {
              _playWithPolicy(controllerToPlay, 'feed immediate autoplay retry');
            } catch (e) {
              AppLogger.log('❌ VideoFeedAdvanced: Retry play failed for $videoId: $e');
            }
          }
        });
      } catch (e) {
        AppLogger.log(
            '❌ VideoFeedAdvanced: Immediate autoplay failed for $videoId: $e, will retry');
        // Retry using callback instead of delay for faster recovery
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted &&
              _currentIndex == index &&
              controllerToPlay.value.isInitialized &&
              !controllerToPlay.value.isPlaying &&
              _userPaused[videoId] != true) {
            
             // **CRITICAL FIX: strictly check lifecycle before retrying**
            if (!_shouldAutoplayForContext('retry catch')) return;

            try {
              _playWithPolicy(controllerToPlay, 'feed autoplay catch retry');
              _ensureWakelockForVisibility();
              _controllerStates[videoId] = true;
              _userPaused[videoId] = false;
              _userPausedVN[videoId]?.value = false; // **Sync VN**
              
              // **NEW: Start view tracking with videoHash for retry play**
              if (index < _videos.length) {
                _viewTracker.startViewTracking(
                  videoId, 
                  videoUploaderId: video.uploader.id,
                  videoHash: video.videoHash,
                );
              }

              AppLogger.log(
                  '✅ VideoFeedAdvanced: Autoplay started on retry for video $videoId');
            } catch (retryError) {
              AppLogger.log(
                  '❌ VideoFeedAdvanced: Retry autoplay failed for $videoId: $retryError');
            }
          }
        });
      }
    }
  }

  void _attachQuizListenerIfNeeded(VideoPlayerController controller, int index) {
    if (index >= _videos.length) return;
    final video = _videos[index];
    final videoId = video.id;

    AppLogger.log('🧪 YugFeed debug: _attachQuizListenerIfNeeded for video $videoId (index $index). Quiz count: ${video.quizzes?.length ?? 0}');

    if (video.quizzes == null || video.quizzes!.isEmpty) {
      if (video.quizzes == null) {
        AppLogger.log('⚠️ YugFeed: Quizzes field is NULL for video $videoId');
      }
      return;
    }

    final existingListener = _quizListeners[videoId];
    if (existingListener != null) {
      SharedVideoControllerPool().detachListener(videoId, existingListener);
    }

    void handleQuizCheck() {
      if (!mounted) return;
      if (_currentIndex != index) return;
      if (_activeQuizVN.value != null) return;

      try {
        if (SharedVideoControllerPool().isControllerDisposed(controller)) return;
        if (!controller.value.isInitialized) return;

        final currentPosition = controller.value.position;
        final currentSeconds = currentPosition.inSeconds;

        final quiz = _quizEngine.evaluatePosition(
          videoId: videoId,
          currentPosition: currentPosition,
          quizzes: video.quizzes!,
        );

        if (quiz != null) {
          _quizEngine.markShown(videoId, quiz);
          _activeQuizVN.value = quiz;
          AppLogger.log('🎉 YugFeed: Triggered quiz "${quiz.question}" at $currentSeconds seconds');
        }
      } catch (e) {
        // Silently ignore disposal errors
      }
    }

    _quizListeners[videoId] = handleQuizCheck;
    SharedVideoControllerPool().attachListener(videoId, handleQuizCheck);
  }

  /// Whether a freshly initialized controller must stay paused.
  ///
  /// Tab and route placement come from the coordinator. The hand-rolled copy
  /// this replaced exempted profile- and deep-link-opened feeds from the tab
  /// check, so one sitting in a background tab would start playing the moment
  /// a controller finished initializing.
  bool _shouldPauseVideo(int index, String videoId) {
    if (index != _currentIndex) return true;
    if (_userPaused[videoId] == true) return true;
    if (_lifecyclePaused) return true;
    if (!_isScreenVisible) return true;

    return !_playbackCoordinator.canPlay(
      _playbackSession,
      reason: 'preload gate for $videoId',
    );
  }
}

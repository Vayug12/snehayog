part of '../video_feed_advanced.dart';

extension _VideoFeedInitialization on _VideoFeedAdvancedState {
  void _initializeServices() {
    // **FIX: For deep links (initialVideoId without initialVideos),
    // we'll set initialPage after fetching the video**
    int initialPage = widget.initialIndex ?? 0;
    if (widget.initialVideoId != null && widget.initialVideos != null) {
      final videoIndex = widget.initialVideos!.indexWhere(
        (v) => v.id == widget.initialVideoId,
      );
      if (videoIndex != -1) {
        initialPage = videoIndex;
        _currentIndex = videoIndex;
      }
    }
    // **FIX: For deep links without initialVideos, start at 0 but we'll correct it after video fetch**
    // Don't set initialPage here for deep links - we'll set it after fetching the video

    _pageController = PageController(initialPage: initialPage, keepPage: false);

    _videoService = VideoService();
    _authService = AuthService();
    _carouselAdManager = CarouselAdManager();
    _dubbingService = widget.dubbingService ?? OnDeviceDubbingServiceImpl();
    _activeAdsService = widget.adService ?? ActiveAdsService();
    _quizEngine = widget.quizEngine ?? StandardQuizEngine();


    _adRefreshSubscription = _adRefreshNotifier.refreshStream.listen((_) {
      refreshAds();
    });

    _connectivitySubscription = ConnectivityService.connectivityStream.listen((results) {
      _handleConnectivityChange(results);
    });

    // **NEW: Shared Pool Disposal Watchdog**
    // Listen for evictions from the global SharedVideoControllerPool.
    // If a controller is disposed by another screen (e.g. Profile), 
    // we MUST remove it from our local pool to prevent "used after disposed" errors.
    _poolDisposalSubscription = SharedVideoControllerPool().disposalStream.listen((videoId) {
      if (mounted && _controllerPool.containsKey(videoId)) {
        AppLogger.log('🧹 VideoFeed: Cleaning up stale controller for $videoId (Evicted from SharedPool)');
        
        // 1. Remove from local state
        _controllerPool.remove(videoId);
        _controllerStates.remove(videoId);
        _preloadedVideos.remove(videoId);
        _loadingVideos.remove(videoId);
        _initializingVideos.remove(videoId);
        
        // 2. Identify the index of this video in our current feed
        int videoIndex = -1;
        try {
          videoIndex = _videos.indexWhere((v) => v.id == videoId);
        } catch (_) {}

        // 3. Proactive Recovery: If this is the currently visible video, 
        // immediately trigger re-initialization so it doesn't get stuck on a spinner.
        if (videoIndex != -1 && videoIndex == _currentIndex && mounted) {
          AppLogger.log('🩹 VideoFeed: PROACTIVE recovery triggered for current video at index $videoIndex');
          
          // Use Future.microtask to allow the UI to react to the "null" controller first
          Future.microtask(() {
            if (mounted && _currentIndex == videoIndex) {
              _preloadVideo(videoIndex);
            }
          });
        }
        
        

        // 4. Trigger UI rebuild to show progress/spinner while healing
        safeSetState(() {});
      }
    });

    _loadInitialData();
    
    // **UNBLOCK AD LOADING: Trigger ad loading immediately (non-blocking)**
    // Triggered here at the very start of service initialization to maximize parallelism.
    _loadActiveAds().catchError((e) {
      AppLogger.log('⚠️ Error pre-loading ads in init: $e');
    });
  }

  /// **Handle connectivity changes for the offline banner**
  void _handleConnectivityChange(List<ConnectivityResult> results) {
    final isOffline = ConnectivityService.isOffline(results);
    
    if (isOffline) {
      if (!_hasShownOfflineBanner) {
        _hasShownOfflineBanner = true;
        _showOfflineBannerVN.value = true;
        
        // Hide after 2 seconds
        Timer(const Duration(seconds: 2), () {
          if (mounted) {
            _showOfflineBannerVN.value = false;
          }
        });
      }
    } else {
      // Reset when back online so it can show again next time it goes offline
      _hasShownOfflineBanner = false;
      _showOfflineBannerVN.value = false;
    }
  }

  Future<void> _loadInitialData() async {
    if (_isInitialDataLoaded && _videos.isNotEmpty) {
      AppLogger.log('ℹ️ VideoFeedAdvanced: Initial data already loaded, skipping redundant fetch.');
      return;
    }

    try {
      AppLogger.log('📥 VideoFeedAdvanced: _loadInitialData() started');
      AppLogger.log('📍 Trace: _loadInitialData called from:');
      AppLogger.log(StackTrace.current.toString().split('\n').take(5).join('\n'));
      
      // **OPTIMIZED: Use ValueNotifiers for granular updates**
      _isLoading = true;
      _errorMessage = null; // Clear any previous error

      // **CRITICAL FIX: Wait for User ID before loading videos**
      // This ensures the first API request includes the Authorization header
      // so backend can return correct isLiked status for each video.
      await _loadCurrentUserId();

      // **NEW: Load persisted seen video keys so cache doesn't re-show watched videos**
      await _loadSeenVideoKeysFromStorage();

      // **BACKEND-FIRST: Backend handles all filtering via WatchHistory**
      // No need to load from local storage - backend is source of truth
      // Backend filters watched videos for ALL users (authenticated + anonymous via deviceId)
      // Even after app reinstall, backend will filter watched videos correctly
      // **ACCELERATED BOOT SYNC: If we don't have initialVideos, check for in-flight background fetch**
      if (widget.initialVideos == null && !(_openedFromProfile || _openedFromDeepLink)) {
        
        // Restoration logic removed. Fallback directly to background fetch or fresh load.

        AppLogger.log('⏳ VideoFeedAdvanced: Checking for accelerated boot background fetch...');
        final bgVideos = await AppInitializationManager.instance.backgroundFetchFuture
            .timeout(const Duration(seconds: 8), onTimeout: () => null);
            
        if (bgVideos != null && bgVideos.isNotEmpty) {
           AppLogger.log('🚀 VideoFeedAdvanced: Consuming background-fetched fresh videos');
           _videos = List.from(bgVideos);
        } else {
           AppLogger.log('⚠️ VideoFeedAdvanced: Background fetch unavailable or timed out, fallback to fresh load');
        }
      } else if (widget.initialVideos != null && widget.initialVideos!.isNotEmpty) {
        _videos = List.from(widget.initialVideos!);
        String? preserveKey;
        if (widget.initialVideoId != null) {
          for (final video in _videos) {
            if (video.id == widget.initialVideoId) {
              preserveKey = videoIdentityKey(video);
              break;
            }
          }
        }
        preserveKey ??=
            _videos.isNotEmpty ? videoIdentityKey(_videos.first) : null;

        // **FIX: Rank videos and find correct index AFTER ranking (async - runs in isolate)**
        // Skip engagement ranking for profile feeds to strictly preserve chronological order
        final rankedVideos = _openedFromProfile
            ? _videos
            : await _rankVideosWithEngagement(
                _videos,
                preserveVideoKey: preserveKey,
              );

        // **CRITICAL FIX: If all videos were filtered out, use original videos as fallback**
        final videosToUse =
            rankedVideos.isEmpty && _videos.isNotEmpty ? _videos : rankedVideos;

        if (rankedVideos.isEmpty && _videos.isNotEmpty) {
          AppLogger.log(
              '⚠️ VideoFeedAdvanced: All ${_videos.length} initial videos were filtered out! Using original videos as fallback.');
        }

        _videos = videosToUse;

        if (mounted) {
          // **FIX: Synchronize pagination state from manager**
          // Set _hasMore to false for profile feeds to prevent loading global feed videos on scroll
          _hasMore = _openedFromProfile ? false : AppInitializationManager.instance.hasInitialVideosMore;
          _currentPage = 1;

          // **FIX: Find correct index AFTER ranking (videos may have been reordered)**
          int correctIndex = 0;
          if (widget.initialVideoId != null && _videos.isNotEmpty) {
            final foundIndex = _videos.indexWhere(
              (v) => v.id == widget.initialVideoId,
            );
            if (foundIndex != -1) {
              correctIndex = foundIndex;
            }
          }

          _currentIndex = correctIndex;

          // **FIX: Update PageController to correct index after ranking**
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _pageController.hasClients) {
              _pageController.jumpToPage(correctIndex);
              AppLogger.log(
                '🎯 VideoFeedAdvanced: Updated PageController to index $correctIndex after ranking',
              );
            }
          });

          // **OPTIMIZED: Use ValueNotifiers for granular updates**
          _isLoading = false;
          _errorMessage = null; // Ensure error is cleared

          AppLogger.log(
            '🚀 VideoFeedAdvanced: Progressive render with provided videos: ${_videos.length}, hasMore: $_hasMore, currentIndex: $_currentIndex',
          );

          // **CLEAR MANAGER CACHE: We've consumed the initial videos**
          if (widget.initialVideos != null) {
            AppInitializationManager.instance.initialVideos = null;
          }

          if (_videos.isNotEmpty) {
            _markCurrentVideoAsSeen();
            _syncLikeStateWithModels(_videos);

            // **OPTIMIZED: Immediately preload first video for instant playback**
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && _videos.isNotEmpty) {
                // **FIX: Set screen visible immediately when opened from profile**
                // Without this, _shouldAutoplayForContext blocks autoplay because
                // _isScreenVisible is still false at this point.
                if (_openedFromProfile) {
                  _isScreenVisible = true;
                  _ensureWakelockForVisibility();
                }

                // Preload current video immediately (don't wait)
                _preloadVideo(_currentIndex);

                // Try autoplay immediately if screen is visible (no delay - autoplay checks controller readiness)
                if (_isScreenVisible || _mainController?.currentIndex == 0) {
                  _tryAutoplayCurrent();
                }
              }
            });

            // Also start normal preloading sequence
            _startVideoPreloading();
          } else {
            AppLogger.log('⚠️ VideoFeedAdvanced: No videos after ranking');
          }
        }

        // User ID loaded earlier at the start of _loadInitialData
        return;
      }

      // **FIX: If initialVideoId is provided (deep link), OR if we have a saved video ID (cold start restore), fetch that video first**
      String? targetVideoId = widget.initialVideoId;
      
      // **NEW: Check saved state if not a deep link**
      if (targetVideoId == null && widget.initialVideos == null) {
        try {
          final prefs = await SharedPreferences.getInstance();
          final savedId = prefs.getString(_kSavedVideoIdKey);
          // Only use saved ID if it's recent (less than 12 hours) to avoid restoring very old state
          final savedTimestamp = prefs.getInt(_kSavedStateTimestampKey);
          if (savedId != null && savedTimestamp != null) {
             final savedTime = DateTime.fromMillisecondsSinceEpoch(savedTimestamp);
             final hoursSince = DateTime.now().difference(savedTime).inHours;
             if (hoursSince < 12) {
               targetVideoId = savedId;
               AppLogger.log('🔄 Restoring saved state: Video ID $targetVideoId (from $hoursSince hours ago)');
             }
          }
        } catch (_) {}
      }

      // **FIX: If initialVideoId is provided (deep link), fetch that video first**
      if ((targetVideoId != null || widget.initialVideoId != null) && widget.initialVideos == null) {
        try {
          final effectiveTargetId = targetVideoId ?? widget.initialVideoId!;
          final cleanTargetId = effectiveTargetId.trim();
          AppLogger.log(
            '🔗 VideoFeedAdvanced: Target video detected (deep link or restore), fetching: $cleanTargetId',
          );

          // Fetch the target video first
          final targetVideo = await _videoService.getVideoById(cleanTargetId);
          AppLogger.log(
            '✅ VideoFeedAdvanced: Fetched deep link video: ${targetVideo.videoName} (ID: ${targetVideo.id})',
          );

          // Load regular videos from API
          await _loadVideos(page: 1, clearSession: false, forceResetIndex: true);

          if (mounted) {
            // **CRITICAL: Only insert if not already present in the list**
            final bool alreadyPresent = _videos.any((v) => v.id == targetVideo.id);
            if (!alreadyPresent) {
              _videos.insert(0, targetVideo);
            } else {
              // Move it to top if present elsewhere
              _videos.removeWhere((v) => v.id == targetVideo.id);
              _videos.insert(0, targetVideo);
            }

            // **CRITICAL: Re-rank videos but preserve deep link video at index 0**
            // Use preserveVideoKey to ensure deep link video stays at position 0
            // (async - runs in isolate)
            final deepLinkVideoKey = videoIdentityKey(targetVideo);
            final rankedVideos = await _rankVideosWithEngagement(
              _videos,
              preserveVideoKey: deepLinkVideoKey.isNotEmpty
                  ? deepLinkVideoKey
                  : cleanTargetId,
            );

            // **CRITICAL FIX: If all videos were filtered out, use original videos as fallback**
            _videos = rankedVideos.isEmpty && _videos.isNotEmpty
                ? _videos
                : rankedVideos;

            if (rankedVideos.isEmpty && _videos.isNotEmpty) {
              AppLogger.log(
                  '⚠️ VideoFeedAdvanced: All videos were filtered out after deep link! Using original videos as fallback.');
            }

            // **VERIFY: Ensure deep link video is still at index 0 after ranking**
            final verifyIndex = _videos.indexWhere((v) {
              final normalizedId = v.id.trim().toLowerCase();
              final normalizedTargetId = cleanTargetId.toLowerCase();
              return normalizedId == normalizedTargetId ||
                  v.id.trim() == cleanTargetId ||
                  v.id == cleanTargetId ||
                  videoIdentityKey(v) == deepLinkVideoKey;
            });

            // **FIX: Always ensure deep link video is at index 0**
            final correctIndex = verifyIndex != -1 ? verifyIndex : 0;

            // If ranking moved the video, move it back to index 0
            if (correctIndex != 0 && correctIndex < _videos.length) {
              final videoToMove = _videos.removeAt(correctIndex);
              _videos.insert(0, videoToMove);
              AppLogger.log(
                '🔧 VideoFeedAdvanced: Moved deep link video back to index 0 after ranking (was at index $correctIndex)',
              );
            }

            // **CRITICAL FIX: Always set currentIndex to 0 for deep link videos**
            // Since we've ensured the video is at index 0, _currentIndex must be 0
            _currentIndex = 0;

            // **DOUBLE VERIFY: Ensure video at index 0 is actually the target video**
            if (_videos.isNotEmpty) {
              final videoAtZero = _videos[0];
              final videoAtZeroId = videoAtZero.id.trim().toLowerCase();
              final targetIdLower = cleanTargetId.toLowerCase();
              if (videoAtZeroId != targetIdLower &&
                  videoAtZero.id.trim() != cleanTargetId &&
                  videoAtZero.id != cleanTargetId) {
                AppLogger.log(
                  '⚠️ VideoFeedAdvanced: Video at index 0 does not match target! Expected: $cleanTargetId, Got: ${videoAtZero.id}',
                );
                // Last resort: find and move the correct video to index 0
                final correctVideoIndex = _videos.indexWhere((v) {
                  final normalizedId = v.id.trim().toLowerCase();
                  return normalizedId == targetIdLower ||
                      v.id.trim() == cleanTargetId ||
                      v.id == cleanTargetId;
                });
                if (correctVideoIndex != -1 && correctVideoIndex != 0) {
                  final correctVideo = _videos.removeAt(correctVideoIndex);
                  _videos.insert(0, correctVideo);
                  AppLogger.log(
                    '🔧 VideoFeedAdvanced: Corrected deep link video position (found at index $correctVideoIndex, moved to 0)',
                  );
                }
              } else {
                AppLogger.log(
                  '✅ VideoFeedAdvanced: Verified deep link video is at index 0 (ID: $cleanTargetId, Name: ${videoAtZero.videoName})',
                );
              }
            }

            AppLogger.log(
              '📊 VideoFeedAdvanced: Total videos after insertion and ranking: ${_videos.length}',
            );

            // **FIX: For cold start, we need to immediately update PageController**
            // The PageController was initialized with initialPage: 0, but we need to ensure it's at 0
            // Since we've verified the video is at index 0, jump to 0 (or stay at 0)
            if (_pageController.hasClients) {
              // PageController is already attached, jump to index 0
              _pageController.jumpToPage(0);
              AppLogger.log(
                '🎯 VideoFeedAdvanced: PageController jumped to index 0 (cold start, immediate)',
              );
            } else {
              // PageController not ready yet, wait for it using nested callbacks instead of delay
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  // Try immediately
                  if (_pageController.hasClients) {
                    _pageController.jumpToPage(0);
                    AppLogger.log(
                      '🎯 VideoFeedAdvanced: PageController jumped to index 0 (cold start, first callback)',
                    );
                  } else {
                    // Use another postFrameCallback instead of delay
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted && _pageController.hasClients) {
                        _pageController.jumpToPage(0);
                        AppLogger.log(
                          '🎯 VideoFeedAdvanced: PageController jumped to index 0 (cold start, second callback)',
                        );
                      }
                    });
                  }
                }
              });
            }

            AppLogger.log(
              '✅ VideoFeedAdvanced: Deep link video ready at index 0 (ID: $cleanTargetId, videoName: ${targetVideo.videoName})',
            );

            // **OPTIMIZED: Use ValueNotifiers for granular updates**
            _isLoading = false;
            _errorMessage = null;

            // **CRITICAL: Ensure video preloading and autoplay for deep link video**
            // Deep link video is always at index 0
            if (_videos.isNotEmpty && _currentIndex < _videos.length) {
              // **CRITICAL: Mark screen as visible for deep link videos (they should autoplay)**
              _isScreenVisible = true;
              _ensureWakelockForVisibility();

              // Mark current video as seen
              _markCurrentVideoAsSeen();

              // Start video preloading (will include the deep link video)
              _startVideoPreloading();

              // **CRITICAL: Force autoplay of deep link video after positioning**
              // Use WidgetsBinding callback to ensure UI is ready
              // Deep link video is always at index 0
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && _currentIndex == 0 && _videos.isNotEmpty) {
                  // First attempt: immediate autoplay (no delay - autoplay checks controller readiness)
                  AppLogger.log(
                    '🎬 VideoFeedAdvanced: Attempting autoplay for deep link video at index 0 (ID: ${_videos[0].id}, Name: ${_videos[0].videoName})',
                  );
                  _tryAutoplayCurrent();

                  // Second attempt: after video controller is ready (use listener instead of delay)
                  // Only retry if first attempt didn't work
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted && _currentIndex == 0 && _videos.isNotEmpty) {
                      final String videoId = _videos[0].id;
                      // Check if video is already playing before retrying
                      bool isPlayingSafe = false;
                      if (_controllerPool.containsKey(videoId)) {
                        try {
                          isPlayingSafe = _controllerPool[videoId]?.value.isPlaying ?? false;
                        } catch (_) {
                          _controllerPool.remove(videoId);
                        }
                      }

                      if (_controllerStates[videoId] != true || !isPlayingSafe) {
                        AppLogger.log(
                          '🎬 VideoFeedAdvanced: Second autoplay attempt for deep link video',
                        );
                        _tryAutoplayCurrent();
                      }

                      // **FORCE PLAY: If video still not playing, force it**
                      // Deep link video is always at index 0
                      if (_controllerPool.containsKey(videoId)) {
                        final controller = _controllerPool[videoId];
                        if (controller != null &&
                            controller.value.isInitialized &&
                            !controller.value.isPlaying) {
                          AppLogger.log(
                            '🎬 VideoFeedAdvanced: Forcing play for deep link video at index 0 (controller ready but not playing)',
                          );
                          _pauseAllOtherVideos(videoId);
                          try {
                            if (!_shouldAutoplayForContext('deep link force play')) return;
                            controller.setVolume(1.0);
                            _playWithPolicy(controller, 'deep link force play');
                            _controllerStates[videoId] = true;
                            _userPaused[videoId] = false;
                            AppLogger.log(
                              '✅ VideoFeedAdvanced: Deep link video force play successful',
                            );
                          } catch (e) {
                            AppLogger.log(
                              '❌ VideoFeedAdvanced: Error forcing play: $e',
                            );
                          }
                        }
                      }
                    }
                  });
                }
              });
            }
          }
        } catch (e) {
          AppLogger.log(
            '⚠️ VideoFeedAdvanced: Error fetching deep link video: $e, falling back to regular load',
          );

          // **OPTIMIZED: Use ValueNotifier for granular update**
          if (mounted) {
            _errorMessage = 'Video not found. Loading feed instead...';
          }

          // **FALLBACK: Load regular videos and try to find the video in the feed**
          await _loadVideos(page: 1, clearSession: false, forceResetIndex: true);
          if (mounted) {
            // **OPTIMIZED: Use ValueNotifier for granular update**
            _errorMessage = null;

            // **ENHANCED: Try to verify and set correct index after loading**
            _verifyAndSetCorrectIndex();

            // **IF VIDEO NOT FOUND: Show error to user**
            if (widget.initialVideoId != null && _videos.isNotEmpty) {
              final targetVideoId = widget.initialVideoId!.trim();
              final videoFound = _videos.any(
                (v) => v.id.trim() == targetVideoId || v.id == targetVideoId,
              );

              if (!videoFound && mounted) {
                AppLogger.log(
                  '❌ VideoFeedAdvanced: Video $targetVideoId not found in feed',
                );
                // Show snackbar to user
                _showSnackBar('Video not found. Showing feed instead.');
              }
            }
          }
        }
      } else {
        // Regular video load (no deep link)
        // **FIX: Wait for videos to load before setting isLoading = false**
        await _loadVideos(page: 1, clearSession: false, forceResetIndex: true);
        if (!mounted) return;
        _verifyAndSetCorrectIndex();
      }

      // User ID already loaded at the start

      if (mounted) {
        // **FIX: Restore saved state (index/position) even on cold start**
        // This enables "Resume where you left off" feature
        await _restoreBackgroundStateIfAny();

        // **FIX: Only set isLoading = false if videos are actually loaded**
        // If videos list is still empty, keep loading state or show error
        if (_videos.isEmpty && _errorMessage == null) {
          AppLogger.log(
            '⚠️ VideoFeedAdvanced: No videos loaded, retrying immediately...',
          );
          // No error but no videos - might be network issue, retry immediately (no delay)
          try {
            await _loadVideos(page: 1, useCache: false, clearSession: false, forceResetIndex: true);
            if (!mounted) return;
            _verifyAndSetCorrectIndex();
          } catch (retryError) {
            AppLogger.log('❌ VideoFeedAdvanced: Retry failed: $retryError');
            if (mounted) {
              // **OPTIMIZED: Use ValueNotifiers for granular updates**
              _isLoading = false;
              _errorMessage = retryError.toString();
            }
            return;
          }
        }

        // Videos loaded successfully or error occurred
        if (mounted) {
          // **OPTIMIZED: Use ValueNotifier for granular update**
          _isLoading = false;
          if (_videos.isNotEmpty) {
            AppLogger.log(
              '🚀 VideoFeedAdvanced: Progressive render after videos loaded: ${_videos.length}',
            );

            // **CRITICAL FIX: Set _isScreenVisible = true when videos are loaded for Yug tab**
            // This ensures autoplay works when Yug tab is first loaded
            if (!_openedFromProfile &&
                _mainController?.currentIndex == 0 &&
                !_isScreenVisible) {
              _isScreenVisible = true;
              _ensureWakelockForVisibility();
              AppLogger.log(
                '✅ VideoFeedAdvanced: Yug tab videos loaded - setting _isScreenVisible = true',
              );
            }

            // **OPTIMIZED: Immediately preload first video for instant playback**
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && _videos.isNotEmpty) {
                // Preload current video immediately
                _preloadVideo(_currentIndex);

                // Try autoplay immediately if Yug tab is active (no delay - autoplay checks controller readiness)
                if (_mainController?.currentIndex == 0 && _isScreenVisible) {
                  _tryAutoplayCurrent();
                }
              }
            });

            _startVideoPreloading();

            // **FIX: Load ads immediately (non-blocking) so custom ads are ready
            // before AdMob fails. Previously delayed 2s which caused adData=null
            // race condition when AdMob failed and fell back to custom ads.**
            if (mounted) {
              _loadActiveAds().catchError((e) {
                AppLogger.log('⚠️ Error loading ads: $e');
              });
              _loadFollowingUsers().catchError((e) {
                AppLogger.log(
                    '⚠️ Error loading following users: $e');
              });
            }
          }
        }
      }
      _isInitialDataLoaded = true;
      AppLogger.log('✅ VideoFeedAdvanced: _loadInitialData() completed successfully');
    } catch (e) {
      AppLogger.log('❌ Error loading initial data: $e');
      if (mounted) {
        // **OPTIMIZED: Use ValueNotifiers for granular updates**
        _isLoading = false;
        _errorMessage = e.toString();
      }
    }
  }

  void _verifyAndSetCorrectIndex() {
    if (widget.initialVideoId != null && _videos.isNotEmpty) {
      final targetVideoId = widget.initialVideoId!.trim();
      final targetVideoIdLower = targetVideoId.toLowerCase();

      // Ensure currentIndex is valid before accessing
      if (_currentIndex >= _videos.length) {
        _currentIndex = 0;
      }

      if (_currentIndex < _videos.length) {
        final videoAtCurrentIndex = _videos[_currentIndex];
        // **FIX: Compare with trimmed and case-insensitive IDs to handle matching issues**
        final currentVideoId = videoAtCurrentIndex.id.trim();
        final currentVideoIdLower = currentVideoId.toLowerCase();

        // Check if current video matches target (with multiple matching strategies)
        final currentMatches = currentVideoIdLower == targetVideoIdLower ||
            currentVideoId == targetVideoId ||
            videoAtCurrentIndex.id == targetVideoId;

        if (!currentMatches) {
          // Find the correct video by ID (try multiple matching strategies)
          final correctIndex = _videos.indexWhere((v) {
            final vId = v.id.trim();
            final vIdLower = vId.toLowerCase();
            return vIdLower == targetVideoIdLower ||
                vId == targetVideoId ||
                v.id == targetVideoId;
          });

          if (correctIndex != -1) {
            AppLogger.log(
              '🔧 VideoFeedAdvanced: Correcting index from $_currentIndex to $correctIndex for video ID: $targetVideoId',
            );
            _currentIndex = correctIndex;
            if (_pageController.hasClients) {
              _pageController.jumpToPage(correctIndex);
              AppLogger.log(
                '✅ VideoFeedAdvanced: PageController updated to index $correctIndex',
              );
            }
          } else {
            AppLogger.log(
              '⚠️ VideoFeedAdvanced: Video with ID $targetVideoId not found in list of ${_videos.length} videos',
            );
            // Log all video IDs for debugging
            AppLogger.log(
              '📋 VideoFeedAdvanced: Available video IDs: ${_videos.map((v) => v.id).join(", ")}',
            );
          }
        } else {
          AppLogger.log(
            '✅ VideoFeedAdvanced: Current video at index $_currentIndex matches target ID: $targetVideoId',
          );
        }
      }
    }
  }

  void _startVideoPreloading() {
    // **FIX: Ensure screen is visible when opened from ProfileScreen**
    final bool openedFromProfile =
        widget.initialVideos != null && widget.initialVideos!.isNotEmpty;
    if (openedFromProfile) {
      _isScreenVisible = true;
      _ensureWakelockForVisibility();
    }

    // **FIX: For deep links on cold start, verify we're preloading the correct video**
    if (widget.initialVideoId != null &&
        widget.initialVideos == null &&
        _videos.isNotEmpty) {
      final targetVideoId = widget.initialVideoId!.trim();
      if (_currentIndex < _videos.length) {
        final currentVideoId = _videos[_currentIndex].id.trim();
        if (currentVideoId != targetVideoId) {
          // Wrong video at current index, find correct one
          final correctIndex = _videos.indexWhere(
            (v) => v.id.trim() == targetVideoId || v.id == targetVideoId,
          );
          if (correctIndex != -1 && correctIndex != _currentIndex) {
            AppLogger.log(
              '🔧 VideoFeedAdvanced: Correcting index from $_currentIndex to $correctIndex before preload (deep link cold start)',
            );
            _currentIndex = correctIndex;
            if (_pageController.hasClients) {
              _pageController.jumpToPage(correctIndex);
            }
          }
        }
      }
    }

    if (_currentIndex < _videos.length) {
      AppLogger.log(
        '🎬 VideoFeedAdvanced: Starting preload for index $_currentIndex (video ID: ${_videos[_currentIndex].id}, name: ${_videos[_currentIndex].videoName})',
      );
      _preloadVideo(_currentIndex).then((_) {
        if (!mounted) return;

        // **FIX: Don't delay autoplay - let _preloadVideo handle it immediately**
        // The _preloadVideo method now triggers autoplay as soon as controller is ready
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _isColdStart = false;
          AppLogger.log(
            '�� VideoFeedAdvanced: Preload complete for index $_currentIndex',
          );

          // **FALLBACK: Only try autoplay if video still hasn't started playing**
          // Use another postFrameCallback instead of delay to check immediately
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _currentIndex < _videos.length) {
              final String videoId = _videos[_currentIndex].id;
              final controller = _controllerPool[videoId];
              if (controller != null &&
                  controller.value.isInitialized &&
                  !controller.value.isPlaying &&
                  _userPaused[videoId] != true) {
                AppLogger.log(
                    '🔄 VideoFeedAdvanced: Fallback autoplay trigger after preload');
                _tryAutoplayCurrent();
              }
            }
          });
        });
      }).catchError((e) {
        AppLogger.log('❌ Error preloading initial video: $e');
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _isColdStart = false;
          _tryAutoplayCurrent();
        });
      });
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _isColdStart = false;
        _tryAutoplayCurrent();
      });
    }
  }

  void _precacheThumbnails() {
    // **OPTIMIZATION: Limited thumbnail precaching for Yug Tab (Main Feed)**
    // User originally requested none, but now needs them for offline mode.
    // We only precache the first 3 videos to save bandwidth.
    if (!_openedFromProfile && _videos.length > 3) {
      // Just precache the very first few for offline visibility
    }

    Future(() async {
      for (final v in _videos.take(5)) {
        if (v.thumbnailUrl.isNotEmpty) {
          try {
            if (mounted) {
              await precacheImage(
                  CachedNetworkImageProvider(v.thumbnailUrl), context);
            }
          } catch (_) {}
        }
      }
    });
  }

  Future<void> _loadCurrentUserId() async {
    try {
      final authController = ref.read(googleSignInProvider);
      
      // 1. Try GoogleSignInController first
      if (authController.isSignedIn && authController.userData != null) {
        final userId = authController.userData!['googleId'] ?? 
                      authController.userData!['id'];
        if (userId != null) {
          _currentUserId = userId.toString();
          AppLogger.log('✅ Loaded current user ID from auth controller: $_currentUserId');
          return;
        }
      }

      // 2. Fallback to SharedPreferences (Instant lookup)
      final prefs = await SharedPreferences.getInstance();
      final fallbackUserStr = prefs.getString('fallback_user');
      if (fallbackUserStr != null) {
        final userDataList = json.decode(fallbackUserStr);
        final userId = userDataList['googleId'] ?? userDataList['id'];
        if (userId != null) {
          _currentUserId = userId.toString();
          AppLogger.log('✅ Loaded current user ID from storage: $_currentUserId');
        }
      }
    } catch (e) {
      AppLogger.log('❌ Error loading current user ID: $e');
    }
  }

  Future<void> _loadActiveAds() async {
    try {
      AppLogger.log(
          '🎯 VideoFeedAdvanced: Loading fallback ads in background...');

      final allAds = await _activeAdsService.fetchActiveAds();
      final bool wasEmpty = _bannerAds.isEmpty;

      if (mounted) {
        // Use safeSetState to ensure the entire UI is aware of loaded ads
        safeSetState(() {
          _bannerAds = allAds['banner'] ?? [];
          _adsLoaded = true;
          
          // **OPTIMIZED: Only clear locked ads if we didn't have any before**
          // This prevents "ad jumping" for already visible videos when updating list
          if (wasEmpty && _bannerAds.isNotEmpty) {
             _lockedBannerAdByVideoId.clear();
          }
        });

        AppLogger.log('✅ VideoFeedAdvanced: Fallback ads loaded:');
        AppLogger.log('   Banner ads: ${_bannerAds.length}');
      }

      if (mounted && (_bannerAds.isEmpty)) {
        AppLogger.log(
            '⚠️ VideoFeedAdvanced: No banner ads received, retrying in 3s...');
        Future.delayed(const Duration(seconds: 3), () async {
          if (!mounted) return;
          try {
            final retry = await _activeAdsService.fetchActiveAds();
            if (!mounted) return;
            if ((retry['banner'] ?? []).isNotEmpty) {
              final bool wasEmptyAfterDelay = _bannerAds.isEmpty;
              // **OPTIMIZED: Use safeSetState to ensure UI rebuilds with new ads**
              safeSetState(() {
                _bannerAds = retry['banner']!;
                _adsLoaded = true;
                if (wasEmptyAfterDelay) {
                  _lockedBannerAdByVideoId.clear();
                }
              });
              AppLogger.log(
                  '✅ VideoFeedAdvanced: Banner ads loaded on retry: ${_bannerAds.length}');
            }
          } catch (e) {
            AppLogger.log('❌ VideoFeedAdvanced: Retry load ads failed: $e');
          }
        });
      }

      await _carouselAdManager.loadCarouselAds();
      // **REFACTORED: Always load carousel ads regardless of category**
      await _loadCarouselAds();
    } catch (e) {
      AppLogger.log('❌ Error loading fallback ads: $e');
      if (mounted) {
        // **OPTIMIZED: Use ValueNotifier for granular update**
        _adsLoaded = true;
      }
    }
  }

  Future<void> _loadFollowingUsers() async {
    if (_currentUserId == null || _videos.isEmpty) return;

    try {
      final uProvider = ref.read(userProvider);
      final uniqueUploaders = _videos
          .map((video) => video.uploader.id.trim())
          .toSet()
          .where((id) => id.isNotEmpty && id != 'unknown' && id != _currentUserId)
          .toList();

      if (uniqueUploaders.isEmpty) return;

      AppLogger.log(
        '🔍 Batch checking follow status for ${uniqueUploaders.length} unique uploaders',
      );

      // **OPTIMIZED: Single batch API call instead of N individual calls**
      await uProvider.batchCheckFollowStatus(uniqueUploaders);

      AppLogger.log('✅ Batch follow status check complete for ${uniqueUploaders.length} users');
    } catch (e) {
      AppLogger.log('❌ Error loading following users: $e');
    }
  }
}

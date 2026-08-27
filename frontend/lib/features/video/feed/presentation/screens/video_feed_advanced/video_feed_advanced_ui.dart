part of '../video_feed_advanced.dart';

extension _VideoFeedUI on _VideoFeedAdvancedState {
  Widget _buildYugPictureInPicturePlayer() {
    final controller = _currentPictureInPictureController;
    return Scaffold(
      backgroundColor: Colors.black,
      // Intentionally video-only: feed overlays and settings have no useful
      // role inside the small system PiP surface.
      body: controller != null && controller.value.isInitialized
          ? Center(
              child: AspectRatio(
                aspectRatio: _pictureInPictureAspectRatio(controller),
                child: VideoPlayer(controller),
              ),
            )
          : const ColoredBox(color: Colors.black),
    );
  }

  double get _primaryActionHitTargetSize {
    const minTouchTarget = AppSpacing.minTouchTarget;
    const primaryContainer = AppConstants.primaryActionButtonContainerSize;
    return minTouchTarget > primaryContainer
        ? minTouchTarget
        : primaryContainer;
  }

  double get _secondaryActionHitTargetSize {
    const minTouchTarget = AppSpacing.minTouchTarget;
    const secondaryContainer = AppConstants.secondaryActionButtonContainerSize;
    return minTouchTarget > secondaryContainer
        ? minTouchTarget
        : secondaryContainer;
  }

  Widget _buildVideoFeed() {
    return VisibilityDetector(
      key: ObjectKey(this),
      onVisibilityChanged: (visibilityInfo) {
        final double visibleFraction = visibilityInfo.visibleFraction;
        // Determine if screen is truly visible to the user
        final bool isCurrentlyVisible = visibleFraction > 0;
        _handleVisibilityChange(isCurrentlyVisible);
      },
      child: _openedFromProfile
          ? PageView.builder(
              controller: _pageController,
              scrollDirection: Axis.vertical,
              onPageChanged: _onPageChanged,
              itemCount: _getTotalItemCount(),
              itemBuilder: (context, index) {
                return _buildFeedItem(index);
              },
            )
          : RefreshIndicator(
              onRefresh: refreshVideos,
              child: PageView.builder(
                controller: _pageController,
                scrollDirection: Axis.vertical,
                onPageChanged: _onPageChanged,
                itemCount: _getTotalItemCount(),
                itemBuilder: (context, index) {
                  return _buildFeedItem(index);
                },
              ),
            ),
    );
  }

  Widget _buildErrorState() {
    final bool isRefreshingOrLoading = _isLoading || _isRefreshing;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 64, color: AppColors.error),
          AppSpacing.vSpace16,
          Text(
            'Failed to load videos',
            style: TextStyle(
              color: AppColors.white,
              fontSize: AppTypography.fontSizeXL,
              fontWeight: AppTypography.weightBold,
            ),
          ),
          if (_errorMessage != null) ...[
            AppSpacing.vSpace8,
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                _getUserFriendlyErrorMessage(_errorMessage!),
                style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: AppTypography.fontSizeBase),
                textAlign: TextAlign.center,
              ),
            ),
          ],
          AppSpacing.vSpace24,
          AppButton(
            onPressed: refreshVideos,
            icon: isRefreshingOrLoading ? null : const Icon(Icons.refresh),
            label: 'Retry',
            variant: AppButtonVariant.primary,
            isLoading: isRefreshingOrLoading,
          ),
          AppSpacing.vSpace12,
          AppButton(
            onPressed: _testApiConnection,
            icon: const Icon(Icons.wifi_find),
            label: 'Test Connection',
            variant: AppButtonVariant.secondary,
            isDisabled: isRefreshingOrLoading,
          ),
        ],
      ),
    );
  }

  bool _isSecureVideoPreparingError(VideoModel? video, String error) {
    final errorLower = error.toLowerCase();
    final isSecureVideo = video?.isSubscriberOnly == true ||
        errorLower.contains('e2ee_error') ||
        errorLower.contains('secure video is still loading');

    if (!isSecureVideo) return false;

    return errorLower.contains('still loading') ||
        errorLower.contains('source') ||
        errorLower.contains('timeout') ||
        errorLower.contains('videoplayer') ||
        errorLower.contains('videoerror') ||
        errorLower.contains('exoplaybackexception') ||
        errorLower.contains('platformexception');
  }

  // **NEW: Individual Video Error State widget**
  Widget _buildVideoErrorState(int index, String error) {
    final String videoId = index < _videos.length ? _videos[index].id : '';
    final VideoModel? video = index < _videos.length ? _videos[index] : null;
    final String errorLower = error.toLowerCase();
    if (video != null && _isE2eeAuthenticationError(errorLower)) {
      return _buildE2eeSignInState(index);
    }
    if (_isSecureVideoPreparingError(video, error) && video != null) {
      return _buildE2eeDecryptingState(video);
    }

    final bool isE2eeError = errorLower.contains('decoding error') ||
        errorLower.contains('e2ee') ||
        errorLower.contains('decrypt') ||
        errorLower.contains('symmetric key') ||
        errorLower.contains('video-key') ||
        errorLower.contains('e2ee_error');

    if (isE2eeError) {
      // Determine if this is a "still loading" vs "access denied" error
      final bool isStillLoading = errorLower.contains('still loading') ||
          errorLower.contains('timeout') ||
          errorLower.contains('source');

      return Container(
        color: AppColors.backgroundPrimary,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: isStillLoading
                        ? AppColors.primary.withValues(alpha: 0.1)
                        : const Color(0xFFFBBF24).withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isStillLoading
                          ? AppColors.primary.withValues(alpha: 0.2)
                          : const Color(0xFFFBBF24).withValues(alpha: 0.2),
                      width: 1.5,
                    ),
                  ),
                  child: Icon(
                    isStillLoading
                        ? Icons.hourglass_top_rounded
                        : Icons.lock_outline_rounded,
                    color: isStillLoading
                        ? AppColors.primary
                        : const Color(0xFFFBBF24),
                    size: 56,
                  ),
                ),
                AppSpacing.vSpace24,
                Text(
                  isStillLoading
                      ? 'Video Still Loading'
                      : 'End-to-End Encrypted',
                  style: const TextStyle(
                    color: AppColors.white,
                    fontSize: 20,
                    fontWeight: AppTypography.weightBold,
                  ),
                  textAlign: TextAlign.center,
                ),
                AppSpacing.vSpace12,
                // One line only: the retry button and the swipe hint below
                // already cover what to do next.
                Text(
                  isStillLoading
                      ? 'This is taking longer than usual.'
                      : _getUserFriendlyErrorMessage(error),
                  style: TextStyle(
                    color: AppColors.white,
                    fontSize: AppTypography.fontSizeBase,
                    fontWeight: AppTypography.weightSemiBold,
                  ),
                  textAlign: TextAlign.center,
                ),
                AppSpacing.vSpace32,
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(20),
                    border:
                        Border.all(color: Colors.white.withValues(alpha: 0.08)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.swap_vert_rounded,
                        color: AppColors.textTertiary,
                        size: 16,
                      ),
                      AppSpacing.hSpace8,
                      Text(
                        'Swipe up or down to continue watching',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: AppTypography.fontSizeXS,
                          fontWeight: AppTypography.weightMedium,
                        ),
                      ),
                    ],
                  ),
                ),
                AppSpacing.vSpace24,
                AppButton(
                  onPressed: () {
                    safeSetState(() {
                      _videoErrors.remove(videoId);
                      _e2eeDecryptingVideos.remove(videoId);
                      _preloadRetryCount.remove(videoId);
                      _loadingVideos.add(videoId);
                      _isBuffering[videoId] = false;
                      _isBufferingVN[videoId]?.value = false;
                    });
                    _preloadVideo(index).then((_) {
                      if (mounted && index == _currentIndex) {
                        _tryAutoplayCurrentImmediate(index);
                      }
                    });
                  },
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: isStillLoading ? 'Retry Loading' : 'Retry Decryption',
                  variant: AppButtonVariant.secondary,
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      color: AppColors.backgroundPrimary,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.warning_amber_rounded,
                color: AppColors.textSecondary, size: 48),
            AppSpacing.vSpace12,
            const Text(
              'Playback Error',
              style: TextStyle(
                  color: AppColors.white, fontWeight: AppTypography.weightBold),
            ),
            AppSpacing.vSpace4,
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Text(
                _getUserFriendlyErrorMessage(error),
                style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: AppTypography.fontSizeSM),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            AppSpacing.vSpace16,
            AppButton(
              onPressed: () {
                safeSetState(() {
                  _videoErrors.remove(videoId);
                  _e2eeDecryptingVideos.remove(videoId);
                  _preloadRetryCount.remove(videoId);
                  _loadingVideos.add(videoId); // Show spinner
                  _isBuffering[videoId] = false; // Reset buffering state
                  _isBufferingVN[videoId]?.value = false;
                });
                // Always use proxy on manual retry (proxy needed for HLS manifest rewriting)
                _preloadVideo(index).then((_) {
                  if (mounted && index == _currentIndex) {
                    _tryAutoplayCurrentImmediate(index);
                  }
                });
              },
              icon: const Icon(Icons.refresh, size: 16),
              label: 'Retry',
              variant: AppButtonVariant.secondary,
            ),
          ],
        ),
      ),
    );
  }

  bool _isE2eeAuthenticationError(String errorLower) {
    return errorLower.contains('authentication_required') ||
        errorLower.contains('please sign in again') ||
        errorLower.contains('please sign in to watch this encrypted video');
  }

  Widget _buildE2eeSignInState(int index) {
    return Container(
      color: AppColors.backgroundPrimary,
      child: AuthSignInPrompt(
        icon: Icons.lock_outline_rounded,
        title: 'Sign in to watch this video',
        subtitle: 'This end-to-end encrypted video requires an active account.',
        onSignedIn: () => _retryE2eeVideo(index),
      ),
    );
  }

  Future<void> _retryE2eeVideo(int index) async {
    if (!mounted || index >= _videos.length) return;
    final videoId = _videos[index].id;
    safeSetState(() {
      _videoErrors.remove(videoId);
      _e2eeDecryptingVideos.remove(videoId);
      _preloadRetryCount.remove(videoId);
      _loadingVideos.add(videoId);
    });
    await _preloadVideo(index);
    if (mounted && index == _currentIndex) {
      _tryAutoplayCurrentImmediate(index);
    }
  }

  Widget _buildE2eeDecryptingState(VideoModel video) {
    // Get download progress for this video
    final originalUrl = _getActingUrl(video);
    final progressNotifier = videoCacheProxy.getDownloadProgress(originalUrl);
    final bool isDownloading = videoCacheProxy.isDownloadActive(originalUrl);

    return Container(
      color: AppColors.backgroundPrimary,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Blurred thumbnail background
          if (video.thumbnailUrl.isNotEmpty)
            ImageFiltered(
              imageFilter: ImageFilter.blur(
                  sigmaX: 20, sigmaY: 20, tileMode: TileMode.clamp),
              child: CachedNetworkImage(
                imageUrl: video.thumbnailUrl,
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
              ),
            ),
          Container(color: Colors.black.withValues(alpha: 0.68)),
          // Decrypting indicator with progress
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 36),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (progressNotifier != null)
                    ValueListenableBuilder<E2eeDownloadProgress>(
                      valueListenable: progressNotifier,
                      builder: (context, progress, _) {
                        final showProgress = progress.downloadedBytes > 0 &&
                            !progress.isComplete;
                        final isDecrypting =
                            progress.isComplete || !isDownloading;
                        final statusTitle = isDecrypting
                            ? 'Decrypting secure video'
                            : showProgress
                                ? 'Downloading secure video'
                                : 'Preparing secure video';
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Circular progress or shield icon
                            if (showProgress && !isDecrypting)
                              SizedBox(
                                width: 64,
                                height: 64,
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    CircularProgressIndicator(
                                      strokeWidth: 3,
                                      value: progress.fraction > 0
                                          ? progress.fraction.clamp(0.0, 1.0)
                                          : null,
                                      color: AppColors.primary,
                                      backgroundColor: AppColors.primary
                                          .withValues(alpha: 0.15),
                                    ),
                                    const Icon(
                                      Icons.enhanced_encryption_rounded,
                                      color: AppColors.primary,
                                      size: 24,
                                    ),
                                  ],
                                ),
                              )
                            else
                              SizedBox(
                                width: 64,
                                height: 64,
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    CircularProgressIndicator(
                                      strokeWidth: 3,
                                      color: AppColors.primary,
                                      backgroundColor: AppColors.primary
                                          .withValues(alpha: 0.15),
                                    ),
                                    const Icon(
                                      Icons.lock_open_rounded,
                                      color: AppColors.primary,
                                      size: 24,
                                    ),
                                  ],
                                ),
                              ),
                            AppSpacing.vSpace24,
                            Text(
                              statusTitle,
                              style: const TextStyle(
                                color: AppColors.white,
                                fontSize: 20,
                                fontWeight: AppTypography.weightBold,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            if (showProgress && !isDecrypting) ...[
                              AppSpacing.vSpace16,
                              Text(
                                '${progress.downloadedFormatted}${progress.totalFormatted != null ? ' / ${progress.totalFormatted}' : ''}',
                                style: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: AppTypography.fontSizeSM,
                                ),
                              ),
                              if (progress.estimatedTimeFormatted != null) ...[
                                AppSpacing.vSpace4,
                                Text(
                                  'Estimated: ${progress.estimatedTimeFormatted}',
                                  style: TextStyle(
                                    color: AppColors.textTertiary,
                                    fontSize: AppTypography.fontSizeXS,
                                  ),
                                ),
                              ],
                              AppSpacing.vSpace12,
                              // Progress bar
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 24),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(2),
                                  child: LinearProgressIndicator(
                                    value: progress.fraction > 0
                                        ? progress.fraction.clamp(0.0, 1.0)
                                        : null,
                                    minHeight: 3,
                                    backgroundColor:
                                        Colors.white.withValues(alpha: 0.1),
                                    valueColor:
                                        const AlwaysStoppedAnimation<Color>(
                                            AppColors.primary),
                                  ),
                                ),
                              ),
                            ] else ...[
                              AppSpacing.vSpace16,
                              Text(
                                'Please keep this screen open',
                                style: TextStyle(
                                  color: AppColors.textTertiary,
                                  fontSize: AppTypography.fontSizeXS,
                                ),
                              ),
                            ],
                          ],
                        );
                      },
                    )
                  else
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(
                          width: 64,
                          height: 64,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              CircularProgressIndicator(
                                strokeWidth: 3,
                                color: AppColors.primary,
                              ),
                              Icon(
                                Icons.enhanced_encryption_rounded,
                                color: AppColors.primary,
                                size: 24,
                              ),
                            ],
                          ),
                        ),
                        AppSpacing.vSpace24,
                        const Text(
                          'Preparing secure video',
                          style: TextStyle(
                            color: AppColors.white,
                            fontSize: 20,
                            fontWeight: AppTypography.weightBold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.video_library_outlined,
            size: 64,
            color: AppColors.textSecondary,
          ),
          AppSpacing.vSpace16,
          Text(
            'No videos available',
            style: TextStyle(
              color: AppColors.white,
              fontSize: AppTypography.fontSizeXL,
              fontWeight: AppTypography.weightBold,
            ),
          ),
          AppSpacing.vSpace24,
          AppButton(
            onPressed: refreshVideos,
            icon: const Icon(Icons.refresh),
            label: 'Refresh',
            variant: AppButtonVariant.primary,
          ),
          // **NEW: Add debug info button for troubleshooting**
          if (_errorMessage != null && _errorMessage!.isNotEmpty) ...[
            AppSpacing.vSpace12,
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                'Error: ${_errorMessage!.length > 100 ? "${_errorMessage!.substring(0, 100)}..." : _errorMessage!}',
                style: TextStyle(
                  color: AppColors.error,
                  fontSize: AppTypography.fontSizeSM,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ],
      ),
    );
  }

  int _getTotalItemCount() {
    if (_openedFromProfile) {
      return _videos.length;
    }
    // **FIXED: Always add THREE extra items (buffer) to allow scrolling past end**
    // This solves "Blocked Scrolling" issue when next video isn't ready.
    // User can drag into these placeholders, triggering the loader.
    return _videos.length + 3;
  }

  Widget _buildFeedItem(int index) {
    final totalVideos = _videos.length;
    final videoIndex = index;

    // **NEW: Pre-fetch Trigger (Buffer 12 videos - Ultra Aggressive for Fast Scroll)**
    // Trigger load more when user is within 12 videos of the end (approx 80% through batch)
    // This provides a much larger safety buffer for slow backend refills or fast scrolling.

    // **OPTIMIZATION: Adjust trigger for Low-RAM devices**
    final int prefetchThreshold = _isLowEndDevice ? 3 : 12;

    if (mounted &&
        totalVideos > 0 &&
        index >= totalVideos - prefetchThreshold &&
        !_isLoadingMore &&
        !_isRefreshing &&
        _hasMore) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _loadMoreVideos();
      });
    }

    if (videoIndex >= totalVideos) {
      // **SEAMLESS END-OF-FEED ITEM**
      // Show last video as placeholder while new videos load (invisible transition)
      // This creates seamless experience - user sees video, not loading state

      if (totalVideos > 0 && videoIndex == totalVideos) {
        // **Format: First extra item = Copy of Last Video (Seamless)**
        final lastVideoIndex = totalVideos - 1;
        final lastVideo = _videos[lastVideoIndex];
        final lastController = _getController(lastVideoIndex);

        // **IMMEDIATE TRIGGER: Load more videos immediately if not already loading**
        if (mounted && !_isRefreshing && !_isLoadingMore) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            AppLogger.log(
                '📡 UI: End-of-feed reached at index $index. Triggering _loadMoreVideos');
            _loadMoreVideos();
          });
        }

        // Return duplicate of last video for seamless feel
        return _buildVideoItem(
          lastVideo,
          lastController,
          videoIndex ==
              _currentIndex, // **FIX: Allow buffer item to be active**
          lastVideoIndex,
        );
      }

      // **FALLBACK: Loading Skeleton for subsequent items (index > totalVideos)**
      // This gives visual feedback that "more is coming" if user scrolls deep
      return Container(
        width: double.infinity,
        height: double.infinity,
        color: AppColors.backgroundPrimary, // Black background
        child: Center(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            if (_errorMessage != null && _errorMessage!.isNotEmpty) ...[
              const Icon(Icons.cloud_off,
                  size: 48, color: AppColors.textTertiary),
              AppSpacing.vSpace16,
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: Text(
                  _getUserFriendlyErrorMessage(_errorMessage!),
                  style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: AppTypography.fontSizeSM),
                  textAlign: TextAlign.center,
                ),
              ),
              AppSpacing.vSpace24,
              AppButton(
                onPressed: () {
                  safeSetState(() {
                    _errorMessage = null;
                    _loadMoreVideos();
                  });
                },
                icon: const Icon(Icons.refresh, size: 18),
                label: "Retry Loading",
                variant: AppButtonVariant.secondary,
              ),
            ] else ...[
              const SizedBox(
                  width: 30,
                  height: 30,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppColors.primary)),
              AppSpacing.vSpace16,
              Text("Loading more videos...",
                  style: TextStyle(
                      color: AppColors.textTertiary,
                      fontSize: AppTypography.fontSizeSM)),
              // **NEW: Safety Trigger: If we land on this screen, force a reload if not already loading**
              if (mounted && !_isLoadingMore && !_isRefreshing && _hasMore) ...[
                AppSpacing.vSpace8,
                Builder(builder: (_) {
                  WidgetsBinding.instance.addPostFrameCallback((__) {
                    if (!_isLoadingMore) _loadMoreVideos();
                  });
                  return const SizedBox.shrink();
                }),
              ],
            ],
          ]),
        ),
      );
    }

    final video = _videos[videoIndex];
    final controller = _getController(videoIndex);
    final isActive = videoIndex == _currentIndex;

    return _buildVideoItem(video, controller, isActive, videoIndex);
  }

  Widget _buildVideoItem(
    VideoModel video,
    VideoPlayerController? controller,
    bool isActive,
    int index,
  ) {
    final String videoId = video.id;
    _getOrCreateNotifier<int>(_currentHorizontalPage, videoId, 0);

    return Container(
      key: ValueKey(
          'video_${video.id}'), // **FIX: Stable key to prevent player recreation on feed update**
      width: double.infinity,
      height: double.infinity,
      color: AppColors.backgroundPrimary,
      child: Stack(
        children: [
          PageView(
            controller: _horizontalControllers.putIfAbsent(
                videoId,
                () => PageController(
                    initialPage: _currentHorizontalPage[videoId]!.value)),
            onPageChanged: (page) {
              _currentHorizontalPage[videoId]!.value = page;
              if (page == 1) {
                // Pause video when swiping to ad
                _pauseCurrentVideo();
              } else if (page == 0 && isActive) {
                // Resume video when swiping back (if it's the active one)
                _tryAutoplayCurrent();
              }
            },
            physics: const BouncingScrollPhysics(),
            children: [
              _buildVideoPage(video, controller, isActive, index),
              if (_carouselAdManager.shouldShowCarouselAd(index))
                _buildCarouselAdPage(index)
              else
                const SizedBox.shrink(),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildVideoPage(
    VideoModel video,
    VideoPlayerController? controller,
    bool isActive,
    int index,
  ) {
    return _buildVideoPageContent(video, controller, isActive, index);
  }

  Widget _buildVideoPageContent(
    VideoModel video,
    VideoPlayerController? controller,
    bool isActive,
    int index,
  ) {
    final String videoId = video.id;
    // **REACTIVE RECOVERY: Validity is now handled by VideoAspectSurface**
    // We just need to know if we should show the player or a spinner/error.
    bool controllerUsable =
        SharedVideoControllerPool().isControllerValid(controller);

    if (!controllerUsable && controller != null) {
      // If we have a controller but it's invalid (disposed), clear it for this build
      controller = null;
    }

    // **E2EE PREBUFFER STATE: Show "Decrypting..." while waiting for enough bytes**
    if (_e2eeDecryptingVideos.contains(videoId)) {
      return _buildE2eeDecryptingState(video);
    }

    // **NEW: Check for error state**
    // **ZOMBIE AUDIO FIX: Check if error is real or if controller recovered**
    bool showError = _videoErrors.containsKey(videoId);
    // Don't show error while E2EE is still decrypting — prebuffer may resolve it
    if (showError && _e2eeDecryptingVideos.contains(videoId)) {
      showError = false;
    }
    if (showError &&
        controllerUsable &&
        controller != null &&
        !controller.value.hasError) {
      // If controller is playing or has buffered content, it's likely a stale error
      // (e.g. transient network error during load, but retry succeeded)
      if (controller.value.isPlaying || controller.value.buffered.isNotEmpty) {
        // It's working! Ignore the error and schedule cleanup
        showError = false;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _videoErrors.containsKey(videoId)) {
            // AppLogger.log('✅ UI: Auto-recovered from stale error for video $videoId (Controller is healthy)');
            safeSetState(() {
              _videoErrors.remove(videoId);
              // Reset buffering state to be safe
              _isBuffering[videoId] = false;
              _isBufferingVN[videoId]?.value = false;
            });
          }
        });
      }
    }

    if (showError) {
      final error = _videoErrors[videoId]!;
      if (_isSecureVideoPreparingError(video, error)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          safeSetState(() {
            _videoErrors.remove(videoId);
            _e2eeDecryptingVideos.add(videoId);
            _isBuffering[videoId] = false;
            _isBufferingVN[videoId]?.value = false;
          });
        });
        return _buildE2eeDecryptingState(video);
      }

      // **FINAL SAFETY: Ensure controller is paused if we show error**
      try {
        if (controller != null &&
            controllerUsable &&
            controller.value.isPlaying) {
          controller.pause();
        }
      } catch (_) {}
      return _buildVideoErrorState(index, _videoErrors[videoId]!);
    }

    return RepaintBoundary(
      child: Stack(
        fit: StackFit.expand,
        children: [
          // **AMBIENT BACKGROUND: Blurred thumbnail — isolated repaint layer**
          RepaintBoundary(
            child: video.thumbnailUrl.isNotEmpty
                ? ImageFiltered(
                    imageFilter: ImageFilter.blur(
                        sigmaX: 28, sigmaY: 28, tileMode: TileMode.clamp),
                    child: CachedNetworkImage(
                      imageUrl: video.thumbnailUrl,
                      fit: BoxFit.cover,
                      memCacheWidth:
                          180, // Low-res cache — background doesn't need quality
                      width: double.infinity,
                      height: double.infinity,
                    ),
                  )
                : Container(color: AppColors.backgroundPrimary),
          ),
          // **DARK OVERLAY: Ensures video stays as the clear primary focus**
          Container(color: Colors.black.withValues(alpha: 0.55)),
          // **VIDEO + ALL OVERLAYS on top**
          RepaintBoundary(
            child: Stack(
              children: [
                // **THUMBNAIL LAYER: Hides once video starts playing**
                ValueListenableBuilder<VideoPlayerValue>(
                  valueListenable: (controller != null && controllerUsable)
                      ? controller
                      : ValueNotifier(const VideoPlayerValue.uninitialized()),
                  builder: (context, value, child) {
                    // Hide thumbnail if video is initialized AND has started playing or rendering
                    final bool hideThumbnail = value.isInitialized &&
                        (value.isPlaying || value.position > Duration.zero);

                    return AnimatedOpacity(
                      opacity: hideThumbnail ? 0.0 : 1.0,
                      duration: const Duration(milliseconds: 300),
                      child: video.aspectRatio < 1.0
                          ? SizedBox.expand(
                              child: _buildVideoThumbnail(video),
                            )
                          : Align(
                              alignment: Alignment.center,
                              child: AspectRatio(
                                aspectRatio: video.aspectRatio,
                                child: _buildVideoThumbnail(video),
                              ),
                            ),
                    );
                  },
                ),

                // **FEEDBACK: Show spinner while loading, identical to Vayu player**
                if (controller == null || !controllerUsable)
                  Align(
                    alignment: Alignment.center,
                    child: AspectRatio(
                      aspectRatio: video.aspectRatio,
                      child: const Center(
                        child: CircularProgressIndicator(
                          color: AppColors.primary,
                          strokeWidth: 2,
                        ),
                      ),
                    ),
                  ),

                // **SIMPLIFIED: Mount VideoPlayer directly when controller is ready.**

                if (controller != null && controllerUsable)
                  Positioned.fill(
                    child:
                        _buildVideoPlayer(controller, isActive, index, video),
                  ),

                // **NEW: Black semi-transparent overlay when paused**
                Positioned.fill(
                  child: ValueListenableBuilder<bool>(
                    valueListenable: _getOrCreateNotifier<bool>(
                        _userPausedVN, videoId, false),
                    builder: (context, isUserPaused, _) {
                      return IgnorePointer(
                        child: AnimatedOpacity(
                          opacity: isUserPaused ? 1.0 : 0.0,
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeInOut,
                          child: Container(
                            color: Colors.black.withValues(alpha: 0.4),
                          ),
                        ),
                      );
                    },
                  ),
                ),

                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: () => _togglePlayPause(index),
                    onDoubleTap: () => _handleDoubleTapLike(video),
                    onLongPress: () => _showLongPressAd(index),
                    child: const SizedBox.expand(),
                  ),
                ),
                Positioned.fill(
                  child: IgnorePointer(
                    // **OPTIMIZED: Use ValueListenableBuilder for granular updates - avoid setState**
                    child: ValueListenableBuilder<bool>(
                      valueListenable: _getOrCreateNotifier<bool>(
                          _userPausedVN, videoId, false),
                      builder: (context, isUserPaused, _) {
                        return Opacity(
                          opacity: isUserPaused ? 1.0 : 0.0,
                          child: Center(
                            child: Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: AppColors.backgroundSecondary
                                    .withValues(alpha: 0.7),
                                shape: BoxShape.circle,
                                border: Border.all(
                                    color:
                                        AppColors.white.withValues(alpha: 0.5),
                                    width: 2),
                              ),
                              child: const Icon(
                                Icons.play_arrow,
                                color: AppColors.white,
                                size: 36,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),

                Positioned.fill(
                  child: IgnorePointer(
                    child: ValueListenableBuilder<bool>(
                      valueListenable: _getOrCreateNotifier<bool>(
                          _isBufferingVN, videoId, false),
                      builder: (context, isBuffering, _) {
                        // **OPTIMIZED: Listen to userPausedVN too for correct visibility**
                        return ValueListenableBuilder<bool>(
                            valueListenable: _getOrCreateNotifier<bool>(
                                _userPausedVN, videoId, false),
                            builder: (context, isUserPaused, _) {
                              final show = isBuffering && !isUserPaused;
                              return Opacity(
                                opacity: show ? 1.0 : 0.0,
                                child: Stack(
                                  children: [
                                    const Center(
                                      child: CircularProgressIndicator(
                                          color: AppColors.primary,
                                          strokeWidth: 2),
                                    ),
                                    // **NEW: Slow Internet message**
                                    ValueListenableBuilder<bool>(
                                      valueListenable:
                                          _getOrCreateNotifier<bool>(
                                              _isSlowConnectionVN,
                                              videoId,
                                              false),
                                      builder: (context, isSlow, _) {
                                        if (!isSlow) {
                                          return const SizedBox.shrink();
                                        }
                                        return Positioned(
                                          top: 100,
                                          left: 0,
                                          right: 0,
                                          child: Center(
                                            child: GestureDetector(
                                              onTap: () {
                                                // **MANUAL RELOAD: User requested immediate fix**
                                                AppLogger.log(
                                                    '🔄 User manually reloaded video $videoId');
                                                // Reset states
                                                _isSlowConnectionVN[videoId]
                                                    ?.value = false;
                                                _isBufferingVN[videoId]?.value =
                                                    false;
                                                _videoErrors.remove(videoId);
                                                // Trigger reload
                                                _preloadVideo(index);
                                              },
                                              child: Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 16,
                                                  vertical: 10,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: AppColors
                                                      .backgroundSecondary
                                                      .withValues(alpha: 0.8),
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                          AppRadius.xl),
                                                  border: Border.all(
                                                      color: AppColors.white
                                                          .withValues(
                                                              alpha: 0.1)),
                                                ),
                                                child: index < _videos.length
                                                    ? Row(
                                                        mainAxisSize:
                                                            MainAxisSize.min,
                                                        children: [
                                                          const Icon(
                                                            Icons
                                                                .refresh_rounded,
                                                            color:
                                                                AppColors.white,
                                                            size: 18,
                                                          ),
                                                          AppSpacing.hSpace8,
                                                          Text(
                                                            'Trouble playing? Tap to Reload',
                                                            style: TextStyle(
                                                              color: AppColors
                                                                  .white
                                                                  .withValues(
                                                                      alpha:
                                                                          0.9),
                                                              fontSize:
                                                                  AppTypography
                                                                      .fontSizeSM,
                                                              fontWeight:
                                                                  AppTypography
                                                                      .weightSemiBold,
                                                            ),
                                                          ),
                                                        ],
                                                      )
                                                    : const SizedBox.shrink(),
                                              ),
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ],
                                ),
                              );
                            });
                      },
                    ),
                  ),
                ),
                Positioned.fill(
                  child: _buildVideoOverlay(video, index, controller),
                ),
                if (controller != null &&
                    isActive &&
                    (() {
                      try {
                        return controller?.value.isInitialized ?? false;
                      } catch (_) {
                        return false;
                      }
                    }()))
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: _buildVideoProgressBar(controller),
                  ),
                if (_showHeartAnimation[videoId]?.value == true)
                  _buildHeartAnimation(index),
                _buildTopGradientOverlay(),
                ValueListenableBuilder<List<Map<String, dynamic>>>(
                  valueListenable: _bannerAdsVN,
                  builder: (context, bannerAds, _) {
                    return Positioned(
                      top: MediaQuery.of(context).padding.top + 4,
                      left: 8,
                      right: 8,
                      child: _buildBannerAd(video, index),
                    );
                  },
                ),
                Positioned.fill(
                  child: ValueListenableBuilder<bool>(
                    valueListenable: _showLongPressAdOverlayVN,
                    builder: (context, showOverlay, _) {
                      if (!showOverlay || index != _currentIndex) {
                        return const SizedBox.shrink();
                      }
                      return _buildLongPressAdContent(index);
                    },
                  ),
                ),

                // **PAUSE AD: Attached per-video so it scrolls with the video**
                Positioned.fill(
                  child: ValueListenableBuilder<bool>(
                    valueListenable: _getOrCreateNotifier<bool>(
                        _showPauseAdOverlayPerVideoVN, videoId, false),
                    builder: (context, showOverlay, _) {
                      if (!showOverlay) {
                        return const SizedBox.shrink();
                      }
                      return _buildLongPressAdContent(index, isPauseAd: true);
                    },
                  ),
                ),

                // Quiz Overlay is now handled inside _buildVideoOverlay for proper bottom alignment
              ],
            ),
          ), // closes inner RepaintBoundary (video + overlays)
        ], // closes ambient Stack children
      ), // closes outer RepaintBoundary
    );
  }

  Widget _buildTopGradientOverlay() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      height: 200, // Top 20-25% approximately
      child: RepaintBoundary(
        child: IgnorePointer(
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  AppColors.backgroundPrimary.withValues(alpha: 0.4),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeartAnimation(int index) {
    final notifier = _showHeartAnimation[index];
    if (notifier == null) {
      return const SizedBox.shrink();
    }
    return RepaintBoundary(child: HeartAnimation(showNotifier: notifier));
  }

  Widget _buildReportIndicator(int index) {
    final String videoId =
        (index >= 0 && index < _videos.length) ? _videos[index].id : '';
    return RepaintBoundary(
      child: AnimatedOpacity(
        opacity: 0.8,
        duration: const Duration(milliseconds: 300),
        child: GestureDetector(
          onTap: () => _openReportDialog(videoId),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.backgroundSecondary.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(
                  color: AppColors.white.withValues(alpha: 0.1), width: 0.5),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Report',
                  style: TextStyle(
                    color: AppColors.white,
                    fontSize: AppTypography.fontSizeSM,
                    fontWeight: AppTypography.weightSemiBold,
                  ),
                ),
                AppSpacing.hSpace4,
                const Icon(Icons.arrow_forward_ios,
                    color: AppColors.white, size: 10),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBannerAd(VideoModel video, int index) {
    // **DEBUG: Track ad state**
    AppLogger.log(
        '📺 UI: _buildBannerAd calling for video $index. AdsLoaded: $_adsLoaded, BannerAds: ${_bannerAds.length}');

    // **FIXED: Prepare custom ad data for fallback (even when AdMob is configured)**
    Map<String, dynamic>? adData;

    if (_lockedBannerAdByVideoId.containsKey(video.id)) {
      adData = _lockedBannerAdByVideoId[video.id];
    } else if (_adsLoaded && _bannerAds.isNotEmpty) {
      // **ROAS IMPROVEMENT: Contextual Ad Matching**
      // Attempt to match ad keywords with video title/description
      Map<String, dynamic>? matchedAd;

      try {
        final videoTitle = video.videoName.toLowerCase();
        final videoDesc = (video.description ?? '').toLowerCase();

        // 1. Search for matching ad
        for (final ad in _bannerAds) {
          final keywords = ad['targetKeywords'];
          if (keywords != null) {
            final List<String> targetWords = (keywords is List)
                ? keywords.map((e) => e.toString().toLowerCase()).toList()
                : keywords
                    .toString()
                    .split(',')
                    .map((e) => e.trim().toLowerCase())
                    .toList();

            for (final word in targetWords) {
              if (word.isNotEmpty &&
                  (videoTitle.contains(word) || videoDesc.contains(word))) {
                matchedAd = ad;
                break;
              }
            }
          }
          if (matchedAd != null) break;
        }
      } catch (e) {
        // AppLogger.log('⚠️ Error in contextual ad matching: $e');
      }

      // 2. Fallback to Round-Robin if no match found
      if (matchedAd == null) {
        final adIndex = index % _bannerAds.length;
        if (adIndex < _bannerAds.length) {
          matchedAd = _bannerAds[adIndex];
        }
      }

      // 3. Lock the selected ad for consistency
      if (matchedAd != null) {
        adData = matchedAd;
        _lockedBannerAdByVideoId[video.id] = adData;
      }
    } else if (_adsLoaded && _bannerAds.isEmpty) {
      // **FIX: If ads are confirmed loaded but empty, hide the section entirely**
      // This avoids showing a "Sponsored" placeholder when no ads exist.
      return const SizedBox.shrink();
    }

    // Prepare ad data map with videoId if available
    Map<String, dynamic>? adDataWithVideoId;
    if (adData != null) {
      adDataWithVideoId = {
        ...adData,
        'videoId': video.id,
        'creatorId': video.uploader.id, // **NEW: Pass creatorId for checking**
      };
    }

    // **FIXED: Always pass custom ad data to BannerAdSection for fallback**
    // BannerAdSection will try AdMob first, then fallback to custom ads
    return BannerAdSection(
      adData: adDataWithVideoId, // **FIXED: Pass custom ad data for fallback**
      adService: _activeAdsService,
      onVideoPause: () {
        // Pause the currently playing video while the browser is open
        final videoId = index < _videos.length ? _videos[index].id : null;
        if (videoId != null && _controllerPool.containsKey(videoId)) {
          _controllerPool[videoId]!.pause();
        }
      },
      onVideoResume: () {
        // Resume the video when the browser is closed (if still active)
        final videoId = index < _videos.length ? _videos[index].id : null;
        if (videoId != null && _controllerPool.containsKey(videoId)) {
          if (!_shouldAutoplayForContext('ad resume')) return;
          _playWithPolicy(_controllerPool[videoId]!, 'banner ad resume');
        }
      },
      onClick: () async {
        AppLogger.log('🖱️ Banner ad clicked on video $index');
        if (index < _videos.length && adData != null) {
          final video = _videos[index];
          final adId = adData['_id'] ?? adData['id'];
          final userData = await _authService.getUserData();

          if (adId != null &&
              userData != null &&
              userData['id'] != video.uploader.id) {
            try {
              await _adImpressionService.trackAdClick(
                videoId: video.id,
                adId: adId.toString(),
                userId: userData['id'],
                adType: 'banner',
              );
            } catch (e) {
              AppLogger.log('❌ Error tracking banner ad click: $e');
            }
          }
        }
      },
      onImpression: () async {
        // **PERFORMANCE FIX: Only track impression for the CURRENTLY ACTIVE video**
        // PageView builds adjacent items (index-1, index+1), but we shouldn't track them
        // until the user actually scrolls to them and they become the primary focus.
        if (index == _currentIndex &&
            _isScreenVisible &&
            index < _videos.length &&
            adData != null) {
          final video = _videos[index];
          final adId = adData['_id'] ?? adData['id'];
          final userData = await _authService.getUserData();

          if (adId != null && userData != null) {
            // **NEW: Check if viewer is the creator**
            if (userData['id'] == video.uploader.id) {
              AppLogger.log('🚫 UI: Self-impression prevented (video owner)');
              return;
            }

            try {
              await _adImpressionService.trackBannerAdImpression(
                videoId: video.id,
                adId: adId.toString(),
                userId: userData['id'],
              );
            } catch (e) {
              AppLogger.log('❌ Error tracking banner ad impression: $e');
            }
          }
        }
      },
    );
  }

  Widget _buildVideoProgressBar(VideoPlayerController controller) {
    // **CRASH-PROOF: Atomic check before passing to progress bar**
    final sharedPool = SharedVideoControllerPool();
    if (!sharedPool.isControllerValid(controller)) {
      return const SizedBox.shrink();
    }

    return RepaintBoundary(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final screenWidth = constraints.maxWidth;
          return ThrottledProgressBar(
            key: ValueKey('progress_${controller.hashCode}'),
            controller: controller,
            screenWidth: screenWidth,
            onSeek: (details) => _seekToPosition(controller, details),
          );
        },
      ),
    );
  }

  Widget _buildVideoPlayer(
    VideoPlayerController controller,
    bool isActive,
    int index,
    VideoModel video,
  ) {
    // **CRASH-PROOF: Final check before building the player widget**
    final sharedPool = SharedVideoControllerPool();
    if (sharedPool.isControllerDisposed(controller)) {
      return const Center(
        child: CircularProgressIndicator(
          color: AppColors.primary,
          strokeWidth: 2,
        ),
      );
    }

    try {
      if (!controller.value.isInitialized) {
        return const Center(
          child: CircularProgressIndicator(
            color: AppColors.primary,
            strokeWidth: 2,
          ),
        );
      }
    } catch (_) {
      return const Center(
        child: CircularProgressIndicator(
          color: AppColors.primary,
          strokeWidth: 2,
        ),
      );
    }

    final String langCode = _selectedAudioLanguage[video.id] ?? 'default';

    return KeyedSubtree(
      key: isActive ? _pictureInPictureSourceKey : null,
      child: RepaintBoundary(
        key: ValueKey('player_${video.id}_${langCode}_${controller.hashCode}'),
        child: Hero(
          tag: 'video_player_${video.id}_$langCode',
          child: _buildVideoWithCorrectAspectRatio(
            controller,
            video,
          ),
        ),
      ),
    );
  }

  Widget _buildVideoWithCorrectAspectRatio(
    VideoPlayerController controller,
    VideoModel currentVideo,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenWidth = constraints.maxWidth;
        final screenHeight = constraints.maxHeight;

        // **FIX: Prioritize detected aspect ratio from video controller**
        // Metadata in the model may incorrectly identify landscape videos as portrait in vertical feeds.
        final double detectedRatio = _getDetectedAspectRatio(controller);
        double modelAspectRatio = detectedRatio > 0
            ? detectedRatio
            : (currentVideo.aspectRatio > 0
                ? currentVideo.aspectRatio
                : 9 / 16);

        // final Size videoSize = controller.value.size; // Unused
        // final int rotation = controller.value.rotationCorrection; // Unused

        // _debugAspectRatio(controller); // Disabled for performance

        // **FIX: Use model aspect ratio to determine portrait vs landscape**
        // Portrait videos have aspect ratio < 1.0 (height > width)
        // Landscape videos have aspect ratio >= 1.0 (width >= height)
        if (modelAspectRatio < 1.0) {
          return _buildPortraitVideoFromModel(
            controller,
            screenWidth,
            screenHeight,
            modelAspectRatio,
            currentVideo,
          );
        } else {
          return _buildLandscapeVideoFromModel(
            controller,
            screenWidth,
            screenHeight,
            modelAspectRatio,
            currentVideo,
          );
        }
      },
    );
  }

  // _isPortraitVideo removed (unused)

  /// **Get detected aspect ratio from video controller**
  /// This ensures videos display in their original aspect ratio even if model doesn't have one
  double _getDetectedAspectRatio(VideoPlayerController controller) {
    try {
      final Size videoSize = controller.value.size;
      final int rotation = controller.value.rotationCorrection;

      double videoWidth = videoSize.width;
      double videoHeight = videoSize.height;

      if (rotation == 90 || rotation == 270) {
        videoWidth = videoSize.height;
        videoHeight = videoSize.width;
      }

      if (videoWidth > 0 && videoHeight > 0) {
        final double aspectRatio = videoWidth / videoHeight;
        return aspectRatio > 0
            ? aspectRatio
            : 9.0 / 16.0; // Fallback if invalid
      }
    } catch (e) {
      AppLogger.log('⚠️ Error detecting aspect ratio: $e');
    }
    return 9.0 / 16.0; // Final fallback
  }

  Widget _buildPortraitVideoFromModel(
    VideoPlayerController controller,
    double screenWidth,
    double screenHeight,
    double modelAspectRatio,
    VideoModel currentVideo,
  ) {
    AppLogger.log(
      '🎬 MODEL Portrait video - Aspect Ratio: $modelAspectRatio',
    );

    // **CRASH-PROOF: Final check before VideoPlayer widget hits the tree**
    if (SharedVideoControllerPool().isControllerDisposed(controller)) {
      return const SizedBox.shrink();
    }

    return VideoAspectSurface(
      key: ValueKey('vas_p_${controller.hashCode}'),
      controller: controller,
      modelAspectRatio: modelAspectRatio,
      onControllerInvalid: () => _handleControllerInvalid(
          _videos.indexWhere((v) => v.id == currentVideo.id)),
    );
  }

  // _debugAspectRatio removed (unused)

  Widget _buildLandscapeVideoFromModel(
    VideoPlayerController controller,
    double screenWidth,
    double screenHeight,
    double modelAspectRatio,
    VideoModel currentVideo,
  ) {
    // Simplification for release build
    // AppLogger.log('🎬 MODEL Landscape video - Aspect Ratio: $modelAspectRatio');

    // **CRASH-PROOF: Final check before VideoPlayer widget hits the tree**
    if (SharedVideoControllerPool().isControllerDisposed(controller)) {
      return const SizedBox.shrink();
    }

    return Align(
      alignment:
          Alignment.center, // **FIX: Center horizontal videos vertically**
      child: VideoAspectSurface(
        key: ValueKey('vas_l_${controller.hashCode}'),
        controller: controller,
        modelAspectRatio: modelAspectRatio,
        onControllerInvalid: () => _handleControllerInvalid(
            _videos.indexWhere((v) => v.id == currentVideo.id)),
      ),
    );
  }

  /// **WEB FIX: Build video player widget with explicit sizing for web compatibility**

  // Debug logic removed for release build
  // void _debugAspectRatio(VideoPlayerController controller) { ... }

  Widget _buildVideoThumbnail(VideoModel video) {
    if (video.thumbnailUrl.isEmpty) {
      return Container(color: AppColors.backgroundPrimary);
    }

    return CachedNetworkImage(
      imageUrl: video.thumbnailUrl,
      fit: BoxFit.cover,
      fadeInDuration: Duration.zero, // **ZERO-BLINK: Remove fade-in delay**
      fadeOutDuration: Duration.zero,
      placeholder: (context, url) =>
          Container(color: AppColors.backgroundPrimary),
      errorWidget: (context, url, error) => Container(
        color: AppColors.backgroundPrimary,
        child: const Icon(
          Icons.video_camera_back_outlined,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }

  Widget _buildVideoOverlay(
      VideoModel video, int index, VideoPlayerController? controller) {
    final sharedPool = SharedVideoControllerPool();
    // **REELS/SHORTS STYLE: Position at absolute bottom with zero spacing**
    return Builder(
      builder: (context) {
        final mediaQuery = MediaQuery.of(context);
        // **ENHANCED: Standardized bottom padding**
        // Ensure UI stays at a safe distance from the bottom edge.
        final double systemBottomPadding = mediaQuery.padding.bottom;
        final double bottomPadding = systemBottomPadding > 14
            ? systemBottomPadding + 5 // Reduced from 15
            : 14.0; // Reduced from 30

        Widget overlayContent = RepaintBoundary(
          child: Stack(
            children: [
              // **NEW: Bottom soft gradient for text readability**
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                height: 200, // Enough to cover caption and action buttons
                child: IgnorePointer(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          AppColors.backgroundPrimary.withValues(alpha: 0.55),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                // **FIX: Adjust bottom padding if Visit Now button is present (approx 55px height)**
                bottom: (video.link?.isNotEmpty == true)
                    ? bottomPadding + 65
                    : bottomPadding,
                left: 0,
                // **FIX: Reserve dynamic space for right-side action column**
                // Prevents "Right overflowed by X pixels" on some devices.
                right: _secondaryActionHitTargetSize + 40,
                child: ValueListenableBuilder<QuizModel?>(
                  valueListenable: _activeQuizVN,
                  builder: (context, activeQuiz, _) {
                    final bool isQuizVisible =
                        activeQuiz != null && index == _currentIndex;
                    return AnimatedOpacity(
                      duration: const Duration(milliseconds: 250),
                      opacity: isQuizVisible ? 0.0 : 1.0,
                      child: IgnorePointer(
                        ignoring: isQuizVisible,
                        child: Container(
                          padding: const EdgeInsets.fromLTRB(
                              12, 8, 12, 4), // **FIX: Tighter bottom padding**
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () => _navigateToCreatorProfile(video),
                                child: Row(
                                  children: [
                                    GestureDetector(
                                      behavior: HitTestBehavior.opaque,
                                      onTap: () =>
                                          _navigateToCreatorProfile(video),
                                      child: Container(
                                        width: AppConstants.avatarRadius * 2,
                                        height: AppConstants.avatarRadius * 2,
                                        decoration: const BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: AppColors.textSecondary,
                                        ),
                                        child: video
                                                .uploader.profilePic.isNotEmpty
                                            ? ClipOval(
                                                child: CachedNetworkImage(
                                                  imageUrl:
                                                      video.uploader.profilePic,
                                                  fit: BoxFit.cover,
                                                  placeholder: (context, url) =>
                                                      Container(
                                                    color:
                                                        AppColors.borderPrimary,
                                                    child: Center(
                                                      child: Text(
                                                        video.uploader.name
                                                                .isNotEmpty
                                                            ? video.uploader
                                                                .name[0]
                                                                .toUpperCase()
                                                            : 'U',
                                                        style: TextStyle(
                                                          color:
                                                              AppColors.white,
                                                          fontWeight:
                                                              AppTypography
                                                                  .weightBold,
                                                          fontSize:
                                                              AppTypography
                                                                  .fontSizeXS,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                  errorWidget:
                                                      (context, url, error) =>
                                                          Container(
                                                    color:
                                                        AppColors.borderPrimary,
                                                    child: Center(
                                                      child: Text(
                                                        video.uploader.name
                                                                .isNotEmpty
                                                            ? video.uploader
                                                                .name[0]
                                                                .toUpperCase()
                                                            : 'U',
                                                        style: TextStyle(
                                                          color:
                                                              AppColors.white,
                                                          fontWeight:
                                                              AppTypography
                                                                  .weightBold,
                                                          fontSize:
                                                              AppTypography
                                                                  .fontSizeXS,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              )
                                            : Center(
                                                child: Text(
                                                  video.uploader.name.isNotEmpty
                                                      ? video.uploader.name[0]
                                                          .toUpperCase()
                                                      : 'U',
                                                  style: TextStyle(
                                                    color: AppColors.white,
                                                    fontWeight: AppTypography
                                                        .weightBold,
                                                    fontSize: AppTypography
                                                        .fontSizeXS,
                                                  ),
                                                ),
                                              ),
                                      ),
                                    ),
                                    AppSpacing.hSpace4 /* closest */,
                                    Flexible(
                                      fit: FlexFit.tight,
                                      child: GestureDetector(
                                        onTap: () =>
                                            _navigateToCreatorProfile(video),
                                        child: Text(
                                          video.uploader.name,
                                          style: TextStyle(
                                            color: AppColors.white,
                                            fontSize: AppTypography
                                                .fontSizeBase, // Increased from 12
                                            fontWeight: AppTypography
                                                .weightSemiBold, // Bold
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ),
                                    AppSpacing.hSpace4 /* closest */,
                                    Consumer(
                                      builder: (context, ref, _) {
                                        final bool isFollowing = ref
                                            .watch(userProvider)
                                            .isFollowingUser(video.uploader.id);
                                        return SubscribeButtonWidget(
                                          isSubscribed: isFollowing,
                                          onPressed: () => _handleFollow(video),
                                        );
                                      },
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 6),
                              GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () => _showVideoDetailsBottomSheet(
                                    context, video),
                                child: Text(
                                  video.videoName,
                                  style: TextStyle(
                                    color: AppColors.white,
                                    fontSize: AppTypography
                                        .fontSizeSM, // Slightly increased
                                    fontWeight:
                                        AppTypography.weightRegular, // Lighter
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              AppSpacing.vSpace4,
                              // Visit Now moved to Positioned stack for visibility control
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              Positioned(
                right: 12,
                bottom:
                    bottomPadding, // Only SafeArea padding, no extra spacing
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _buildReportIndicator(index),
                    AppSpacing.vSpace16,
                    _buildLikeButton(video, index),
                    AppSpacing.vSpace12,
                    _buildAudioDubbingButton(video, index),
                    AppSpacing.vSpace12,
                    _buildVerticalActionButton(
                      icon: Icons.share,
                      onTap: () => _handleShare(video),
                    ),
                    AppSpacing.vSpace12,
                    if (video.episodes != null && video.episodes!.isNotEmpty)
                      _buildVerticalActionButton(
                        icon: Icons.playlist_play_rounded,
                        onTap: () => _showEpisodeList(context, video),
                        labelOverride: 'Episode',
                        isPrimary: true, // **Match Like button size**
                      ),
                  ],
                ),
              ),
            ],
          ),
        );

        // **VISIT NOW PROTECTION: Always show button if it exists, even if overlay hides**
        final visitNowButton = (video.link?.isNotEmpty == true)
            ? Padding(
                padding: EdgeInsets.only(
                  left: 16,
                  bottom: bottomPadding + 16,
                ),
                child: SizedBox(
                  width: (_screenWidth ?? MediaQuery.of(context).size.width) *
                      0.75,
                  child: AppButton(
                    label: 'Visit Now',
                    onPressed: () => _handleVisitNow(video),
                    icon: const Icon(Icons.open_in_new,
                        size: 14, color: AppColors.white),
                    variant: AppButtonVariant.secondary,
                    size: AppButtonSize.small,
                  ),
                ),
              )
            : const SizedBox.shrink();

        final bool isYugTab = widget.videoType == 'yog';
        if (!isYugTab || controller == null) {
          return Stack(
            children: [
              overlayContent,
              Positioned(left: 0, bottom: 0, child: visitNowButton),
            ],
          );
        }

        // Get or create the force-show notifier for this video
        final forceShowNotifier =
            _forceShowOverlayVN[video.id] ??= ValueNotifier<bool>(false);

        // **CRASH-PROOF: Don't listen to disposed controllers. If disposed, trigger a re-fetch.**
        if (SharedVideoControllerPool().isControllerDisposed(controller)) {
          // Trigger a re-fetch for the next frame
          Future.microtask(() {
            if (mounted) {
              _getController(index);
              safeSetState(() {});
            }
          });
          return overlayContent;
        }

        return ValueListenableBuilder<QuizModel?>(
          valueListenable: _activeQuizVN,
          builder: (context, activeQuiz, _) {
            final bool isQuizVisible =
                activeQuiz != null && index == _currentIndex;

            return ValueListenableBuilder<bool>(
              valueListenable: forceShowNotifier,
              builder: (context, forceShow, _) {
                // **CRASH-PROOF: Sequential safety check**
                if (!sharedPool.isControllerValid(controller)) {
                  Future.microtask(() {
                    if (mounted) {
                      _getController(index);
                      safeSetState(() {});
                    }
                  });
                  return overlayContent;
                }

                return ListenableBuilder(
                  listenable: controller,
                  builder: (context, _) {
                    try {
                      if (sharedPool.isControllerDisposed(controller)) {
                        return overlayContent;
                      }

                      final value = controller.value;
                      final bool isPlaying = value.isPlaying;

                      // If quiz is visible, only hide overlay when video is playing.
                      // If video is paused, we want all the action buttons to appear!
                      final bool hideOverlayForQuiz =
                          isQuizVisible && isPlaying;
                      final bool shouldShow =
                          (forceShow || !isPlaying) && !hideOverlayForQuiz;

                      Widget contentWithVisibility = AnimatedOpacity(
                        opacity: shouldShow ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                        child: IgnorePointer(
                          ignoring: !shouldShow,
                          child: overlayContent,
                        ),
                      );

                      // Compact state when video is paused (to prevent overlapping the vertical actions bar on the right side)
                      final bool isCompact = !isPlaying;

                      final double targetBottom = isQuizVisible
                          ? bottomPadding + (isCompact ? 10.0 : 20.0)
                          : bottomPadding + 16.0;

                      final double targetRight = isCompact ? 80.0 : 16.0;

                      return Stack(
                        children: [
                          contentWithVisibility,

                          // Unified Quiz & CTA Column positioned reactively at the bottom
                          AnimatedPositioned(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.fastOutSlowIn,
                            left: 16,
                            right: targetRight,
                            bottom: targetBottom,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment
                                  .stretch, // Matches both widths perfectly!
                              children: [
                                if (video.link?.isNotEmpty == true)
                                  AppButton(
                                    label: 'Visit Now',
                                    onPressed: () => _handleVisitNow(video),
                                    icon: const Icon(Icons.open_in_new,
                                        size: 14, color: AppColors.white),
                                    variant: AppButtonVariant.secondary,
                                    size: AppButtonSize.small,
                                  ),
                                if (isQuizVisible) ...[
                                  const SizedBox(height: 12.0),
                                  QuizOverlay(
                                    quiz: activeQuiz,
                                    isCompact: isCompact, // Set compact mode
                                    onDismiss: () => _activeQuizVN.value = null,
                                    onBack: () {
                                      final String videoId = video.id;
                                      _quizEngine.removeLastHistory(videoId);
                                      final history =
                                          _quizEngine.getHistory(videoId);
                                      if (history.isNotEmpty) {
                                        _activeQuizVN.value = history.last;
                                      } else {
                                        _activeQuizVN.value = null;
                                      }
                                    },
                                    onAnswered: (int answerIndex) {
                                      _quizEngine.submitAnswer(
                                          video.id, activeQuiz, answerIndex);
                                    },
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      );
                    } catch (e) {
                      return overlayContent;
                    }
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  ValueNotifier<bool> _getLikeNotifier(VideoModel video) {
    return _getOrCreateNotifier<bool>(_isLikedVN, video.id, video.isLiked);
  }

  ValueNotifier<int> _getLikeCountNotifier(VideoModel video) {
    return _getOrCreateNotifier<int>(_likeCountVN, video.id, video.likes);
  }

  Widget _buildLikeButton(VideoModel video, int index) {
    return ValueListenableBuilder<bool>(
      valueListenable: _getLikeNotifier(video),
      builder: (context, isLiked, _) {
        return ValueListenableBuilder<int>(
          valueListenable: _getLikeCountNotifier(video),
          builder: (context, likeCount, _) {
            // **NEW: Using LikeButton for burst animation**
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                LikeButton(
                  size: AppConstants.primaryActionButtonContainerSize,
                  isLiked: isLiked,
                  circleColor: const CircleColor(
                    start: Color(0xff00ddff),
                    end: Color(0xff0099cc),
                  ),
                  bubblesColor: const BubblesColor(
                    dotPrimaryColor: Color(0xff33b5e5),
                    dotSecondaryColor: Color(0xff0099cc),
                  ),
                  likeBuilder: (bool isLiked) {
                    return Center(
                      child: Container(
                        width: AppConstants.primaryActionButtonContainerSize,
                        height: AppConstants.primaryActionButtonContainerSize,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: AppColors.backgroundSecondary
                              .withValues(alpha: 0.7),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.shadowSecondary
                                  .withValues(alpha: 0.2),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Icon(
                          isLiked ? Icons.favorite : Icons.favorite_border,
                          color: isLiked ? AppColors.error : AppColors.white,
                          size: AppConstants.primaryActionButtonSize,
                          shadows: const [
                            Shadow(
                              color: AppColors.overlayMedium,
                              blurRadius: 4,
                              offset: Offset(0, 2),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                  onTap: (bool isLiked) async {
                    await _handleLike(video);
                    return !isLiked;
                  },
                ),
                if (widget.videoType != 'yog') ...[
                  AppSpacing.vSpace4,
                  Text(
                    _formatCount(likeCount),
                    style: TextStyle(
                      color: AppColors.white,
                      fontSize: AppTypography.fontSizeSM,
                      fontWeight: AppTypography.weightMedium,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildAudioDubbingButton(VideoModel video, int index) {
    final videoId = video.id;
    final resultVN = _getOrCreateNotifier<DubbingResult>(
      _dubbingResultsVN,
      videoId,
      const DubbingResult(status: DubbingStatus.idle),
    );

    return ValueListenableBuilder<DubbingResult>(
      valueListenable: resultVN,
      builder: (context, result, _) {
        final bool isDubbed = result.isDone && result.dubbedUrl != null;
        final bool isProcessing =
            result.status != DubbingStatus.idle && !result.isDone;

        IconData icon = Icons.multitrack_audio_rounded;
        Color iconColor = AppColors.white;
        String label = AppConstants.audioButtonLabel;

        if (isProcessing) {
          icon = Icons.hourglass_empty_rounded;
          iconColor = AppColors.primary;
          label = '${result.progress}%';
        } else if (isDubbed) {
          icon = Icons.volume_up_rounded;
          iconColor = AppColors.primary;
        }

        return _buildVerticalActionButton(
          icon: icon,
          onTap: () => _onAudioDubTap(video),
          color: iconColor,
          labelOverride: label,
        );
      },
    );
  }

  Widget _buildVerticalActionButton({
    required IconData icon,
    required VoidCallback onTap,
    Color color = AppColors.white,
    int? count,
    String? labelOverride,
    bool isPrimary = false,
  }) {
    final containerSize = isPrimary
        ? AppConstants.primaryActionButtonContainerSize
        : AppConstants.secondaryActionButtonContainerSize;
    final iconSize = isPrimary
        ? AppConstants.primaryActionButtonSize
        : AppConstants.secondaryActionButtonSize;
    final hitTargetSize =
        isPrimary ? _primaryActionHitTargetSize : _secondaryActionHitTargetSize;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: hitTargetSize,
            height: hitTargetSize,
            child: Center(
              child: Container(
                width: containerSize,
                height: containerSize,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.backgroundSecondary.withValues(alpha: 0.7),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.shadowSecondary.withValues(alpha: 0.2),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Icon(
                  icon,
                  color: color,
                  size: iconSize,
                  shadows: const [
                    Shadow(
                      color: AppColors.overlayDark,
                      blurRadius: 4,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (count != null || labelOverride != null) ...[
            AppSpacing.vSpace4,
            Text(
              labelOverride ?? _formatCount(count!),
              style: TextStyle(
                color: AppColors.white,
                fontSize: AppTypography.fontSizeXS,
                fontWeight: AppTypography.weightSemiBold,
                shadows: const [
                  Shadow(
                    offset: Offset(0, 1),
                    blurRadius: 2,
                    color: AppColors.overlayDark,
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _formatCount(int count) {
    if (count < 1000) {
      return count.toString();
    } else if (count < 1000000) {
      return '${(count / 1000).toStringAsFixed(1)}K';
    } else {
      return '${(count / 1000000).toStringAsFixed(1)}M';
    }
  }

  Widget _buildCarouselAdPage(int videoIndex) {
    final carouselAd = _carouselAdManager.getCarouselAdForIndex(videoIndex);
    if (carouselAd == null) {
      return Container(
        width: double.infinity,
        height: double.infinity,
        color: AppColors.backgroundPrimary,
        child: const Center(
          child: Text(
            'No carousel ads available',
            style: TextStyle(color: AppColors.white),
          ),
        ),
      );
    }

    String? videoId;
    if (videoIndex < _videos.length) {
      videoId = _videos[videoIndex].id;
    }

    return CarouselAdWidget(
      carouselAd: carouselAd,
      videoId: videoId,
      onVideoPause: () {
        // Pause the currently playing video while the browser is open
        if (videoId != null && _controllerPool.containsKey(videoId)) {
          _controllerPool[videoId]!.pause();
        }
      },
      onVideoResume: () {
        // Resume the video when the browser is closed (if still active)
        if (videoId != null && _controllerPool.containsKey(videoId)) {
          if (!_shouldAutoplayForContext('carousel ad resume')) return;
          _playWithPolicy(_controllerPool[videoId]!, 'carousel ad resume');
        }
      },
      onAdClosed: () {
        if (videoId != null && _currentHorizontalPage.containsKey(videoId)) {
          _currentHorizontalPage[videoId]!.value = 0;
        }
      },
      autoPlay: true,
    );
  }

  /// **LONG-PRESS AD OVERLAY: Show carousel ad image on long press**
  void _showLongPressAd(int index) async {
    final carouselAd = _carouselAdManager.getCarouselAdForIndex(index);
    if (carouselAd == null || carouselAd.slides.isEmpty) return;

    _showLongPressAdOverlayVN.value = true;

    // **NEW: Track popup ad impression**
    if (index < _videos.length) {
      final video = _videos[index];
      final adId = carouselAd.id;
      final userData = await _authService.getUserData();

      if (userData != null) {
        // Prevent self-impressions
        if (userData['id'] != video.uploader.id) {
          try {
            await _adImpressionService.trackCarouselAdImpression(
              videoId: video.id,
              adId: adId,
              userId: userData['id'],
              scrollPosition: 0, // Popup is considered position 0
            );
          } catch (e) {
            AppLogger.log('❌ Error tracking popup ad impression: $e');
          }
        }
      }
    }

    // Auto-hide after 3 seconds
    _longPressAdAutoHideTimer?.cancel();
    _longPressAdAutoHideTimer = Timer(const Duration(seconds: 3), () {
      _hideLongPressAdOverlay();
    });
  }

  void _hideLongPressAdOverlay() {
    _showLongPressAdOverlayVN.value = false;
    _longPressAdAutoHideTimer?.cancel();
    _longPressAdAutoHideTimer = null;
  }

  /// **PAUSE AD: Show ad on pause — no auto-hide, hides only when video plays**
  void _showPauseAd(int index) {
    if (index >= _videos.length) return;
    final carouselAd = _carouselAdManager.getCarouselAdForIndex(index);
    if (carouselAd == null || carouselAd.slides.isEmpty) return;
    final videoId = _videos[index].id;
    _getOrCreateNotifier<bool>(_showPauseAdOverlayPerVideoVN, videoId, false)
        .value = true;
  }

  void _hidePauseAdOverlay({String? videoId}) {
    // If a specific videoId is provided, hide only that video's pause ad
    if (videoId != null) {
      _showPauseAdOverlayPerVideoVN[videoId]?.value = false;
      return;
    }
    // Fallback: Hide the pause ad for the currently active video
    if (_currentIndex < _videos.length) {
      final activeVideoId = _videos[_currentIndex].id;
      _showPauseAdOverlayPerVideoVN[activeVideoId]?.value = false;
    }
  }

  Widget _buildLongPressAdContent(int index, {bool isPauseAd = false}) {
    final carouselAd = _carouselAdManager.getCarouselAdForIndex(index);
    if (carouselAd == null || carouselAd.slides.isEmpty) {
      return const SizedBox.shrink();
    }

    final slide = carouselAd.slides.first;
    final imageUrl = slide.thumbnailUrl ?? slide.mediaUrl;

    return Stack(
      children: [
        // Circular ad image - slightly left, vertically centered, with popup animation
        Positioned(
          left: 40,
          top: 0,
          bottom: 0,
          child: Align(
            alignment: Alignment.centerLeft,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.0, end: 1.0),
              duration: const Duration(milliseconds: 350),
              curve: Curves.elasticOut,
              builder: (context, value, child) {
                return Transform.scale(
                  scale: value,
                  child: Opacity(
                    opacity: value.clamp(0.0, 1.0),
                    child: child,
                  ),
                );
              },
              child: GestureDetector(
                onTap: () async {
                  _hideLongPressAdOverlay();
                  _hidePauseAdOverlay();

                  // **NEW: Track popup ad click**
                  if (index < _videos.length) {
                    final video = _videos[index];
                    final userData = await _authService.getUserData();
                    if (userData != null &&
                        userData['id'] != video.uploader.id) {
                      try {
                        await _adImpressionService.trackCarouselAdClick(
                          videoId: video.id,
                          adId: carouselAd.id,
                          userId: userData['id'],
                        );
                      } catch (e) {
                        AppLogger.log('❌ Error tracking popup ad click: $e');
                      }
                    }
                  }

                  // Prioritize external navigation if URL is available
                  if (carouselAd.callToActionUrl.isNotEmpty) {
                    AppLogger.log(
                        '🔗 LongPressOverlay: Launching URL: ${carouselAd.callToActionUrl}');
                    _launchExternalUrl(carouselAd.callToActionUrl);
                    return;
                  }

                  // Fallback: Transition to carousel ad page (Existing logic)
                  if (_videos.isNotEmpty && index < _videos.length) {
                    final videoId = _videos[index].id;
                    AppLogger.log(
                        '🖱️ LongPressOverlay: Tapped for video $videoId (Fallback to feed)');

                    if (_carouselAdManager.getTotalCarouselAds() > 0) {
                      if (_currentHorizontalPage.containsKey(videoId)) {
                        _currentHorizontalPage[videoId]!.value = 1;
                      }
                    }
                  }
                },
                child: Container(
                  width: 70,
                  height: 70,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.white, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color:
                            AppColors.backgroundPrimary.withValues(alpha: 0.5),
                        blurRadius: 10,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: ClipOval(
                    child: CachedNetworkImage(
                      imageUrl: imageUrl,
                      width: 70,
                      height: 70,
                      fit: BoxFit.cover,
                      memCacheWidth: 140,
                      maxWidthDiskCache: 140,
                      errorWidget: (context, url, error) {
                        return Container(
                          color: AppColors.borderPrimary,
                          child: const Icon(Icons.ad_units,
                              color: AppColors.white, size: 30),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// **OFFLINE INDICATOR: Shows when device has no internet connection**
  Widget _buildOfflineIndicator() {
    return ValueListenableBuilder<bool>(
      valueListenable: _showOfflineBannerVN,
      builder: (context, show, _) {
        if (!show) {
          return const SizedBox.shrink();
        }

        return Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            bottom: false,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              color: Colors.orange.shade700,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.wifi_off,
                    color: AppColors.white,
                    size: 20,
                  ),
                  AppSpacing.hSpace8,
                  Text(
                    'No internet connection',
                    style: TextStyle(
                      color: AppColors.white,
                      fontSize: AppTypography.fontSizeBase,
                      fontWeight: AppTypography.weightSemiBold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showEpisodeList(BuildContext context, VideoModel video) {
    if (video.episodes == null || video.episodes!.isEmpty) return;

    VayuBottomSheet.show(
      context: context,
      title: 'Episodes',
      child: EpisodeGridWidget(
        episodes: video.episodes!,
        currentVideoId: video.id,
        onEpisodeTap: (ep, index) {
          Navigator.pop(context);
          final String epId = (ep['id'] ?? ep['_id'])?.toString() ?? '';
          if (epId != video.id) {
            final targetIndex = _videos.indexWhere((v) => v.id == epId);
            if (targetIndex != -1) {
              _pageController.animateToPage(
                targetIndex,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
              );
            } else {
              _showSnackBar(
                  'Episode is not in current feed. Scrolling to find it...');
            }
          }
        },
      ),
    );
  }

  String _formatUploadDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays > 365) {
      return '${(difference.inDays / 365).floor()}y ago';
    } else if (difference.inDays > 30) {
      return '${(difference.inDays / 30).floor()}mo ago';
    } else if (difference.inDays > 0) {
      return '${difference.inDays}d ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m ago';
    } else {
      return 'Just now';
    }
  }

  /// **SHOW VIDEO DETAILS BOTTOM SHEET**
  void _showVideoDetailsBottomSheet(BuildContext context, VideoModel video) {
    VayuBottomSheet.show(
      context: context,
      title: 'Video Details',
      actions: [
        if (_currentUserId != null &&
            (video.uploader.googleId == _currentUserId ||
                video.uploader.id == _currentUserId))
          SizedBox(
            width: 80,
            child: AppButton(
              size: AppButtonSize.small,
              variant: AppButtonVariant.secondary,
              onPressed: () async {
                Navigator.of(context).pop();
                final result =
                    await Navigator.of(context).push<Map<String, dynamic>>(
                  MaterialPageRoute(
                    builder: (context) => EditVideoDetails(video: video),
                  ),
                );

                if (result != null) {
                  safeSetState(() {
                    final index = _videos.indexWhere((v) => v.id == video.id);
                    if (index != -1) {
                      _videos[index] = _videos[index].copyWith(
                        videoName: result['videoName'],
                        link: result['link'],
                        tags: result['tags'],
                        quizzes: result['quizzes'],
                        seriesId: result['seriesId'],
                        episodes: result['episodes'] != null
                            ? List<Map<String, dynamic>>.from(
                                result['episodes'])
                            : null,
                      );
                    }
                  });
                }
              },
              icon: const Icon(Icons.edit_outlined, size: 14),
              label: 'Edit',
            ),
          ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (video.tags != null && video.tags!.isNotEmpty) ...[
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: video.tags!
                  .map((tag) => Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                              color: AppColors.primary.withValues(alpha: 0.2)),
                        ),
                        child: Text(
                          '#$tag',
                          style: TextStyle(
                            color: AppColors.primary,
                            fontSize: AppTypography.fontSizeXS,
                            fontWeight: AppTypography.weightMedium,
                          ),
                        ),
                      ))
                  .toList(),
            ),
            AppSpacing.vSpace16,
            const Divider(),
            AppSpacing.vSpace16,
          ],
          Row(
            children: [
              const Icon(Icons.calendar_today,
                  size: 20, color: AppColors.textSecondary),
              AppSpacing.hSpace12,
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Published on',
                    style: TextStyle(
                      fontSize: AppTypography.fontSizeSM,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  Text(
                    _formatUploadDate(video.uploadedAt),
                    style: TextStyle(
                      fontSize: AppTypography.fontSizeLG,
                      fontWeight: AppTypography.weightMedium,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ],
          ),
          AppSpacing.vSpace16,
          const Divider(),
          AppSpacing.vSpace16,
          Row(
            children: [
              const Icon(Icons.remove_red_eye_outlined,
                  size: 20, color: AppColors.textSecondary),
              AppSpacing.hSpace12,
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Total Views',
                    style: TextStyle(
                      fontSize: AppTypography.fontSizeSM,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  Text(
                    '${_formatCount(video.views)} views',
                    style: TextStyle(
                      fontSize: AppTypography.fontSizeLG,
                      fontWeight: AppTypography.weightMedium,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ],
          ),
          AppSpacing.vSpace16,
        ],
      ),
    );
  }
}

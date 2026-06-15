part of '../video_feed_advanced.dart';

extension _VideoFeedPlayback on _VideoFeedAdvancedState {
  void _reprimeWindowIfNeeded() {
    final int start = _currentIndex;
    final int end = (_currentIndex + _decoderPrimeBudget - 1).clamp(
      0,
      _videos.length - 1,
    );

    if (_primedStartIndex == start) return;

    _controllerPool.forEach((videoId, controller) {
      // Find index of this videoId
      int? idx;
      try {
        idx = _videos.indexWhere((v) => v.id == videoId);
      } catch (_) {}

      if (idx == null || idx < start || idx > end) {
        try {
          if (SharedVideoControllerPool().isControllerDisposed(controller)) {
            _controllerPool.remove(videoId);
            _controllerStates.remove(videoId);
            return;
          }
          final value = controller.value;
          if (value.isInitialized) {
            controller.pause();
            _controllerStates[videoId] = false;
          }
        } catch (e) {
          _controllerPool.remove(videoId);
          _controllerStates.remove(videoId);
        }
      }
    });

    _primedStartIndex = start;
  }

  void _pauseAllOtherVideos(String? currentVideoId) {
    _controllerPool.forEach((videoId, controller) {
      if (videoId == currentVideoId) return;

      try {
        if (SharedVideoControllerPool().isControllerDisposed(controller)) {
          // Internal cleanup handled by pool usually, but we help
          return;
        }
        final value = controller.value;
        if (value.isInitialized) {
          controller.pause();
          _controllerStates[videoId] = false;
        }
      } catch (e) {
        _controllerPool.remove(videoId);
        _controllerStates.remove(videoId);
      }
    });

    _videoControllerManager.pauseAllVideosOnTabChange(
        exceptVideoId: currentVideoId);

    final sharedPool = SharedVideoControllerPool();
    sharedPool.pauseAllControllers(exceptVideoId: currentVideoId);
    _ensureWakelockForVisibility();
  }

  void forcePlayCurrent() {
    if (_videos.isEmpty ||
        _currentIndex < 0 ||
        _currentIndex >= _videos.length) {
      return;
    }

    final video = _videos[_currentIndex];
    final videoId = video.id;
    final controller = _controllerPool[videoId];

    bool isInitializedSafe = false;
    if (controller != null) {
      try {
        if (!SharedVideoControllerPool().isControllerDisposed(controller)) {
          isInitializedSafe = controller.value.isInitialized;
        } else {
           _controllerPool.remove(videoId);
           _controllerStates.remove(videoId);
        }
      } catch (_) {
        _controllerPool.remove(videoId);
        _controllerStates.remove(videoId);
      }
    }

    if (controller != null && isInitializedSafe) {
      if (!_shouldAutoplayForContext('forcePlayCurrent')) return;
      _pauseAllOtherVideos(videoId);
      _lifecyclePaused = false;
      controller.play();
      
      safeSetState(() {
        _controllerStates[videoId] = true;
        _userPaused[videoId] = false; // **Ensure user paused is reset**
        _getOrCreateNotifier<bool>(_userPausedVN, videoId, false);
      });
      
      _ensureWakelockForVisibility();
      return;
    }

    _preloadVideo(_currentIndex).then((_) {
      if (!mounted) return;
      final c = _controllerPool[videoId];
      bool cInit = false;
      if (c != null) {
        try {
          cInit = c.value.isInitialized;
        } catch (_) {
          _controllerPool.remove(videoId);
          _controllerStates.remove(videoId);
        }
      }
      if (c != null && cInit) {
        if (!_shouldAutoplayForContext('forcePlayCurrent preload')) return;
        _pauseAllOtherVideos(videoId);
        _lifecyclePaused = false;
        c.play();
        
        safeSetState(() {
          _controllerStates[videoId] = true;
          _userPaused[videoId] = false;
          _getOrCreateNotifier<bool>(_userPausedVN, videoId, false);
        });
        
        _ensureWakelockForVisibility();
      }
    });
  }

  void _pauseCurrentVideo() {
    if (_currentIndex < _videos.length) {
      final currentVideo = _videos[_currentIndex];
      final videoId = currentVideo.id;
      _viewTracker.stopViewTracking(videoId);

      if (_controllerPool.containsKey(videoId)) {
        final controller = _controllerPool[videoId];

        if (controller != null) {
          try {
            if (!SharedVideoControllerPool().isControllerDisposed(controller)) {
              final value = controller.value;
              if (value.isInitialized) {
                controller.pause();
                _controllerStates[videoId] = false;
              }
            } else {
              _controllerPool.remove(videoId);
              _controllerStates.remove(videoId);
            }
          } catch (e) {
            _controllerPool.remove(videoId);
            _controllerStates.remove(videoId);
          }
        }
      }
    }

    _videoControllerManager.pauseAllVideosOnTabChange();
  }

  void _pauseAllVideosOnTabSwitch() {
    _controllerPool.forEach((videoId, controller) {
      try {
        if (!SharedVideoControllerPool().isControllerDisposed(controller)) {
          final value = controller.value;
          if (value.isInitialized) {
            controller.pause();
            _controllerStates[videoId] = false;
          }
        } else {
          _controllerPool.remove(videoId);
          _controllerStates.remove(videoId);
        }
      } catch (e) {
        _controllerPool.remove(videoId);
        _controllerStates.remove(videoId);
      }
    });

    _videoControllerManager.pauseAllVideosOnTabChange();
    SharedVideoControllerPool().pauseAllControllers();

    _isScreenVisible = false;
    _ensureWakelockForVisibility();
  }


}

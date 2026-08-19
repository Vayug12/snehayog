part of '../video_feed_advanced.dart';

extension _VideoFeedPersistence on _VideoFeedAdvancedState {



  Future<void> _restoreBackgroundStateIfAny() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedIndex = prefs.getInt(_kSavedFeedIndexKey);
      final savedType = prefs.getString(_kSavedFeedTypeKey);
      final savedVideoId = prefs.getString(_kSavedVideoIdKey);
      final savedTimestamp = prefs.getInt(_kSavedStateTimestampKey);

      // **NEW: Check if saved state is too old (more than 24 hours)**
      if (savedTimestamp != null) {
        final savedTime = DateTime.fromMillisecondsSinceEpoch(savedTimestamp);
        final hoursSinceSaved = DateTime.now().difference(savedTime).inHours;
        // **FIX: Extend expiry to 7 days (168 hours) for "Resume" feature**
        if (hoursSinceSaved > 168) {
          AppLogger.log(
              'ℹ️ Saved state is too old ($hoursSinceSaved hours), ignoring');
          // Clear old state
          await prefs.remove(_kSavedFeedIndexKey);
          // **Restoration logic removed**
          await prefs.remove(_kSavedVideoIdKey);
          await prefs.remove(_kSavedPageKey);
          await prefs.remove(_kSavedStateTimestampKey);
          return;
        }
      }

      // **NEW: Try to restore by video ID first (more reliable than index)**
      if (savedVideoId != null && _videos.isNotEmpty) {
        final videoIndex =
            FeedPageAlignment.indexOfVideoId(_videos, savedVideoId);
        if (videoIndex != -1) {
          AppLogger.log(
              '✅ Restored to video ID: $savedVideoId at index $videoIndex');
          _applyRestoredIndex(videoIndex);
          return;
        }
      }

      // **FALLBACK: Restore by index if video ID not found**
      if (savedIndex != null &&
          savedIndex >= 0 &&
          savedIndex < _videos.length &&
          (savedType == null || savedType == widget.videoType)) {
        AppLogger.log('✅ Restored to index: $savedIndex');
        _applyRestoredIndex(savedIndex);
      }
    } catch (e) {
      AppLogger.log('❌ Error restoring background state: $e');
    }
  }

  /// Moves the index field and the viewport together, or neither.
  ///
  /// `_currentIndex` used to be assigned outside the `hasClients` check while
  /// the `jumpToPage` beside it sat inside, so a restore that ran with the
  /// PageView detached — the app resuming while the picture-in-picture tree was
  /// still mounted — moved the index without moving the viewport, and the feed
  /// went on playing one video while displaying another. Waiting a frame keeps
  /// the restore working in that case instead of dropping it.
  void _applyRestoredIndex(int index) {
    void apply() {
      if (!mounted || !_pageController.hasClients) return;
      // Set before the jump: _onPageChanged returns early for an index it
      // already holds, so the realignment does not re-run page-change work.
      _currentIndex = index;
      FeedPageAlignment.jumpToIndex(_pageController, index);
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _tryAutoplayCurrent());
    }

    if (_pageController.hasClients) {
      apply();
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => apply());
    }
  }

  /// **NEW: Persist seen video keys so reopened app doesn't re-show them at top**
  Future<void> _loadSeenVideoKeysFromStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final storedKeys = prefs.getStringList(_kSeenVideoKeysKey) ?? const [];
      if (storedKeys.isNotEmpty) {
        _seenVideoKeys.addAll(storedKeys);
        AppLogger.log(
          '✅ VideoFeedAdvanced: Loaded ${_seenVideoKeys.length} seen video keys from storage',
        );
      }
    } catch (e) {
      AppLogger.log('⚠️ VideoFeedAdvanced: Error loading seen video keys: $e');
    }
  }

  Future<void> _saveSeenVideoKeysToStorage() async {
    try {
      // Keep only a reasonable number of recent keys to avoid unbounded growth
      const maxKeys = 1000;
      final keys = _seenVideoKeys.toList();
      if (keys.length > maxKeys) {
        keys.removeRange(0, keys.length - maxKeys);
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_kSeenVideoKeysKey, keys);
    } catch (e) {
      AppLogger.log('⚠️ VideoFeedAdvanced: Error saving seen video keys: $e');
    }
  }
}

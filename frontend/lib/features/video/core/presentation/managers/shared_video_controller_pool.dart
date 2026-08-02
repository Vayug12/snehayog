import 'dart:async';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:vayug/shared/utils/app_logger.dart';

/// **Shared Video Controller Pool: Singleton manager for persisting video controllers**
/// This class manages a shared pool of video controllers that can be reused
/// across different screens (VideoFeedAdvanced, VideoScreen, ProfileScreen)
class SharedVideoControllerPool {
  static final SharedVideoControllerPool _instance =
      SharedVideoControllerPool._internal();
  factory SharedVideoControllerPool() => _instance;
  SharedVideoControllerPool._internal();

  // **CONTROLLER STORAGE**
  final Map<String, VideoPlayerController> _controllerPool = {};
  bool Function(VideoPlayerController controller)? _playbackGuard;
  final Map<String, bool> _controllerStates = {}; // Track if controller is active

  // **LISTENER OWNERSHIP**
  // A single controller carries several independent listeners (end-of-video,
  // buffering/stall watchdog, quiz triggers, error handling). All of them tick
  // on every VideoPlayerValue update, so any listener that outlives its
  // controller keeps burning UI-isolate time. The pool owns the full set so
  // eviction can guarantee every one of them is detached.
  final Map<String, List<VoidCallback>> _listeners = {};

  void setPlaybackGuard(bool Function(VideoPlayerController controller)? guard) {
    _playbackGuard = guard;
  }

  // **PIN: the video the user is actually watching**
  //
  // LRU alone cannot protect it: preloading a neighbour refreshes that
  // neighbour's access time and pushes the playing video down the list, so a
  // full pool would evict the very controller producing frames on screen.
  // A pinned video is never evicted by LRU, by retainOnly, or by a
  // memory-pressure sweep — only an explicit dispose can take it.
  String? _pinnedVideoId;

  String? get pinnedVideoId => _pinnedVideoId;

  /// **Pin the currently watched video. Pass `null` when nothing is playing.**
  void pinVideo(String? videoId) {
    if (_pinnedVideoId == videoId) return;
    _pinnedVideoId = videoId;
    if (videoId != null) {
      _lastAccessed[videoId] = DateTime.now();
    }
  }

  /// **Does the pool own a controller for this video?** (no validation side effects)
  bool isPooled(String videoId) => _controllerPool.containsKey(videoId);

  // **DISPOSAL STREAM: Notify listeners when a controller is evicted**
  final StreamController<String> _disposalStreamController =
      StreamController<String>.broadcast();
  Stream<String> get disposalStream => _disposalStreamController.stream;

  // **CLEANUP QUEUE: Graceful disposal to prevent race conditions**
  // Move controllers to a "waiting room" for 200ms before disposing them.
  final Map<String, VideoPlayerController> _cleanupQueue = {};
  final Map<String, Timer> _cleanupTimers = {};

  // **LRU TRACKING**
  final Map<String, DateTime> _lastAccessed =
      {}; // Track when each video was last accessed
  // **DYNAMIC CONFIG: Hard limit to prevent NO_MEMORY**
  // Android usually supports ~16 hardware decoders, but other apps/services might use them.
  // We stay well below this limit.
  int _maxPoolSize = 15; // **Increased from 6 to 15 for better multi-screen stability and reactive headroom**

  /// **Configure pool based on device capabilities**
  void configurePool({required bool isLowEndDevice}) {
    // High-end: 6 controllers
    // Low-end: 2 controllers (ExoPlayer decoders are heavy on old phones)
    _maxPoolSize = isLowEndDevice ? 6 : 15;
    
    AppLogger.log(
      '📱 SharedPool Configured: Max $_maxPoolSize active controllers '
      '(${isLowEndDevice ? "Low End Mode" : "High End Mode"})'
    );
    
    // If shrinking, trigger immediate eviction
    if (_controllerPool.length > _maxPoolSize) {
       _evictLRUIfNeeded();
    }
  }

  /// **Controllers currently holding a hardware decoder.**
  ///
  /// A queued controller has been removed from the active pool but has NOT yet
  /// released its decoder — it only does so on `dispose()`. Budgeting against
  /// `_controllerPool.length` alone under-counts by the size of the queue,
  /// which is exactly what lets fast scrolling blow past the device's decoder
  /// limit and produce silent init failures.
  int get _liveDecoderCount => _controllerPool.length + _cleanupQueue.length;

  /// **ADMISSION CONTROL: acquire decoder headroom BEFORE creating a controller.**
  ///
  /// Returns `false` when no decoder could be freed. A caller that gets `false`
  /// must NOT construct a controller — the whole point is that a speculative
  /// preload gets refused instead of stealing the decoder out from under the
  /// video the user is actually watching.
  ///
  /// [highPriority] is for the video being watched right now: if the normal
  /// pass cannot free room, every unpinned controller is released.
  Future<bool> makeRoomForNewController({
    String? forVideoId,
    bool highPriority = false,
  }) async {
    if (_liveDecoderCount < _maxPoolSize) return true;

    // **PREEMPTIVE DISPOSAL: Be ruthless during fast scroll**
    // Don't just evict one, evict until we are at least 1 below the limit
    // to avoid fighting for decoders on every single swipe.
    _evictLRUIfNeeded(forceRelease: true, excluding: forVideoId);

    // **CRITICAL: eviction only queues the teardown. Without draining, this
    // method returns while every evicted decoder is still held, and the caller
    // allocates on top of them.**
    await _drainCleanupQueue();

    if (_liveDecoderCount < _maxPoolSize) return true;

    if (highPriority) {
      // The watched video outranks every cached neighbour.
      final sacrificial = _controllerPool.keys
          .where((id) => id != _pinnedVideoId && id != forVideoId)
          .toList();
      for (final videoId in sacrificial) {
        disposeController(videoId);
      }
      await _drainCleanupQueue();

      if (_liveDecoderCount < _maxPoolSize) return true;
    }

    AppLogger.log(
        '⛔ SharedPool: Admission denied for ${forVideoId ?? "new controller"} '
        '($_liveDecoderCount/$_maxPoolSize decoders held)');
    return false;
  }

  // **CACHE STATISTICS**
  int _cacheHits = 0;
  int _cacheMisses = 0;
  int _totalRequests = 0;

  /// **Check if video controller is already loaded (updates LRU)**
  bool isVideoLoaded(String videoId) {
    if (_cleanupQueue.containsKey(videoId)) return false; // Treat as not loaded if pending disposal
    return _validatedController(videoId) != null;
  }

  /// Returns the pooled video id for a controller, when it is currently
  /// registered. This lets the playback coordinator pause competing pooled
  /// controllers without pausing the controller it just claimed.
  String? videoIdForController(VideoPlayerController? controller) {
    if (controller == null) return null;
    for (final entry in _controllerPool.entries) {
      if (identical(entry.value, controller)) return entry.key;
    }
    return null;
  }

  /// **Check if a controller is effectively disposed**
  bool isControllerDisposed(VideoPlayerController? controller) {
    if (controller == null) return true;
    
    // Check if it's in the cleanup queue (effectively dead for the UI)
    for (final pending in _cleanupQueue.values) {
      if (pending == controller) return true;
    }

    try {
      // Accessing value throws IF disposed.
      // However, we want to be sure it's a disposal error and not just a 
      // temporary platform channel lag during orientation change.
      final _ = controller.value;
      return false;
    } catch (e) {
      final errorStr = e.toString().toLowerCase();
      // Only treat as disposed if the error message explicitly mentions it
      if (errorStr.contains('disposed') || errorStr.contains('closed')) {
        return true;
      }
      
      // If it's some other error, it might be transient (e.g. during rotation)
      // so we don't immediately treat it as dead.
      return false;
    }
  }

  /// **Check if controller is valid (not disposed, initialized, and no errors)**
  bool isControllerValid(VideoPlayerController? controller) {
    if (controller == null) return false;
    
    // Check if effectively disposed without property access if possible
    // (Flutter doesn't provide a direct isDisposed, but accessing value is the standard way)
    try {
      final value = controller.value;
      return value.isInitialized && !value.hasError;
    } catch (_) {
      // Accessing value on a disposed controller throws
      return false;
    }
  }

  /// **Safe value lookup: Returns null if controller is disposed**
  VideoPlayerValue? safeValue(VideoPlayerController? controller) {
    if (isControllerDisposed(controller)) return null;
    try {
      return controller!.value;
    } catch (_) {
      return null;
    }
  }

  /// Safely read controller value. Returns null if controller is disposed.
  VideoPlayerValue? _safeControllerValue(
    String videoId,
    VideoPlayerController controller,
  ) {
    try {
      return controller.value;
    } catch (e) {
      _evictController(videoId, controller, reason: 'stale/disposed: $e');
      return null;
    }
  }

  /// Remove invalid controller references so caller can recreate a fresh one.
  void _evictController(
    String videoId,
    VideoPlayerController controller, {
    String? reason,
    bool disposeInstance = false,
  }) {
    _detachListeners(videoId, controller);

    _controllerPool.remove(videoId);
    _controllerStates.remove(videoId);
    _listeners.remove(videoId);
    _lastAccessed.remove(videoId);

    // Notify listeners that this controller is being evicted
    _disposalStreamController.add(videoId);

    if (disposeInstance) {
      try {
        controller.dispose();
      } catch (_) {}
    }

    AppLogger.log(
      'SharedPool: Evicted invalid controller for video: $videoId'
      '${reason != null ? ' ($reason)' : ''}',
    );
  }

  VideoPlayerController? _validatedController(
    String videoId, {
    bool requireInitialized = true,
  }) {
    final controller = _controllerPool[videoId];
    if (controller == null) return null;

    // **CRITICAL: check disposal first**
    if (isControllerDisposed(controller)) {
      _evictController(videoId, controller, reason: 'proactive cleanup: controller disposed');
      return null;
    }

    final value = _safeControllerValue(videoId, controller);
    if (value == null) return null;

    if (value.hasError) {
      _evictController(
        videoId,
        controller,
        reason: 'controller has error',
        disposeInstance: true,
      );
      return null;
    }

    if (requireInitialized && !value.isInitialized) {
      _evictController(
        videoId,
        controller,
        reason: 'not initialized',
        disposeInstance: true,
      );
      return null;
    }

    _lastAccessed[videoId] = DateTime.now();
    return controller;
  }

  /// **Get existing controller for a video (updates LRU)**
  VideoPlayerController? getController(String videoId) {
    final controller = _validatedController(videoId);
    if (controller != null) {
      trackCacheHit();
      return controller;
    }
    trackCacheMiss();
    return null;
  }

  /// **Get controller with instant playback guarantee (for cached videos)**
  VideoPlayerController? getControllerForInstantPlay(String videoId) {
    final controller = getController(videoId);
    if (controller != null) {
      if (isControllerDisposed(controller)) {
        _evictController(videoId, controller, reason: 'disposed in instant check');
        return null;
      }

      final value = _safeControllerValue(videoId, controller);
      if (value == null || !value.isInitialized) {
        trackCacheMiss();
        return null;
      }

      // **INSTANT PLAYBACK: Ensure first frame is ready**
      if (value.position > Duration.zero || !value.isBuffering) {
        return controller;
      }
    }
    return controller;
  }

  /// **Add controller to pool with LRU eviction**
  void addController(String videoId, VideoPlayerController controller,
      {bool skipDisposeOld = false}) {
    AppLogger.log('📥 SharedPool: Adding controller for video: $videoId');

    // **LRU: Update access time**
    _lastAccessed[videoId] = DateTime.now();

    // Dispose old controller if exists (unless we're explicitly replacing with the same controller)
    if (_controllerPool.containsKey(videoId)) {
      final oldController = _controllerPool[videoId];

      // **CRITICAL FIX: Only dispose if it's a different controller instance**
      // This prevents disposing the controller we're trying to save
      if (oldController != controller && !skipDisposeOld) {
        disposeController(videoId); // Use delayed disposal
        AppLogger.log(
            '🗑️ SharedPool: Scheduled old controller for disposal: $videoId');
      } else {
        AppLogger.log(
            '♻️ SharedPool: Skipping dispose - same controller instance or skipDisposeOld=true');
      }
    } else {
      // **NEW: LRU Eviction - Remove least recently used if pool is full**
      _evictLRUIfNeeded(excluding: videoId);
    }

    // Ensure it's not in the cleanup queue anymore if we're adding it back
    _cancelCleanup(videoId);

    _controllerPool[videoId] = controller;
    _controllerStates[videoId] = false; // Not playing initially

    AppLogger.log(
        '✅ SharedPool: Controller added, total controllers: ${_controllerPool.length}');
  }

  /// **Release every controller except the given videos.**
  ///
  /// Identity-based on purpose. The pool used to track which feed *positions* a
  /// video occupied, but positions are only meaningful inside the list that
  /// produced them: after pagination, a refresh, or a reorder, those stored
  /// indices describe a list that no longer exists — so the pool would keep
  /// controllers it should drop and drop ones still on screen.
  ///
  /// The caller owns the list and recomputes [keepVideoIds] fresh each time.
  /// The pinned video always survives, whether or not it is in the set.
  void retainOnly(Set<String> keepVideoIds) {
    final toRemove = _controllerPool.keys
        .where((videoId) =>
            !keepVideoIds.contains(videoId) && videoId != _pinnedVideoId)
        .toList();

    for (final videoId in toRemove) {
      disposeController(videoId);
    }

    if (toRemove.isNotEmpty) {
      AppLogger.log(
          '🧹 SharedPool: Released ${toRemove.length} controller(s) outside the keep set '
          '(kept ${_controllerPool.length})');
    }
  }

  /// **Remove controller from pool (but keep it initialized)**
  void removeController(String videoId) {
    if (_controllerPool.containsKey(videoId)) {
      final controller = _controllerPool[videoId]!;
      _detachListeners(videoId, controller);
      _controllerPool.remove(videoId);
      _controllerStates.remove(videoId);
      _listeners.remove(videoId);
      _lastAccessed.remove(videoId); // Remove LRU tracking

      AppLogger.log('🗑️ SharedPool: Removed controller for video: $videoId');
    }
  }

  /// **LRU Eviction: Remove least recently used controllers**
  void _evictLRUIfNeeded({String? excluding, bool forceRelease = false}) {
    if (_liveDecoderCount < _maxPoolSize) return;

    // Sort by last accessed time (oldest first)
    final sortedEntries = _lastAccessed.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));

    // Calculate how many to remove
    // If forceRelease is true, we remove 2 to create a healthy "buffer"
    final int targetCapacity = forceRelease ? _maxPoolSize - 2 : _maxPoolSize - 1;
    final toRemove = (_controllerPool.length - targetCapacity).clamp(1, _controllerPool.length);

    int removed = 0;
    for (final entry in sortedEntries) {
      if (removed >= toRemove) break;
      if (entry.key == excluding) continue; // Don't remove the one we're adding
      if (entry.key == _pinnedVideoId) continue; // NEVER evict what's playing

      if (_controllerPool.containsKey(entry.key)) {
        disposeController(entry.key);
        removed++;
      }
    }

    if (removed > 0) {
      AppLogger.log('🧹 SharedPool: LRU evicted $removed old controllers (Reason: ${forceRelease ? "Ruthless/FastScroll" : "Pool Full"})');
    }
  }

  /// **Dispose controller and remove from pool (with 200ms safety delay)**
  Future<void> disposeController(String videoId) async {
    if (_controllerPool.containsKey(videoId)) {
      final controller = _controllerPool[videoId]!;

      // **1. Detach listeners NOW**
      // The controller is leaving the active pool, so nothing should still be
      // reacting to its ticks during the grace window.
      _detachListeners(videoId, controller);

      // **2. Remove from active pool IMMEDIATELY**
      _controllerPool.remove(videoId);
      _controllerStates.remove(videoId);
      _lastAccessed.remove(videoId);

      // **3. Signal UI immediately via broadcast stream**
      _disposalStreamController.add(videoId);

      // **4. Move to Cleanup Queue**
      // NOTE: the controller still holds its hardware decoder until the timer
      // fires, so it stays counted in `_liveDecoderCount`.
      _cleanupQueue[videoId] = controller;

      // **5. Schedule actual disposal with 200ms delay**
      _cleanupTimers[videoId]?.cancel();
      _cleanupTimers[videoId] = Timer(const Duration(milliseconds: 200), () {
        _performActualDisposal(videoId, controller);
      });
    }
  }

  Future<void> _performActualDisposal(
    String videoId,
    VideoPlayerController controller,
  ) async {
    if (!_cleanupQueue.containsKey(videoId)) return;

    // Final sanity check: ensure it's not back in the active pool
    if (identical(_controllerPool[videoId], controller)) {
      _cleanupQueue.remove(videoId);
      _cleanupTimers.remove(videoId);
      return;
    }

    // **CLAIM FIRST: remove from the queue before the await so a concurrent
    // drain or a late timer cannot dispose the same controller twice.**
    _cleanupQueue.remove(videoId);
    _cleanupTimers.remove(videoId)?.cancel();

    try {
      if (controller.value.isInitialized) {
        controller.pause();
        controller.setVolume(0.0);
      }
      await controller.dispose();
    } catch (e) {
      AppLogger.log('⚠️ SharedPool: Error during final disposal of $videoId: $e');
    }
  }

  /// **Release every queued controller right now, without waiting for timers.**
  ///
  /// The 200ms grace window exists to stop the UI from reading a controller
  /// mid-teardown, but a decoder is only actually freed by `dispose()`. Any
  /// caller that needs decoder headroom must drain rather than assume the
  /// timers have fired.
  Future<void> _drainCleanupQueue() async {
    if (_cleanupQueue.isEmpty) return;

    final pending = Map<String, VideoPlayerController>.from(_cleanupQueue);
    AppLogger.log(
        '🚿 SharedPool: Draining ${pending.length} pending controller(s) to free decoders');

    await Future.wait(
      pending.entries.map((e) => _performActualDisposal(e.key, e.value)),
    );
  }

  void _cancelCleanup(String videoId) {
    if (_cleanupQueue.containsKey(videoId)) {
      _cleanupTimers[videoId]?.cancel();
      _cleanupTimers.remove(videoId);
      _cleanupQueue.remove(videoId);
      AppLogger.log('🔄 SharedPool: Cancelled cleanup for $videoId (Resurrected)');
    }
  }

  /// **Attach a listener to a pooled controller**
  ///
  /// Callers must route every `addListener` through here instead of touching
  /// the controller directly. A listener the pool does not know about cannot be
  /// detached on eviction, and will keep firing against a dead controller.
  void attachListener(String videoId, VoidCallback listener) {
    final controller = _controllerPool[videoId];
    if (controller == null) {
      AppLogger.log(
          '⚠️ SharedPool: attachListener ignored — no pooled controller for $videoId');
      return;
    }

    final listeners = _listeners.putIfAbsent(videoId, () => <VoidCallback>[]);
    if (listeners.contains(listener)) return; // Idempotent re-attach

    listeners.add(listener);
    controller.addListener(listener);
  }

  /// **Detach a single listener previously registered via [attachListener]**
  void detachListener(String videoId, VoidCallback listener) {
    final listeners = _listeners[videoId];
    if (listeners == null) return;

    if (listeners.remove(listener)) {
      final controller = _controllerPool[videoId] ?? _cleanupQueue[videoId];
      try {
        controller?.removeListener(listener);
      } catch (_) {}
    }

    if (listeners.isEmpty) _listeners.remove(videoId);
  }

  /// **Detach every listener registered for a video**
  void _detachListeners(String videoId, VideoPlayerController? controller) {
    final listeners = _listeners.remove(videoId);
    if (listeners == null || controller == null) return;

    for (final listener in listeners) {
      try {
        controller.removeListener(listener);
      } catch (_) {}
    }
  }

  /// **Remove all listeners from a controller**
  void removeListener(String videoId) {
    _detachListeners(videoId, _controllerPool[videoId] ?? _cleanupQueue[videoId]);
  }

  /// **Set controller state (playing/paused)**
  void setControllerState(String videoId, bool isPlaying) {
    _controllerStates[videoId] = isPlaying;
  }

  /// **Get controller state**
  bool? getControllerState(String videoId) {
    return _controllerStates[videoId];
  }

  /// **Check if controller exists (even if not initialized)**
  bool hasController(String videoId) {
    return _validatedController(videoId, requireInitialized: false) != null;
  }

  /// **Get statistics**
  Map<String, dynamic> getStatistics() {
    return {
      'totalControllers': _controllerPool.length,
      'cacheHits': _cacheHits,
      'cacheMisses': _cacheMisses,
      'totalRequests': _totalRequests,
      'hitRate': _totalRequests > 0
          ? (_cacheHits / _totalRequests * 100).toStringAsFixed(2)
          : '0.00',
      'controllerIds': _controllerPool.keys.toList(),
    };
  }

  /// **Track cache hit**
  void trackCacheHit() {
    _cacheHits++;
    _totalRequests++;
  }

  /// **Track cache miss**
  void trackCacheMiss() {
    _cacheMisses++;
    _totalRequests++;
  }

  /// **Pause all controllers instead of disposing (better UX)**
  void pauseAllControllers({String? exceptVideoId}) {
    AppLogger.log(
        '⏸️ SharedPool: Pausing all controllers (except $exceptVideoId)');

    for (final entry in _controllerPool.entries) {
      if (exceptVideoId != null && entry.key == exceptVideoId) continue;

      try {
        if (entry.value.value.isInitialized && entry.value.value.isPlaying) {
          entry.value.pause();
          _controllerStates[entry.key] = false;
          AppLogger.log('⏸️ SharedPool: Paused controller ${entry.key}');
        }
      } catch (e) {
        AppLogger.log(
            '⚠️ SharedPool: Error pausing controller ${entry.key}: $e');
      }
    }

    AppLogger.log(
        '✅ SharedPool: Paused controllers${exceptVideoId != null ? ' (except current)' : ''}');
  }

  /// **Safe pause: Pause controller only if it's not disposed**
  void safePause(VideoPlayerController? controller) {
    if (controller == null) return;
    try {
      if (!isControllerDisposed(controller) &&
          controller.value.isInitialized &&
          controller.value.isPlaying) {
        controller.pause();
      }
    } catch (_) {
      // Silently fail if disposed mid-check
    }
  }

  /// **Resume specific controller (for better UX)**
  void resumeController(String videoId) {
    if (_controllerPool.containsKey(videoId)) {
      try {
        final controller = _controllerPool[videoId]!;
        if (controller.value.isInitialized && !controller.value.isPlaying) {
          if (_playbackGuard?.call(controller) != false) {
            controller.play();
          }
          _controllerStates[videoId] = true;
          AppLogger.log('▶️ SharedPool: Resumed controller $videoId');
        }
      } catch (e) {
        AppLogger.log('⚠️ SharedPool: Error resuming controller $videoId: $e');
      }
    }
  }

  /// **Check if any controller is currently playing**
  bool hasActivePlayback() {
    for (final controller in _controllerPool.values) {
      try {
        if (controller.value.isInitialized && controller.value.isPlaying) {
          return true;
        }
      } catch (_) {
        // Ignore controllers that may have been disposed mid-iteration
      }
    }
    return false;
  }

  /// **Check if controller is paused (not disposed)**
  bool isControllerPaused(String videoId) {
    final controller = _validatedController(videoId);
    if (controller == null) return false;

    final value = _safeControllerValue(videoId, controller);
    return value != null && !value.isPlaying;
  }

  /// **Memory management: Dispose controllers when memory usage is high**
  void disposeControllersForMemoryManagement() {
    AppLogger.log('🧹 SharedPool: Disposing controllers for memory management');

    // Keep the 2 most recently used controllers, plus the pinned one.
    // NOTE: this used to take `_controllerPool.keys` in insertion order, which
    // is unrelated to recency — it could drop the video being watched.
    if (_controllerPool.length > 2) {
      final sortedKeys = _lastAccessed.entries
          .where((e) => _controllerPool.containsKey(e.key))
          .toList()
        ..sort((a, b) => a.value.compareTo(b.value));

      final controllersToDispose = sortedKeys
          .map((e) => e.key)
          .where((id) => id != _pinnedVideoId)
          .take((_controllerPool.length - 2).clamp(0, _controllerPool.length))
          .toList();

      for (final videoId in controllersToDispose) {
        disposeController(videoId);
      }

      AppLogger.log(
          '✅ SharedPool: Disposed ${controllersToDispose.length} controllers for memory management');
    }
  }

  /// **Smart resume: Resume controller if available, otherwise show first frame**
  void smartResumeController(String videoId) {
    if (_controllerPool.containsKey(videoId)) {
      final controller = _controllerPool[videoId]!;
      if (controller.value.isInitialized) {
        // Show first frame immediately (no loading)
        AppLogger.log('🖼️ SharedPool: Showing first frame for video $videoId');

        // Resume in background
        Future.microtask(() {
          if (controller.value.isInitialized && !controller.value.isPlaying) {
            if (_playbackGuard?.call(controller) != false) {
              controller.play();
              _controllerStates[videoId] = true;
            }
            AppLogger.log(
                '▶️ SharedPool: Resumed video $videoId in background');
          }
        });
      }
    }
  }

  /// **Clear all controllers (only when memory is high)**
  void clearAll() {
    AppLogger.log('🗑️ SharedPool: Clearing all controllers');

    for (final entry in _controllerPool.entries) {
      try {
        _detachListeners(entry.key, entry.value);
        entry.value.dispose();
      } catch (e) {
        AppLogger.log(
            '⚠️ SharedPool: Error disposing controller ${entry.key}: $e');
      }
    }

    _controllerPool.clear();
    _controllerStates.clear();
    _listeners.clear();
    _lastAccessed.clear(); // Clear LRU tracking
    _pinnedVideoId = null; // Nothing is playing anymore

    AppLogger.log('✅ SharedPool: All controllers cleared');
  }

  /// **Clear controllers except specified ones**
  void clearExcept(List<String> keepVideoIds) {
    final keepSet = keepVideoIds.toSet();
    final toRemove = <String>[];

    for (final videoId in _controllerPool.keys) {
      if (!keepSet.contains(videoId)) {
        toRemove.add(videoId);
      }
    }

    for (final videoId in toRemove) {
      disposeController(videoId);
    }

    AppLogger.log(
        '🗑️ SharedPool: Cleared ${toRemove.length} controllers, keeping ${keepVideoIds.length}');
  }

  /// **Print pool status**
  void printStatus() {
    AppLogger.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    AppLogger.log('📊 SHARED VIDEO CONTROLLER POOL STATUS');
    AppLogger.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    AppLogger.log('   Total Controllers: ${_controllerPool.length}');
    AppLogger.log('   Video IDs: ${_controllerPool.keys.toList()}');
    AppLogger.log('   Cache Hits: $_cacheHits');
    AppLogger.log('   Cache Misses: $_cacheMisses');
    AppLogger.log(
        '   Hit Rate: ${_totalRequests > 0 ? (_cacheHits / _totalRequests * 100).toStringAsFixed(2) : '0.00'}%');
    AppLogger.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  }

  /// **App backgrounded: Perform aggressive cleanup to free memory**
  void onAppBackgrounded() {
    AppLogger.log('🧹 SharedPool: App backgrounded - releasing all controllers except the current one');
    
    // 1. Identify the video to keep.
    // Prefer the explicit pin — "most recently accessed" is unreliable here
    // because preloading a neighbour bumps that neighbour's access time.
    String? currentVideoId = _pinnedVideoId;
    if (currentVideoId == null || !_controllerPool.containsKey(currentVideoId)) {
      currentVideoId = null;
      if (_lastAccessed.isNotEmpty) {
        final sortedEntries = _lastAccessed.entries
            .where((e) => _controllerPool.containsKey(e.key))
            .toList()
          ..sort((a, b) => a.value.compareTo(b.value));
        if (sortedEntries.isNotEmpty) currentVideoId = sortedEntries.last.key;
      }
    }

    // 2. Clear all except the current one to free up hardware decoders
    if (currentVideoId != null) {
      AppLogger.log('🛡️ SharedPool: Keeping current video $currentVideoId, clearing others');
      
      // Pause it first
      final controller = _controllerPool[currentVideoId];
      if (controller != null && controller.value.isInitialized) {
        controller.pause();
      }
      
      clearExcept([currentVideoId]);
    } else {
      clearAll();
    }
  }

  /// **Dispose all resources**
  void dispose() {
    AppLogger.log('🗑️ SharedPool: Disposing all resources');
    clearAll();
    _disposalStreamController.close();
  }
}

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

class PictureInPictureModeEvent {
  final String ownerId;
  final bool isActive;

  const PictureInPictureModeEvent(this.ownerId, this.isActive);
}

class PictureInPicturePlaybackEvent {
  final String ownerId;
  final bool shouldPlay;

  const PictureInPicturePlaybackEvent(this.ownerId, this.shouldPlay);
}

/// Session-aware bridge to the host platform's picture-in-picture player.
///
/// Yug and Vayu can stay mounted together. Only the surface that most recently
/// supplied active playback state owns native PiP callbacks, so a hidden feed
/// cannot pause or rebuild the visible player.
class PictureInPictureService {
  static const String channelName = 'vayug/picture_in_picture';
  static final PictureInPictureService instance = PictureInPictureService();

  final MethodChannel _channel;
  final StreamController<PictureInPictureModeEvent> _modeChanges =
      StreamController<PictureInPictureModeEvent>.broadcast(sync: true);
  final StreamController<PictureInPicturePlaybackEvent> _playbackRequests =
      StreamController<PictureInPicturePlaybackEvent>.broadcast(sync: true);
  final StreamController<String> _preparationRequests =
      StreamController<String>.broadcast(sync: true);

  Future<bool>? _supportCheck;
  String? _activeOwnerId;
  double _lastAspectRatio = 16 / 9;
  bool _lastIsPlaying = false;
  bool _desiredAutoEnterEnabled = false;
  List<double>? _lastSourceRect;
  int _autoEnterSuppressionCount = 0;

  PictureInPictureService({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(channelName);

  /// Whether the Activity is rendering for the system PiP window.
  ///
  /// Android shrinks the whole Activity, not just the player, so app chrome
  /// that lives outside the owning surface (the main bottom navigation bar)
  /// has to collapse too. This is owner-independent on purpose: the shell has
  /// no way to know which feed asked for PiP, only that PiP is happening.
  final ValueNotifier<bool> isActive = ValueNotifier<bool>(false);

  Stream<PictureInPictureModeEvent> get modeChanges => _modeChanges.stream;
  Stream<PictureInPicturePlaybackEvent> get playbackRequests =>
      _playbackRequests.stream;
  Stream<String> get preparationRequests => _preparationRequests.stream;

  Future<bool> initialize() {
    _channel.setMethodCallHandler(_handlePlatformCall);
    return _supportCheck ??= _checkSupport();
  }

  Future<bool> _checkSupport() async {
    try {
      return await _channel.invokeMethod<bool>('isSupported') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  Future<bool> enter({
    required String ownerId,
    required double aspectRatio,
    required bool isPlaying,
    List<double>? sourceRect,
  }) async {
    _activeOwnerId = ownerId;
    try {
      return await _channel.invokeMethod<bool>('enter', <String, Object>{
            'aspectRatio': aspectRatio,
            'isPlaying': isPlaying,
            if (sourceRect != null) 'sourceRect': sourceRect,
          }) ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  Future<void> update({
    required String ownerId,
    required double aspectRatio,
    required bool isPlaying,
    required bool autoEnterEnabled,
    List<double>? sourceRect,
  }) async {
    if (autoEnterEnabled) {
      _activeOwnerId = ownerId;
    } else if (_activeOwnerId != ownerId) {
      return;
    }
    _lastAspectRatio = aspectRatio;
    _lastIsPlaying = isPlaying;
    _desiredAutoEnterEnabled = autoEnterEnabled;
    _lastSourceRect = sourceRect;
    await _sendUpdate(
      aspectRatio: aspectRatio,
      isPlaying: isPlaying,
      autoEnterEnabled: autoEnterEnabled && _autoEnterSuppressionCount == 0,
      sourceRect: sourceRect,
    );
  }

  /// Prevents a system dialog from being mistaken for a Home gesture.
  ///
  /// Android 12's framework auto-enter can shrink an Activity while a runtime
  /// permission prompt is opening. Keep the desired player state and restore
  /// it after the dialog closes, without allowing that transition into PiP.
  Future<T> withAutoEnterSuppressed<T>(Future<T> Function() action) async {
    _autoEnterSuppressionCount++;
    if (_autoEnterSuppressionCount == 1 && _activeOwnerId != null) {
      await _sendUpdate(
        aspectRatio: _lastAspectRatio,
        isPlaying: _lastIsPlaying,
        autoEnterEnabled: false,
        sourceRect: _lastSourceRect,
      );
    }
    try {
      return await action();
    } finally {
      _autoEnterSuppressionCount--;
      if (_autoEnterSuppressionCount == 0 && _activeOwnerId != null) {
        await _sendUpdate(
          aspectRatio: _lastAspectRatio,
          isPlaying: _lastIsPlaying,
          autoEnterEnabled: _desiredAutoEnterEnabled,
          sourceRect: _lastSourceRect,
        );
      }
    }
  }

  Future<void> release(String ownerId) async {
    if (_activeOwnerId != ownerId) return;
    await _sendUpdate(
      aspectRatio: 16 / 9,
      isPlaying: false,
      autoEnterEnabled: false,
    );
    if (_activeOwnerId == ownerId) {
      // The owner is going away (dispose), so no `modeChanged` can arrive to
      // restore the app chrome. Without this the shell would keep its bottom
      // navigation collapsed for the rest of the session.
      isActive.value = false;
      _activeOwnerId = null;
      _desiredAutoEnterEnabled = false;
      _lastIsPlaying = false;
      _lastSourceRect = null;
    }
  }

  Future<void> _sendUpdate({
    required double aspectRatio,
    required bool isPlaying,
    required bool autoEnterEnabled,
    List<double>? sourceRect,
  }) async {
    try {
      await _channel.invokeMethod<void>('update', <String, Object>{
        'aspectRatio': aspectRatio,
        'isPlaying': isPlaying,
        'autoEnterEnabled': autoEnterEnabled,
        if (sourceRect != null) 'sourceRect': sourceRect,
      });
    } on MissingPluginException {
      // PiP is optional on unsupported platforms.
    } on PlatformException {
      // A transient host failure must never interrupt video playback.
    }
  }

  Future<void> dispose() async {
    final ownerId = _activeOwnerId;
    if (ownerId != null) await release(ownerId);
    _channel.setMethodCallHandler(null);
    await _modeChanges.close();
    await _playbackRequests.close();
    await _preparationRequests.close();
  }

  Future<Object?> _handlePlatformCall(MethodCall call) async {
    final ownerId = _activeOwnerId;
    if (ownerId == null) return null;
    switch (call.method) {
      case 'prepareToEnter':
        // Android PiP contains the complete Activity; sourceRectHint controls
        // only its transition animation and does not crop the final window.
        // Ask the active Flutter surface to render its video-only tree, then
        // wait for that frame before allowing Android to shrink the Activity.
        isActive.value = true;
        _preparationRequests.add(ownerId);
        await SchedulerBinding.instance.endOfFrame;
        return true;
      case 'modeChanged':
        final arguments = call.arguments;
        final isModeActive =
            arguments is Map ? arguments['isActive'] as bool? ?? false : false;
        // Also covers a failed entry: the host reports `false` after
        // `prepareToEnter` optimistically shrank the app chrome.
        isActive.value = isModeActive;
        _modeChanges.add(PictureInPictureModeEvent(ownerId, isModeActive));
        break;
      case 'playbackRequested':
        final arguments = call.arguments;
        final shouldPlay = arguments is Map
            ? arguments['shouldPlay'] as bool? ?? false
            : false;
        _playbackRequests.add(
          PictureInPicturePlaybackEvent(ownerId, shouldPlay),
        );
        break;
    }
    return null;
  }
}

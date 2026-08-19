import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:flutter_volume_controller/flutter_volume_controller.dart';
import 'package:video_player/video_player.dart';
import 'package:vibration/vibration.dart';

/// Mixin to handle all gesture and control button logic for the Vayu Player.
/// This keeps the main screen file clean from volume, brightness, seeking, and UI overlay timers.
mixin VayuPlayerGesturesMixin<T extends StatefulWidget> on State<T> {
  // Controls State
  // Controls State (Using ValueNotifiers for performance optimization)
  final ValueNotifier<bool> showControlsVN = ValueNotifier<bool>(true);
  final ValueNotifier<bool> showScrubbingOverlayVN = ValueNotifier<bool>(false);
  final ValueNotifier<Duration> scrubbingTargetTimeVN = ValueNotifier<Duration>(Duration.zero);
  final ValueNotifier<Duration> scrubbingDeltaVN = ValueNotifier<Duration>(Duration.zero);
  final ValueNotifier<bool> isForwardVN = ValueNotifier<bool>(true);
  final ValueNotifier<bool> isControlsLockedVN = ValueNotifier<bool>(false);
  final ValueNotifier<bool> isSeekingBufferingVN = ValueNotifier<bool>(false);

  // Getters for compatibility (optional, but good for transition)
  bool get showControls => showControlsVN.value;
  bool get showScrubbingOverlay => showScrubbingOverlayVN.value;
  Duration get scrubbingTargetTime => scrubbingTargetTimeVN.value;
  Duration get scrubbingDelta => scrubbingDeltaVN.value;
  bool get isForward => isForwardVN.value;
  bool get isControlsLocked => isControlsLockedVN.value;
  bool get isSeekingBuffering => isSeekingBufferingVN.value;

  double horizontalDragTotal = 0.0;
  Timer? controlsTimer;

  // Gesture state
  double brightnessValue = 0.5;
  double volumeValue = 0.5;
  Timer? overlayTimer;

  /// The host state must provide the current active video controller.
  VideoPlayerController? get currentVideoController;

  /// Hosts with playback policy can override this instead of allowing a
  /// gesture to call VideoPlayerController.play directly.
  Future<void> playCurrentVideo() async {
    await currentVideoController?.play();
  }

  /// Host screens can persist user intent in their playback session.
  void onUserPlaybackChanged(bool isPlaying) {}

  void handleUnifiedHorizontalDrag(double deltaX) {
    if (isControlsLocked || currentVideoController == null) return;
    overlayTimer?.cancel();
    horizontalDragTotal += deltaX;
    final controller = currentVideoController!;
    final seekOffset = Duration(milliseconds: (horizontalDragTotal * 500).toInt());
    var targetPosition = controller.value.position + seekOffset;
    if (targetPosition < Duration.zero) targetPosition = Duration.zero;
    if (targetPosition > controller.value.duration) targetPosition = controller.value.duration;

    showScrubbingOverlayVN.value = true;
    scrubbingTargetTimeVN.value = targetPosition;
    scrubbingDeltaVN.value = seekOffset;
    isForwardVN.value = deltaX > 0;
    overlayTimer = Timer(const Duration(milliseconds: 900), () {
      if (mounted) showScrubbingOverlayVN.value = false;
    });
  }

  void handleHorizontalDragEnd() {
    overlayTimer?.cancel();
    if (currentVideoController != null) {
      isSeekingBufferingVN.value = true;
      currentVideoController!.seekTo(scrubbingTargetTimeVN.value);
    }
    showScrubbingOverlayVN.value = false;
    horizontalDragTotal = 0.0;
    showControlsVN.value = true;
  }

  void handleVerticalDragUpdate(double primaryDelta, Offset localPosition, Size size) {
    if (isControlsLocked) return;
    final isLeftSide = localPosition.dx < size.width / 2;
    final delta = primaryDelta / size.height * 1.5;
    if (isLeftSide) {
      brightnessValue = (brightnessValue - delta).clamp(0.0, 1.0);
      ScreenBrightness().setApplicationScreenBrightness(brightnessValue);
    } else {
      volumeValue = (volumeValue - delta).clamp(0.0, 1.0);
      FlutterVolumeController.setVolume(volumeValue);
    }
    showScrubbingOverlayVN.value = false;
    showControlsVN.value = false;
    resetOverlayTimer();
    controlsTimer?.cancel();
  }

  void resetOverlayTimer() {
    overlayTimer?.cancel();
  }

  void handleTap(Orientation orientation) {
    showControlsVN.value = !showControlsVN.value;
    if (orientation == Orientation.landscape) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
    if (showControlsVN.value) startHideControlsTimer(orientation);
  }

  void startHideControlsTimer(Orientation orientation) {
    controlsTimer?.cancel();
    controlsTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        showControlsVN.value = false;
        if (orientation == Orientation.landscape) {
          SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
        }
      }
    });
  }

  void handleDoubleTapToSeek(TapDownDetails details, Size size, Orientation orientation) {
    final controller = currentVideoController;
    if (controller == null || !controller.value.isInitialized) return;
    final isLeftSide = details.localPosition.dx < size.width / 2;
    final seekOffset = Duration(seconds: isLeftSide ? -10 : 10);
    var target = controller.value.position + seekOffset;
    if (target < Duration.zero) target = Duration.zero;
    if (target > controller.value.duration) target = controller.value.duration;
    
    isSeekingBufferingVN.value = true;
    controller.seekTo(target);
    showControlsVN.value = true;
    showScrubbingOverlayVN.value = true;
    scrubbingTargetTimeVN.value = target;
    scrubbingDeltaVN.value = seekOffset;
    isForwardVN.value = !isLeftSide;
    
    startHideControlsTimer(orientation);
    overlayTimer?.cancel();
    overlayTimer = Timer(const Duration(milliseconds: 700), () {
      if (mounted) showScrubbingOverlayVN.value = false;
    });
  }

  void togglePlay() {
    final controller = currentVideoController;
    if (controller == null) return;
    Vibration.vibrate(duration: 50, amplitude: 128);
    if (controller.value.isPlaying) {
      controller.pause();
      onUserPlaybackChanged(false);
    } else {
      onUserPlaybackChanged(true);
      playCurrentVideo();
      hideControlsWithDelay();
    }
  }

  void hideControlsWithDelay() {
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted && currentVideoController?.value.isPlaying == true && showControlsVN.value) {
        showControlsVN.value = false;
      }
    });
  }

  void disposeGestures() {
    controlsTimer?.cancel();
    overlayTimer?.cancel();
    showControlsVN.dispose();
    showScrubbingOverlayVN.dispose();
    scrubbingTargetTimeVN.dispose();
    scrubbingDeltaVN.dispose();
    isForwardVN.dispose();
    isControlsLockedVN.dispose();
    isSeekingBufferingVN.dispose();
  }
}

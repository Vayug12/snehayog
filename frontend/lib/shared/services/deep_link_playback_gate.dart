import 'package:vayug/features/video/core/presentation/managers/shared_video_controller_pool.dart';
import 'package:vayug/features/video/core/presentation/managers/video_controller_manager.dart';

/// Keeps the home feed silent while a shared-video link is being resolved.
///
/// The target player is not allowed to be chosen until its metadata is known.
/// This gate prevents a preloaded Yug item from starting in the meantime.
class DeepLinkPlaybackGate {
  DeepLinkPlaybackGate._();

  static int _activeRequestId = 0;
  static bool _isActive = false;

  static bool get isActive => _isActive;

  static int beginResolution() {
    _activeRequestId++;
    _isActive = true;
    pauseAllPlayback();
    return _activeRequestId;
  }

  static bool isCurrent(int requestId) =>
      _isActive && requestId == _activeRequestId;

  static void release(int requestId) {
    if (requestId == _activeRequestId) {
      _isActive = false;
    }
  }

  static void pauseAllPlayback() {
    SharedVideoControllerPool().pauseAllControllers();
    VideoControllerManager().forcePauseAllVideosSync();
  }
}

import 'package:flutter/widgets.dart';
import 'package:vayug/features/video/core/data/models/video_model.dart';

/// Keeps a vertical video feed's [PageController] pointed at a chosen video.
///
/// Every feed here tracks the video on screen twice: once as an index field,
/// and once as the PageView's own scroll position. The two drift apart whenever
/// something invalidates positions:
///
///  * the list drops leading entries to cap memory, shifting every index below
///    the viewport while the viewport itself stays put;
///  * the PageView is unmounted and rebuilt. System picture-in-picture does
///    this — the player swaps in a video-only tree while the Activity is
///    shrunk, so on the way back a fresh PageView starts at its `initialPage`
///    while the still-playing controller belongs to a different video.
///
/// Either way the feed ends up showing one video and playing another. Indices
/// cannot survive those events; ids can, so everything here resolves a video
/// **id** against the list as it exists at call time.
class FeedPageAlignment {
  FeedPageAlignment._();

  /// Current position of [videoId] in [videos], or -1 when it is not there.
  ///
  /// A -1 is a real answer, not a failure: the video was dropped from the list
  /// while the caller was not looking. Callers must leave their index field
  /// alone in that case, because any positional guess would quietly select a
  /// different video — the exact failure this class exists to prevent.
  static int indexOfVideoId(List<VideoModel> videos, String? videoId) {
    if (videoId == null || videos.isEmpty) return -1;
    return videos.indexWhere((video) => video.id == videoId);
  }

  /// Snaps [controller]'s viewport to [index] without animating.
  ///
  /// Update the feed's own index field *before* calling this. `jumpToPage`
  /// reaches `onPageChanged`, and every feed here opens that callback with
  /// `if (index == _currentIndex) return;` — so a realignment the field already
  /// reflects stays silent instead of re-running page-change side effects
  /// (pausing, view tracking, preloads, ad rotation) for a page the user never
  /// actually left.
  ///
  /// Does nothing while the PageView is detached, which is the normal state
  /// during the build that remounts it; callers run this from a post-frame
  /// callback for that reason.
  static void jumpToIndex(PageController controller, int index) {
    if (index < 0 || !controller.hasClients) return;
    controller.jumpToPage(index);
  }
}

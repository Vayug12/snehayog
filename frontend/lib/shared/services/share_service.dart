import 'package:share_plus/share_plus.dart';
import 'package:vayug/features/ads/data/carousel_ad_model.dart';
import 'package:vayug/features/video/core/data/models/video_model.dart';
import 'package:vayug/features/video/core/data/services/video_service.dart';
import 'package:vayug/shared/utils/app_logger.dart';
import 'package:vayug/shared/utils/url_utils.dart';

class ShareService {
  final VideoService _videoService = VideoService();

  /// Shares a public app link. Section timestamps are part of the link so a
  /// recipient can enter the player at the selected point.
  Future<void> shareVideo(
    VideoModel video, {
    Duration? startAt,
    Duration? endAt,
  }) async {
    try {
      final shareText = _generateVideoShareText(
        video,
        startAt: startAt,
        endAt: endAt,
      );
      await SharePlus.instance.share(ShareParams(text: shareText));
      await _incrementVideoShareCount(video.id);
    } catch (e) {
      AppLogger.log('ShareService: Error sharing video: $e');
    }
  }

  Future<void> shareAd(CarouselAdModel ad) async {
    try {
      final shareText = _generateAdShareText(ad);
      await SharePlus.instance.share(ShareParams(text: shareText));
    } catch (e) {
      AppLogger.log('ShareService: Error sharing ad: $e');
    }
  }

  String _generateVideoShareText(
    VideoModel video, {
    Duration? startAt,
    Duration? endAt,
  }) {
    final queryParameters = <String, String>{};
    final startSeconds = startAt?.inSeconds ?? 0;
    final endSeconds = endAt?.inSeconds;

    if (startSeconds > 0 || (endSeconds != null && endSeconds > startSeconds)) {
      queryParameters['t'] = '$startSeconds';
    }
    if (endSeconds != null && endSeconds > startSeconds) {
      queryParameters['end'] = '$endSeconds';
    }

    final shareLink = UrlUtils.buildVideoShareUrl(
      video.id,
      video.videoName,
      queryParameters: queryParameters,
    );
    final sectionLabel = endSeconds != null && endSeconds > startSeconds
        ? ' Watch the shared section.'
        : startSeconds > 0
            ? ' Starts at ${_formatTimestamp(startSeconds)}.'
            : '';

    return 'Watch "${video.videoName}" on Vayug.$sectionLabel\n\n$shareLink';
  }

  String _formatTimestamp(int seconds) {
    final duration = Duration(seconds: seconds);
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final remainingSeconds =
        duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (duration.inHours > 0) {
      return '${duration.inHours}:$minutes:$remainingSeconds';
    }
    return '${duration.inMinutes}:$remainingSeconds';
  }

  String _generateAdShareText(CarouselAdModel ad) {
    final link = ad.callToActionUrl;
    return 'Check out this ad on Vayu: ${ad.slides.firstOrNull?.title ?? "Great content"} \n$link';
  }

  Future<void> _incrementVideoShareCount(String videoId) async {
    try {
      await _videoService.incrementShares(videoId);
      AppLogger.log('Share count updated for video: $videoId');
    } catch (e) {
      AppLogger.log('ShareService: Failed to update share count: $e');
    }
  }
}

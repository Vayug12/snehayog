import 'package:vayug/features/video/core/data/models/video_model.dart';

/// Resolves which URL a [VideoModel] is actually streaming from.
///
/// The same three-step fallback — selected dub, then an HLS playlist, then the
/// plain source — is needed in three unrelated places: building a controller,
/// deciding which background prefetches to keep alive, and reporting what a
/// surface is currently playing. Keeping it here means those three can never
/// disagree about which URL belongs to a video, which is what makes prefetch
/// bookkeeping (keyed by URL hash) reliable.
String resolveActingUrl(VideoModel video, {String? selectedLanguage}) {
  if (selectedLanguage != null && selectedLanguage != 'default') {
    final dubbed = video.dubbedUrls?[selectedLanguage];
    if (dubbed != null && dubbed.isNotEmpty) return dubbed;
  }

  final playlist = video.hlsPlaylistUrl;
  if (playlist != null && playlist.isNotEmpty) return playlist;

  final master = video.hlsMasterPlaylistUrl;
  if (master != null && master.isNotEmpty) return master;

  return video.videoUrl;
}

/// Every URL that could have been used to cache or prefetch [video].
///
/// Prefetches are tracked by URL hash, and a video can legitimately be fetched
/// under more than one of its URLs — `VideoControllerFactory` prefetches
/// `videoUrl` while the player streams the HLS playlist. A keep-set built from
/// only one of them cancels a download that is still needed.
Set<String> cacheKeyUrlsFor(VideoModel video, {String? selectedLanguage}) {
  return <String>{
    resolveActingUrl(video, selectedLanguage: selectedLanguage),
    video.videoUrl,
  }..removeWhere((url) => url.isEmpty);
}

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:vayug/features/video/core/data/models/video_model.dart';
import 'package:vayug/features/video/feed/presentation/screens/video_feed_advanced/widgets/video_aspect_surface.dart';
import 'package:vayug/core/design/colors.dart';

class VideoPage extends StatelessWidget {
  final VideoModel video;
  final VideoPlayerController? controller;
  final bool isActive;
  final int index;
  final Widget overlay;
  final Widget? buffering;
  final Widget? progressBar;
  final bool showPlayer;
  final VoidCallback? onControllerInvalid;

  const VideoPage({
    Key? key,
    required this.video,
    required this.controller,
    required this.isActive,
    required this.index,
    required this.overlay,
    this.buffering,
    this.progressBar,
    this.showPlayer = true,
    this.onControllerInvalid,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      color: Colors.black,
      child: Stack(
        children: [
          Align(
            alignment: Alignment.bottomCenter,
            child: AspectRatio(
              aspectRatio: video.aspectRatio,
              child: _buildVideoThumbnail(video),
            ),
          ),
          if (controller == null ||
              (() {
                try {
                  return !controller!.value.isInitialized;
                } catch (_) {
                  return true;
                }
              }()))
            Align(
              alignment: Alignment.bottomCenter,
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
          if (controller != null &&
              showPlayer &&
              (() {
                try {
                  return controller!.value.isInitialized;
                } catch (_) {
                  return false;
                }
              }()))
            Positioned.fill(
              child: VideoAspectSurface(
                key: ValueKey('vas_${controller.hashCode}'),
                controller: controller!,
                modelAspectRatio: video.aspectRatio,
                onControllerInvalid: onControllerInvalid,
              ),
            ),
          if (buffering != null) Positioned.fill(child: buffering!),
          if (progressBar != null)
            Positioned(left: 0, right: 0, bottom: 0, child: progressBar!),
          overlay,
        ],
      ),
    );
  }

  Widget _buildVideoThumbnail(VideoModel video) {
    if (video.thumbnailUrl.isEmpty) {
      return Container(color: Colors.black);
    }

    return CachedNetworkImage(
      imageUrl: video.thumbnailUrl,
      fit: BoxFit.cover,
      memCacheWidth: 1080,
      maxWidthDiskCache: 1080,
      placeholder: (context, url) => Container(color: Colors.black),
      errorWidget: (context, url, error) => Container(color: Colors.black),
    );
  }
}


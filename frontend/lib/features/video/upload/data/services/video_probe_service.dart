import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'package:vayug/shared/utils/app_logger.dart';

/// What we could read off a local video file before uploading it.
class VideoProbe {
  final Duration duration;
  final double aspectRatio;
  final Uint8List? thumbnail;

  const VideoProbe({
    required this.duration,
    required this.aspectRatio,
    this.thumbnail,
  });
}

/// Reads duration, aspect ratio and a poster frame off local video files.
///
/// Probing means spinning up a real platform decoder per file, so this is the
/// expensive part of picking episodes. Two rules keep it from freezing the UI:
/// probes run at bounded concurrency instead of one-at-a-time, and every probe
/// is time-boxed so a corrupt file cannot hang the picker forever.
class VideoProbeService {
  static const int _maxConcurrentProbes = 3;
  static const Duration _probeTimeout = Duration(seconds: 12);
  static const int _thumbnailWidth = 160;

  /// Probes [file]. Returns null when the file is unreadable — callers decide
  /// whether that is fatal; the backend still does authoritative validation.
  Future<VideoProbe?> probe(File file, {bool withThumbnail = true}) async {
    try {
      if (!await file.exists()) return null;

      final metadata = await _readMetadata(file).timeout(
        _probeTimeout,
        onTimeout: () => null,
      );
      if (metadata == null) return null;

      final thumbnail =
          withThumbnail ? await _readThumbnail(file.path) : null;

      return VideoProbe(
        duration: metadata.$1,
        aspectRatio: metadata.$2,
        thumbnail: thumbnail,
      );
    } catch (e) {
      AppLogger.log('VideoProbeService: probe failed for ${file.path}: $e');
      return null;
    }
  }

  /// Probes every file, at most [_maxConcurrentProbes] at a time. The result is
  /// positionally aligned with [files]; a null entry means that file failed.
  Future<List<VideoProbe?>> probeAll(
    List<File> files, {
    bool withThumbnail = true,
  }) async {
    final results = <VideoProbe?>[];
    for (var i = 0; i < files.length; i += _maxConcurrentProbes) {
      final end = (i + _maxConcurrentProbes).clamp(0, files.length);
      final batch = files.sublist(i, end);
      results.addAll(
        await Future.wait(
          batch.map((file) => probe(file, withThumbnail: withThumbnail)),
        ),
      );
    }
    return results;
  }

  /// (duration, aspectRatio) or null.
  Future<(Duration, double)?> _readMetadata(File file) async {
    VideoPlayerController? controller;
    try {
      controller = VideoPlayerController.file(file);
      await controller.initialize();
      final value = controller.value;
      final size = value.size;
      final aspectRatio = (size.width > 0 && size.height > 0)
          ? size.width / size.height
          : 9 / 16;
      return (value.duration, aspectRatio);
    } catch (e) {
      AppLogger.log('VideoProbeService: metadata read failed: $e');
      return null;
    } finally {
      await controller?.dispose();
    }
  }

  Future<Uint8List?> _readThumbnail(String path) async {
    try {
      return await VideoThumbnail.thumbnailData(
        video: path,
        imageFormat: ImageFormat.JPEG,
        maxWidth: _thumbnailWidth,
        quality: 60,
      ).timeout(_probeTimeout, onTimeout: () => null);
    } catch (e) {
      AppLogger.log('VideoProbeService: thumbnail failed for $path: $e');
      return null;
    }
  }
}

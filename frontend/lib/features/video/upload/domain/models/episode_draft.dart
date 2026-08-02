import 'dart:io';
import 'dart:typed_data';

/// A series needs at least this many episodes to be meaningful. Episode 1 is
/// always the video picked in the main upload flow, so the user has to add at
/// least [kMinEpisodesPerSeries] - 1 extra episodes.
const int kMinEpisodesPerSeries = 2;

/// Clips shorter than this are rejected — the feed treats them as unwatchable.
const Duration kMinEpisodeDuration = Duration(seconds: 8);

/// One *extra* episode in a series draft, before anything is uploaded.
///
/// Episode 1 is never an [EpisodeDraft]: it is the video already selected in
/// the main upload flow, and stays the single source of truth for that file.
/// Drafts only describe episodes 2..N.
///
/// The episode number is deliberately not stored — it is derived from list
/// position at upload time, so reordering can never leave stale numbering
/// behind.
class EpisodeDraft {
  final File file;
  final String title;

  /// Null when the probe failed (corrupt file, unsupported codec). The draft is
  /// still usable; the backend does the authoritative validation.
  final Duration? duration;
  final Uint8List? thumbnail;

  const EpisodeDraft({
    required this.file,
    required this.title,
    this.duration,
    this.thumbnail,
  });

  String get path => file.path;

  EpisodeDraft copyWith({String? title}) => EpisodeDraft(
        file: file,
        title: title ?? this.title,
        duration: duration,
        thumbnail: thumbnail,
      );

  /// `my_holiday-clip 01.mp4` -> `my holiday clip 01`.
  static String titleFromFile(File file) {
    final fileName = file.path.split(RegExp(r'[/\\]')).last;
    final dotIndex = fileName.lastIndexOf('.');
    final baseName = dotIndex > 0 ? fileName.substring(0, dotIndex) : fileName;
    final cleaned = baseName.replaceAll(RegExp(r'[_\-]+'), ' ').trim();
    return cleaned.isEmpty ? 'Untitled episode' : cleaned;
  }

  static String formatDuration(Duration? duration) {
    if (duration == null) return '--:--';
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is EpisodeDraft && other.path == path);

  @override
  int get hashCode => path.hashCode;
}

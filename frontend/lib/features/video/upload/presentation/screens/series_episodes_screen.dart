import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vayug/core/design/colors.dart';
import 'package:vayug/core/design/spacing.dart';
import 'package:vayug/core/design/typography.dart';
import 'package:vayug/features/video/upload/data/services/video_probe_service.dart';
import 'package:vayug/features/video/upload/domain/models/episode_draft.dart';
import 'package:vayug/shared/services/file_picker_service.dart';
import 'package:vayug/shared/utils/app_logger.dart';
import 'package:vayug/shared/widgets/app_button.dart';
import 'package:vayug/shared/widgets/vayu_snackbar.dart';

/// Arranges the episodes of a series. **This screen never uploads anything.**
///
/// It is a settings screen like every other one reachable from Advanced
/// Settings: it edits the draft and hands it back with Save. The upload itself
/// stays where the user started it, in the main flow, so the metadata they
/// already filled in is never abandoned.
///
/// Episode 1 is fixed: it is the video picked in the main flow. Only episodes
/// 2..N live here, which is what [initialEpisodes] holds and what Save returns.
class SeriesEpisodesScreen extends ConsumerStatefulWidget {
  final File primaryVideo;
  final String primaryTitle;
  final List<EpisodeDraft> initialEpisodes;

  const SeriesEpisodesScreen({
    super.key,
    required this.primaryVideo,
    required this.primaryTitle,
    this.initialEpisodes = const [],
  });

  @override
  ConsumerState<SeriesEpisodesScreen> createState() =>
      _SeriesEpisodesScreenState();
}

class _SeriesEpisodesScreenState extends ConsumerState<SeriesEpisodesScreen> {
  final VideoProbeService _probeService = VideoProbeService();
  late final FilePickerService _filePickerService;

  late List<EpisodeDraft> _episodes;
  VideoProbe? _primaryProbe;
  bool _isProbing = false;
  bool _isDirty = false;

  int get _totalEpisodes => _episodes.length + 1;
  bool get _meetsMinimum => _totalEpisodes >= kMinEpisodesPerSeries;

  @override
  void initState() {
    super.initState();
    _filePickerService = ref.read(filePickerServiceProvider);
    _episodes = List<EpisodeDraft>.from(widget.initialEpisodes);
    _probePrimary();
  }

  Future<void> _probePrimary() async {
    final probe = await _probeService.probe(widget.primaryVideo);
    if (!mounted) return;
    setState(() => _primaryProbe = probe);
  }

  // --- Actions ---

  Future<void> _addEpisodes() async {
    if (_isProbing) return;

    FilePickerResult? result;
    try {
      result = await _filePickerService.pickFiles(
        type: FileType.custom,
        allowMultiple: true,
        allowedExtensions: const ['mp4', 'avi', 'mov', 'wmv', 'flv', 'webm'],
      );
    } catch (e) {
      AppLogger.log('SeriesEpisodesScreen: file pick failed: $e');
      if (mounted) {
        VayuSnackBar.showError(context, 'Could not open your files. Try again.');
      }
      return;
    }

    if (result == null || !mounted) return;

    final knownPaths = {
      widget.primaryVideo.path,
      ..._episodes.map((e) => e.path),
    };
    final picked = <File>[];
    var duplicates = 0;
    for (final path in result.paths) {
      if (path == null) continue;
      if (!knownPaths.add(path)) {
        duplicates++;
        continue;
      }
      picked.add(File(path));
    }

    if (picked.isEmpty) {
      if (duplicates > 0) {
        VayuSnackBar.showInfo(
            context, 'Those episodes are already in this series.');
      }
      return;
    }

    setState(() => _isProbing = true);
    final probes = await _probeService.probeAll(picked);
    if (!mounted) return;

    final accepted = <EpisodeDraft>[];
    final rejected = <String>[];

    for (var i = 0; i < picked.length; i++) {
      final file = picked[i];
      final probe = probes[i];
      // A failed probe is not a rejection: the file may simply use a codec the
      // local decoder cannot open. The backend validates authoritatively.
      if (probe != null && probe.duration < kMinEpisodeDuration) {
        rejected.add(_fileName(file));
        continue;
      }
      accepted.add(EpisodeDraft(
        file: file,
        title: EpisodeDraft.titleFromFile(file),
        duration: probe?.duration,
        thumbnail: probe?.thumbnail,
      ));
    }

    setState(() {
      _episodes.addAll(accepted);
      _isProbing = false;
      if (accepted.isNotEmpty) _isDirty = true;
    });

    if (rejected.isNotEmpty) {
      _showRejectedDialog(rejected);
    } else if (duplicates > 0) {
      VayuSnackBar.showInfo(
          context, '$duplicates already in this series and skipped.');
    }
  }

  void _showRejectedDialog(List<String> rejected) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.backgroundSecondary,
        title: const Text('Some clips were too short'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Episodes must be at least ${kMinEpisodeDuration.inSeconds} seconds long. These were not added:',
              style: AppTypography.bodySmall
                  .copyWith(color: AppColors.textSecondary),
            ),
            AppSpacing.vSpace12,
            ...rejected.map(
              (name) => Padding(
                padding: EdgeInsets.only(bottom: AppSpacing.space4),
                child: Text('• $name', style: AppTypography.bodySmall),
              ),
            ),
          ],
        ),
        actions: [
          AppButton(
            onPressed: () => Navigator.pop(dialogContext),
            label: 'Got it',
            variant: AppButtonVariant.primary,
          ),
        ],
      ),
    );
  }

  void _editTitle(int index) {
    final controller = TextEditingController(text: _episodes[index].title);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.backgroundPrimary,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 24,
          left: 24,
          right: 24,
          top: 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Episode ${index + 2} title',
                style: AppTypography.titleMedium
                    .copyWith(fontWeight: FontWeight.bold)),
            AppSpacing.vSpace16,
            TextField(
              controller: controller,
              autofocus: true,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                hintText: 'Episode title',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              onSubmitted: (_) => Navigator.pop(sheetContext),
            ),
            AppSpacing.vSpace24,
            AppButton(
              onPressed: () => Navigator.pop(sheetContext),
              label: 'Save Title',
              variant: AppButtonVariant.primary,
              isFullWidth: true,
            ),
          ],
        ),
      ),
    ).whenComplete(() {
      final title = controller.text.trim();
      controller.dispose();
      if (title.isEmpty || !mounted) return;
      if (title == _episodes[index].title) return;
      setState(() {
        _episodes[index] = _episodes[index].copyWith(title: title);
        _isDirty = true;
      });
    });
  }

  void _removeEpisode(int index) {
    setState(() {
      _episodes.removeAt(index);
      _isDirty = true;
    });
  }

  /// [newIndex] already accounts for the removed item — that adjustment is what
  /// `onReorderItem` does over the deprecated `onReorder`.
  void _reorder(int oldIndex, int newIndex) {
    setState(() {
      _episodes.insert(newIndex, _episodes.removeAt(oldIndex));
      _isDirty = true;
    });
  }

  void _save() => Navigator.pop(context, List<EpisodeDraft>.from(_episodes));

  Future<void> _removeSeries() async {
    final confirmed = await _confirm(
      title: 'Remove series?',
      message:
          'Your video will be uploaded on its own. The episodes you added here are discarded.',
      confirmLabel: 'Remove series',
    );
    if (confirmed && mounted) Navigator.pop(context, <EpisodeDraft>[]);
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    required String confirmLabel,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.backgroundSecondary,
        title: Text(title),
        content: Text(message,
            style: AppTypography.bodySmall
                .copyWith(color: AppColors.textSecondary)),
        actions: [
          AppButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            label: 'Keep editing',
            variant: AppButtonVariant.text,
          ),
          AppButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            label: confirmLabel,
            variant: AppButtonVariant.danger,
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _handlePop() async {
    if (!_isDirty) {
      Navigator.pop(context);
      return;
    }
    final discard = await _confirm(
      title: 'Discard changes?',
      message: 'Your episode list will go back to how it was.',
      confirmLabel: 'Discard',
    );
    if (discard && mounted) Navigator.pop(context);
  }

  static String _fileName(File file) =>
      file.path.split(RegExp(r'[/\\]')).last;

  // --- UI ---

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isDirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handlePop();
      },
      child: Scaffold(
        backgroundColor: AppColors.backgroundPrimary,
        appBar: AppBar(
          title: const Text('Series Episodes'),
          centerTitle: true,
          backgroundColor: AppColors.backgroundPrimary,
          elevation: 0,
          actions: [
            if (_episodes.isNotEmpty)
              IconButton(
                onPressed: _removeSeries,
                icon: const Icon(Icons.delete_outline_rounded),
                tooltip: 'Remove series',
              ),
          ],
          bottom: _isProbing
              ? const PreferredSize(
                  preferredSize: Size.fromHeight(2),
                  child: LinearProgressIndicator(minHeight: 2),
                )
              : null,
        ),
        body: ReorderableListView.builder(
          padding: EdgeInsets.fromLTRB(
              AppSpacing.space16, 0, AppSpacing.space16, AppSpacing.space24),
          header: _buildHeader(),
          footer: _buildFooter(),
          itemCount: _episodes.length,
          onReorderItem: _reorder,
          itemBuilder: (context, index) => _buildEpisodeTile(index),
        ),
        bottomNavigationBar: _buildBottomBar(),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      key: const ValueKey('series-header'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppSpacing.vSpace8,
        Text(
          'Arrange your episodes',
          style:
              AppTypography.titleMedium.copyWith(fontWeight: FontWeight.bold),
        ),
        AppSpacing.vSpace4,
        Text(
          'Drag to reorder — episode numbers update automatically. Nothing uploads until you start the upload.',
          style:
              AppTypography.bodySmall.copyWith(color: AppColors.textTertiary),
        ),
        AppSpacing.vSpace16,
        _buildPrimaryTile(),
        if (_episodes.isNotEmpty) ...[
          AppSpacing.vSpace16,
          Text(
            'NEXT EPISODES',
            style: AppTypography.labelSmall.copyWith(
              color: AppColors.textTertiary,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
            ),
          ),
          AppSpacing.vSpace8,
        ],
      ],
    );
  }

  Widget _buildPrimaryTile() {
    return _EpisodeCard(
      episodeNumber: 1,
      title: widget.primaryTitle.trim().isEmpty
          ? _fileName(widget.primaryVideo)
          : widget.primaryTitle,
      duration: _primaryProbe?.duration,
      thumbnail: _primaryProbe?.thumbnail,
      badge: 'Your video',
      onTap: () => VayuSnackBar.showInfo(
        context,
        'Episode 1 is the video you picked. Edit its title on the upload screen.',
      ),
    );
  }

  Widget _buildEpisodeTile(int index) {
    final episode = _episodes[index];
    return Padding(
      key: ValueKey(episode.path),
      padding: EdgeInsets.only(bottom: AppSpacing.space8),
      child: _EpisodeCard(
        episodeNumber: index + 2,
        title: episode.title,
        duration: episode.duration,
        thumbnail: episode.thumbnail,
        onTap: () => _editTitle(index),
        onRemove: () => _removeEpisode(index),
        dragIndex: index,
      ),
    );
  }

  Widget _buildFooter() {
    return Column(
      key: const ValueKey('series-footer'),
      children: [
        if (_episodes.isEmpty) ...[
          AppSpacing.vSpace16,
          Container(
            width: double.infinity,
            padding: AppSpacing.edgeInsetsAll24,
            decoration: BoxDecoration(
              color: AppColors.backgroundSecondary.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: AppColors.borderPrimary.withValues(alpha: 0.4)),
            ),
            child: Column(
              children: [
                const Icon(Icons.video_library_outlined,
                    size: 40, color: AppColors.textTertiary),
                AppSpacing.vSpace12,
                Text(
                  'Add at least one more episode',
                  style: AppTypography.bodyMedium
                      .copyWith(fontWeight: FontWeight.bold),
                ),
                AppSpacing.vSpace4,
                Text(
                  'A series needs $kMinEpisodesPerSeries episodes or more.',
                  textAlign: TextAlign.center,
                  style: AppTypography.bodySmall
                      .copyWith(color: AppColors.textTertiary),
                ),
              ],
            ),
          ),
        ],
        AppSpacing.vSpace16,
        AppButton(
          onPressed: _isProbing ? null : _addEpisodes,
          label: _isProbing ? 'Reading episodes…' : 'Add episodes',
          variant: AppButtonVariant.secondary,
          isFullWidth: true,
          isLoading: _isProbing,
        ),
      ],
    );
  }

  Widget _buildBottomBar() {
    final canSave = _meetsMinimum && !_isProbing;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.backgroundPrimary,
        border: Border(
          top: BorderSide(
              color: AppColors.borderPrimary.withValues(alpha: 0.4)),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                canSave
                    ? '$_totalEpisodes episodes · numbered in this order'
                    : 'A series needs at least $kMinEpisodesPerSeries episodes — add ${kMinEpisodesPerSeries - _totalEpisodes} more.',
                textAlign: TextAlign.center,
                style: AppTypography.bodySmall.copyWith(
                  color: canSave ? AppColors.textTertiary : AppColors.warning,
                ),
              ),
              AppSpacing.vSpace8,
              AppButton(
                onPressed: canSave ? _save : null,
                label: 'Save',
                variant: AppButtonVariant.primary,
                isFullWidth: true,
                isDisabled: !canSave,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One row in the episode list. Rendered identically for the locked episode 1
/// and the draggable ones so the series reads as a single ordered thing.
class _EpisodeCard extends StatelessWidget {
  final int episodeNumber;
  final String title;
  final Duration? duration;
  final Uint8List? thumbnail;
  final String? badge;
  final VoidCallback? onTap;
  final VoidCallback? onRemove;
  final int? dragIndex;

  const _EpisodeCard({
    required this.episodeNumber,
    required this.title,
    this.duration,
    this.thumbnail,
    this.badge,
    this.onTap,
    this.onRemove,
    this.dragIndex,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.backgroundSecondary.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: EdgeInsets.all(AppSpacing.space8),
          child: Row(
            children: [
              _buildThumbnail(),
              AppSpacing.hSpace12,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.bodyMedium
                          .copyWith(fontWeight: FontWeight.w600),
                    ),
                    AppSpacing.vSpace4,
                    Row(
                      children: [
                        Text(
                          'Episode $episodeNumber · ${EpisodeDraft.formatDuration(duration)}',
                          style: AppTypography.labelSmall
                              .copyWith(color: AppColors.textTertiary),
                        ),
                        if (badge != null) ...[
                          AppSpacing.hSpace8,
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              badge!,
                              style: AppTypography.labelSmall.copyWith(
                                color: AppColors.primary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              if (onRemove != null)
                IconButton(
                  onPressed: onRemove,
                  icon: const Icon(Icons.close_rounded, size: 20),
                  color: AppColors.textTertiary,
                  tooltip: 'Remove episode',
                ),
              if (dragIndex != null)
                ReorderableDragStartListener(
                  index: dragIndex!,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4),
                    child: Icon(Icons.drag_handle_rounded,
                        color: AppColors.textTertiary),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildThumbnail() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 44,
        height: 60,
        child: thumbnail != null
            ? Image.memory(thumbnail!, fit: BoxFit.cover)
            : Container(
                color: AppColors.borderPrimary.withValues(alpha: 0.4),
                child: const Icon(Icons.movie_outlined,
                    size: 18, color: AppColors.textTertiary),
              ),
      ),
    );
  }
}

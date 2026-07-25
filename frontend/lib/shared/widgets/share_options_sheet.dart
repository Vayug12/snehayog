import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:vayug/core/design/colors.dart';
import 'package:vayug/core/design/typography.dart';
import 'package:vayug/features/video/core/data/models/video_model.dart';
import 'package:vayug/shared/services/share_service.dart';
import 'package:vayug/shared/widgets/app_button.dart';
import 'package:vayug/shared/widgets/vayu_bottom_sheet.dart';

/// Bottom sheet offering "Share full video" and "Share a section" with
/// timestamps. Used by both the Yug feed and the Vayu long-form player so
/// sharing behaves identically everywhere in the app.
class ShareOptionsSheet {
  ShareOptionsSheet._();

  static void show(
    BuildContext context, {
    required VideoModel video,
    VideoPlayerController? controller,
  }) {
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    final duration = controller?.value.duration ?? video.duration;
    final durationSeconds = duration.inSeconds;
    final currentSeconds = controller?.value.position.inSeconds ?? 0;
    final canSelectSection = durationSeconds > 1;
    var startSeconds = currentSeconds.clamp(
      0,
      durationSeconds > 0 ? durationSeconds - 1 : 0,
    ).toInt();
    var endSeconds = canSelectSection
        ? (startSeconds + 30).clamp(startSeconds + 1, durationSeconds).toInt()
        : 0;

    VayuBottomSheet.show<void>(
      context: context,
      title: 'Share video',
      maxWidth: isLandscape ? 380.0 : null,
      child: StatefulBuilder(
        builder: (context, setSheetState) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              dense: true,
              visualDensity: VisualDensity.compact,
              leading: const Icon(
                Icons.video_library_outlined,
                color: AppColors.textPrimary,
              ),
              title: const Text('Share full video'),
              onTap: () {
                Navigator.pop(context);
                ShareService().shareVideo(video);
              },
            ),
            if (canSelectSection) ...[
              const Divider(height: 20),
              Text(
                'Share a section',
                style: AppTypography.labelLarge.copyWith(
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${_formatDuration(Duration(seconds: startSeconds))} – ${_formatDuration(Duration(seconds: endSeconds))}',
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              RangeSlider(
                values: RangeValues(
                  startSeconds.toDouble(),
                  endSeconds.toDouble(),
                ),
                min: 0,
                max: durationSeconds.toDouble(),
                onChanged: (values) {
                  setSheetState(() {
                    startSeconds = values.start.round();
                    endSeconds = values.end.round();
                  });
                },
              ),
              AppButton(
                onPressed: () {
                  Navigator.pop(context);
                  ShareService().shareVideo(
                    video,
                    startAt: Duration(seconds: startSeconds),
                    endAt: Duration(seconds: endSeconds),
                  );
                },
                label: 'Share section',
                icon: const Icon(Icons.share_rounded),
                isFullWidth: true,
              ),
            ] else
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'The video needs to finish loading before a section can be selected.',
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  static String _formatDuration(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return d.inHours > 0
        ? '${d.inHours}:${two(d.inMinutes.remainder(60))}:${two(d.inSeconds.remainder(60))}'
        : '${two(d.inMinutes.remainder(60))}:${two(d.inSeconds.remainder(60))}';
  }
}

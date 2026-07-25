import 'package:flutter/material.dart';
import 'package:vayug/core/design/colors.dart';
import 'package:vayug/features/video/dubbing/data/models/dubbing_models.dart';

class VayuDubbingStatusOverlay extends StatelessWidget {
  final DubbingResult result;
  final bool isVisible;
  final VoidCallback onCancel;
  final VoidCallback onHide;

  const VayuDubbingStatusOverlay({
    super.key,
    required this.result,
    required this.isVisible,
    required this.onCancel,
    required this.onHide,
  });

  @override
  Widget build(BuildContext context) {
    if (!isVisible || result.status == DubbingStatus.idle || result.isDone) {
      return const SizedBox.shrink();
    }

    final progressValue = result.progress / 100.0;
    final statusText = result.statusLabel;
    final isLandscape = MediaQuery.orientationOf(context) == Orientation.landscape;

    final horizontalMargin = isLandscape ? 32.0 : 16.0;
    final bottomMargin = isLandscape ? 48.0 : 12.0;

    return Center(
      child: Container(
        constraints: BoxConstraints(
            maxWidth: isLandscape ? MediaQuery.sizeOf(context).width * 0.5 : double.infinity),
        margin: EdgeInsets.fromLTRB(horizontalMargin, 0, horizontalMargin, bottomMargin),
        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 10.0),
        decoration: BoxDecoration(
          color: isLandscape ? Colors.black87 : AppColors.backgroundSecondary.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.2), width: 1),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: onCancel,
                    behavior: HitTestBehavior.opaque,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                'AI Dubbing: $statusText',
                                style: TextStyle(
                                    color: isLandscape ? Colors.white : AppColors.textPrimary,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Text(
                              '${result.progress}%',
                              style: const TextStyle(
                                  color: AppColors.primary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: progressValue,
                            backgroundColor:
                                isLandscape ? Colors.white24 : AppColors.borderPrimary,
                            valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
                            minHeight: 4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                GestureDetector(
                  onTap: onHide,
                  child: Text(
                    'Hide',
                    style: TextStyle(
                      color: isLandscape ? Colors.white : AppColors.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      decoration: TextDecoration.underline,
                      decorationColor:
                          isLandscape ? Colors.white.withValues(alpha: 0.5) : AppColors.primary.withValues(alpha: 0.5),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

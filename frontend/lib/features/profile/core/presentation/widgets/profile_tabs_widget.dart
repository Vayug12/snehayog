import 'package:flutter/material.dart';
import 'package:vayug/core/design/colors.dart';
import 'package:vayug/core/design/typography.dart';

/// Profile content tabs (Yug / Vayu / Top Creators).
///
/// When [animation] is supplied (pass `TabController.animation`) the underline
/// tracks the horizontal swipe frame-by-frame instead of jumping after the
/// gesture settles, so the indicator stays under the user's finger.
class ProfileTabsWidget extends StatelessWidget {
  final int activeIndex;
  final ValueChanged<int> onSelect;
  final bool showTopCreators;

  /// Continuous tab position (index + drag offset). Null falls back to a
  /// static indicator at [activeIndex].
  final Animation<double>? animation;

  const ProfileTabsWidget({
    super.key,
    required this.activeIndex,
    required this.onSelect,
    this.showTopCreators = true,
    this.animation,
  });

  static const double _tabHeight = 48;
  static const double _indicatorHeight = 2;

  @override
  Widget build(BuildContext context) {
    final labels = <String>[
      'Yug',
      'Vayu',
      if (showTopCreators) 'Top Creators',
    ];

    // The TabController is always length 3; when Top Creators is hidden the
    // position must not run past the last visible tab.
    final double maxPosition = (labels.length - 1).toDouble();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: AppColors.borderPrimary,
            width: 1,
          ),
        ),
      ),
      child: SizedBox(
        height: _tabHeight,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final double tabWidth = constraints.maxWidth / labels.length;

            return AnimatedBuilder(
              animation: animation ?? kAlwaysDismissedAnimation,
              builder: (context, _) {
                final double position = (animation?.value ?? activeIndex.toDouble())
                    .clamp(0.0, maxPosition);

                return Stack(
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (int i = 0; i < labels.length; i++)
                          Expanded(
                            child: _buildTabItem(
                              label: labels[i],
                              index: i,
                              position: position,
                            ),
                          ),
                      ],
                    ),
                    Positioned(
                      left: position * tabWidth,
                      width: tabWidth,
                      bottom: 0,
                      height: _indicatorHeight,
                      child: const ColoredBox(color: AppColors.primary),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildTabItem({
    required String label,
    required int index,
    required double position,
  }) {
    // 1.0 when the tab is fully selected, 0.0 once the neighbour takes over.
    final double selection = (1 - (position - index).abs()).clamp(0.0, 1.0);
    final bool isNearest = (position - index).abs() < 0.5;

    return Semantics(
      button: true,
      selected: isNearest,
      label: '$label tab',
      child: InkWell(
        onTap: () => onSelect(index),
        splashColor: AppColors.primary.withValues(alpha: 0.08),
        highlightColor: AppColors.primary.withValues(alpha: 0.04),
        child: Center(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.labelLarge.copyWith(
              color: Color.lerp(
                AppColors.textSecondary,
                AppColors.textPrimary,
                selection,
              ),
              fontWeight: isNearest ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

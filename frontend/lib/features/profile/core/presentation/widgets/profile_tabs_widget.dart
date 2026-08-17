import 'package:flutter/material.dart';
import 'package:vayug/core/design/colors.dart';
import 'package:vayug/core/design/typography.dart';

class ProfileTabsWidget extends StatelessWidget {
  final int activeIndex;
  final ValueChanged<int> onSelect;
  final bool showTopCreators;

  const ProfileTabsWidget({
    super.key,
    required this.activeIndex,
    required this.onSelect,
    this.showTopCreators = true,
  });

  @override
  Widget build(BuildContext context) {
    final tabs = <({String label, int index})>[
      (label: 'Yug', index: 0),
      (label: 'Vayu', index: 1),
      if (showTopCreators) (label: 'Top Creators', index: 2),
    ];

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
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final tab in tabs)
            Expanded(
              child: _buildTabItem(label: tab.label, index: tab.index),
            ),
        ],
      ),
    );
  }

  Widget _buildTabItem({required String label, required int index}) {
    final bool isSelected = activeIndex == index;
    return Semantics(
      button: true,
      selected: isSelected,
      label: '$label tab',
      child: InkWell(
        onTap: () => onSelect(index),
        splashColor: AppColors.primary.withValues(alpha: 0.08),
        highlightColor: AppColors.primary.withValues(alpha: 0.04),
        child: SizedBox(
          height: 48,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Center(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.labelLarge.copyWith(
                    color: isSelected
                        ? AppColors.textPrimary
                        : AppColors.textSecondary,
                    fontWeight:
                        isSelected ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ),
              if (isSelected)
                const Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: SizedBox(
                    height: 2,
                    child: ColoredBox(color: AppColors.primary),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

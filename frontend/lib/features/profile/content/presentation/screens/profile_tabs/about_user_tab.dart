import 'package:flutter/material.dart';
import 'package:vayug/features/profile/core/presentation/managers/profile_state_manager.dart';
import 'package:vayug/features/profile/core/presentation/widgets/top_earners_grid.dart';
import 'package:vayug/features/profile/core/presentation/widgets/profile_dialogs_widget.dart';
import 'package:vayug/shared/utils/app_text.dart';
import 'package:vayug/core/design/colors.dart';

class AboutUserTab extends StatelessWidget {
  final ProfileStateManager manager;

  const AboutUserTab({super.key, required this.manager});

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      key: const PageStorageKey<String>('profile_tab_about'),
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverOverlapInjector(
          handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
        ),
        const SliverToBoxAdapter(child: TopEarnersGrid()),
        if (manager.isOwner)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: 24.0, bottom: 24.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  GestureDetector(
                    onTap: () => ProfileDialogsWidget.showFAQDialog(context),
                    child: Text(
                      AppText.get('profile_help_guide', fallback: 'Help? Watch Guide Video'),
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 48)),
      ],
    );
  }
}

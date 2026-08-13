import 'package:flutter/material.dart';
import 'package:vayug/features/profile/core/presentation/managers/profile_state_manager.dart';
import 'package:vayug/features/profile/core/presentation/widgets/profile_videos_widget.dart';
import 'package:vayug/features/profile/core/presentation/widgets/profile_dialogs_widget.dart';
import 'package:vayug/shared/utils/app_text.dart';
import 'package:vayug/core/design/colors.dart';

class YugGridTab extends StatelessWidget {
  final ProfileStateManager manager;
  final VoidCallback? onReferFriends;
  final bool hasReferralBillingUnlock;

  const YugGridTab({super.key, required this.manager, this.onReferFriends, this.hasReferralBillingUnlock = false});

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: (ScrollNotification scrollInfo) {
        if (scrollInfo.metrics.pixels >=
                scrollInfo.metrics.maxScrollExtent - 300 &&
            !manager.isFetchingMore &&
            manager.hasMoreVideos) {
          manager.loadMoreVideos();
        }
        return false;
      },
      child: CustomScrollView(
        key: const PageStorageKey<String>('profile_tab_yug'),
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverOverlapInjector(
            handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
          ),
          ProfileVideosWidget(
            stateManager: manager,
            filterVideoType: 'yog', // 'yog' is the internal identifier for Yug
            showHeader: false,
            isSliver: true,
            onReferFriends: onReferFriends,
            hasReferralBillingUnlock: hasReferralBillingUnlock,
          ),
          if (manager.videoError != null && manager.userVideos.isNotEmpty)
            SliverToBoxAdapter(
              child: ProfileVideosWidget.buildRefreshNotice(context, manager),
            ),
          if (manager.isFetchingMore)
            SliverToBoxAdapter(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.green.shade500),
                    ),
                  ),
                ),
              ),
            ),
          if (manager.isOwner &&
              manager.videoError == null &&
              !manager.isVideosLoading)
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
      ),
    );
  }
}

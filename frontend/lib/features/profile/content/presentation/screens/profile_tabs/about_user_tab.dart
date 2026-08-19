import 'package:flutter/material.dart';
import 'package:vayug/features/profile/core/presentation/managers/profile_state_manager.dart';
import 'package:vayug/features/profile/core/presentation/widgets/top_earners_grid.dart';

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
        const SliverToBoxAdapter(child: SizedBox(height: 48)),
      ],
    );
  }
}

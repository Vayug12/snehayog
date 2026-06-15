import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vayug/core/providers/profile_providers.dart';
import 'package:vayug/core/providers/auth_providers.dart';
import 'package:vayug/features/profile/core/presentation/screens/saved_videos_screen.dart';
import 'package:vayug/features/profile/core/presentation/screens/linked_accounts_screen.dart';
import 'package:vayug/core/design/colors.dart';
import 'package:vayug/core/design/typography.dart';
import 'package:vayug/shared/utils/app_text.dart';
import 'package:vayug/shared/widgets/vayu_bottom_sheet.dart';
import 'package:vayug/features/profile/core/data/services/user_service.dart';

import 'package:vayug/features/profile/core/presentation/screens/creator_tools_screen.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});
 
  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}
 
class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _isLoading = false;

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) { 
    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            title: Text(AppText.get('settings_title', fallback: 'Settings')),
            backgroundColor: AppColors.backgroundPrimary,
            floating: true,
            snap: true,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          if (_isLoading)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: CircularProgressIndicator()),
            )
          else
            SliverList(
              delegate: SliverChildListDelegate([
                const SizedBox(height: 16),
                _buildActionTile(
                  title: AppText.get('settings_saved_videos', fallback: 'Saved Videos'),
                  icon: Icons.bookmark_outline_rounded,
                  color: AppColors.textPrimary,
                  onTap: () {
                    Navigator.push(context, MaterialPageRoute(builder: (context) => const SavedVideosScreen()));
                  },
                ),
                _buildActionTile(
                  title: AppText.get('settings_linked_accounts', fallback: 'Linked Accounts'),
                  icon: Icons.link_rounded,
                  color: AppColors.textPrimary,
                  onTap: () {
                    Navigator.push(context, MaterialPageRoute(builder: (context) => const LinkedAccountsScreen()));
                  },
                ),
                
                _buildActionTile(
                  title: 'Manage Alerts',
                  subtitle: 'Notifications from creators you subscribe to',
                  icon: Icons.notifications_active_outlined,
                  color: AppColors.textPrimary,
                  onTap: () => _showSubscriptionAlertsSettings(context),
                ),
                
                _buildActionTile(
                  title: 'Broadcast Alerts',
                  subtitle: 'Send direct updates to your subscribers',
                  icon: Icons.campaign_outlined,
                  color: AppColors.textPrimary,
                  onTap: () {
                    Navigator.push(context, MaterialPageRoute(builder: (context) => const CreatorToolsScreen()));
                  },
                ),
                
                _buildActionTile(
                  title: AppText.get('btn_logout', fallback: 'Logout'),
                  icon: Icons.logout_rounded,
                  color: AppColors.error,
                  onTap: () {
                    ref.read(googleSignInProvider).signOut();
                    Navigator.of(context).pop();
                  },
                ),
                const SizedBox(height: 40),
              ]),
            ),
        ],
      ),
    );
  }



  Widget _buildActionTile({
    required String title,
    String? subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: color, size: 20),
      ),
      title: Text(
        title,
        style: AppTypography.bodyMedium.copyWith(color: color, fontWeight: FontWeight.w500),
      ),
      subtitle: subtitle != null ? Text(subtitle, style: AppTypography.bodySmall.copyWith(color: AppColors.textTertiary)) : null,
      trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.textTertiary, size: 20),
    );
  }

  void _showSubscriptionAlertsSettings(BuildContext context) {
    // Hoist the future so it doesn't get re-fetched on every Consumer rebuild
    final followingFuture = UserService().getFollowingList();

    VayuBottomSheet.show(
      context: context,
      title: 'Manage Alerts',
      child: Consumer(
        builder: (context, ref, child) {
          final manager = ref.watch(profileStateManagerProvider);
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Builder(
                builder: (context) {
                  bool isGlobalEnabled = manager.isGlobalAlertsEnabled;
                  return StatefulBuilder(
                    builder: (context, setGlobalState) {
                      return SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Global Alerts', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                        subtitle: const Text('Enable/disable all creator notifications', style: TextStyle(color: Colors.white54, fontSize: 12)),
                        value: isGlobalEnabled,
                        activeTrackColor: AppColors.primary,
                        activeThumbColor: Colors.white,
                        onChanged: (value) {
                          setGlobalState(() {
                            isGlobalEnabled = value;
                          });
                          manager.updateNotificationPreference(globalEnabled: value);
                        },
                      );
                    }
                  );
                }
              ),
              
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20.0),
                child: Divider(color: Colors.white12),
              ),
              const Text(
                'Mute or unmute specific creators you subscribe to.',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
              const SizedBox(height: 16),
 
              FutureBuilder<List<Map<String, dynamic>>>(
                future: followingFuture,
                builder: (context, snapshot) {
                  // Debugging the list
                  if (snapshot.hasData) {
                    debugPrint('🔍 Manage Alerts: Found ${snapshot.data!.length} creators');
                  }

                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(20.0),
                        child: CircularProgressIndicator(color: AppColors.primary),
                      ),
                    );
                  }
                  
                  if (snapshot.hasError || !snapshot.hasData || snapshot.data!.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 40.0),
                        child: Column(
                          children: [
                            const Icon(Icons.notifications_off_outlined, color: Colors.white24, size: 48),
                            const SizedBox(height: 16),
                            Text(
                              snapshot.hasError ? 'Error loading creators' : 'You haven\'t subscribed to any creators yet.',
                              style: const TextStyle(color: Colors.white38, fontSize: 13),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    );
                  }
 
                  final following = snapshot.data!;
                  return ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: following.length,
                    itemBuilder: (context, index) {
                      final creator = following[index];
                      final creatorId = creator['id']?.toString() ?? creator['_id']?.toString() ?? '';
                      bool isMuted = manager.disabledCreatorIds.contains(creatorId);
 
                      return StatefulBuilder(
                        builder: (context, setLocalState) {
                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.03),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: SwitchListTile.adaptive(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                              secondary: CircleAvatar(
                                radius: 18,
                                backgroundColor: Colors.white10,
                                backgroundImage: creator['profilePic'] != null 
                                  ? NetworkImage(creator['profilePic']) 
                                  : null,
                                child: creator['profilePic'] == null 
                                  ? const Icon(Icons.person, color: Colors.white24, size: 20) 
                                  : null,
                              ),
                              title: Text(
                                creator['name'] ?? 'Creator',
                                style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500),
                              ),
                              subtitle: Text(
                                isMuted ? 'Muted' : 'Alerts On',
                                style: TextStyle(color: isMuted ? Colors.white38 : AppColors.primary, fontSize: 11),
                              ),
                              value: !isMuted,
                              activeTrackColor: AppColors.primary,
                              activeThumbColor: Colors.white,
                              onChanged: (bool value) {
                                // Optimistic UI update locally
                                setLocalState(() {
                                  isMuted = !value;
                                });
                                // API call runs in background without blocking UI
                                if (value) {
                                  manager.updateNotificationPreference(enabledCreatorId: creatorId);
                                } else {
                                  manager.updateNotificationPreference(disabledCreatorId: creatorId);
                                }
                              },
                            ),
                          );
                        }
                      );
                    },
                  );
                },
              ),
              const SizedBox(height: 30),
            ],
          );
        },
      ),
    );
  }
}

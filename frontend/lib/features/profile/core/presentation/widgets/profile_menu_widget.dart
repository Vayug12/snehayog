import 'package:flutter/material.dart';
import 'package:vayug/core/design/spacing.dart';
import 'package:vayug/core/design/radius.dart';
import 'package:provider/provider.dart';
import 'package:vayug/features/profile/core/presentation/managers/profile_state_manager.dart';
import 'package:vayug/shared/services/auto_scroll_settings.dart';
import 'package:vayug/features/profile/core/presentation/widgets/profile_dialogs_widget.dart';

import 'package:vayug/core/design/colors.dart';
import 'package:vayug/core/design/typography.dart';

import 'package:vayug/features/profile/core/presentation/screens/settings_screen.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:vayug/features/profile/core/presentation/screens/edit_profile_screen.dart';
import 'package:vayug/shared/widgets/vayu_snackbar.dart';

class ProfileMenuWidget extends StatelessWidget {
  final ProfileStateManager stateManager;
  final String? userId;
  final VoidCallback? onEditProfile;
  final VoidCallback? onSaveProfile;
  final VoidCallback? onCancelEdit;
  final VoidCallback? onReportUser;
  final VoidCallback? onShowWhatsApp;
  final VoidCallback? onShowFAQ;
  final VoidCallback? onEnterSelectionMode;
  final VoidCallback? onLogout;
  final VoidCallback? onGoogleSignIn;
  final Future<bool> Function()? onCheckPaymentSetupStatus;

  const ProfileMenuWidget({
    super.key,
    required this.stateManager,
    this.userId,
    this.onEditProfile,
    this.onSaveProfile,
    this.onCancelEdit,
    this.onReportUser,
    this.onShowWhatsApp,
    this.onShowFAQ,
    this.onEnterSelectionMode,
    this.onLogout,
    this.onGoogleSignIn,
    this.onCheckPaymentSetupStatus,
  });

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: AppColors.backgroundPrimary,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.backgroundPrimary,
          border: Border(
            left: BorderSide(
                color: AppColors.borderPrimary.withValues(alpha: 0.5),
                width: 1),
          ),
        ),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Consumer<ProfileStateManager>(
                  builder: (context, stateManager, child) {
                    List<Map<String, dynamic>> menuItems = [];

                    // Settings (New)
                    menuItems.add({
                      'title': 'Settings',
                      'icon': HugeIcons.strokeRoundedSettings02,
                      'color': AppColors.textSecondary,
                      'onTap': () {
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (context) => const SettingsScreen()),
                        );
                      },
                    });

                    // Auto Scroll
                    menuItems.add({
                      'title': 'Auto Scroll',
                      'icon': HugeIcons.strokeRoundedScrollVertical,
                      'color': AppColors.textSecondary,
                      'onTap': () async {
                        final enabled = await AutoScrollSettings.isEnabled();
                        await AutoScrollSettings.setEnabled(!enabled);
                        if (context.mounted) {
                          VayuSnackBar.showInfo(
                            context,
                            'Auto Scroll: ${!enabled ? 'ON' : 'OFF'}',
                            duration: const Duration(seconds: 1),
                          );
                          Navigator.pop(context);
                        }
                      },
                    });

                    // Edit Profile / Save / Cancel
                    if (!stateManager.isEditing) {
                      menuItems.add({
                        'title': 'Edit Profile',
                        'icon': HugeIcons.strokeRoundedUser,
                        'color': AppColors.textSecondary,
                        'onTap': () {
                          Navigator.pop(context);
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => EditProfileScreen(
                                stateManager: stateManager,
                              ),
                            ),
                          );
                          onEditProfile?.call();
                        },
                      });
                    } else {
                      menuItems.add({
                        'title': 'Save',
                        'icon': HugeIcons.strokeRoundedCheckmarkCircle01,
                        'color': AppColors.textSecondary,
                        'onTap': () {
                          Navigator.pop(context);
                          onSaveProfile?.call();
                        },
                      });
                      menuItems.add({
                        'title': 'Cancel',
                        'icon': HugeIcons.strokeRoundedCancel01,
                        'color': AppColors.textSecondary,
                        'onTap': () {
                          Navigator.pop(context);
                          onCancelEdit?.call();
                        },
                      });
                    }

                    // Setup Billing (Shifted from Header when completed)
                    if (stateManager.isOwner && stateManager.hasUpiId) {
                      menuItems.add({
                        'title': 'Setup Billing',
                        'icon': HugeIcons.strokeRoundedWallet01,
                        'color': AppColors.textSecondary,
                        'onTap': () {
                          Navigator.pop(context);
                          ProfileDialogsWidget.showHowToEarnDialog(
                            context,
                            stateManager: stateManager,
                          );
                        },
                      });
                    }

                    // Delete Videos
                    if (stateManager.isOwner) {
                      menuItems.add({
                        'title': 'Manage Content',
                        'icon': HugeIcons.strokeRoundedDelete02,
                        'color': AppColors.textSecondary,
                        'onTap': () {
                          Navigator.pop(context);
                          onEnterSelectionMode?.call();
                        },
                      });
                    }

                    // Support Chat (Replaced Feedback)
                    menuItems.add({
                      'title': 'Support Chat',
                      'icon': HugeIcons.strokeRoundedMessageQuestion,
                      'color': AppColors.textSecondary,
                      'onTap': () {
                        Navigator.pop(context);
                        onShowWhatsApp?.call();
                      },
                    });

                    // FAQ
                    menuItems.add({
                      'title': 'Help & FAQ',
                      'icon': HugeIcons.strokeRoundedHelpCircle,
                      'color': AppColors.textSecondary,
                      'onTap': () {
                        Navigator.pop(context);
                        onShowFAQ?.call();
                      },
                    });

                    // Legal & About
                    menuItems.add({
                      'title': 'Legal',
                      'icon': HugeIcons.strokeRoundedAgreement01,
                      'color': AppColors.textSecondary,
                      'onTap': () {
                        Navigator.pop(context);
                        ProfileDialogsWidget.showLegalBottomSheet(context);
                      },
                    });

                    // Report User
                    if (userId != null &&
                        ((stateManager.userData?['_id'] ??
                                stateManager.userData?['id'] ??
                                stateManager.userData?['googleId']) !=
                            userId)) {
                      menuItems.add({
                        'title': 'Report',
                        'icon': HugeIcons.strokeRoundedAlert01,
                        'color': AppColors.textSecondary,
                        'onTap': () {
                          Navigator.pop(context);
                          onReportUser?.call();
                        },
                      });
                    }

                    // Sign Out (Moved to bottom or kept in grid?)
                    menuItems.add({
                      'title': 'Logout',
                      'icon': HugeIcons.strokeRoundedLogout01,
                      'color': AppColors.error,
                      'onTap': () {
                        Navigator.pop(context);
                        onLogout?.call();
                      },
                    });

                    return ListView.separated(
                      padding: EdgeInsets.symmetric(
                        horizontal: AppSpacing.spacing2,
                        vertical: AppSpacing.spacing3,
                      ),
                      itemCount: menuItems.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 4),
                      itemBuilder: (context, index) {
                        final item = menuItems[index];
                        return _buildMenuRow(
                          title: item['title'],
                          icon: item['icon'],
                          color: item['color'],
                          onTap: item['onTap'],
                        );
                      },
                    );
                  },
                ),
              ),
              Padding(
                padding: EdgeInsets.all(AppSpacing.spacing3),
                child: Text(
                  'Vayu v1.1.0',
                  style: AppTypography.labelSmall
                      .copyWith(color: AppColors.textTertiary),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMenuRow({
    required String title,
    required dynamic icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: AppSpacing.spacing2,
            vertical: AppSpacing.spacing2,
          ),
          child: Row(
            children: [
              SizedBox(
                width: 40,
                height: 40,
                child: Center(
                  child: HugeIcon(
                    icon: icon,
                    color: color,
                    size: 22,
                  ),
                ),
              ),
              SizedBox(width: AppSpacing.spacing2),
              Expanded(
                child: Text(
                  title,
                  style: AppTypography.bodyMedium.copyWith(
                    color: title == 'Logout' ? AppColors.error : AppColors.textPrimary,
                    fontWeight: AppTypography.weightMedium,
                    letterSpacing: -0.1,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              HugeIcon(
                icon: HugeIcons.strokeRoundedArrowRight01,
                color: AppColors.textTertiary.withValues(alpha: 0.7),
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

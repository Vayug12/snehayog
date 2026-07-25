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
              Container(
                padding: EdgeInsets.all(AppSpacing.spacing3),
                decoration: BoxDecoration(
                  color: AppColors.backgroundSecondary.withValues(alpha: 0.5),
                  border: const Border(
                    bottom:
                        BorderSide(color: AppColors.borderPrimary, width: 1),
                  ),
                ),
                child: Row(
                  children: [
                    const HugeIcon(
                        icon: HugeIcons.strokeRoundedMenu01,
                        color: AppColors.primary,
                        size: 24),
                    SizedBox(width: AppSpacing.spacing3),
                    Text(
                      'Account Menu',
                      style: AppTypography.headlineSmall.copyWith(
                        color: AppColors.textPrimary,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ],
                ),
              ),
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
                      'color': AppColors.info,
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
                        'color': AppColors.success,
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
                        'color': AppColors.success,
                        'onTap': () {
                          Navigator.pop(context);
                          onSaveProfile?.call();
                        },
                      });
                      menuItems.add({
                        'title': 'Cancel',
                        'icon': HugeIcons.strokeRoundedCancel01,
                        'color': AppColors.error,
                        'onTap': () {
                          Navigator.pop(context);
                          onCancelEdit?.call();
                        },
                      });
                    }

                    // Report User
                    if (userId != null &&
                        ((stateManager.userData?['_id'] ??
                                stateManager.userData?['id'] ??
                                stateManager.userData?['googleId']) !=
                            userId)) {
                      menuItems.add({
                        'title': 'Report',
                        'icon': HugeIcons.strokeRoundedAlert01,
                        'color': AppColors.error,
                        'onTap': () {
                          Navigator.pop(context);
                          onReportUser?.call();
                        },
                      });
                    }

                    // Support Chat (Replaced Feedback)
                    menuItems.add({
                      'title': 'Support Chat',
                      'icon': HugeIcons.strokeRoundedMessageQuestion,
                      'color': const Color(0xFF10B981),
                      'onTap': () {
                        Navigator.pop(context);
                        onShowWhatsApp?.call();
                      },
                    });

                    // FAQ
                    menuItems.add({
                      'title': 'Help & FAQ',
                      'icon': HugeIcons.strokeRoundedHelpCircle,
                      'color': AppColors.primaryLight,
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

                    // Setup Billing (Shifted from Header when completed)
                    if (stateManager.isOwner && stateManager.hasUpiId) {
                      menuItems.add({
                        'title': 'Setup Billing',
                        'icon': HugeIcons.strokeRoundedWallet01,
                        'color': AppColors.primary,
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
                        'color': AppColors.error,
                        'onTap': () {
                          Navigator.pop(context);
                          onEnterSelectionMode?.call();
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

                    return GridView.builder(
                      padding: EdgeInsets.symmetric(
                        horizontal: AppSpacing.spacing4,
                        vertical: AppSpacing.spacing2,
                      ),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: AppSpacing.spacing2,
                        mainAxisSpacing: AppSpacing.spacing2,
                        childAspectRatio: 1.4,
                      ),
                      itemCount: menuItems.length,
                      itemBuilder: (context, index) {
                        final item = menuItems[index];
                        return _buildMenuBox(
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

  Widget _buildMenuBox({
    required String title,
    required dynamic icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.backgroundSecondary.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(
              color: AppColors.borderPrimary.withValues(alpha: 0.5),
              width: 1,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: EdgeInsets.all(AppSpacing.spacing1),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: HugeIcon(
                  icon: icon,
                  color: color,
                  size: 22,
                ),
              ),
              SizedBox(height: AppSpacing.spacing1),
              Text(
                title,
                style: AppTypography.labelMedium.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: AppTypography.weightMedium,
                  fontSize: 11,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

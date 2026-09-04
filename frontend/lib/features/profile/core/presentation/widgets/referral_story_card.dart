import 'dart:io';
import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:vayug/core/design/colors.dart';
import 'package:vayug/core/design/radius.dart';
import 'package:vayug/core/design/typography.dart';

class ReferralStoryCard extends StatelessWidget {
  final String creatorName;
  final String? profilePicUrl;
  final String? referralCode;
  final double width;
  final double height;

  const ReferralStoryCard({
    super.key,
    required this.creatorName,
    this.profilePicUrl,
    this.referralCode,
    this.width = 300,
    this.height = 520,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
      decoration: BoxDecoration(
        color: AppColors.backgroundPrimary,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: AppColors.borderPrimary,
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // 1. Top Bar: Minimal Vayug Wordmark
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'VAYUG',
                style: AppTypography.titleSmall.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2.0,
                  fontSize: 14,
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.surfacePrimary,
                  borderRadius: BorderRadius.circular(AppRadius.xs),
                  border: Border.all(color: AppColors.borderPrimary, width: 1),
                ),
                child: Text(
                  'CREATOR',
                  style: AppTypography.labelSmall.copyWith(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.0,
                    fontSize: 10,
                  ),
                ),
              ),
            ],
          ),

          // 2. Creator Profile Section
          Row(
            children: [
              _buildAvatar(),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      creatorName.isNotEmpty ? creatorName : 'Vayug Creator',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.titleSmall.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Creator on Vayu',
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const Divider(color: AppColors.borderPrimary, height: 1),

          // 3. Direct Features List (Zero helper text, calm & minimal)
          Column(
            children: [
              _buildFeatureRow(
                icon: HugeIcons.strokeRoundedMoney04,
                label: 'Day 1 monetization',
              ),
              const SizedBox(height: 18),
              _buildFeatureRow(
                icon: HugeIcons.strokeRoundedLink01,
                label: 'Link below every video',
              ),
              const SizedBox(height: 18),
              _buildFeatureRow(
                icon: HugeIcons.strokeRoundedShield01,
                label: 'Private E2EE videos',
              ),
              const SizedBox(height: 18),
              _buildFeatureRow(
                icon: HugeIcons.strokeRoundedFlash,
                label: 'Instant UPI payouts',
              ),
            ],
          ),

          const Divider(color: AppColors.borderPrimary, height: 1),

          // 4. Bottom Footer: Referral Code + Store Info
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              if (referralCode != null && referralCode!.isNotEmpty)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppColors.surfacePrimary,
                    borderRadius: BorderRadius.circular(AppRadius.xs),
                    border:
                        Border.all(color: AppColors.borderPrimary, width: 1),
                  ),
                  child: Text(
                    'Code: $referralCode',
                    style: AppTypography.labelSmall.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 11,
                    ),
                  ),
                )
              else
                const SizedBox.shrink(),
              Text(
                'Google Play Store',
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAvatar() {
    Widget avatarContent;
    if (profilePicUrl != null && profilePicUrl!.isNotEmpty) {
      if (profilePicUrl!.startsWith('http')) {
        avatarContent = Image.network(
          profilePicUrl!,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _fallbackAvatarIcon(),
        );
      } else {
        avatarContent = Image.file(
          File(profilePicUrl!),
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _fallbackAvatarIcon(),
        );
      }
    } else {
      avatarContent = _fallbackAvatarIcon();
    }

    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: AppColors.borderPrimary,
          width: 1,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: avatarContent,
      ),
    );
  }

  Widget _fallbackAvatarIcon() {
    return Container(
      color: AppColors.surfacePrimary,
      alignment: Alignment.center,
      child: const HugeIcon(
        icon: HugeIcons.strokeRoundedUser,
        color: AppColors.textSecondary,
        size: 20,
      ),
    );
  }

  Widget _buildFeatureRow({
    required dynamic icon,
    required String label,
  }) {
    return Row(
      children: [
        HugeIcon(
          icon: icon,
          color: AppColors.primary,
          size: 18,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w500,
              fontSize: 14,
            ),
          ),
        ),
      ],
    );
  }
}

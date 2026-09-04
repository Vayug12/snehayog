import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:vayug/core/design/colors.dart';
import 'package:vayug/core/design/typography.dart';
import 'package:vayug/shared/services/story_share_service.dart';
import 'package:vayug/shared/widgets/vayu_bottom_sheet.dart';
import 'package:vayug/shared/widgets/vayu_snackbar.dart';
import 'package:vayug/features/profile/core/presentation/widgets/referral_story_card.dart';

class ReferralShareBottomSheet extends StatefulWidget {
  final String creatorName;
  final String? profilePicUrl;
  final String? referralCode;
  final String playStoreUrl;
  final String shareMessage;
  final int invitedCount;

  const ReferralShareBottomSheet({
    super.key,
    required this.creatorName,
    this.profilePicUrl,
    this.referralCode,
    required this.playStoreUrl,
    required this.shareMessage,
    required this.invitedCount,
  });

  static Future<void> show({
    required BuildContext context,
    required String creatorName,
    String? profilePicUrl,
    String? referralCode,
    required String playStoreUrl,
    required String shareMessage,
    required int invitedCount,
  }) {
    return VayuBottomSheet.show(
      context: context,
      isScrollControlled: true,
      showHandle: true,
      showCloseButton: true,
      title: 'Share Creator Card',
      child: ReferralShareBottomSheet(
        creatorName: creatorName,
        profilePicUrl: profilePicUrl,
        referralCode: referralCode,
        playStoreUrl: playStoreUrl,
        shareMessage: shareMessage,
        invitedCount: invitedCount,
      ),
    );
  }

  @override
  State<ReferralShareBottomSheet> createState() =>
      _ReferralShareBottomSheetState();
}

class _ReferralShareBottomSheetState extends State<ReferralShareBottomSheet> {
  final GlobalKey _cardBoundaryKey = GlobalKey();
  bool _isExporting = false;

  Future<File?> _captureCard() async {
    return await StoryShareService.captureCardToPng(_cardBoundaryKey);
  }

  Future<void> _shareToWhatsApp() async {
    if (_isExporting) return;
    setState(() => _isExporting = true);
    try {
      HapticFeedback.lightImpact();
      final file = await _captureCard();
      await StoryShareService.shareToWhatsAppStatus(
        imageFile: file,
        message: widget.shareMessage,
      );
      if (mounted) {
        Navigator.of(context, rootNavigator: true).maybePop();
      }
    } catch (e) {
      if (mounted) {
        VayuSnackBar.showError(context, 'Unable to share to WhatsApp');
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<void> _shareToInstagram() async {
    if (_isExporting) return;
    setState(() => _isExporting = true);
    try {
      HapticFeedback.lightImpact();
      final file = await _captureCard();
      await StoryShareService.shareToInstagramStory(
        imageFile: file,
        message: widget.shareMessage,
        playStoreUrl: widget.playStoreUrl,
      );
      if (mounted) {
        Navigator.of(context, rootNavigator: true).maybePop();
      }
    } catch (e) {
      if (mounted) {
        VayuSnackBar.showError(context, 'Unable to share to Instagram');
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<void> _shareNative() async {
    if (_isExporting) return;
    setState(() => _isExporting = true);
    try {
      HapticFeedback.lightImpact();
      final file = await _captureCard();
      await StoryShareService.shareGeneral(
        imageFile: file,
        message: widget.shareMessage,
      );
    } catch (e) {
      if (mounted) {
        VayuSnackBar.showError(context, 'Unable to open share menu');
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<void> _copyLinkAndCode() async {
    HapticFeedback.mediumImpact();
    final copyText =
        '${widget.shareMessage}\n\nInstall Link: ${widget.playStoreUrl}';
    await Clipboard.setData(ClipboardData(text: copyText));
    if (mounted) {
      VayuSnackBar.showSuccess(
        context,
        'Copied to clipboard',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Status Text (Calm & minimal, 1 line)
          Text(
            widget.invitedCount >= 2
                ? 'Full access unlocked'
                : 'Share with 2 friends to unlock billing setup (${widget.invitedCount}/2)',
            textAlign: TextAlign.center,
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.textSecondary,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 16),

          // 2. Story Card Preview
          Center(
            child: RepaintBoundary(
              key: _cardBoundaryKey,
              child: ReferralStoryCard(
                creatorName: widget.creatorName,
                profilePicUrl: widget.profilePicUrl,
                referralCode: widget.referralCode,
                width: 280,
                height: 480,
              ),
            ),
          ),
          const SizedBox(height: 24),

          // 3. Share Buttons (Consistent secondary surface style matching design.md)
          if (_isExporting)
            const SizedBox(
              height: 52,
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor:
                        AlwaysStoppedAnimation<Color>(AppColors.primary),
                  ),
                ),
              ),
            )
          else ...[
            Row(
              children: [
                Expanded(
                  child: _buildShareButton(
                    icon: HugeIcons.strokeRoundedWhatsapp,
                    label: 'WhatsApp',
                    onTap: _shareToWhatsApp,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildShareButton(
                    icon: HugeIcons.strokeRoundedInstagram,
                    label: 'Instagram',
                    onTap: _shareToInstagram,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildShareButton(
                    icon: HugeIcons.strokeRoundedCopy01,
                    label: 'Copy link',
                    onTap: _copyLinkAndCode,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildShareButton(
                    icon: HugeIcons.strokeRoundedShare01,
                    label: 'More',
                    onTap: _shareNative,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildShareButton({
    required dynamic icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Material(
      color: AppColors.surfacePrimary,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: AppColors.borderPrimary,
              width: 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              HugeIcon(
                icon: icon,
                color: AppColors.textPrimary,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: AppTypography.labelMedium.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w500,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

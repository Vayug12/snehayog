import 'package:flutter/material.dart';
import 'package:vayug/features/profile/core/presentation/managers/profile_state_manager.dart';
import 'package:vayug/shared/widgets/feedback/feedback_dialog_widget.dart';
import 'package:vayug/shared/widgets/report_dialog_widget.dart';
import 'package:vayug/core/design/colors.dart';
import 'package:vayug/core/design/typography.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vayug/shared/widgets/app_button.dart';
import 'package:vayug/shared/widgets/vayu_bottom_sheet.dart';
import 'package:vayug/shared/utils/url_utils.dart';
import 'package:vayug/shared/utils/app_logger.dart';
import 'package:vayug/shared/widgets/vayu_snackbar.dart';
import 'package:vayug/features/onboarding/presentation/widgets/onboarding_video_player.dart';

class ProfileDialogsWidget {
  static Future<bool> showDeleteConfirmationDialog(
    BuildContext context, {
    String title = 'Delete Content?',
    String message = 'Are you sure you want to delete this? This action cannot be undone.',
    String confirmLabel = 'Delete',
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surfacePrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          title,
          style: AppTypography.titleLarge.copyWith(color: AppColors.textPrimary),
        ),
        content: Text(
          message,
          style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.bold),
            ),
          ),
          AppButton(
            onPressed: () => Navigator.pop(context, true),
            label: confirmLabel,
            variant: AppButtonVariant.danger,
          ),
        ],
      ),
    );
    return result ?? false;
  }


  static void showHelpDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surfacePrimary,
        title: Row(
          children: [
            const Icon(Icons.help_outline, color: AppColors.textPrimary),
            const SizedBox(width: 12),
            Text('Help & Support',
                style: Theme.of(context).textTheme.headlineSmall),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Need help? Here are some common solutions:',
              style: AppTypography.bodyMedium,
            ),
            const SizedBox(height: 16),
            Text(
              '• Profile Issues: Try refreshing your profile',
              style: AppTypography.bodySmall,
            ),
            Text(
              '• Video Problems: Check if videos need HLS conversion',
              style: AppTypography.bodySmall,
            ),
            Text(
              '• Billing Setup: Complete billing setup for rewards',
              style: AppTypography.bodySmall,
            ),
            Text(
              '• Account Issues: Try signing out and back in',
              style: AppTypography.bodySmall,
            ),
          ],
        ),
        actions: [
          AppButton(
            onPressed: () => Navigator.pop(context),
            label: 'Close',
            variant: AppButtonVariant.text,
          ),
        ],
      ),
    );
  }

  static void showFeedbackDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => const FeedbackDialogWidget(),
    );
  }

  static void showReportDialog(
    BuildContext context, {
    required String targetType,
    required String targetId,
  }) {
    VayuBottomSheet.show(
      context: context,
      title: 'Report ${targetType[0].toUpperCase()}${targetType.substring(1)}',
      icon: Icons.report_problem_outlined,
      child: ReportDialogWidget(targetType: targetType, targetId: targetId),
    );
  }

  /// Help sheet: a flow diagram guide and the walkthrough video, switched
  /// from the icon toggle in the header corner. No title, no close button -
  /// the user opened it, the handle closes it.
  static void showFAQDialog(BuildContext context) {
    final section = ValueNotifier<_HelpSection>(_HelpSection.guide);

    VayuBottomSheet.show(
      context: context,
      useDraggable: true,
      showCloseButton: false,
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      actions: [_HelpSectionToggle(section: section)],
      child: ValueListenableBuilder<_HelpSection>(
        valueListenable: section,
        builder: (context, selected, _) => selected == _HelpSection.video
            // Swapping the player out of the tree disposes its controller, so
            // nothing keeps buffering while the guide is open.
            ? _buildHelpVideoSection(context)
            : _buildHelpGuideSection(context),
      ),
    ).whenComplete(section.dispose);
  }

  /// Two diagrams instead of two paragraphs: earning, then payout.
  static Widget _buildHelpGuideSection(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _HelpFlow(
          title: 'Kamai ka formula',
          steps: [
            _FlowStep(Icons.file_upload_outlined, '2 Videos\nUpload'),
            _FlowStep(Icons.share_outlined, 'Ya 2 Friends\nKo Share'),
            _FlowStep(Icons.lock_open_rounded, 'Billing\nUnlock'),
          ],
        ),
        const SizedBox(height: 24),
        const _HelpFlow(
          title: 'Paisa kaise aayega',
          steps: [
            _FlowStep(Icons.account_balance_wallet_outlined, 'UPI ID\nDalo'),
            _FlowStep(Icons.calendar_month_outlined, '1st Ko\nScore'),
            _FlowStep(Icons.account_balance_outlined, 'Bank\nMein'),
          ],
          note: 'Har mahine automatic',
        ),
        const SizedBox(height: 32),
        AppButton(
          isFullWidth: true,
          onPressed: () => Navigator.pop(context),
          label: 'Samajh Gaya',
          variant: AppButtonVariant.primary,
        ),
      ],
    );
  }

  static Widget _buildHelpVideoSection(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const OnboardingVideoPlayer(
          videoUrl: 'https://cdn.snehayog.site/guide_video.mp4',
          autoPlay: true,
        ),
        const SizedBox(height: 24),
        AppButton(
          isFullWidth: true,
          onPressed: () => Navigator.pop(context),
          label: 'Samajh Gaya',
          variant: AppButtonVariant.primary,
        ),
      ],
    );
  }

  static Widget _buildFAQItem({
    required String question,
    required String answer,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.backgroundSecondary,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderPrimary, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  question,
                  style: AppTypography.titleSmall.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.bold,
                    height: 1.3,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Text(
              answer,
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.textSecondary,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static void showLegalBottomSheet(BuildContext context) {
    VayuBottomSheet.show(
      context: context,
      title: 'Legal & About',
      icon: Icons.gavel_rounded,
      iconColor: AppColors.primary,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: const Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children:  [
           Text(
            'Policies and contact information',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
           SizedBox(height: 8),
          // **FIX: Use _LegalItemWidget to provide visual feedback on click**
          _VerticalLegalItem(
            title: 'Privacy Policy',
            icon: Icons.privacy_tip_outlined,
            url: 'https://snehayog.site/privacy.html',
          ),
          _VerticalLegalItem(
            title: 'Terms & Conditions',
            icon: Icons.description_outlined,
            url: 'https://snehayog.site/terms.html',
          ),
          _VerticalLegalItem(
            title: 'Refund & Cancellation',
            icon: Icons.assignment_return_outlined,
            url: 'https://snehayog.site/refund.html',
          ),
          _VerticalLegalItem(
            title: 'Contact Us',
            icon: Icons.contact_support_outlined,
            url: 'https://snehayog.site/contact.html',
          ),
          _VerticalLegalItem(
            title: 'About Us',
            icon: Icons.info_outline_rounded,
            url: 'https://snehayog.site/about.html',
          ),
          SizedBox(height: 8),
        ],
      ),
    );
  }


  static Future<void> _launchURL(String url, {BuildContext? context}) async {
    final enrichedUrl = UrlUtils.enrichUrl(
      url.trim(),
      source: 'vayug',
      medium: 'internal_link',
      campaign: 'legal_docs',
    );
    
    AppLogger.log('🔗 ProfileDialogs: Attempting to launch legal link: $enrichedUrl');
    
    try {
      final Uri uri = Uri.parse(enrichedUrl);
      if (await canLaunchUrl(uri)) {
        // **FIX: Launch first, then optionally pop if successful**
        final success = await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
        
        if (success) {
          // If we launched successfully, we can close the bottom sheet
          if (context != null && context.mounted) {
             Navigator.maybePop(context);
          }
        } else {
          AppLogger.log('❌ ProfileDialogs: launchUrl returned false for $enrichedUrl');
          if (context != null && context.mounted) {
            VayuSnackBar.showError(context, 'Could not open link in browser.');
          }
        }
      } else {
        AppLogger.log('⚠️ ProfileDialogs: canLaunchUrl returned false for $enrichedUrl');
        if (context != null && context.mounted) {
          VayuSnackBar.showError(context, 'Invalid link or no browser found.');
        }
      }
    } catch (e) {
      AppLogger.log('❌ ProfileDialogs: Exception while launching link: $e');
      if (context != null && context.mounted) {
        VayuSnackBar.showError(context, 'An error occurred while opening the link.');
      }
    }
  }

  static String _maskUpiId(String upi) {
    if (upi.isEmpty) return '';
    final parts = upi.split('@');
    if (parts.length < 2) {
      if (upi.length > 4) {
        return '${upi.substring(0, 4)}•••';
      }
      return '$upi•••';
    }
    final handle = parts[0];
    return '$handle@•••';
  }

  static Future<void> showHowToEarnDialog(
    BuildContext context, {
    required ProfileStateManager stateManager,
  }) async {
    await stateManager.ensurePaymentDetailsHydrated();

    final userData = stateManager.userData;
    String currentUpi =
        userData?['paymentDetails']?['upiId']?.toString().trim() ?? '';

    final upiController = TextEditingController(text: currentUpi);

    bool showUpiField = currentUpi.isEmpty;
    bool isSaving = false;
    String? validationMessage;

    await VayuBottomSheet.show(
      context: context,
      title: 'Creator Rewards ki Jankari',
      icon: Icons.monetization_on_outlined,
      isScrollControlled: true,
      padding: EdgeInsets.zero,
      child: StatefulBuilder(
        builder: (context, setState) {
          final bottomInset = MediaQuery.of(context).viewInsets.bottom;

          return SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 0,
                bottom: bottomInset + 16,
              ),
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHowToEarnPoint(
                      title: 'Rewards kaise milenge?',
                      body:
                          'Rewards har mahine ki 1st date ko aapki profile mein reset kiye jaate hain.',
                    ),
                    _buildHowToEarnPoint(
                      title: 'Identity Verification kyun zaroori hai?',
                      body:
                          'Platform ko safe aur genuine rakhne ke liye hum UPI ID ka use identity verification ke liye karte hain. Isse duplicate accounts nahi bante aur rewards seedha sahi creators tak pahunchte hain.',
                    ),
                    if (!showUpiField && currentUpi.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.backgroundSecondary,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.borderPrimary),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Saved UPI ID',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _maskUpiId(currentUpi),
                              style: const TextStyle(
                                fontSize: 15,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: AppButton(
                          onPressed: () {
                            setState(() {
                              showUpiField = true;
                              validationMessage = null;
                              upiController.text = currentUpi;
                            });
                          },
                          label: 'UPI ID Update karein',
                          variant: AppButtonVariant.text,
                        ),
                      ),
                    ],
                    if (showUpiField) ...[
                      const SizedBox(height: 16),
                      TextField(
                        controller: upiController,
                        decoration: const InputDecoration(
                          labelText: 'Apna UPI ID enter karein',
                          hintText: 'example@bank',
                          border: OutlineInputBorder(),
                        ),
                        textInputAction: TextInputAction.done,
                      ),
                      if (validationMessage != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          validationMessage!,
                          style: TextStyle(
                            color: Colors.red.shade600,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                    const SizedBox(height: 16),
                    AppButton(
                      isFullWidth: true,
                      isDisabled: isSaving,
                      onPressed: () async {
                        if (!showUpiField) {
                          Navigator.pop(context);
                          return;
                        }

                        final upiId = upiController.text.trim();
                        final regex = RegExp(
                          r'^[a-zA-Z0-9.\-_]{2,}@[a-zA-Z]{2,}$',
                        );

                        if (upiId.isEmpty || !regex.hasMatch(upiId)) {
                          setState(() {
                            validationMessage =
                                'Enter a valid UPI ID (for example: creator@bank).';
                          });
                          return;
                        }

                        FocusScope.of(context).unfocus();
                        setState(() {
                          isSaving = true;
                          validationMessage = null;
                        });

                        try {
                          await stateManager.saveUpiIdQuick(upiId);
                          currentUpi = upiId;
                          if (context.mounted) {
                            VayuSnackBar.showSuccess(
                              context,
                              'Billing info update ho gayi hai. Har mahine ki 1st date ko scores update honge.',
                            );
                          }
                          setState(() {
                            isSaving = false;
                            showUpiField = false;
                            validationMessage =
                                'Information save ho gayi hai! Aapke rewards 1st date ko update honge.';
                          });
                        } catch (e) {
                          setState(() {
                            isSaving = false;
                            validationMessage =
                                e.toString().replaceFirst('Exception: ', '');
                          });
                        }
                      },
                      label: isSaving
                          ? 'Save ho raha hai...'
                          : showUpiField
                              ? 'Verify aur Save karein'
                              : 'Ho gaya',
                      variant: AppButtonVariant.primary,
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );

    upiController.dispose();

    if (stateManager.hasUpiId) {
      await stateManager.refreshData();
    }
  }

  static Widget _buildHowToEarnPoint({
    required String title,
    required String body,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            body,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  static void showNotificationGuide(BuildContext context) {
    VayuBottomSheet.show(
      context: context,
      title: 'Direct Alerts Guide',
      icon: Icons.help_outline,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Ye feature aapko apne subscribers ke saath judne mein madad karta hai.',
            style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 16),
          _buildFAQItem(
            question: "Creator Notification kya hai?",
            answer:
                "Ye feature aapko apne subscribers ko direct notification bhejne ki power deta hai.",
            icon: Icons.notifications_active_outlined,
            color: Colors.orange,
          ),
          _buildFAQItem(
            question: "Views ka matlab kya hai?",
            answer:
                "Notifications ke context mein 'Views' ka matlab hai ki kitne users ne aapke bhejey huye notification par click kiya ya use open kiya.",
            icon: Icons.remove_red_eye_outlined,
            color: Colors.blue,
          ),
          const SizedBox(height: 12),
          AppButton(
            isFullWidth: true,
            onPressed: () => Navigator.pop(context),
            label: 'Done',
            variant: AppButtonVariant.primary,
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// **NEW: Internal widget for legal items with loading state feedback**
class _VerticalLegalItem extends StatefulWidget {
  final String title;
  final IconData icon;
  final String url;

  const _VerticalLegalItem({
    required this.title,
    required this.icon,
    required this.url,
  });

  @override
  State<_VerticalLegalItem> createState() => _VerticalLegalItemState();
}

class _VerticalLegalItemState extends State<_VerticalLegalItem> {
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(widget.icon, color: AppColors.primary),
      title: Text(
        widget.title,
        style: AppTypography.bodyMedium.copyWith(
          fontWeight: FontWeight.w500,
          color: AppColors.textPrimary,
        ),
      ),
      trailing: _isLoading
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
              ),
            )
          : const Icon(Icons.chevron_right,
              color: AppColors.textTertiary, size: 18),
      onTap: _isLoading
          ? null
          : () async {
              setState(() => _isLoading = true);
              try {
                await ProfileDialogsWidget._launchURL(widget.url,
                    context: context);
              } finally {
                if (mounted) {
                  setState(() => _isLoading = false);
                }
              }
            },
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
    );
  }
}

/// Which half of the help sheet is showing
enum _HelpSection { guide, video }

/// Icon-only segmented toggle for the help sheet header corner.
class _HelpSectionToggle extends StatelessWidget {
  const _HelpSectionToggle({required this.section});

  final ValueNotifier<_HelpSection> section;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<_HelpSection>(
      valueListenable: section,
      builder: (context, selected, _) => Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: AppColors.backgroundSecondary,
          borderRadius: BorderRadius.circular(100),
          border: Border.all(color: AppColors.borderPrimary),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildSegment(
              value: _HelpSection.guide,
              selected: selected,
              icon: Icons.article_outlined,
              label: 'Guide',
            ),
            _buildSegment(
              value: _HelpSection.video,
              selected: selected,
              icon: Icons.play_arrow_rounded,
              label: 'Video',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSegment({
    required _HelpSection value,
    required _HelpSection selected,
    required IconData icon,
    required String label,
  }) {
    final isSelected = value == selected;

    // The icon carries the meaning; the label stays for screen readers.
    return Semantics(
      button: true,
      selected: isSelected,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => section.value = value,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(100),
          ),
          child: Icon(
            icon,
            size: 16,
            color: isSelected ? AppColors.white : AppColors.textTertiary,
          ),
        ),
      ),
    );
  }
}

/// One node of a help flow diagram.
class _FlowStep {
  const _FlowStep(this.icon, this.label);

  final IconData icon;
  final String label;
}

/// Icon nodes joined by arrows, so the guide reads as a picture instead of a
/// paragraph. The last node is the outcome and carries the accent.
class _HelpFlow extends StatelessWidget {
  const _HelpFlow({
    required this.title,
    required this.steps,
    this.note,
  });

  final String title;
  final List<_FlowStep> steps;

  /// Only for what the diagram cannot show, e.g. when the money lands.
  final String? note;

  @override
  Widget build(BuildContext context) {
    final row = <Widget>[];
    for (var i = 0; i < steps.length; i++) {
      if (i > 0) row.add(_buildArrow());
      row.add(
        Expanded(
          child: _buildNode(steps[i], isOutcome: i == steps.length - 1),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: AppTypography.titleSmall.copyWith(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: row),
        if (note != null) ...[
          const SizedBox(height: 12),
          Text(
            note!,
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ],
    );
  }

  /// Sized to the node tile so the arrow lands on the tile's centre line.
  Widget _buildArrow() {
    return const SizedBox(
      height: _tileSize,
      width: 24,
      child: Center(
        child: Icon(
          Icons.arrow_forward_rounded,
          size: 16,
          color: AppColors.textTertiary,
        ),
      ),
    );
  }

  Widget _buildNode(_FlowStep step, {required bool isOutcome}) {
    return Column(
      children: [
        Container(
          height: _tileSize,
          width: _tileSize,
          decoration: BoxDecoration(
            color: isOutcome
                ? AppColors.primary.withValues(alpha: 0.12)
                : AppColors.backgroundSecondary,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isOutcome
                  ? AppColors.primary.withValues(alpha: 0.4)
                  : AppColors.borderPrimary,
            ),
          ),
          child: Icon(
            step.icon,
            size: 20,
            color: isOutcome ? AppColors.primaryLight : AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          step.label,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.labelSmall.copyWith(
            color: isOutcome ? AppColors.textPrimary : AppColors.textSecondary,
          ),
        ),
      ],
    );
  }

  static const double _tileSize = 48;
}

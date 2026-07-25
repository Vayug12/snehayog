import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vayug/core/design/colors.dart';
import 'package:vayug/core/design/spacing.dart';
import 'package:vayug/core/design/typography.dart';
import 'package:vayug/core/design/radius.dart';
import 'package:vayug/features/profile/core/data/services/user_service.dart';
import 'package:vayug/core/providers/profile_providers.dart';
import 'package:vayug/shared/utils/app_text.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vayug/shared/utils/app_logger.dart';
import 'package:vayug/shared/widgets/vayu_snackbar.dart';
import 'package:hugeicons/hugeicons.dart';

class LinkedAccountsScreen extends ConsumerStatefulWidget {
  const LinkedAccountsScreen({super.key});

  @override
  ConsumerState<LinkedAccountsScreen> createState() => _LinkedAccountsScreenState();
}

class _LinkedAccountsScreenState extends ConsumerState<LinkedAccountsScreen> {
  bool _isConnecting = false;
  final UserService _userService = UserService();

  Future<void> _connectYouTube() async {
    if (_isConnecting) return;

    setState(() => _isConnecting = true);

    try {
      final authUrl = await _userService.getYouTubeAuthUrl();
      if (authUrl != null) {
        final uri = Uri.parse(authUrl);
        // Direct launch with externalApplication is more robust for OAuth redirects
        final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
        
        if (launched && mounted) {
          VayuSnackBar.showInfo(
            context,
            AppText.get('linked_accounts_opening_browser',
                fallback: 'Opening browser to connect YouTube...'),
          );
        } else if (!launched) {
          throw Exception('Mobile browser could not be opened. Please check your browser settings.');
        }
      }
    } catch (e) {
      AppLogger.log('Error connecting YouTube: $e');
      if (mounted) {
        VayuSnackBar.showError(
          context,
          '${AppText.get('error_connect_youtube', fallback: 'Failed to connect YouTube')}: $e',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isConnecting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final stateManager = ref.watch(profileStateManagerProvider);
    final userData = stateManager.userData;
    
    final bool isYouTubeConnected = userData?['socialAccounts']?['youtube']?['connected'] ?? false;
    final String? channelTitle = userData?['socialAccounts']?['youtube']?['channelTitle'];

    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            title: Text(AppText.get('linked_accounts_title', fallback: 'Linked Accounts')),
            backgroundColor: AppColors.backgroundPrimary,
            floating: true,
            snap: true,
            elevation: 0,
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(AppSpacing.spacing4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(height: AppSpacing.spacing3),     
                  // YouTube Account Tile
                  _buildAccountTile(
                    context: context,
                    icon: HugeIcons.strokeRoundedYoutube,
                    title: AppText.get('linked_accounts_youtube', fallback: 'YouTube'),
                    description: AppText.get('linked_accounts_youtube_desc', fallback: 'Cross-post your videos to your YouTube channel automatically.'),
                    isConnected: isYouTubeConnected,
                    statusText: isYouTubeConnected 
                        ? (channelTitle ?? AppText.get('linked_accounts_connected', fallback: 'Connected'))
                        : AppText.get('linked_accounts_not_connected', fallback: 'Not Connected'),
                    onActionTap: isYouTubeConnected ? null : _connectYouTube,
                    isLoading: _isConnecting,
                    color: const Color(0xFFFF0000),
                  ),
                ],
              ),
            ),
          ),
          SliverFillRemaining(
            hasScrollBody: false,
            child: Column(
              children: [
                const Spacer(),
                if (isYouTubeConnected)
                  Center(
                    child: Text(
                      AppText.get('linked_accounts_refresh_hint', fallback: 'Refresh your profile after connecting to see the updated status.'),
                      style: AppTypography.labelSmall.copyWith(color: AppColors.textTertiary),
                      textAlign: TextAlign.center,
                    ),
                  ),
                SizedBox(height: AppSpacing.spacing4),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAccountTile({
    required BuildContext context,
    required dynamic icon,
    required String title,
    required String description,
    required bool isConnected,
    required String statusText,
    required VoidCallback? onActionTap,
    required bool isLoading,
    required Color color,
  }) {
    return Container(
      padding: EdgeInsets.all(AppSpacing.spacing4),
      decoration: BoxDecoration(
        color: AppColors.backgroundSecondary.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: AppColors.borderPrimary.withValues(alpha: 0.5),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(AppSpacing.spacing2),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: HugeIcon(
                  icon: icon,
                  color: color,
                  size: 24,
                ),
              ),
              SizedBox(width: AppSpacing.spacing3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppTypography.titleMedium.copyWith(color: AppColors.textPrimary),
                    ),
                    Text(
                      statusText,
                      style: AppTypography.labelMedium.copyWith(
                        color: isConnected ? AppColors.success : AppColors.textTertiary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              if (isLoading)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else if (!isConnected)
                TextButton(
                  onPressed: onActionTap,
                  child: Text(
                    AppText.get('linked_accounts_connect', fallback: 'Connect'),
                    style: AppTypography.labelMedium.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                )
              else
                 const Icon(Icons.check_circle, color: AppColors.success, size: 24),
            ],
          ),
          SizedBox(height: AppSpacing.spacing3),
          Text(
            description,
            style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

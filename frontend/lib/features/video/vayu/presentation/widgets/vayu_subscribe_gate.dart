import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vayug/core/design/colors.dart';
import 'package:vayug/core/design/radius.dart';
import 'package:vayug/core/design/spacing.dart';
import 'package:vayug/core/design/typography.dart';
import 'package:vayug/core/providers/user_data_providers.dart';
import 'package:vayug/features/profile/core/data/services/user_service.dart';
import 'package:vayug/shared/utils/app_logger.dart';
import 'package:vayug/shared/utils/format_utils.dart';
import 'package:vayug/shared/widgets/app_button.dart';
import 'package:vayug/shared/widgets/vayu_snackbar.dart';

/// First-run gate for the Vayu feed.
///
/// The feed is built from the creators a user subscribes to, so it stays locked
/// until [required] subscriptions exist. Progress is shown with dots instead of
/// a counter sentence — the UI says as little as possible.
class VayuSubscribeGate extends ConsumerStatefulWidget {
  final int followingCount;
  final int required;
  final Future<void> Function() onUnlock;

  const VayuSubscribeGate({
    super.key,
    required this.followingCount,
    required this.required,
    required this.onUnlock,
  });

  @override
  ConsumerState<VayuSubscribeGate> createState() => _VayuSubscribeGateState();
}

class _VayuSubscribeGateState extends ConsumerState<VayuSubscribeGate> {
  final UserService _userService = UserService();

  List<SuggestedCreator> _creators = [];
  final Set<String> _subscribedIds = {};
  final Set<String> _pendingIds = {};

  bool _isLoading = true;
  bool _isUnlocking = false;
  String? _errorMessage;

  int get _subscribedCount => widget.followingCount + _subscribedIds.length;
  bool get _isUnlocked => _subscribedCount >= widget.required;

  @override
  void initState() {
    super.initState();
    _loadCreators();
  }

  Future<void> _loadCreators() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final creators = await _userService.getSuggestedCreators(limit: 20);
      if (!mounted) return;
      setState(() {
        _creators = creators;
        _isLoading = false;
      });
    } catch (e) {
      AppLogger.log('❌ VayuSubscribeGate: Failed to load creators: $e');
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Could not load creators.';
      });
    }
  }

  /// Optimistic subscribe/unsubscribe. Reverts on failure so the dots never
  /// promise progress the backend did not record.
  Future<void> _toggleSubscription(SuggestedCreator creator) async {
    if (_pendingIds.contains(creator.id) || _isUnlocking) return;

    final wasSubscribed = _subscribedIds.contains(creator.id);
    setState(() {
      _pendingIds.add(creator.id);
      if (wasSubscribed) {
        _subscribedIds.remove(creator.id);
      } else {
        _subscribedIds.add(creator.id);
      }
    });

    try {
      final userProviderRef = ref.read(userProvider);
      final success = wasSubscribed
          ? await userProviderRef.unfollowUser(creator.id)
          : await userProviderRef.followUser(creator.id);

      if (!success) throw Exception('Request rejected');
    } catch (e) {
      AppLogger.log('❌ VayuSubscribeGate: Subscription failed: $e');
      if (mounted) {
        setState(() {
          if (wasSubscribed) {
            _subscribedIds.add(creator.id);
          } else {
            _subscribedIds.remove(creator.id);
          }
        });
        VayuSnackBar.showError(context, 'Could not update subscription.');
      }
    } finally {
      if (mounted) {
        setState(() => _pendingIds.remove(creator.id));
      }
    }
  }

  Future<void> _handleUnlock() async {
    if (_isUnlocking) return;
    setState(() => _isUnlocking = true);
    try {
      await widget.onUnlock();
    } finally {
      if (mounted) setState(() => _isUnlocking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(),
        Expanded(child: _buildCreatorList()),
        _buildFooter(),
      ],
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.spacing5,
        AppSpacing.spacing4,
        AppSpacing.spacing5,
        AppSpacing.spacing6,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildProgressDots(),
          SizedBox(height: AppSpacing.spacing5),
          Text(
            'Subscribe to ${widget.required} creators',
            style: AppTypography.headlineLarge,
          ),
          SizedBox(height: AppSpacing.spacing2),
          Text(
            'Your Vayu feed is built from them.',
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  /// Progress as dots — conveys "x of required" without a sentence.
  Widget _buildProgressDots() {
    return Row(
      children: List.generate(widget.required, (index) {
        final isFilled = index < _subscribedCount;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          margin: EdgeInsets.only(right: AppSpacing.spacing2),
          width: isFilled ? 24 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: isFilled ? AppColors.primary : AppColors.borderPrimary,
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
        );
      }),
    );
  }

  Widget _buildCreatorList() {
    if (_isLoading) {
      return ListView.builder(
        padding: EdgeInsets.symmetric(horizontal: AppSpacing.spacing5),
        itemCount: 6,
        itemBuilder: (context, index) => _buildShimmerRow(),
      );
    }

    if (_errorMessage != null) {
      return _buildMessage(
        _errorMessage!,
        action: AppButton(
          onPressed: _loadCreators,
          label: 'Try Again',
          variant: AppButtonVariant.outline,
        ),
      );
    }

    if (_creators.isEmpty) {
      return _buildMessage('No creators to show yet.');
    }

    return ListView.separated(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.spacing5,
        0,
        AppSpacing.spacing5,
        AppSpacing.spacing6,
      ),
      itemCount: _creators.length,
      separatorBuilder: (_, __) => SizedBox(height: AppSpacing.spacing5),
      itemBuilder: (context, index) => _buildCreatorRow(_creators[index]),
    );
  }

  Widget _buildCreatorRow(SuggestedCreator creator) {
    final isSubscribed = _subscribedIds.contains(creator.id);
    final isPending = _pendingIds.contains(creator.id);

    return InkWell(
      onTap: () => _toggleSubscription(creator),
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.spacing1),
        child: Row(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: AppColors.backgroundSecondary,
              backgroundImage: creator.profilePic.isNotEmpty
                  ? CachedNetworkImageProvider(creator.profilePic)
                  : null,
              child: creator.profilePic.isEmpty
                  ? const Icon(Icons.person_outline,
                      size: 20, color: AppColors.textTertiary)
                  : null,
            ),
            SizedBox(width: AppSpacing.spacing4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    creator.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.titleMedium,
                  ),
                  Text(
                    '${FormatUtils.formatViews(creator.followerCount)} subscribers',
                    style: AppTypography.bodySmall
                        .copyWith(color: AppColors.textTertiary),
                  ),
                ],
              ),
            ),
            SizedBox(width: AppSpacing.spacing3),
            _buildSubscribePill(isSubscribed: isSubscribed, isPending: isPending),
          ],
        ),
      ),
    );
  }

  Widget _buildSubscribePill({
    required bool isSubscribed,
    required bool isPending,
  }) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
      height: 34,
      width: isSubscribed ? 34 : 96,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: isSubscribed ? AppColors.primary : Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: isSubscribed
            ? null
            : Border.all(color: AppColors.borderPrimary, width: 1),
      ),
      child: isPending
          ? const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.textSecondary,
              ),
            )
          : isSubscribed
              ? const Icon(Icons.check_rounded,
                  size: 18, color: AppColors.white)
              : Text(
                  'Subscribe',
                  style: AppTypography.labelMedium,
                ),
    );
  }

  Widget _buildMessage(String message, {Widget? action}) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            message,
            style: AppTypography.bodyMedium
                .copyWith(color: AppColors.textSecondary),
          ),
          if (action != null) ...[
            SizedBox(height: AppSpacing.spacing6),
            action,
          ],
        ],
      ),
    );
  }

  /// The CTA only exists once the gate is cleared — nothing to explain, nothing
  /// to disable.
  Widget _buildFooter() {
    return AnimatedSize(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      child: _isUnlocked
          ? Padding(
              padding: EdgeInsets.fromLTRB(
                AppSpacing.spacing5,
                AppSpacing.spacing2,
                AppSpacing.spacing5,
                AppSpacing.spacing6,
              ),
              child: AppButton(
                onPressed: _handleUnlock,
                label: 'Continue',
                isLoading: _isUnlocking,
                isFullWidth: true,
              ),
            )
          : const SizedBox.shrink(),
    );
  }

  Widget _buildShimmerRow() {
    return Padding(
      padding: EdgeInsets.only(bottom: AppSpacing.spacing5),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.backgroundSecondary,
            ),
          ),
          SizedBox(width: AppSpacing.spacing4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 14,
                  width: 140,
                  decoration: BoxDecoration(
                    color: AppColors.backgroundSecondary,
                    borderRadius: BorderRadius.circular(AppRadius.xs),
                  ),
                ),
                SizedBox(height: AppSpacing.spacing2),
                Container(
                  height: 12,
                  width: 64,
                  decoration: BoxDecoration(
                    color: AppColors.backgroundSecondary.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(AppRadius.xs),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vayug/core/design/colors.dart';
import 'package:vayug/core/design/radius.dart';
import 'package:vayug/core/design/spacing.dart';
import 'package:vayug/core/design/typography.dart';
import 'package:vayug/core/providers/user_data_providers.dart';
import 'package:vayug/features/profile/core/data/services/user_service.dart';
import 'package:vayug/features/profile/core/presentation/screens/profile_screen.dart';
import 'package:vayug/shared/utils/app_logger.dart';
import 'package:vayug/shared/utils/format_utils.dart';
import 'package:vayug/shared/widgets/interactive_scale_button.dart';
import 'package:vayug/shared/widgets/vayu_snackbar.dart';

/// Horizontal rail of creators to subscribe to, injected once into the Vayu
/// feed so subscriptions can grow without leaving the feed.
///
/// It reserves its height while loading and disappears entirely when it has
/// nothing to offer — a half-broken shelf in the middle of a feed is worse than
/// no shelf at all.
class CreatorSuggestionsRail extends ConsumerStatefulWidget {
  const CreatorSuggestionsRail({super.key});

  @override
  ConsumerState<CreatorSuggestionsRail> createState() =>
      _CreatorSuggestionsRailState();
}

class _CreatorSuggestionsRailState
    extends ConsumerState<CreatorSuggestionsRail> {
  static const int _pageSize = 12;
  static const double _cardWidth = 104;
  static const double _avatarRadius = 22;
  static const double _buttonHeight = 32;

  /// Shared by the card and its skeleton so both measure identically.
  static EdgeInsets get _cardPadding => EdgeInsets.symmetric(
        horizontal: AppSpacing.spacing2,
        vertical: AppSpacing.spacing3,
      );

  final UserService _userService = UserService();
  final ScrollController _railController = ScrollController();

  List<SuggestedCreator> _creators = [];
  final Set<String> _subscribedIds = {};
  final Set<String> _pendingIds = {};

  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  bool _hasFailed = false;
  String? _nextCursor;

  @override
  void initState() {
    super.initState();
    _railController.addListener(_onRailScroll);
    _loadCreators();
  }

  @override
  void dispose() {
    _railController.dispose();
    super.dispose();
  }

  void _onRailScroll() {
    if (!_railController.hasClients ||
        _isLoading ||
        _isLoadingMore ||
        !_hasMore) {
      return;
    }
    if (_railController.position.extentAfter < _cardWidth * 2) {
      _loadCreators(loadMore: true);
    }
  }

  Future<void> _loadCreators({bool loadMore = false}) async {
    if (loadMore) {
      if (_isLoadingMore || !_hasMore) return;
      setState(() => _isLoadingMore = true);
    }

    try {
      final page = await _userService.getSuggestedCreatorsPage(
        limit: _pageSize,
        cursor: loadMore ? _nextCursor : null,
      );
      if (!mounted) return;
      setState(() {
        final existingIds = _creators.map((creator) => creator.id).toSet();
        final newCreators =
            page.creators.where((creator) => !existingIds.contains(creator.id));
        if (loadMore) {
          _creators.addAll(newCreators);
        } else {
          _creators = newCreators.toList();
        }
        _nextCursor = page.nextCursor;
        _hasMore = page.hasMore && page.nextCursor != null;
        _isLoading = false;
        _isLoadingMore = false;
      });
    } catch (e) {
      AppLogger.log('❌ CreatorSuggestionsRail: Failed to load creators: $e');
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _isLoadingMore = false;
        if (loadMore) {
          _hasMore = false;
        } else {
          _hasFailed = true;
        }
      });
    }
  }

  /// Optimistic, and reversible — the card keeps its place either way so the
  /// rail never reshuffles under the user's thumb.
  Future<void> _toggleSubscription(SuggestedCreator creator) async {
    if (_pendingIds.contains(creator.id)) return;

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
      AppLogger.log('❌ CreatorSuggestionsRail: Subscription failed: $e');
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
      if (mounted) setState(() => _pendingIds.remove(creator.id));
    }
  }

  void _openProfile(SuggestedCreator creator) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ProfileScreen(userId: creator.id)),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_hasFailed || (!_isLoading && _creators.isEmpty)) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: EdgeInsets.only(bottom: AppSpacing.spacing6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.spacing1,
              0,
              AppSpacing.spacing1,
              AppSpacing.spacing4,
            ),
            child: Text('More creators', style: AppTypography.headlineSmall),
          ),
          // No fixed rail height: the cards define it, so there is never
          // leftover space below them.
          SingleChildScrollView(
            controller: _railController,
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: AppSpacing.spacing1),
            physics: _isLoading
                ? const NeverScrollableScrollPhysics()
                : const ClampingScrollPhysics(),
            child: Row(children: _buildRailChildren()),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildRailChildren() {
    final cards = _isLoading
        ? List.generate(3, (_) => _buildSkeletonCard())
        : _creators.map(_buildCreatorCard).toList();

    return [
      for (int i = 0; i < cards.length; i++) ...[
        if (i > 0) SizedBox(width: AppSpacing.spacing3),
        cards[i],
      ],
      if (_isLoadingMore) ...[
        SizedBox(width: AppSpacing.spacing3),
        _buildSkeletonCard(),
      ],
    ];
  }

  Widget _buildCreatorCard(SuggestedCreator creator) {
    final isSubscribed = _subscribedIds.contains(creator.id);
    final isPending = _pendingIds.contains(creator.id);

    return InteractiveScaleButton(
      onTap: () => _openProfile(creator),
      child: SizedBox(
        width: _cardWidth,
        child: AspectRatio(
          aspectRatio: 9 / 16,
          child: Container(
            padding: _cardPadding,
            decoration: BoxDecoration(
              color: AppColors.backgroundSecondary,
              borderRadius: BorderRadius.circular(AppRadius.lg),
            ),
            child: Column(
              children: [
                CircleAvatar(
                  radius: _avatarRadius,
                  backgroundColor: AppColors.backgroundTertiary,
                  backgroundImage: creator.profilePic.isNotEmpty
                      ? CachedNetworkImageProvider(creator.profilePic)
                      : null,
                  child: creator.profilePic.isEmpty
                      ? const Icon(Icons.person_outline,
                          size: 22, color: AppColors.textTertiary)
                      : null,
                ),
                SizedBox(height: AppSpacing.spacing2),
                Text(
                  creator.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: AppTypography.titleMedium.copyWith(height: 1.2),
                ),
                Text(
                  '${FormatUtils.formatViews(creator.followerCount)} subs',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.labelSmall
                      .copyWith(color: AppColors.textTertiary, height: 1.2),
                ),
                const Spacer(),
                _buildSubscribeButton(
                  isSubscribed: isSubscribed,
                  isPending: isPending,
                  onTap: () => _toggleSubscription(creator),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSubscribeButton({
    required bool isSubscribed,
    required bool isPending,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: isPending ? null : onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        height: 44,
        child: Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            height: _buttonHeight,
            width: double.infinity,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isSubscribed ? Colors.transparent : AppColors.primary,
              borderRadius: BorderRadius.circular(AppRadius.pill),
              border: isSubscribed
                  ? Border.all(color: AppColors.borderPrimary, width: 1)
                  : null,
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
                        size: 18, color: AppColors.textSecondary)
                    : Text(
                        'Subscribe',
                        style: AppTypography.labelMedium.copyWith(
                          fontWeight: AppTypography.weightSemiBold,
                        ),
                      ),
          ),
        ),
      ),
    );
  }

  /// Mirrors the real card's structure — same avatar, same text metrics, same
  /// button — so the rail keeps its height when the data lands.
  Widget _buildSkeletonCard() {
    Widget bar(double width, double height) => Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: AppColors.backgroundTertiary.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(AppRadius.xs),
          ),
        );

    return SizedBox(
      width: _cardWidth,
      child: AspectRatio(
        aspectRatio: 9 / 16,
        child: Container(
          padding: _cardPadding,
          decoration: BoxDecoration(
            color: AppColors.backgroundSecondary.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
          child: Column(
            children: [
              CircleAvatar(
                radius: _avatarRadius,
                backgroundColor:
                    AppColors.backgroundTertiary.withValues(alpha: 0.4),
              ),
              SizedBox(height: AppSpacing.spacing2),
              bar(72, AppTypography.fontSizeBase * 1.2),
              bar(40, AppTypography.fontSizeXS * 1.2),
              const Spacer(),
              SizedBox(
                height: 44,
                child: Center(child: bar(double.infinity, _buttonHeight)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

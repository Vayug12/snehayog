import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:vayug/core/design/colors.dart';
import 'package:vayug/core/design/radius.dart';
import 'package:vayug/core/design/typography.dart';
import 'package:vayug/core/providers/profile_providers.dart';
import 'package:vayug/features/profile/core/data/services/user_service.dart';
import 'package:vayug/shared/utils/app_logger.dart';
import 'package:vayug/shared/utils/app_text.dart';
import 'package:vayug/shared/utils/format_utils.dart';
import 'package:vayug/shared/widgets/app_button.dart';

/// Opens the creator's subscriber list and clears the new-subscriber dot.
Future<void> showSubscribersBottomSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.48),
    builder: (_) => const SubscribersBottomSheet(),
  );
}

/// Paginated list of everyone subscribed to the signed-in creator, newest
/// first. Opening it marks the list as seen, which removes the red dot.
class SubscribersBottomSheet extends ConsumerStatefulWidget {
  const SubscribersBottomSheet({super.key});

  @override
  ConsumerState<SubscribersBottomSheet> createState() =>
      _SubscribersBottomSheetState();
}

class _SubscribersBottomSheetState
    extends ConsumerState<SubscribersBottomSheet> {
  static const int _pageSize = 30;
  static const double _loadMoreThreshold = 320;

  final List<Subscriber> _subscribers = <Subscriber>[];
  final UserService _userService = UserService();

  String? _cursor;
  String? _error;
  bool _hasMore = false;
  bool _isLoadingFirstPage = true;
  bool _isLoadingMore = false;
  int _total = 0;

  @override
  void initState() {
    super.initState();
    _loadFirstPage();
  }

  /// [showSpinner] is off for pull-to-refresh so the list stays on screen
  /// while the new page loads.
  Future<void> _loadFirstPage({bool showSpinner = true}) async {
    setState(() {
      if (showSpinner) _isLoadingFirstPage = true;
      _error = null;
    });

    try {
      final page = await _userService.getSubscribersPage(limit: _pageSize);
      if (!mounted) return;

      setState(() {
        _subscribers
          ..clear()
          ..addAll(page.subscribers);
        _cursor = page.nextCursor;
        _hasMore = page.hasMore;
        _total = page.total;
        _isLoadingFirstPage = false;
      });

      // The rows already carry the isNew flags computed before this call, so
      // the NEW pills stay visible for this viewing while the dot clears.
      _markSeen(page.newestSubscribedAt);
    } catch (e) {
      AppLogger.log('❌ SubscribersBottomSheet: Failed to load subscribers: $e');
      if (!mounted) return;
      setState(() {
        _isLoadingFirstPage = false;
        _error = AppText.get('subscribers_load_error');
      });
    }
  }

  Future<void> _loadMore() async {
    final cursor = _cursor;
    if (_isLoadingMore || !_hasMore || cursor == null) return;

    setState(() => _isLoadingMore = true);

    try {
      final page = await _userService.getSubscribersPage(
        limit: _pageSize,
        cursor: cursor,
      );
      if (!mounted) return;

      setState(() {
        _subscribers.addAll(page.subscribers);
        // Guard against a repeated cursor so the list can never loop forever
        _hasMore = page.hasMore && page.nextCursor != cursor;
        _cursor = page.nextCursor;
        _total = page.total;
        _isLoadingMore = false;
      });
    } catch (e) {
      AppLogger.log('❌ SubscribersBottomSheet: Failed to load next page: $e');
      if (!mounted) return;
      // Keep what is already on screen; scrolling again retries
      setState(() => _isLoadingMore = false);
    }
  }

  void _markSeen(DateTime? newestSubscribedAt) {
    // Runs on every successful first-page load: a refresh that pulls in newer
    // subscribers should clear the dot for those too.
    ref
        .read(subscribersBadgeManagerProvider)
        .markSeen(upTo: newestSubscribedAt);
  }

  bool _onScroll(ScrollNotification notification) {
    if (notification.metrics.axis != Axis.vertical) return false;
    final remaining =
        notification.metrics.maxScrollExtent - notification.metrics.pixels;
    if (remaining <= _loadMoreThreshold) _loadMore();
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: AppColors.surfacePrimary,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            children: [
              _buildHandle(),
              _buildHeader(),
              Expanded(child: _buildContent(scrollController)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHandle() {
    return Container(
      width: 32,
      height: 4,
      margin: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.textTertiary,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }

  Widget _buildHeader() {
    // The count is the title once it is known: "8 Subscribers"
    final title = _isLoadingFirstPage
        ? AppText.get('subscribers_title')
        : AppText.get('subscribers_title_count')
            .replaceAll('{count}', _total.toString());

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.titleMedium.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const HugeIcon(
              icon: HugeIcons.strokeRoundedCancel01,
              size: 20,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(ScrollController scrollController) {
    if (_isLoadingFirstPage) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }

    if (_error != null) return _buildErrorState(scrollController);

    if (_subscribers.isEmpty) return _buildEmptyState(scrollController);

    return RefreshIndicator(
      color: AppColors.primary,
      backgroundColor: AppColors.surfacePrimary,
      onRefresh: () => _loadFirstPage(showSpinner: false),
      child: NotificationListener<ScrollNotification>(
        onNotification: _onScroll,
        child: ListView.separated(
          controller: scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
          itemCount: _subscribers.length + (_hasMore ? 1 : 0),
          separatorBuilder: (_, __) => const SizedBox(height: 4),
          itemBuilder: (context, index) {
            if (index >= _subscribers.length) return _buildLoadMoreTile();
            return _SubscriberTile(subscriber: _subscribers[index]);
          },
        ),
      ),
    );
  }

  Widget _buildLoadMoreTile() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppColors.primary,
          ),
        ),
      ),
    );
  }

  Widget _buildErrorState(ScrollController scrollController) {
    return _buildMessageState(
      scrollController: scrollController,
      icon: const HugeIcon(
        icon: HugeIcons.strokeRoundedAlert02,
        size: 40,
        color: AppColors.textTertiary,
      ),
      title: _error!,
      message: AppText.get('subscribers_error_hint'),
      action: AppButton(
        label: AppText.get('subscribers_retry'),
        onPressed: _loadFirstPage,
        size: AppButtonSize.small,
      ),
    );
  }

  Widget _buildEmptyState(ScrollController scrollController) {
    return _buildMessageState(
      scrollController: scrollController,
      icon: const HugeIcon(
        icon: HugeIcons.strokeRoundedUserGroup,
        size: 40,
        color: AppColors.textTertiary,
      ),
      title: AppText.get('subscribers_empty_title'),
      message: AppText.get('subscribers_empty_hint'),
    );
  }

  Widget _buildMessageState({
    required ScrollController scrollController,
    required Widget icon,
    required String title,
    required String message,
    Widget? action,
  }) {
    // Scrollable so pull-to-refresh keeps working on empty/error states
    return RefreshIndicator(
      color: AppColors.primary,
      backgroundColor: AppColors.surfacePrimary,
      onRefresh: () => _loadFirstPage(showSpinner: false),
      child: ListView(
        controller: scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(32, 64, 32, 32),
        children: [
          icon,
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: AppTypography.bodyLarge.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          if (action != null) ...[
            const SizedBox(height: 20),
            Center(child: action),
          ],
        ],
      ),
    );
  }
}

class _SubscriberTile extends StatelessWidget {
  const _SubscriberTile({required this.subscriber});

  final Subscriber subscriber;

  @override
  Widget build(BuildContext context) {
    final subscribedAt = subscriber.subscribedAt;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: subscriber.isNew
            ? AppColors.primary.withValues(alpha: 0.08)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Row(
        children: [
          _buildAvatar(),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  subscriber.name.isEmpty ? 'Vayug user' : subscriber.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.bodyMedium.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (subscribedAt != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    AppText.get('subscribers_subscribed_at').replaceAll(
                      '{time}',
                      FormatUtils.formatTimeAgo(subscribedAt),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (subscriber.isNew) ...[
            const SizedBox(width: 8),
            _buildNewPill(),
          ],
        ],
      ),
    );
  }

  Widget _buildAvatar() {
    final profilePic = subscriber.profilePic ?? '';

    return ClipOval(
      child: SizedBox(
        width: 44,
        height: 44,
        child: profilePic.isEmpty
            ? _buildAvatarFallback()
            : CachedNetworkImage(
                imageUrl: profilePic,
                fit: BoxFit.cover,
                placeholder: (_, __) => _buildAvatarFallback(),
                errorWidget: (_, __, ___) => _buildAvatarFallback(),
              ),
      ),
    );
  }

  Widget _buildAvatarFallback() {
    return Container(
      color: AppColors.backgroundTertiary,
      child: const HugeIcon(
        icon: HugeIcons.strokeRoundedUser,
        size: 20,
        color: AppColors.textTertiary,
      ),
    );
  }

  Widget _buildNewPill() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.error,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        AppText.get('subscribers_new_badge'),
        style: AppTypography.labelSmall.copyWith(
          color: AppColors.white,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:vayug/core/design/colors.dart';
import 'package:vayug/core/design/typography.dart';
import 'package:vayug/core/design/spacing.dart';
import 'package:vayug/features/profile/core/data/services/user_service.dart';
import 'package:vayug/shared/utils/app_logger.dart';
import 'package:vayug/shared/widgets/app_button.dart';

class SubscriberSelectionScreen extends StatefulWidget {
  final ValueNotifier<List<String>> selectedSubscribers;

  const SubscriberSelectionScreen({
    super.key,
    required this.selectedSubscribers,
  });

  @override
  State<SubscriberSelectionScreen> createState() => _SubscriberSelectionScreenState();
}

class _SubscriberSelectionScreenState extends State<SubscriberSelectionScreen> {
  final TextEditingController _searchController = TextEditingController();
  final ValueNotifier<List<Subscriber>> _subscribers = ValueNotifier<List<Subscriber>>([]);
  final ValueNotifier<bool> _isLoading = ValueNotifier<bool>(true);
  final ValueNotifier<String?> _error = ValueNotifier<String?>(null);
  final UserService _userService = UserService();
  final ValueNotifier<List<String>> _internalSelection = ValueNotifier<List<String>>([]);

  @override
  void initState() {
    super.initState();
    _internalSelection.value = List<String>.from(widget.selectedSubscribers.value);
    _fetchSubscribers();
  }

  Future<void> _fetchSubscribers() async {
    try {
      _isLoading.value = true;
      _error.value = null;
      final subscribers = await _userService.getSubscribers();
      _subscribers.value = subscribers;
    } catch (e) {
      AppLogger.log('❌ Failed to fetch subscribers: $e');
      _error.value = 'Failed to load subscribers';
    } finally {
      _isLoading.value = false;
    }
  }

  void _toggleSelection(String id) {
    final current = List<String>.from(_internalSelection.value);
    if (current.contains(id)) {
      current.remove(id);
    } else {
      current.add(id);
    }
    _internalSelection.value = current;
  }

  void _toggleAll(bool selectAll) {
    if (selectAll) {
      _internalSelection.value = _subscribers.value.map((s) => s.id).toList();
    } else {
      _internalSelection.value = [];
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _subscribers.dispose();
    _isLoading.dispose();
    _error.dispose();
    _internalSelection.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      body: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverAppBar(
            backgroundColor: AppColors.backgroundPrimary,
            elevation: 0,
            floating: true,
            snap: true,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
              onPressed: () => Navigator.pop(context),
            ),
            title: Text(
              'Select Subscribers',
              style: AppTypography.headlineSmall.copyWith(fontWeight: FontWeight.w700),
            ),
            actions: [
              ValueListenableBuilder<List<String>>(
                valueListenable: _internalSelection,
                builder: (context, selected, _) {
                  if (selected.isEmpty) return const SizedBox.shrink();
                  return Center(
                    child: Padding(
                      padding: EdgeInsets.only(right: AppSpacing.spacing4),
                      child: Text(
                        '${selected.length}',
                        style: AppTypography.titleMedium.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
          SliverToBoxAdapter(child: _buildSearchBar()),
          SliverToBoxAdapter(child: _buildSelectAllBar()),
          ..._buildSliverSubscriberList(),
          SliverToBoxAdapter(child: _buildBottomAction()),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: EdgeInsets.fromLTRB(AppSpacing.spacing4, AppSpacing.spacing2, AppSpacing.spacing4, AppSpacing.spacing4),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.backgroundSecondary.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(16),
        ),
        child: TextField(
          controller: _searchController,
          onChanged: (_) => setState(() {}),
          style: AppTypography.bodyMedium,
          decoration: InputDecoration(
            hintText: 'Search subscribers...',
            hintStyle: AppTypography.bodySmall.copyWith(color: AppColors.textTertiary),
            prefixIcon: const Icon(Icons.search_rounded, size: 20, color: AppColors.textTertiary),
            border: InputBorder.none,
            contentPadding: EdgeInsets.symmetric(vertical: AppSpacing.spacing3),
          ),
        ),
      ),
    );
  }

  Widget _buildSelectAllBar() {
    return ValueListenableBuilder<List<Subscriber>>(
      valueListenable: _subscribers,
      builder: (context, all, _) {
        if (all.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: EdgeInsets.symmetric(horizontal: AppSpacing.spacing5, vertical: AppSpacing.spacing2),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'FOLLOWERS',
                  style: AppTypography.labelSmall.copyWith(
                    fontWeight: FontWeight.w800,
                    color: AppColors.textTertiary,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              ValueListenableBuilder<List<String>>(
                valueListenable: _internalSelection,
                builder: (context, selected, _) {
                  final isAllSelected = selected.length == all.length && all.isNotEmpty;
                  return InkWell(
                    onTap: () => _toggleAll(!isAllSelected),
                    child: Text(
                      isAllSelected ? 'Deselect All' : 'Select All',
                      style: AppTypography.labelMedium.copyWith(
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  List<Widget> _buildSliverSubscriberList() {
    return [
      ValueListenableBuilder<bool>(
        valueListenable: _isLoading,
        builder: (context, loading, _) {
          if (loading) {
            return const SliverFillRemaining(
              hasScrollBody: false,
              child:  Center(child: CircularProgressIndicator(strokeWidth: 2)),
            );
          }

          return ValueListenableBuilder<String?>(
            valueListenable: _error,
            builder: (context, error, _) {
              if (error != null) {
                return SliverFillRemaining(
                  hasScrollBody: false,
                  child: _buildErrorState(error),
                );
              }

              final query = _searchController.text.toLowerCase().trim();
              final filtered = _subscribers.value.where((s) =>
                  s.name.toLowerCase().contains(query)).toList();

              if (filtered.isEmpty) {
                return SliverFillRemaining(
                  hasScrollBody: false,
                  child: _buildEmptyState(),
                );
              }

              return SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final sub = filtered[index];
                    return ValueListenableBuilder<List<String>>(
                      valueListenable: _internalSelection,
                      builder: (context, selected, _) {
                        final isSelected = selected.contains(sub.id);
                        return Padding(
                          padding: EdgeInsets.symmetric(horizontal: AppSpacing.spacing4),
                          child: _buildSubscriberTile(sub, isSelected),
                        );
                      },
                    );
                  },
                  childCount: filtered.length,
                ),
              );
            },
          );
        },
      ),
    ];
  }

  Widget _buildSubscriberTile(Subscriber sub, bool isSelected) {
    return InkWell(
      onTap: () => _toggleSelection(sub.id),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.spacing2, horizontal: AppSpacing.spacing1),
        child: Container(
          padding: EdgeInsets.all(AppSpacing.spacing2),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primary.withValues(alpha: 0.05) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: AppColors.backgroundSecondary,
                backgroundImage: sub.profilePic != null ? NetworkImage(sub.profilePic!) : null,
                child: sub.profilePic == null
                    ? Text(sub.name.isNotEmpty ? sub.name[0].toUpperCase() : '?', style: AppTypography.titleSmall)
                    : null,
              ),
              SizedBox(width: AppSpacing.spacing3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(sub.name, style: AppTypography.titleSmall.copyWith(fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isSelected ? AppColors.primary : Colors.transparent,
                  border: Border.all(
                    color: isSelected ? AppColors.primary : AppColors.textTertiary.withValues(alpha: 0.3),
                    width: 1.5,
                  ),
                ),
                child: isSelected
                    ? const Icon(Icons.check, size: 14, color: Colors.white)
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomAction() {
    return Container(
      padding: EdgeInsets.fromLTRB(AppSpacing.spacing6, AppSpacing.spacing4, AppSpacing.spacing6, AppSpacing.spacing8),
      decoration: BoxDecoration(
        color: AppColors.backgroundPrimary,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: AppButton(
        onPressed: () {
          widget.selectedSubscribers.value = _internalSelection.value;
          Navigator.pop(context);
        },
        label: 'Confirm Selection',
        variant: AppButtonVariant.primary,
        isFullWidth: true,
      ),
    );
  }

  Widget _buildErrorState(String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 40),
          SizedBox(height: AppSpacing.spacing3),
          Text(message, style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary)),
          TextButton(onPressed: _fetchSubscribers, child: const Text('Retry')),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Text('No subscribers found', style: AppTypography.bodySmall.copyWith(color: AppColors.textTertiary)),
    );
  }
}

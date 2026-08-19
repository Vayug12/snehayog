import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vayug/core/design/colors.dart';
import 'package:vayug/core/design/typography.dart';
import 'package:vayug/core/design/spacing.dart';
import 'package:vayug/core/design/radius.dart';
import 'package:vayug/core/providers/auth_providers.dart';
import 'package:vayug/features/ads/data/ad_model.dart';
import 'package:vayug/features/ads/data/services/ad_service.dart';
import 'package:vayug/features/ads/presentation/screens/ad_detail_screen.dart';
import 'package:vayug/features/ads/presentation/screens/create_ad_screen_refactored.dart';
import 'package:vayug/features/auth/data/services/logout_service.dart';
import 'package:vayug/features/auth/presentation/controllers/auth_flow.dart';
import 'package:vayug/features/profile/core/presentation/widgets/profile_static_views.dart';
import 'package:vayug/shared/widgets/app_button.dart';

class AdManagementScreen extends ConsumerStatefulWidget {
  const AdManagementScreen({super.key});

  @override
  ConsumerState<AdManagementScreen> createState() => _AdManagementScreenState();
}

class _AdManagementScreenState extends ConsumerState<AdManagementScreen> {
  final AdService _adService = AdService();
  List<AdModel> _ads = [];
  bool _isLoading = true;
  String? _errorMessage;
  bool _showExpired = false;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadAds();
  }

  Future<void> _loadAds() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final ads = await _adService.getUserAds();
      setState(() {
        _ads = ads;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  List<AdModel> get _filteredAds {
    return _ads.where((ad) {
      // Expiration filter
      if (!_showExpired && ad.isExpired) return false;

      // Search filter
      if (_searchQuery.isNotEmpty) {
        final query = _searchQuery.toLowerCase();
        return ad.title.toLowerCase().contains(query) ||
            ad.description.toLowerCase().contains(query);
      }
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final authController = ref.watch(googleSignInProvider);
    final isSignedIn = authController.isSignedIn;

    if (!isSignedIn) {
      return ProfileSignInView(
        onGoogleSignIn: () async {
          await AuthFlow.signIn(
            context,
            ref,
            onSuccess: () async {
              await LogoutService.refreshAllState(ref);
              _loadAds();
            },
          );
        },
      );
    }

    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            title: const Text('Manage Ads', style: TextStyle(fontWeight: FontWeight.bold)),
            backgroundColor: AppColors.backgroundPrimary,
            floating: true,
            snap: true,
            elevation: 0,
            actions: [
              IconButton(
                icon: Icon(_showExpired ? Icons.history_toggle_off : Icons.history, 
                    color: _showExpired ? AppColors.primary : AppColors.textTertiary),
                onPressed: () => setState(() => _showExpired = !_showExpired),
                tooltip: _showExpired ? 'Hide Expired' : 'Show Expired',
              ),
              IconButton(
                icon: const Icon(Icons.refresh_rounded),
                onPressed: _loadAds,
              ),
            ],
          ),
          SliverToBoxAdapter(child: _buildSearchBar()),
          if (_isLoading)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_errorMessage != null)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _buildErrorView(),
            )
          else if (_filteredAds.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _buildEmptyView(),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final ad = _filteredAds[index];
                  return Padding(
                    padding: EdgeInsets.symmetric(horizontal: AppSpacing.space16),
                    child: _buildAdTile(ad),
                  );
                },
                childCount: _filteredAds.length,
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const CreateAdScreenRefactored()),
          );
          _loadAds();
        },
        backgroundColor: AppColors.primary,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Create Ad', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: EdgeInsets.all(AppSpacing.space16),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.backgroundSecondary,
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        child: TextField(
          onChanged: (v) => setState(() => _searchQuery = v),
          decoration: const InputDecoration(
            hintText: 'Search ads...',
            prefixIcon: Icon(Icons.search, size: 20),
            border: InputBorder.none,
            contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
        ),
      ),
    );
  }

  Widget _buildAdTile(AdModel ad) {
    return Container(
      margin: EdgeInsets.only(bottom: AppSpacing.space16),
      decoration: BoxDecoration(
        color: AppColors.backgroundSecondary,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: AppColors.borderPrimary.withValues(alpha: 0.3)),
      ),
      child: ListTile(
        contentPadding: EdgeInsets.all(AppSpacing.space8),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => AdDetailScreen(ad: ad, onRefresh: _loadAds),
          ),
        ),
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: Container(
            width: 60,
            height: 60,
            color: AppColors.backgroundTertiary,
            child: ad.imageUrl != null
                ? Image.network(ad.imageUrl!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.image_outlined))
                : const Icon(Icons.ad_units_outlined),
          ),
        ),
        title: Text(
          ad.title,
          style: AppTypography.labelLarge.copyWith(fontWeight: FontWeight.bold),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Row(
              children: [
                _buildCompactStatus(ad),
                const SizedBox(width: 8),
                Text(
                  '${ad.impressions} views • ${ad.clicks} clicks',
                  style: AppTypography.labelSmall.copyWith(color: AppColors.textTertiary),
                ),
              ],
            ),
          ],
        ),
        trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.textTertiary),
      ),
    );
  }

  Widget _buildCompactStatus(AdModel ad) {
    final isExpired = ad.isExpired;
    final color = isExpired ? AppColors.error : ad.performanceColor;
    final text = isExpired ? 'Expired' : ad.status;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 0.5),
      ),
    );
  }

  Widget _buildEmptyView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.ad_units_rounded, size: 64, color: AppColors.textTertiary.withValues(alpha: 0.3)),
          const SizedBox(height: 16),
          Text('No ads found', style: AppTypography.bodyLarge.copyWith(color: AppColors.textTertiary)),
          if (_searchQuery.isNotEmpty || !_showExpired)
            TextButton(
              onPressed: () => setState(() {
                _searchQuery = '';
                _showExpired = true;
              }),
              child: const Text('Clear filters'),
            ),
        ],
      ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(AppSpacing.space24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: AppColors.error),
            const SizedBox(height: 16),
            Text('Something went wrong', style: AppTypography.headlineSmall),
            const SizedBox(height: 8),
            Text(_errorMessage!, textAlign: TextAlign.center, style: AppTypography.bodySmall),
            const SizedBox(height: 24),
            AppButton(onPressed: _loadAds, label: 'Try Again'),
          ],
        ),
      ),
    );
  }
}

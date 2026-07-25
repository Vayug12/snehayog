import 'package:flutter/material.dart';
import 'package:vayug/core/design/colors.dart';
import 'package:vayug/core/design/typography.dart';
import 'package:vayug/core/design/spacing.dart';
import 'package:vayug/core/design/radius.dart';
import 'package:vayug/features/ads/data/ad_model.dart';
import 'package:vayug/features/ads/data/services/ad_service.dart';
import 'package:vayug/shared/widgets/app_button.dart';
import 'package:vayug/features/ads/data/services/ad_impression_service.dart';
import 'package:vayug/shared/utils/app_logger.dart';
import 'package:vayug/shared/widgets/vayu_snackbar.dart';
class AdDetailScreen extends StatefulWidget {
  final AdModel ad;
  final VoidCallback onRefresh;

  const AdDetailScreen({
    super.key,
    required this.ad,
    required this.onRefresh,
  });

  @override
  State<AdDetailScreen> createState() => _AdDetailScreenState();
}

class _AdDetailScreenState extends State<AdDetailScreen> {
  final AdService _adService = AdService();
  final AdImpressionService _adImpressionService = AdImpressionService();
  late AdModel _ad;
  bool _isLoading = false;
  bool _isStatsLoading = true;
  
  // Real-time metrics
  int _realTimeImpressions = 0;
  int _realTimeViews = 0;
  int _realTimeClicks = 0;
  double _realTimeSpend = 0.0;
  List<Map<String, dynamic>> _videoBreakdown = [];

  @override
  void initState() {
    super.initState();
    _ad = widget.ad;
    _fetchRealTimePerformance();
  }

  Future<void> _fetchRealTimePerformance() async {
    if (!mounted) return;
    setState(() => _isStatsLoading = true);
    
    try {
      // 1. Fetch overall analytics (summary)
      final analytics = await _adService.getAdAnalytics(_ad.id);
      final adData = analytics['ad'] ?? {};
      
      // 2. Fetch video-specific breakdown
      final breakdown = await _adImpressionService.getAdVideoBreakdown(_ad.id);
      
      if (mounted) {
        setState(() {
          _realTimeImpressions = int.tryParse(adData['impressions']?.toString() ?? '0') ?? 0;
          _realTimeViews = int.tryParse(adData['views']?.toString() ?? '0') ?? 0;
          _realTimeClicks = int.tryParse(adData['clicks']?.toString() ?? '0') ?? 0;
          _realTimeSpend = double.tryParse(adData['spend']?.toString() ?? '0.0') ?? 0.0;
          _videoBreakdown = breakdown;
          _isStatsLoading = false;
        });
      }
    } catch (e) {
      AppLogger.log('❌ AdDetailScreen: Error fetching real-time performance: $e');
      if (mounted) {
        setState(() {
          _realTimeImpressions = _ad.impressions;
          _realTimeClicks = _ad.clicks;
          _isStatsLoading = false;
        });
      }
    }
  }

  Future<void> _updateStatus(String newStatus) async {
    setState(() => _isLoading = true);
    try {
      final updatedAd = await _adService.updateAdStatus(_ad.id, newStatus);
      setState(() {
        _ad = updatedAd;
        _isLoading = false;
      });
      widget.onRefresh();
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        VayuSnackBar.showError(context, 'Error: $e');
      }
    }
  }

  Future<void> _deleteAd() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Advertisement'),
        content: const Text('Are you sure you want to delete this ad? This action cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() => _isLoading = true);
      try {
        final success = await _adService.deleteAd(_ad.id);
        if (success) {
          widget.onRefresh();
          if (mounted) Navigator.pop(context);
        }
      } catch (e) {
        setState(() => _isLoading = false);
        if (mounted) {
          VayuSnackBar.showError(context, 'Error: $e');
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            title: const Text('Ad Details', style: TextStyle(fontWeight: FontWeight.bold)),
            centerTitle: true,
            backgroundColor: AppColors.backgroundPrimary,
            floating: true,
            snap: true,
            elevation: 0,
            actions: [
              IconButton(
                icon: const Icon(Icons.delete_outline, color: AppColors.error),
                onPressed: _isLoading ? null : _deleteAd,
              ),
            ],
          ),
          if (_isLoading)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: CircularProgressIndicator()),
            )
          else
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(AppSpacing.space16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildStatusBanner(),
                    SizedBox(height: AppSpacing.space16),
                    _buildHeader(),
                    SizedBox(height: AppSpacing.space24),
                    _buildAnalyticsSection(),
                    SizedBox(height: AppSpacing.space24),
                    _buildDetailsSection(),
                    SizedBox(height: AppSpacing.space24),
                    _buildTargetingSection(),
                    SizedBox(height: AppSpacing.space32),
                    _buildActions(),
                    SizedBox(height: AppSpacing.space48),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStatusBanner() {
    final isExpired = _ad.isExpired;
    final color = isExpired ? AppColors.error : _ad.performanceColor;
    final statusText = isExpired ? 'EXPIRED' : _ad.status.toUpperCase();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(isExpired ? Icons.timer_off_outlined : Icons.info_outline, color: color, size: 16),
          const SizedBox(width: 8),
          Text(
            statusText,
            style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1.1),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_ad.imageUrl != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.md),
            child: Image.network(
              _ad.imageUrl!,
              width: 100,
              height: 100,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                width: 100,
                height: 100,
                color: AppColors.backgroundTertiary,
                child: const Icon(Icons.image_outlined, color: AppColors.textTertiary),
              ),
            ),
          )
        else
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: AppColors.backgroundTertiary,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: const Icon(Icons.ad_units_outlined, color: AppColors.textTertiary),
          ),
        SizedBox(width: AppSpacing.space16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_ad.title, style: AppTypography.headlineSmall),
              const SizedBox(height: 4),
              Text(
                _ad.adType.toUpperCase(),
                style: const TextStyle(
                  color: AppColors.primary,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _ad.description,
                style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAnalyticsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Performance', style: AppTypography.labelLarge),
            if (_isStatsLoading)
              const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2))
            else
              GestureDetector(
                onTap: _fetchRealTimePerformance,
                child: const Icon(Icons.refresh, size: 16, color: AppColors.primary),
              ),
          ],
        ),
        SizedBox(height: AppSpacing.space16),
        Row(
          children: [
            _buildStatCard('Impressions', _realTimeImpressions.toString(), Icons.visibility_outlined),
            SizedBox(width: AppSpacing.space16),
            _buildStatCard('Views', _realTimeViews.toString(), Icons.play_circle_outline),
          ],
        ),
        SizedBox(height: AppSpacing.space16),
        Row(
          children: [
            _buildStatCard('Clicks', _realTimeClicks.toString(), Icons.touch_app_outlined),
            SizedBox(width: AppSpacing.space16),
            _buildStatCard(
              'CTR', 
              _realTimeImpressions > 0 
                ? '${((_realTimeClicks / _realTimeImpressions) * 100).toStringAsFixed(2)}%' 
                : '0.00%', 
              Icons.trending_up
            ),
          ],
        ),
        SizedBox(height: AppSpacing.space16),
        Row(children: [_buildStatCard('Total Spend', '₹${_realTimeSpend.toStringAsFixed(2)}', Icons.account_balance_wallet_outlined)]),
        if (_videoBreakdown.isNotEmpty) ...[
          SizedBox(height: AppSpacing.space24),
          _buildPerformanceBreakdown(),
        ],
      ],
    );
  }

  Widget _buildPerformanceBreakdown() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Video Breakdown', style: AppTypography.labelLarge),
        const SizedBox(height: 8),
        Text(
          'See which videos are driving your campaign performance',
          style: AppTypography.labelSmall.copyWith(color: AppColors.textTertiary),
        ),
        SizedBox(height: AppSpacing.space16),
        Container(
          decoration: BoxDecoration(
            color: AppColors.backgroundSecondary,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: AppColors.borderPrimary.withValues(alpha: 0.5)),
          ),
          child: ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _videoBreakdown.length,
            separatorBuilder: (_, __) => Divider(color: AppColors.borderPrimary.withValues(alpha: 0.3), height: 1),
            itemBuilder: (context, index) {
              final item = _videoBreakdown[index];
              return Padding(
                padding: EdgeInsets.all(AppSpacing.space12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item['videoTitle'] ?? 'Untitled Video',
                      style: AppTypography.labelMedium.copyWith(fontWeight: FontWeight.bold),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _buildMiniStat('Impressions', item['impressions'].toString()),
                        _buildMiniStat('Views', item['views'].toString()),
                        _buildMiniStat('CTR', '${item['ctr']}%'),
                        _buildMiniStat('Spend', '₹${item['spend']}'),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildMiniStat(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: AppTypography.labelMedium.copyWith(fontWeight: FontWeight.bold, fontSize: 13)),
        Text(label, style: AppTypography.labelSmall.copyWith(color: AppColors.textTertiary, fontSize: 10)),
      ],
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon) {
    return Expanded(
      child: Container(
        padding: EdgeInsets.all(AppSpacing.space16),
        decoration: BoxDecoration(
          color: AppColors.backgroundSecondary,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: AppColors.borderPrimary.withValues(alpha: 0.5)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: AppColors.textTertiary),
            const SizedBox(height: 8),
            Text(value, style: AppTypography.headlineSmall.copyWith(fontSize: 18)),
            const SizedBox(height: 2),
            Text(label, style: AppTypography.labelSmall.copyWith(color: AppColors.textTertiary)),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Campaign Details', style: AppTypography.labelLarge),
        SizedBox(height: AppSpacing.space16),
        _buildDetailRow('Budget', _ad.formattedBudget),
        _buildDetailRow('Start Date', _ad.startDate?.toString().split(' ')[0] ?? 'Not set'),
        _buildDetailRow('End Date', _ad.endDate?.toString().split(' ')[0] ?? 'Not set'),
        _buildDetailRow('Destination', _ad.link ?? 'None'),
      ],
    );
  }

  Widget _buildTargetingSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Targeting', style: AppTypography.labelLarge),
        SizedBox(height: AppSpacing.space16),
        _buildDetailRow('Age', _ad.ageTargeting),
        _buildDetailRow('Gender', _ad.genderTargeting),
        _buildDetailRow('Locations', _ad.locationSummary),
        _buildDetailRow('Platforms', _ad.platformSummary),
      ],
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: EdgeInsets.only(bottom: AppSpacing.space8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: AppTypography.bodySmall.copyWith(color: AppColors.textTertiary)),
          Text(value, style: AppTypography.bodySmall.copyWith(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildActions() {
    return Column(
      children: [
        if (_ad.isActive)
          AppButton(
            onPressed: () => _updateStatus('paused'),
            label: 'Pause Campaign',
            variant: AppButtonVariant.secondary,
            isFullWidth: true,
          )
        else if (_ad.status == 'paused')
          AppButton(
            onPressed: () => _updateStatus('active'),
            label: 'Resume Campaign',
            variant: AppButtonVariant.primary,
            isFullWidth: true,
          ),
      ],
    );
  }
}

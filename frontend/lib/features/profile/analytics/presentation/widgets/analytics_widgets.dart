import 'package:flutter/material.dart';
import 'package:vayug/core/design/colors.dart';
import 'package:vayug/core/design/spacing.dart';
import 'package:vayug/core/design/radius.dart';
import 'package:vayug/core/design/typography.dart';
import '../../domain/models/analytics_models.dart';

class AnalyticsStatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final VoidCallback? onTap;
  final Color color;
  final int? growth;

  const AnalyticsStatCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.onTap,
    this.color = AppColors.primary,
    this.growth,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Container(
        padding: EdgeInsets.all(AppSpacing.spacing4),
        decoration: BoxDecoration(
          color: AppColors.backgroundSecondary,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: AppColors.borderPrimary),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 20),
            AppSpacing.vSpace8,
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  value,
                  style: AppTypography.titleLarge.copyWith(fontWeight: AppTypography.weightBold),
                ),
                if (growth != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: (growth! >= 0 ? Colors.green : Colors.red).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          growth! >= 0 ? Icons.trending_up : Icons.trending_down,
                          size: 12,
                          color: growth! >= 0 ? Colors.green : Colors.red,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          "${growth!.abs()}%",
                          style: AppTypography.labelSmall.copyWith(
                            color: growth! >= 0 ? Colors.green : Colors.red,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            Text(
              label,
              style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class PerformanceChart extends StatelessWidget {
  final List<DailyStat> data;
  final String title;
  final VoidCallback? onTap;

  const PerformanceChart({super.key, required this.data, required this.title, this.onTap});

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) return const SizedBox.shrink();
    
    // Simple bar chart representation for now
    final maxViews = data.map((e) => e.views).reduce((a, b) => a > b ? a : b);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: Container(
        padding: EdgeInsets.all(AppSpacing.spacing4),
        decoration: BoxDecoration(
          color: AppColors.backgroundSecondary,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: AppColors.borderPrimary),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: AppTypography.titleMedium),
            AppSpacing.vSpace16,
            SizedBox(
              height: 150,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: data.map((d) {
                  final heightFactor = maxViews > 0 ? d.views / maxViews : 0.0;
                  return Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Container(
                        width: 20,
                        height: 100 * heightFactor,
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(AppRadius.xs),
                        ),
                      ),
                      AppSpacing.vSpace4,
                      Text(
                        d.date.length >= 2 ? d.date.substring(d.date.length - 2) : d.date,
                        style: AppTypography.labelSmall,
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class TopVideosList extends StatelessWidget {
  final List<VideoPerformance> videos;

  const TopVideosList({super.key, required this.videos});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("Top Performing Videos", style: AppTypography.titleMedium),
        AppSpacing.vSpace12,
        ...videos.map((v) => Container(
          margin: EdgeInsets.only(bottom: AppSpacing.spacing2),
          padding: EdgeInsets.all(AppSpacing.spacing3),
          decoration: BoxDecoration(
            color: AppColors.backgroundSecondary,
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(v.title, style: AppTypography.bodyMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text("${v.views} views • ${v.shares} shares", style: AppTypography.labelSmall.copyWith(color: AppColors.textSecondary)),
                  ],
                ),
              ),
              const Icon(Icons.trending_up, color: AppColors.success, size: 16),
            ],
          ),
        )),
      ],
    );
  }
}

class AudienceInsightCard extends StatelessWidget {
  final String title;
  final Widget content;

  const AudienceInsightCard({super.key, required this.title, required this.content});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(AppSpacing.spacing4),
      decoration: BoxDecoration(
        color: AppColors.backgroundSecondary,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.borderPrimary),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppTypography.titleMedium),
          AppSpacing.vSpace12,
          content,
        ],
      ),
    );
  }
}

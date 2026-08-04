import 'package:flutter/material.dart';
import 'package:vayug/core/design/colors.dart';
import 'package:vayug/core/design/typography.dart';
import 'package:vayug/shared/widgets/app_button.dart';

/// **AdvertisingBenefitsWidget - Explains the value of advertising on Vayug**
class AdvertisingBenefitsWidget {
  /// Show advertising benefits dialog
  static void show(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.star, color: AppColors.warning, size: 24),
            const SizedBox(width: 12),
            Text(
              'Why Advertise on Vayug?',
              style: AppTypography.headlineSmall.copyWith(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppColors.white,
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildBenefitItem(
                'Guaranteed Ad Impressions',
                'Unlike other platforms where ad reach is uncertain, Vayug ensures advertisers get guaranteed impressions, providing clear ROI visibility.',
                Icons.visibility,
                AppColors.primary,
              ),
              const SizedBox(height: 16),
              _buildBenefitItem(
                'Creator-First Reward Model',
                'Creators receive rewards based on engagement, leading to higher motivation and engagement. This results in more authentic content, ensuring advertisers\' ads are placed in highly engaging and trusted environments.',
                Icons.people,
                AppColors.success,
              ),
              const SizedBox(height: 16),
              _buildBenefitItem(
                'High Engagement & Brand Recall',
                'Since creators are directly incentivized, they actively promote and integrate brand ads, leading to better click-through and conversion rates.',
                Icons.trending_up,
                AppColors.warning,
              ),
              const SizedBox(height: 16),
              _buildBenefitItem(
                'Less Competition, More Attention',
                'Unlike crowded platforms (YouTube, Instagram, etc.), Vayug offers advertisers a space with lower competition for user attention, increasing ad visibility and impact.',
                Icons.psychology,
                AppColors.primaryDark,
              ),
              const SizedBox(height: 16),
              _buildBenefitItem(
                'Safe & Relevant Ad Placements',
                'Ads are displayed only on clean and safe content, ensuring brand safety and alignment with advertiser values.',
                Icons.security,
                AppColors.primaryLight,
              ),
              const SizedBox(height: 16),
              _buildBenefitItem(
                'Focused User Experience',
                'With a clutter-free interface and fewer distractions, ads receive greater user focus compared to traditional platforms overloaded with content.',
                Icons.center_focus_strong,
                AppColors.info,
              ),
              const SizedBox(height: 16),
              _buildBenefitItem(
                'Emerging Market Advantage',
                'Early advertisers on Vayug benefit from first-mover advantage, capturing audience attention before the platform scales massively.',
                Icons.rocket_launch,
                AppColors.error,
              ),
            ],
          ),
        ),
        actions: [
          AppButton(
            onPressed: () => Navigator.pop(context),
            label: 'Got it!',
            variant: AppButtonVariant.text,
          ),
        ],
      ),
    );
  }

  static Widget _buildBenefitItem(
      String title, String description, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                    height: 1.4,
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

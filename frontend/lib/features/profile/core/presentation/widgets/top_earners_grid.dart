import 'dart:convert';
import 'package:vayug/core/design/spacing.dart';
import 'package:vayug/core/design/radius.dart';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:vayug/shared/services/http_client_service.dart';
import 'package:vayug/shared/config/app_config.dart';
import 'package:vayug/features/auth/data/services/authservices.dart';
import 'package:vayug/shared/utils/app_logger.dart';
import 'package:vayug/features/profile/core/presentation/screens/profile_screen.dart';
import 'package:vayug/core/design/colors.dart';
import 'package:vayug/core/design/typography.dart';
import 'package:vayug/shared/widgets/app_button.dart';

/// Compact grid (3 columns) showing top creators from the user's following list.
/// This reuses the same API as `TopEarnersBottomSheet` but is optimised for the
/// ProfileScreen "Recommendations" tab.
class TopEarnersGrid extends StatefulWidget {
  const TopEarnersGrid({super.key});

  @override
  State<TopEarnersGrid> createState() => _TopEarnersGridState();
}

class _TopEarnersGridState extends State<TopEarnersGrid> {
  List<Map<String, dynamic>> _topCreators = [];
  bool _isLoading = false;
  bool _hasError = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadTopCreators();
  }

  Future<void> _loadTopCreators() async {
    if (_isLoading) return;

    setState(() {
      _isLoading = true;
      _hasError = false;
      _errorMessage = null;
    });

    try {
      final token = await AuthService.getToken();
      if (token == null || token.isEmpty) {
        setState(() {
          _hasError = true;
          _errorMessage = 'Sign in to see top creators.';
          _isLoading = false;
        });
        return;
      }

      final baseUrl = await AppConfig.getBaseUrlWithFallback();
      final uri = Uri.parse('$baseUrl/api/users/top-earners-from-following');

      AppLogger.log('💰 TopCreatorsGrid: Fetching top creators from $uri');

      final response = await httpClientService.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        timeout: const Duration(seconds: 30),
      );

      AppLogger.log(
          '💰 TopCreatorsGrid: Response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final topCreators =
            List<Map<String, dynamic>>.from(data['topEarners'] ?? []);

        setState(() {
          _topCreators = topCreators;
          _isLoading = false;
        });
      } else {
        setState(() {
          _hasError = true;
          _errorMessage = 'Failed to load top creators (${response.statusCode})';
          _isLoading = false;
        });
      }
    } catch (e, stackTrace) {
      AppLogger.log('❌ TopCreatorsGrid: Error loading top creators: $e');
      AppLogger.log('❌ TopCreatorsGrid: Stack trace: $stackTrace');
      setState(() {
        _hasError = true;
        _errorMessage = e.toString().contains('TimeoutException')
            ? 'Request timeout. Please check your connection.'
            : e.toString().contains('SocketException')
                ? 'Network error. Please check your internet connection.'
                : 'Failed to load top creators';
        _isLoading = false;
      });
    }
  }

  void _navigateToUserProfile(String userId) {
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ProfileScreen(userId: userId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24.0),
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_hasError) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 32),
              const SizedBox(height: 8),
              Text(
                _errorMessage ?? 'Failed to load top creators',
                style: const TextStyle(
                  color: Colors.black87,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              AppButton(
                onPressed: _loadTopCreators,
                icon: const Icon(Icons.refresh, size: 18),
                label: 'Retry',
                variant: AppButtonVariant.text,
              ),
            ],
          ),
        ),
      );
    }

    if (_topCreators.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.people_outline, size: 40, color: Colors.grey),
              SizedBox(height: 8),
              Text(
                'No top creators yet',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF4B5563),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // LIST: Professional vertical list with horizontal items
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.symmetric(
        horizontal: AppSpacing.spacing4,
        vertical: AppSpacing.spacing4,
      ),
      itemCount: _topCreators.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final creator = _topCreators[index];
        return _buildCreatorListItem(creator, index + 1);
      },
    );
  }

  Widget _buildCreatorListItem(Map<String, dynamic> creator, int rank) {
    final userId = creator['userId'] as String?;
    final name = creator['name'] as String? ?? 'Unknown';
    final profilePic = creator['profilePic'] as String?;
    final score = (creator['totalEarnings'] as num?)?.toDouble() ?? 0.0;

    Color badgeColor;
    if (rank == 1) {
      badgeColor = const Color(0xFFFFD700); // gold
    } else if (rank == 2) {
      badgeColor = const Color(0xFFC0C0C0); // silver
    } else if (rank == 3) {
      badgeColor = const Color(0xFFCD7F32); // bronze
    } else {
      badgeColor = Colors.transparent;
    }

    return GestureDetector(
      onTap: userId != null ? () => _navigateToUserProfile(userId) : null,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.backgroundSecondary.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(
            color: AppColors.borderPrimary.withValues(alpha: 0.5),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            // Rank Number/Badge
            Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: badgeColor != Colors.transparent 
                    ? badgeColor 
                    : AppColors.backgroundPrimary.withValues(alpha: 0.3),
                shape: BoxShape.circle,
                boxShadow: rank <= 3 ? [
                  BoxShadow(
                    color: badgeColor.withValues(alpha: 0.3),
                    blurRadius: 4,
                    spreadRadius: 1,
                  )
                ] : [],
              ),
              child: Text(
                '$rank',
                style: TextStyle(
                  color: rank <= 3 ? AppColors.textInverse : AppColors.textPrimary,
                  fontSize: AppTypography.fontSizeSM,
                  fontWeight: AppTypography.weightBold,
                ),
              ),
            ),
            const SizedBox(width: 12),
            
            // Avatar
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.2), 
                  width: 2,
                ),
              ),
              child: ClipOval(
                child: profilePic != null && profilePic.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: profilePic,
                        fit: BoxFit.cover,
                        placeholder: (context, url) => Container(
                          color: AppColors.backgroundSecondary,
                          child: const Icon(Icons.person, size: 24),
                        ),
                        errorWidget: (context, url, error) => Container(
                          color: AppColors.backgroundSecondary,
                          child: const Icon(Icons.person, size: 24),
                        ),
                      )
                    : Container(
                        color: AppColors.backgroundSecondary,
                        child: const Icon(Icons.person, size: 24),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            
            // Name
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: AppTypography.fontSizeBase,
                      fontWeight: AppTypography.weightSemiBold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  if (rank <= 3)
                    Text(
                      rank == 1 ? 'Top Creator' : 'Popular Creator',
                      style: TextStyle(
                        fontSize: AppTypography.fontSizeXS,
                        color: AppColors.primary,
                        fontWeight: AppTypography.weightMedium,
                      ),
                    ),
                ],
              ),
            ),
            
            // Score
            if (score > 0)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.trending_up, size: 14, color: AppColors.success),
                    const SizedBox(width: 4),
                    Text(
                      _formatScore(score),
                      style: TextStyle(
                        fontSize: AppTypography.fontSizeSM,
                        fontWeight: AppTypography.weightBold,
                        color: AppColors.success,
                      ),
                    ),
                  ],
                ),
              ),
            
            const SizedBox(width: 4),
            const Icon(
              Icons.chevron_right,
              color: AppColors.textTertiary,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  String _formatScore(double score) {
    if (score >= 10000000) {
      return '${(score / 10000000).toStringAsFixed(1)} Cr';
    } else if (score >= 100000) {
      return '${(score / 100000).toStringAsFixed(1)} L';
    } else if (score >= 1000) {
      return '${(score / 1000).toStringAsFixed(1)}K';
    } else {
      return score.toStringAsFixed(0);
    }
  }
}

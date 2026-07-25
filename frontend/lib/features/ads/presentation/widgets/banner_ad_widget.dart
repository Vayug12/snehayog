import 'dart:async';
import 'package:flutter/material.dart';

import 'package:vayug/features/ads/data/services/active_ads_service.dart';
import 'package:vayug/features/ads/domain/i_ad_service.dart';
import 'package:vayug/features/ads/data/services/ad_impression_service.dart';
import 'package:vayug/features/auth/data/services/authservices.dart';
import 'package:vayug/shared/config/app_config.dart';
import 'package:vayug/shared/utils/app_logger.dart';
import 'package:vayug/shared/utils/url_utils.dart';
import 'package:vayug/shared/constants/app_constants.dart';
import 'package:vayug/core/design/colors.dart';
import 'package:vayug/shared/widgets/in_app_browser.dart';
import 'package:vayug/shared/widgets/vayu_snackbar.dart';

/// Widget to display banner ads at the top of video feed
class BannerAdWidget extends StatefulWidget {
  final Map<String, dynamic> adData;
  final VoidCallback? onAdClick;
  final VoidCallback? onAdImpression;
  final VoidCallback? onVideoPause;
  final VoidCallback? onVideoResume;
  final IAdService? adService;

  const BannerAdWidget({
    Key? key,
    required this.adData,
    this.onAdClick,
    this.onAdImpression,
    this.onVideoPause,
    this.onVideoResume,
    this.adService,
  }) : super(key: key);

  @override
  State<BannerAdWidget> createState() => _BannerAdWidgetState();
}

class _BannerAdWidgetState extends State<BannerAdWidget> {
  bool _hasTrackedView = false; // Prevent duplicate view tracking
  DateTime? _viewStartTime; // Track when ad became visible
  Timer? _viewTrackingTimer; // Timer to check view duration

  // Cache image provider per banner to avoid rebuild flicker
  static final Map<String, ImageProvider> _imageProviderCache = {};

  final AdImpressionService _adImpressionService = AdImpressionService();
  final AuthService _authService = AuthService();

  @override
  void initState() {
    super.initState();
    // Start tracking view duration when widget is built
    _startViewTracking();
  }

  @override
  void dispose() {
    _viewTrackingTimer?.cancel();
    super.dispose();
  }

  /// **NEW: Track ad view duration (minimum 4 seconds)**
  void _startViewTracking() {
    _viewStartTime = DateTime.now();

    // Track view after minimum duration (4 seconds for ads)
    _viewTrackingTimer = Timer(AppConstants.adViewCountThreshold, () async {
      if (!_hasTrackedView && mounted) {
        await _trackAdView();
      }
    });
  }

  /// **NEW: Track ad view (minimum 4 seconds visible)**
  Future<void> _trackAdView() async {
    if (_hasTrackedView || _viewStartTime == null) return;

    try {
      final viewDuration =
          DateTime.now().difference(_viewStartTime!).inMilliseconds / 1000.0;

      // Minimum view duration for ads (4 seconds)
      final minSeconds = AppConstants.adViewCountThreshold.inSeconds;
      if (viewDuration < minSeconds) {
        AppLogger.log(
            '⚠️ BannerAdWidget: View duration too short ($viewDuration s), not tracking (min: ${minSeconds}s)');
        return;
      }

      final userData = await _authService.getUserData();
      if (userData == null) {
        AppLogger.log(
            '⚠️ BannerAdWidget: No user data, skipping view tracking');
        return;
      }

      final videoId = widget.adData['videoId'] ?? '';
      final adId = widget.adData['_id'] ?? widget.adData['id'] ?? '';
      final userId = userData['id'] ?? '';

      if (videoId.isEmpty || adId.isEmpty) {
        AppLogger.log(
            '⚠️ BannerAdWidget: Missing videoId or adId, skipping view tracking');
        return;
      }

      // **NEW: Check if viewer is the creator**
      final creatorId = widget.adData['creatorId'];
      if (creatorId != null && creatorId.toString() == userId) {
        AppLogger.log('🚫 BannerAdWidget: Self-view prevented (video owner)');
        return;
      }

      await _adImpressionService.trackBannerAdView(
        videoId: videoId,
        adId: adId,
        userId: userId,
        viewDuration: viewDuration,
      );

      _hasTrackedView = true;
      AppLogger.log(
          '✅ BannerAdWidget: Ad view tracked (${viewDuration.toStringAsFixed(2)}s)');
    } catch (e) {
      AppLogger.log('❌ BannerAdWidget: Error tracking ad view: $e');
    }
  }

  // Ensure absolute URL (adds scheme or base URL if needed)
  String _ensureAbsoluteUrl(String url) {
    final u = url.trim();
    if (u.isEmpty) return u;
    if (u.startsWith('http://') || u.startsWith('https://')) return u;
    if (u.startsWith('//')) return 'https:$u';
    if (u.startsWith('/')) {
      // Use environment-configured baseUrl for relative backend paths
      return '${AppConfig.baseUrl}$u';
    }
    return 'https://$u';
  }

  @override
  Widget build(BuildContext context) {
    // Resolve image URL from multiple possible keys and ensure absolute URL
    final dynamic rawImage = widget.adData['imageUrl'] ??
        widget.adData['image'] ??
        widget.adData['bannerImageUrl'] ??
        widget.adData['mediaUrl'] ??
        widget.adData['cloudinaryUrl'] ??
        widget.adData['thumbnail'] ??
        '';
    final String imageUrl = _ensureAbsoluteUrl(
        rawImage is String ? rawImage : rawImage?.toString() ?? '');

    // **MODIFIED: Removed text-only fallback to maintain consistent layout**
    // The widget will now always render the standard image-based layout, 
    // ensuring elements like the 'Sponsored' label never disappear and 
    // the layout remains stable even if the image fails or is missing.

    // **NEW: Track ad impression when widget is built**
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onAdImpression?.call();
    });

    // **FIX: Isolate banner with RepaintBoundary to prevent compositing over video texture**
    return RepaintBoundary(
      child: Align(
        alignment: Alignment.topLeft,
        child: Container(
            width: double.infinity,
            height: 50, // **REDUCED from 60 for more video space**
            margin: const EdgeInsets.only(top: 1),
            // Solid surface so the image, title, CTA, and Sponsored tag read
            // as one contained card instead of loose elements over the video.
            decoration: BoxDecoration(
              color: AppColors.surfacePrimary,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Material(
              color: Colors.transparent,
              borderRadius:
                  BorderRadius.circular(12), // Match container rounded corners
              child: InkWell(
                borderRadius: BorderRadius.circular(
                    12), // Match container rounded corners
                onTap: () => _handleAdClick(context),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12), // Rounded corners
                  clipBehavior: Clip
                      .hardEdge, // **FIX: Hard-edge clipping for isolation**
                  child: Row(
                    children: [
                      // 40% space for banner image
                      Expanded(
                        flex: 2,
                        child: SizedBox(
                          height: 50, // **REDUCED from 60 to match container**
                          child: imageUrl.isNotEmpty
                              ? RepaintBoundary(
                                  // **FIX: Isolate image with RepaintBoundary**
                                  child: Image(
                                    image: _getCachedImageProvider(imageUrl),
                                    fit: BoxFit.cover,
                                    filterQuality: FilterQuality.low,
                                    gaplessPlayback:
                                        true, // **FIX: Gapless image to prevent flicker**
                                    errorBuilder: (context, error, stackTrace) {
                                      AppLogger.log(
                                          '❌ BannerAdWidget: Failed to load image: $imageUrl, Error: $error');
                                      return Container(
                                        color: Colors.white10,
                                        child: const Center(
                                          child: Icon(Icons.broken_image_outlined, color: Colors.white24, size: 16),
                                        ),
                                      );
                                    },
                                  ),
                                )
                              : Container(
                                  color: Colors.white10,
                                  width: double.infinity,
                                  height: double.infinity,
                                ),
                        ),
                      ),

                      // 60% space for title and CTA
                      Expanded(
                        flex: 3,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6), // more compact
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              // Ad title
                              Expanded(
                                child: Text(
                                  widget.adData['title'] ?? 'Sponsored Content',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10, // compact text
                                    fontWeight: FontWeight.w600,
                                    height: 1.1, // Reduced line height
                                  ),
                                  maxLines:
                                      3, // Increased from 2 to 3 to accommodate more text
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),

                              const SizedBox(height: 3),

                              // Call to action button
                              Row(
                                children: [
                                  GestureDetector(
                                    onTap: () => _handleAdClick(context),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: AppColors.primary,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: (() {
                                        String label = 'Learn More';
                                        final cta = widget.adData['callToAction'];
                                        if (cta is Map) {
                                          label = cta['label']?.toString() ?? 'Learn More';
                                        } else if (cta is String) {
                                          label = cta;
                                        }
                                        // **FIX: Replace 'Shop Now' with 'Learn More'**
                                        if (label.toUpperCase() == 'SHOP NOW') {
                                          label = 'Learn More';
                                        }

                                        return Text(
                                          label,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 10,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        );
                                      })(),
                                    ),
                                  ),
                                  const Spacer(),
                                  // Small "Sponsored" label
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 5,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(alpha: 0.3),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Text(
                                      'Sponsored',
                                      style: TextStyle(
                                        fontSize: 8,
                                        color: Colors.white,
                                        fontWeight: FontWeight.w500,
                                        letterSpacing: 0.3,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
    );
  }

  // **FIX: Get cached image provider for banner image to avoid rebuild flicker**
  ImageProvider _getCachedImageProvider(String url) {
    final cached = _imageProviderCache[url];
    if (cached != null) return cached;
    final provider = NetworkImage(url);
    _imageProviderCache[url] = provider;
    return provider;
  }



  /// Handle ad click directly (for Learn More button)
  void _handleAdClick(BuildContext context) async {
    try {
      final adId = widget.adData['_id'] ?? widget.adData['id'];

      // Resolve link from multiple keys and ensure absolute URL
      String link = (widget.adData['link'] ??
              widget.adData['url'] ??
              widget.adData['ctaUrl'] ??
              widget.adData['callToActionUrl'] ??
              widget.adData['targetUrl'] ??
              '')
          .toString();

      // Fallback: nested callToAction map from backend
      if (link.trim().isEmpty && widget.adData['callToAction'] is Map) {
        final nested = widget.adData['callToAction'] as Map;
        final candidate = (nested['url'] ?? nested['link'])?.toString();
        if (candidate != null && candidate.trim().isNotEmpty) {
          link = candidate.trim();
        }
      }

      link = _ensureAbsoluteUrl(link);

      // **UTM TRACKING IMPLEMENTATION**
      // Automatically append source and medium using central utility
      if (link.isNotEmpty) {
        link = UrlUtils.enrichUrl(
          link,
          source: 'vayug',
          medium: 'in_app_ad',
          campaign: 'vayug_ads',
        );
        AppLogger.log('🔗 BannerAdWidget: Resolved Link with UTM: $link');
      }

      // Directly open link if available (no confirmation dialog)
      if (link.isNotEmpty) {
        // Track click
        if (adId != null) {
          final activeAdsService = widget.adService ?? ActiveAdsService();
          await activeAdsService.trackClick(adId);
        }

        // Execute callback
        widget.onAdClick?.call();

        // **ROAS IMPROVEMENT: Use In-App Browser**
        if (context.mounted) {
          // Pause video while browser is open
          widget.onVideoPause?.call();
          showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            useSafeArea: true,
            backgroundColor: Colors.transparent,
            builder: (context) => SizedBox(
              height: MediaQuery.of(context).size.height * 0.9,
              child: InAppBrowser(
                url: link,
                title: widget.adData['title'] ?? 'Sponsored Content',
              ),
            ),
          ).then((_) {
            // Resume video when browser is closed
            widget.onVideoResume?.call();
          });
        }
      } else {
        // Show simple message to user
        if (context.mounted) {
          VayuSnackBar.showWarning(context, 'This ad has no link to open');
        }
      }
    } catch (e) {
      AppLogger.log('❌ Error handling banner ad click: $e');

      // Show error to user
      if (context.mounted) {
        VayuSnackBar.showError(context, 'Error opening link',
            duration: const Duration(seconds: 2));
      }
    }
  }
}

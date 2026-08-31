import 'package:flutter/material.dart';
import 'package:vayug/features/ads/presentation/widgets/banner_ad_widget.dart';
import 'package:vayug/features/ads/domain/i_ad_service.dart';
import 'package:vayug/shared/utils/app_logger.dart';

/// Banner Ad Section Widget
/// Supports only custom banner ads (AdMob removed)
class BannerAdSection extends StatefulWidget {
  final Map<String, dynamic>? adData;
  final VoidCallback? onClick;
  final Future<void> Function()? onImpression;
  final VoidCallback? onVideoPause;
  final VoidCallback? onVideoResume;
  final IAdService? adService;

  const BannerAdSection({
    Key? key,
    this.adData,
    this.onClick,
    this.onImpression,
    this.onVideoPause,
    this.onVideoResume,
    this.adService,
  }) : super(key: key);

  @override
  State<BannerAdSection> createState() => _BannerAdSectionState();
}

class _BannerAdSectionState extends State<BannerAdSection>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  bool _hasAnimatedIn = false;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOut,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCubic,
    ));
    // Agar pehle se adData hai toh seedha visible rakho, nahi toh slide+fade se dikhao
    if (widget.adData != null) {
      _hasAnimatedIn = true;
      _animController.value = 1.0;
    }
  }

  @override
  void didUpdateWidget(BannerAdSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.adData == null && widget.adData != null && !_hasAnimatedIn) {
      _hasAnimatedIn = true;
      _animController.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Widget _buildPlaceholder() {
    return SafeArea(
      child: Align(
        alignment: Alignment.topLeft,
        child: Container(
          width: double.infinity,
          height: 30,
          margin: const EdgeInsets.only(top: 20),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Center(
            child: Text(
              'Sponsored',
              style: TextStyle(color: Colors.white24, fontSize: 9),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAdContent(Map<String, dynamic> data) {
    AppLogger.log(
        '🔄 BannerAdSection: Showing custom backend ad: ${data['title'] ?? data['id']}');
    return BannerAdWidget(
      key: ValueKey('banner_${data['videoId'] ?? data['_id'] ?? data['id']}'),
      adData: data,
      onAdClick: () => widget.onClick?.call(),
      onAdImpression: () async => await widget.onImpression?.call(),
      onVideoPause: widget.onVideoPause,
      onVideoResume: widget.onVideoResume,
      adService: widget.adService,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.adData == null) {
      return _buildPlaceholder();
    }

    final data = widget.adData!;
    return AnimatedSize(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      child: SlideTransition(
        position: _slideAnimation,
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: _buildAdContent(data),
        ),
      ),
    );
  }
}

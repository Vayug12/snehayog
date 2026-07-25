import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'dart:math' as math;
import 'package:hugeicons/hugeicons.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vayug/features/onboarding/data/services/welcome_onboarding_service.dart';
import 'package:vayug/core/design/colors.dart';
import 'package:vayug/core/design/typography.dart';
import 'package:vayug/shared/widgets/app_button.dart';
import 'package:vayug/shared/widgets/vayu_snackbar.dart';
import 'package:vayug/features/onboarding/presentation/widgets/onboarding_video_player.dart';

class WelcomeOnboardingScreen extends StatefulWidget {
  final VoidCallback onGetStarted;

  const WelcomeOnboardingScreen({
    Key? key,
    required this.onGetStarted,
  }) : super(key: key);

  @override
  State<WelcomeOnboardingScreen> createState() =>
      _WelcomeOnboardingScreenState();
}

class _WelcomeOnboardingScreenState extends State<WelcomeOnboardingScreen> {
  
  // Guide State
  final PageController _pageController = PageController();
  int _currentPage = 0;
  // Show the "Get Started" button immediately so users aren't confused by a delay
  bool _isVideoProgressSufficient = true;

  final List<GuideStep> _steps = [
    GuideStep(
      title: 'No Interrupted Ads',
      description: 'Experience seamless streaming without any annoying ad interruptions.',
      icon: HugeIcons.strokeRoundedVideo01,
      color: AppColors.primary,
    ),
    GuideStep(
      title: 'Share & Earn',
      description: 'Bas 2 friends ke saath share karein aur full access ke saath earning shuru karein.',
      icon: HugeIcons.strokeRoundedShare01,
      color: AppColors.success,
    ),
    GuideStep(
      title: 'UPI ID Setup karein (Setup billing button)',
      description: 'Apne rewards paane ke liye Account tab mein jaakar apni setup billing button pe click karkeUPI ID add karein.',
      icon: HugeIcons.strokeRoundedWallet02,
      color: AppColors.warning,
    ),
    GuideStep(
      title: 'Rewards har mahine',
      description: 'Aapka sara reward har mahine ki 1st tarikh ko aapke account mein bhej diya jayega.',
      icon: HugeIcons.strokeRoundedCalendar01,
      color: AppColors.info,
    ),
    GuideStep(
      title: 'App kaise use karein?',
      description: 'Ye chhota sa video dekhein aur samjhein Vayu app ke saare features.',
      icon: HugeIcons.strokeRoundedPlay,
      color: AppColors.primary,
      isVideo: true,
      videoUrl: 'https://cdn.snehayog.site/guide_video.mp4',
    ),
  ];

  @override
  void initState() {
    super.initState();
    // Mark as shown immediately so it doesn't repeatedly show if the user closes the app
    WelcomeOnboardingService.markWelcomeOnboardingShown();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }


  Future<void> _launchURL(String url) async {
    final Uri uri = Uri.parse(url);
    try {
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        throw Exception('Could not launch $url');
      }
    } catch (e) {
      if (mounted) {
        VayuSnackBar.showError(context, 'Could not open link: $url');
      }
    }
  }

  void _onNext() {
    if (_currentPage < _steps.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
    } else {
      _completeOnboarding();
    }
  }

  Future<void> _completeOnboarding() async {
    await WelcomeOnboardingService.markWelcomeOnboardingShown();
    widget.onGetStarted();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                onPageChanged: (index) {
                  setState(() {
                    _currentPage = index;
                  });
                },
                itemCount: _steps.length,
                itemBuilder: (context, index) {
                  return _buildStep(_steps[index]);
                },
              ),
            ),

            // Navigation Area
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
              child: Column(
                children: [
                  // Dots Indicator (Hidden on video step to maximize space)
                  if (_currentPage != _steps.length - 1) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(
                        _steps.length,
                        (index) => AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          height: 8,
                          width: _currentPage == index ? 24 : 8,
                          decoration: BoxDecoration(
                            color: _currentPage == index
                                ? AppColors.primary
                                : AppColors.textSecondary.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),
                  ],

                  // Action Button
                  if (_currentPage != _steps.length - 1)
                    AppButton(
                      onPressed: _onNext,
                      label: 'Next',
                      variant: AppButtonVariant.primary,
                      isFullWidth: true,
                      size: AppButtonSize.large,
                    )
                  else
                    AnimatedOpacity(
                      duration: const Duration(milliseconds: 500),
                      opacity: _isVideoProgressSufficient ? 1.0 : 0.0,
                      child: IgnorePointer(
                        ignoring: !_isVideoProgressSufficient,
                        child: AppButton(
                          onPressed: _onNext,
                          label: 'Get Started',
                          variant: AppButtonVariant.primary,
                          isFullWidth: true,
                          size: AppButtonSize.large,
                        ),
                      ),
                    ),
                  const SizedBox(height: 24),

                  // Legal Disclosure (Only show on first or last page to keep it clean?)
                  // Showing on all for legal safety
                  RichText(
                    textAlign: TextAlign.center,
                    text: TextSpan(
                      style: AppTypography.labelSmall.copyWith(
                        color: AppColors.textSecondary,
                        height: 1.5,
                      ),
                      children: [
                        const TextSpan(text: 'By continuing, you agree to our '),
                        TextSpan(
                          text: 'Terms of Service',
                          style: const TextStyle(
                            color: AppColors.primary,
                            decoration: TextDecoration.underline,
                          ),
                          recognizer: TapGestureRecognizer()
                            ..onTap = () =>
                                _launchURL('https://snehayog.site/terms.html'),
                        ),
                        const TextSpan(text: ' and '),
                        TextSpan(
                          text: 'Privacy Policy',
                          style: const TextStyle(
                            color: AppColors.primary,
                            decoration: TextDecoration.underline,
                          ),
                          recognizer: TapGestureRecognizer()
                            ..onTap = () =>
                                _launchURL('https://snehayog.site/privacy.html'),
                        ),
                        const TextSpan(text: '.'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStep(GuideStep step) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: constraints.maxHeight,
            ),
            child: IntrinsicHeight(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(height: step.isVideo ? 0 : 24),
                  
                  // Visual Section
                  if (step.isVideo && step.videoUrl != null)
                    Padding(
                      padding: EdgeInsets.zero, // Edge-to-edge horizontally
                      child: OnboardingVideoPlayer(
                        videoUrl: step.videoUrl!,
                        // Reserve the step's bottom spacing. The player fits
                        // its width to this height while keeping the video's
                        // natural aspect ratio, including for portrait videos.
                        maxHeight: math.max(0.0, constraints.maxHeight - 24),
                        autoPlay: true,
                        onProgress: (progress) {
                          if (progress >= 0.2 && !_isVideoProgressSufficient) {
                            setState(() {
                              _isVideoProgressSufficient = true;
                            });
                          }
                        },
                      ),
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: step.color.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: step.color.withValues(alpha: 0.2),
                            width: 2,
                          ),
                        ),
                        child: HugeIcon(
                          icon: step.icon,
                          size: 64,
                          color: step.color,
                        ),
                      ),
                    ),

                  if (!step.isVideo) ...[
                    const SizedBox(height: 32),

                    // Text Content
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Column(
                        children: [
                          Text(
                            step.title,
                            textAlign: TextAlign.center,
                            style: AppTypography.headlineLarge.copyWith(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.bold,
                              letterSpacing: -0.5,
                              fontSize: 24,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            step.description,
                            textAlign: TextAlign.center,
                            style: AppTypography.bodyLarge.copyWith(
                              color: AppColors.textSecondary,
                              height: 1.5,
                              fontSize: 15,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class GuideStep {
  final String title;
  final String description;
  final dynamic icon;
  final Color color;
  final bool isVideo;
  final String? videoUrl;

  GuideStep({
    required this.title,
    required this.description,
    required this.icon,
    required this.color,
    this.isVideo = false,
    this.videoUrl,
  });
}

import 'package:flutter/material.dart';
import 'package:vayug/core/design/colors.dart';
import 'package:vayug/shared/utils/app_text.dart';
import 'package:vayug/shared/utils/responsive_helper.dart';
import 'package:vayug/shared/widgets/app_button.dart';

class ProfileSkeleton extends StatelessWidget {
  const ProfileSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: SingleChildScrollView(
        child: Column(
          children: [
            // Profile header skeleton
            RepaintBoundary(
              child: Container(
                padding: ResponsiveHelper.getAdaptivePadding(context),
                child: Column(
                  children: [
                    // Profile picture skeleton
                    Container(
                      width: ResponsiveHelper.isMobile(context) ? 100 : 150,
                      height: ResponsiveHelper.isMobile(context) ? 100 : 150,
                      decoration: BoxDecoration(
                        color:
                            AppColors.backgroundTertiary.withValues(alpha: 0.5),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Name skeleton
                    Container(
                      width: 200,
                      height: 32,
                      decoration: BoxDecoration(
                        color:
                            AppColors.backgroundTertiary.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Edit button skeleton
                    Container(
                      width: 120,
                      height: 40,
                      decoration: BoxDecoration(
                        color:
                            AppColors.backgroundTertiary.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Stats skeleton
            RepaintBoundary(
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 20),
                decoration: const BoxDecoration(
                  border: Border(
                    top: BorderSide(color: AppColors.borderPrimary),
                    bottom: BorderSide(color: AppColors.borderPrimary),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: List.generate(
                      3,
                      (index) => Column(
                            children: [
                              Container(
                                width: 60,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: AppColors.backgroundTertiary
                                      .withValues(alpha: 0.5),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Container(
                                width: 80,
                                height: 20,
                                decoration: BoxDecoration(
                                  color: AppColors.backgroundTertiary
                                      .withValues(alpha: 0.5),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                            ],
                          )),
                ),
              ),
            ),

            // Videos section skeleton
            RepaintBoundary(
              child: Padding(
                padding: ResponsiveHelper.getAdaptivePadding(context),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title skeleton
                    Container(
                      width: 150,
                      height: 24,
                      decoration: BoxDecoration(
                        color:
                            AppColors.backgroundTertiary.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Video grid skeleton
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        crossAxisSpacing: 1,
                        mainAxisSpacing: 1,
                        childAspectRatio: 0.5,
                      ),
                      itemCount: 6,
                      itemBuilder: (context, index) => Container(
                        decoration: BoxDecoration(
                          color: AppColors.backgroundTertiary
                              .withValues(alpha: 0.5),
                          borderRadius: BorderRadius.zero,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ProfileSignInView extends StatelessWidget {
  // Phone verification is not ready for release yet.
  static const bool _showPhoneVerification = false;

  final VoidCallback onGoogleSignIn;
  final VoidCallback? onPhoneSignIn;
  final bool sessionExpired;

  const ProfileSignInView({
    super.key,
    required this.onGoogleSignIn,
    this.onPhoneSignIn,
    this.sessionExpired = false,
  });

  @override
  Widget build(BuildContext context) {
    final showPhoneSignIn = _showPhoneVerification && onPhoneSignIn != null;

    return RepaintBoundary(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 300),
                child: Column(
                  children: [
                    if (showPhoneSignIn) ...[
                      AppButton(
                        onPressed: onPhoneSignIn!,
                        icon: const Icon(Icons.phone_android, size: 20),
                        label: 'Continue with phone number',
                        isFullWidth: true,
                        variant: AppButtonVariant.primary,
                        size: AppButtonSize.large,
                      ),
                      const SizedBox(height: 12),
                    ],
                    AppButton(
                      onPressed: onGoogleSignIn,
                      icon: Image.network(
                        'https://www.google.com/favicon.ico',
                        height: 20,
                      ),
                      label: sessionExpired
                          ? 'Sign In Again with Google'
                          : AppText.get('profile_sign_in_button'),
                      isFullWidth: true,
                      variant: !showPhoneSignIn
                          ? AppButtonVariant.primary
                          : AppButtonVariant.secondary,
                      size: AppButtonSize.large,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

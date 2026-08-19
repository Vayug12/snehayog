import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vayug/core/providers/auth_providers.dart';
import 'package:vayug/features/auth/presentation/controllers/auth_flow.dart';
import 'package:vayug/core/providers/navigation_providers.dart';
import 'package:vayug/features/onboarding/data/services/location_onboarding_service.dart';
import 'package:vayug/shared/utils/app_logger.dart';
import 'package:vayug/shared/widgets/app_button.dart';
import 'package:vayug/shared/widgets/vayu_logo.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  bool _isLocalLoading = false;

  /// The login screen's only sign-in path.
  ///
  /// Outcome messaging lives in [AuthFlow], so a timed-out backend exchange
  /// reports the failure instead of dropping the user on the home feed with a
  /// session that does not exist.
  Future<void> _signInAndContinue() async {
    ref.read(googleSignInProvider).clearError();

    final result = await AuthFlow.signIn(
      context,
      ref,
      onSuccess: () async {
        if (!mounted) return;
        // **OPTIMIZED: Parallel state refresh and pre-fetch**
        setState(() => _isLocalLoading = true);
        try {
          await ref
              .read(mainControllerProvider)
              .refreshAppStateAfterSwitch(ref);
        } finally {
          if (mounted) setState(() => _isLocalLoading = false);
        }
      },
    );

    if (!result.isSuccess || !mounted) return;

    final granted =
        await LocationOnboardingService.showLocationOnboarding(context);
    AppLogger.log(granted
        ? 'User granted location permission'
        : 'User denied location permission');

    if (!mounted) return;
    Navigator.pushReplacementNamed(context, '/home');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Consumer(
        builder: (context, ref, _) {
          final authController = ref.watch(googleSignInProvider);
          final bool showOverlay = authController.isLoading || _isLocalLoading;
          return Stack(
            children: [
              // Main Content
              Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                ),
                child: SafeArea(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 120,
                            height: 120,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.1),
                                  blurRadius: 20,
                                  offset: const Offset(0, 10),
                                ),
                              ],
                            ),
                            child: const Center(
                              child: VayuLogo(
                                fontSize: 32,
                              ),
                            ),
                          ),

                          const SizedBox(height: 32),

                          // Welcome Text
                          const Text(
                            'Welcome to Vayu',
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                            textAlign: TextAlign.center,
                          ),

                          Column(
                            children: [
                              const Text(
                                'Create • Video • Discover',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.grey,
                                  fontWeight: FontWeight.w500,
                                  letterSpacing: 0.5,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 8),
                                decoration: BoxDecoration(
                                  color: Colors.green.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: Colors.green.withValues(alpha: 0.3),
                                    width: 1,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.verified,
                                      color: Colors.green[300],
                                      size: 16,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Engagement Rewards',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.green[800],
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 48),

                          // Sign In Section
                          if (authController.error != null) ...[
                            Column(children: [
                              Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(20),
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [
                                        Colors.red[50]!,
                                        Colors.red[100]!,
                                      ],
                                    ),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: Colors.red[200]!,
                                      width: 1.5,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color:
                                            Colors.red.withValues(alpha: 0.1),
                                        blurRadius: 10,
                                        offset: const Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  child: Column(
                                    children: [
                                      // **Error Icon with Animation**
                                      Container(
                                        width: 60,
                                        height: 60,
                                        decoration: BoxDecoration(
                                          color: Colors.red[100],
                                          shape: BoxShape.circle,
                                        ),
                                        child: Icon(
                                          Icons.wifi_off_rounded,
                                          color: Colors.red[600],
                                          size: 30,
                                        ),
                                      ),

                                      const SizedBox(height: 16),
                                      Text(
                                        'Connection Failed',
                                        style: TextStyle(
                                          color: Colors.red[800],
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),

                                      const SizedBox(height: 8),

                                      // **Error Message**
                                      Text(
                                        authController.error!,
                                        style: TextStyle(
                                          color: Colors.red[700],
                                          fontSize: 14,
                                          height: 1.4,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),

                                      const SizedBox(height: 20),

                                      // **Horizontal Button Layout**
                                      Row(
                                        children: [
                                          // Skip Button
                                          Expanded(
                                            flex: 2,
                                            child: AppButton(
                                              isFullWidth: true,
                                              onPressed: () async {
                                                // Skip sign-in and go to home even during error
                                                // Clear error state and set skip flag
                                                authController.clearError();
                                                final prefs =
                                                    await SharedPreferences
                                                        .getInstance();
                                                await prefs.setBool(
                                                    'auth_skip_login', true);
                                                if (context.mounted) {
                                                  Navigator
                                                      .pushReplacementNamed(
                                                          context, '/home');
                                                }
                                              },
                                              icon: const Icon(
                                                Icons.arrow_forward_ios,
                                                size: 16,
                                              ),
                                              label: 'Skip',
                                              variant: AppButtonVariant.outline,
                                            ),
                                          ),

                                          const SizedBox(width: 12),

                                          // Retry Button
                                          Expanded(
                                            flex: 3,
                                            child: AppButton(
                                              isFullWidth: true,
                                              onPressed: _signInAndContinue,
                                              icon: const Icon(
                                                Icons.refresh_rounded,
                                                size: 18,
                                              ),
                                              label: 'Retry Connection',
                                              variant: AppButtonVariant.danger,
                                            ),
                                          ),
                                        ],
                                      ),

                                      const SizedBox(height: 12),

                                      // **Additional Help Text**
                                      Text(
                                        'Check your internet connection and try again',
                                        style: TextStyle(
                                          color: Colors.red[600],
                                          fontSize: 12,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ],
                                  ))
                            ])
                          ] else ...[
                            Column(
                              children: [
                                AppButton(
                                  isFullWidth: true,
                                  isDisabled: authController.isLoading,
                                  onPressed: () async {
                                    final prefs =
                                        await SharedPreferences.getInstance();
                                    await prefs.setBool(
                                        'auth_skip_login', true);
                                    Navigator.pushReplacementNamed(
                                        context, '/home');
                                  },
                                  icon: const Icon(
                                    Icons.arrow_forward_ios,
                                    size: 16,
                                  ),
                                  label: 'Skip',
                                  variant: AppButtonVariant.outline,
                                ),

                                const SizedBox(height: 12),

                                // Google Sign-In Button
                                AppButton(
                                  isFullWidth: true,
                                  isDisabled: authController.isLoading,
                                  onPressed: _signInAndContinue,
                                  icon: Image.network(
                                    'https://www.google.com/favicon.ico',
                                    height: 24,
                                    errorBuilder:
                                        (context, error, stackTrace) =>
                                            Image.asset(
                                      'assets/icons/google_logo.png',
                                      width: 24,
                                      height: 24,
                                    ),
                                  ),
                                  label: 'Sign in with Google',
                                  variant: AppButtonVariant.primary,
                                ),
                              ],
                            ),
                          ],

                          const SizedBox(height: 24),

                          // Help Text
                          const Text(
                            'By signing in, you agree to our Terms of Service and Privacy Policy',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // Loading Overlay
              if (showOverlay)
                Container(
                  color: Colors.black.withValues(alpha: 0.5),
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 32, vertical: 24),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 20,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: const Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 32,
                            height: 32,
                            child: CircularProgressIndicator(
                              strokeWidth: 3,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(Colors.green),
                            ),
                          ),
                          SizedBox(height: 16),
                          Text(
                            'Signing in...',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.black87,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vayug/core/design/colors.dart';
import 'package:vayug/core/design/radius.dart';
import 'package:vayug/core/design/typography.dart';
import 'package:vayug/core/providers/profile_providers.dart';
import 'package:vayug/core/providers/user_data_providers.dart';
import 'package:vayug/core/providers/auth_providers.dart';
import 'package:vayug/shared/widgets/vayu_snackbar.dart';

class FollowButtonWidget extends ConsumerStatefulWidget {
  final String uploaderId;
  final String uploaderName;
  final VoidCallback? onFollowChanged;
  final String? followText;
  final String? followingText;
  final Color? backgroundColor;
  final Color? followingBackgroundColor;
  final Color? textColor;
  final Color? followingTextColor;
  final Border? border;
  final Border? followingBorder;
  final EdgeInsetsGeometry? padding;
  final double? borderRadius;
  final double? fontSize;
  final FontWeight? fontWeight;

  const FollowButtonWidget({
    super.key,
    required this.uploaderId,
    required this.uploaderName,
    this.onFollowChanged,
    this.followText,
    this.followingText,
    this.backgroundColor,
    this.followingBackgroundColor,
    this.textColor,
    this.followingTextColor,
    this.border,
    this.followingBorder,
    this.padding,
    this.borderRadius,
    this.fontSize,
    this.fontWeight,
  });

  @override
  ConsumerState<FollowButtonWidget> createState() => _FollowButtonWidgetState();
}

class _FollowButtonWidgetState extends ConsumerState<FollowButtonWidget> {
  late final ValueNotifier<bool> _isOwnVideoNotifier;
  late final ValueNotifier<bool> _isInitializedNotifier;
  late final ValueNotifier<bool> _isLoadingNotifier;
  late final ValueNotifier<bool?> _optimisticIsFollowingNotifier;
  bool _hasCheckedOwnVideo = false;
  bool _isInitializing = false;

  @override
  void initState() {
    super.initState();
    _isOwnVideoNotifier = ValueNotifier<bool>(false);
    _isInitializedNotifier = ValueNotifier<bool>(false);
    _isLoadingNotifier = ValueNotifier<bool>(false);
    _optimisticIsFollowingNotifier = ValueNotifier<bool?>(null);

    _checkIfOwnVideo();
    _initializeFollowStatus();
  }

  @override
  void didUpdateWidget(covariant FollowButtonWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.uploaderId.trim() != widget.uploaderId.trim()) {
      _hasCheckedOwnVideo = false;
      _isInitializing = false;
      _isOwnVideoNotifier.value = false;
      _isInitializedNotifier.value = false;
      _isLoadingNotifier.value = false;
      _optimisticIsFollowingNotifier.value = null;
      _checkIfOwnVideo();
      _initializeFollowStatus();
    }
  }

  void _initializeFollowStatus() {
    if (_isInitializing) return;
    _isInitializing = true;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (mounted && _isInitializing) {
        try {
          final trimmedUploaderId = widget.uploaderId.trim();
          if (trimmedUploaderId.isEmpty || trimmedUploaderId == 'unknown') {
            _isInitializedNotifier.value = true;
            _isInitializing = false;
            return;
          }

          final userProviderRef = ref.read(userProvider);
          final authService = ref.read(authServiceProvider);

          final userData = await authService.getUserData();
          if (userData != null && userData['token'] != null) {
            await userProviderRef.checkFollowStatus(trimmedUploaderId);
          }

          _isInitializedNotifier.value = true;
          _isInitializing = false;
        } catch (e) {
          print('❌ FollowButtonWidget: Error initializing follow status: $e');
          _isInitializedNotifier.value = true;
          _isInitializing = false;
        }
      }
    });
  }

  void _checkIfOwnVideo() {
    if (_hasCheckedOwnVideo) return;
    _hasCheckedOwnVideo = true;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (mounted) {
        try {
          final authController = ref.read(googleSignInProvider);
          final authService = ref.read(authServiceProvider);

          String? currentUserId;

          if (authController.isSignedIn && authController.userData != null) {
            currentUserId = authController.userData!['googleId'] ??
                authController.userData!['id'] ??
                authController.userData!['_id'];
          }

          if (currentUserId == null) {
            final userData = await authService.getUserData();
            if (userData != null) {
              currentUserId =
                  userData['googleId'] ?? userData['id'] ?? userData['_id'];
            }
          }

          final trimmedUploaderId = widget.uploaderId.trim();

          if (currentUserId != null &&
              trimmedUploaderId.isNotEmpty &&
              trimmedUploaderId != 'unknown') {
            final isOwnVideo = currentUserId == trimmedUploaderId;
            _isOwnVideoNotifier.value = isOwnVideo;
          } else {
            _isOwnVideoNotifier.value = false;
          }
        } catch (e) {
          print('❌ FollowButtonWidget: Error checking if own video: $e');
          _isOwnVideoNotifier.value = false;
        }
      }
    });
  }

  Future<void> _handleFollowTap() async {
    if (_isOwnVideoNotifier.value || _isLoadingNotifier.value) {
      return;
    }

    final trimmedUploaderId = widget.uploaderId.trim();
    if (trimmedUploaderId.isEmpty || trimmedUploaderId == 'unknown') {
      _showSnackBar('Unable to follow right now. Please try again later.');
      return;
    }

    final userProviderRef = ref.read(userProvider);
    final currentlyFollowingFromProvider =
        userProviderRef.isFollowingUser(trimmedUploaderId);
    final currentlyFollowing =
        _optimisticIsFollowingNotifier.value ?? currentlyFollowingFromProvider;
    _optimisticIsFollowingNotifier.value = !currentlyFollowing;

    try {
      _isLoadingNotifier.value = true;
      print(
          '🎯 FollowButtonWidget: Attempting to toggle follow for ${widget.uploaderName} (ID: $trimmedUploaderId)');
      final authService = ref.read(authServiceProvider);
      final userData = await authService.getUserData();
      if (userData == null || userData['token'] == null) {
        _showSnackBar('Please sign in to follow users');
        return;
      }

      final success = await userProviderRef.toggleFollow(trimmedUploaderId);

      if (success) {
        final isFollowing = userProviderRef.isFollowingUser(trimmedUploaderId);
        _optimisticIsFollowingNotifier.value = isFollowing;
        _showSnackBar(isFollowing
            ? 'Subscribed to ${widget.uploaderName}'
            : 'Unsubscribed from ${widget.uploaderName}');

        try {
          final profileStateManager = ref.read(profileStateManagerProvider);
          profileStateManager.updateFollowerCount(
            trimmedUploaderId,
            increment: isFollowing,
          );
        } catch (e) {
          print('⚠️ FollowButtonWidget: Could not update ProfileStateManager: $e');
        }

        Future.delayed(const Duration(seconds: 1), () async {
          try {
            await userProviderRef.checkFollowStatus(trimmedUploaderId,
                forceRefresh: true);
          } catch (e) {}
        });

        Future.delayed(const Duration(seconds: 1), () async {
          try {
            await userProviderRef.refreshUserDataForId(trimmedUploaderId);
          } catch (e) {}
        });

        Future.delayed(const Duration(milliseconds: 500), () async {
          try {
            await userProviderRef.refreshUserData();
          } catch (e) {}
        });

        widget.onFollowChanged?.call();
      } else {
        _optimisticIsFollowingNotifier.value = currentlyFollowing;
        _showSnackBar('Failed to update follow status');
      }
    } catch (e) {
      _optimisticIsFollowingNotifier.value = currentlyFollowing;
      _showSnackBar('Error: $e');
    } finally {
      if (mounted) {
        _isLoadingNotifier.value = false;
      }
    }
  }

  void _showSnackBar(String message) {
    if (mounted) {
      VayuSnackBar.showInfo(context, message,
          duration: const Duration(seconds: 2));
    }
  }

  @override
  void dispose() {
    _isOwnVideoNotifier.dispose();
    _isInitializedNotifier.dispose();
    _isLoadingNotifier.dispose();
    _optimisticIsFollowingNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final userProviderRef = ref.watch(userProvider);
    final trimmedUploaderId = widget.uploaderId.trim();
    final isFollowingFromProvider =
        userProviderRef.isFollowingUser(trimmedUploaderId);

    return ValueListenableBuilder<bool>(
      valueListenable: _isOwnVideoNotifier,
      builder: (context, isOwnVideo, child) {
        if (isOwnVideo) {
          return const SizedBox.shrink();
        }

        return ValueListenableBuilder<bool>(
          valueListenable: _isInitializedNotifier,
          builder: (context, isInitialized, child) {
            if (!isInitialized) {
              return Container(
                width: 60,
                height: 24,
                decoration: BoxDecoration(
                  color: widget.backgroundColor ?? AppColors.backgroundSecondary.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(widget.borderRadius ?? AppRadius.pill),
                  border: widget.border,
                ),
                child: const Center(
                  child: SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.0,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  ),
                ),
              );
            }

            return ValueListenableBuilder<bool>(
                valueListenable: _isLoadingNotifier,
                builder: (context, isLoading, _) {
                  return ValueListenableBuilder<bool?>(
                      valueListenable: _optimisticIsFollowingNotifier,
                      builder: (context, optimisticIsFollowing, __) {
                        final effectiveIsFollowing =
                            optimisticIsFollowing ?? isFollowingFromProvider;
                        return GestureDetector(
                          onTap: isLoading ? null : _handleFollowTap,
                          behavior: HitTestBehavior.opaque,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: widget.padding ?? const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: effectiveIsFollowing
                                  ? (widget.followingBackgroundColor ?? AppColors.backgroundTertiary)
                                  : (widget.backgroundColor ?? AppColors.backgroundSecondary.withValues(alpha: 0.7)),
                              borderRadius:
                                  BorderRadius.circular(widget.borderRadius ?? AppRadius.pill),
                              border: effectiveIsFollowing ? widget.followingBorder : widget.border,
                            ),
                            child: isLoading
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor:
                                          AlwaysStoppedAnimation<Color>(
                                              Colors.white),
                                    ),
                                  )
                                : Text(
                                    effectiveIsFollowing
                                        ? (widget.followingText ??
                                            'Subscribed')
                                        : (widget.followText ?? 'Subscribe'),
                                    maxLines: 1,
                                    softWrap: false,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: effectiveIsFollowing
                                          ? (widget.followingTextColor ?? AppColors.white)
                                          : (widget.textColor ?? AppColors.white),
                                      fontSize: widget.fontSize ?? AppTypography.fontSizeSM,
                                      fontWeight: widget.fontWeight ?? AppTypography.weightBold,
                                    ),
                                  ),
                          ),
                        );
                      });
                });
          },
        );
      },
    );
  }
}

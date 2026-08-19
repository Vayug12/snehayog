import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:vayug/core/design/colors.dart';
import 'package:vayug/core/design/radius.dart';
import 'package:vayug/core/design/typography.dart';

class VayuBottomSheet extends StatelessWidget {
  final Widget child;
  final String? title;
  final IconData? icon;
  final Color? iconColor;
  final bool showHandle;
  final bool showCloseButton;
  final EdgeInsetsGeometry? padding;
  final List<Widget>? actions;
  final ScrollController? scrollController;
  final double? height;
  final double? maxWidth;
  final Widget Function(BuildContext context, ScrollController? scrollController)? builder;

  const VayuBottomSheet({
    super.key,
    required this.child,
    this.title,
    this.icon,
    this.iconColor,
    this.showHandle = true,
    this.showCloseButton = true,
    this.padding,
    this.actions,
    this.scrollController,
    this.height,
    this.maxWidth,
    this.builder,
  });

  /// Static helper to show the bottom sheet with consistent styling.
  static Future<T?> show<T>({
    required BuildContext context,
    Widget? child,
    Widget Function(BuildContext context, ScrollController? scrollController)? builder,
    String? title,
    IconData? icon,
    Color? iconColor,
    bool showHandle = true,
    bool showCloseButton = true,
    bool isScrollControlled = true,
    EdgeInsetsGeometry? padding,
    List<Widget>? actions,
    double initialChildSize = 0.5,
    double minChildSize = 0.3,
    double maxChildSize = 0.9,
    bool useDraggable = false,
    double? height,
    double? maxWidth,
  }) {
    assert(child != null || builder != null, 'Either child or builder must be provided');
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: isScrollControlled,
      backgroundColor: Colors.transparent,
      barrierColor: AppColors.overlayDark.withValues(alpha: 0.6),
      builder: (context) {
        if (useDraggable) {
          return DraggableScrollableSheet(
            initialChildSize: initialChildSize,
            minChildSize: minChildSize,
            maxChildSize: maxChildSize,
            expand: false,
            builder: (context, scrollController) => VayuBottomSheet(
              title: title,
              icon: icon,
              iconColor: iconColor,
              showHandle: showHandle,
              showCloseButton: showCloseButton,
              padding: padding,
              actions: actions,
              scrollController: scrollController,
              height: height,
              maxWidth: maxWidth,
              builder: builder,
              child: child ?? const SizedBox.shrink(),
            ),
          );
        }
        return VayuBottomSheet(
          title: title,
          icon: icon,
          iconColor: iconColor,
          showHandle: showHandle,
          showCloseButton: showCloseButton,
          padding: padding,
          actions: actions,
          height: height,
          maxWidth: maxWidth,
          builder: builder,
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    final effectiveMaxWidth = maxWidth ?? (isLandscape ? 420.0 : null);
    final isFloating = isLandscape && effectiveMaxWidth != null;

    Widget content = ClipRRect(
      borderRadius: isFloating 
        ? BorderRadius.circular(28) 
        : BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: Container(
          constraints: effectiveMaxWidth != null ? BoxConstraints(maxWidth: effectiveMaxWidth) : null,
          decoration: BoxDecoration(
            color: AppColors.backgroundPrimary.withValues(alpha: 0.75),
            borderRadius: isFloating 
              ? BorderRadius.circular(28)
              : BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.1),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.4),
                blurRadius: 24,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (showHandle)
                  Center(
                    child: Container(
                      width: 32,
                      height: 4,
                      margin: EdgeInsets.symmetric(vertical: isLandscape ? 6 : 10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(100),
                      ),
                    ),
                  ),
                
                // Header. A titleless sheet still gets one when it has actions,
                // so a corner control has somewhere to sit.
                if (title != null || (actions?.isNotEmpty ?? false))
                  Padding(
                    padding: EdgeInsets.fromLTRB(20, showHandle ? 0 : (isLandscape ? 8 : 20), 12, isLandscape ? 6 : 12),
                    child: Row(
                      children: [
                        if (title != null) ...[
                          if (icon != null) ...[
                            Icon(icon, color: iconColor ?? AppColors.primary, size: isLandscape ? 18 : 22),
                            const SizedBox(width: 12),
                          ],
                          Expanded(
                            child: Text(
                              title!,
                              style: AppTypography.titleMedium.copyWith(
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.bold,
                                letterSpacing: -0.5,
                                fontSize: isLandscape ? 14.0 : null,
                              ),
                            ),
                          ),
                        ] else
                          const Spacer(),
                        if (actions != null) ...actions!,
                        if (showCloseButton)
                          IconButton(
                            icon: const Icon(Icons.close, color: AppColors.textTertiary, size: 18),
                            onPressed: () => Navigator.pop(context),
                            visualDensity: VisualDensity.compact,
                          ),
                      ],
                    ),
                  ),
                
                // Main Content
                Flexible(
                  child: builder != null 
                    ? builder!(context, scrollController)
                    : SingleChildScrollView(
                      controller: scrollController,
                      physics: const BouncingScrollPhysics(),
                      padding: padding ?? const EdgeInsets.fromLTRB(20, 0, 20, 20),
                      child: child,
                    ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (isFloating) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Material(
            color: Colors.transparent,
            child: content,
          ),
        ),
      );
    }

    return Material(
      color: Colors.transparent,
      child: content,
    );
  }
}

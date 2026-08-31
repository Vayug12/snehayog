import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:vayug/core/design/spacing.dart';

/// Shared visual geometry for the Vayu player chrome.
///
/// Playback and interaction behavior deliberately stay outside this class. It
/// only keeps the top, centre, bottom and quiz rails on one spacing system.
class VayuPlayerLayout {
  VayuPlayerLayout._();

  static const double portraitUtilityControlSize = 36;
  static const double landscapeUtilityControlSize = 40;
  static const double portraitUtilityIconSize = 20;
  static const double landscapeUtilityIconSize = 20;

  static const double landscapeTransportControlSize = 44;
  static const double landscapeTransportIconSize = 26;
  static const double portraitPrimaryControlSize = 48;
  static const double landscapePrimaryControlSize = 64;
  static const double portraitPrimaryIconSize = 30;
  static const double landscapePrimaryIconSize = 40;

  /// Keeps the painted control surface dense without changing its outer
  /// layout box or tap position.
  static const double compactIconPadding = 2;

  static double compactSurfaceSize(double iconSize) =>
      iconSize + (compactIconPadding * 2);

  static double utilityControlSize({required bool isPortrait}) =>
      isPortrait ? portraitUtilityControlSize : landscapeUtilityControlSize;

  static double utilityIconSize({required bool isPortrait}) =>
      isPortrait ? portraitUtilityIconSize : landscapeUtilityIconSize;

  static double primaryControlSize({required bool isPortrait}) =>
      isPortrait ? portraitPrimaryControlSize : landscapePrimaryControlSize;

  static double primaryIconSize({required bool isPortrait}) =>
      isPortrait ? portraitPrimaryIconSize : landscapePrimaryIconSize;

  static double get transportGap => AppSpacing.spacing6;

  static double get transportRailWidth =>
      (landscapeTransportControlSize * 2) +
      landscapePrimaryControlSize +
      (transportGap * 2);

  static EdgeInsets playerInsets(
    BuildContext context, {
    required bool isFullScreen,
  }) {
    final safePadding = MediaQuery.viewPaddingOf(context);
    final baseInset = isFullScreen ? AppSpacing.spacing6 : AppSpacing.spacing4;

    return EdgeInsets.fromLTRB(
      safePadding.left + baseInset,
      safePadding.top + baseInset,
      safePadding.right + baseInset,
      safePadding.bottom + baseInset,
    );
  }

  /// Width of the fullscreen landscape quiz lane. Its right edge always stops
  /// before the centred transport rail, leaving one major spacing unit between
  /// the two regions.
  static double landscapeQuizWidth({
    required double viewportWidth,
    required double leftInset,
  }) {
    final transportLeft = (viewportWidth - transportRailWidth) / 2;
    final availableWidth = transportLeft - leftInset - AppSpacing.spacing6;
    return math.max(0, math.min(400, availableWidth));
  }
}

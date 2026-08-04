import 'package:flutter/widgets.dart';

/// Declares which bottom-navigation tab a subtree lives in.
///
/// A tab is not a route, so a screen pushed from a tab has no way to discover
/// that its tab went to the background — it keeps `isCurrent == true` inside its
/// own nested `Navigator`. Every screen used to guess its tab instead, and a
/// wrong guess let a hidden player keep claiming playback.
///
/// Installed once per tab, above that tab's `Navigator`, so every route pushed
/// at any depth resolves the same answer. A subtree with no [TabScope] (a route
/// on the root navigator, a test) reports `null`, which media treats as
/// "not tab-bound" rather than "tab 0".
class TabScope extends InheritedWidget {
  const TabScope({
    super.key,
    required this.index,
    required super.child,
  });

  final int index;

  static int? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<TabScope>()?.index;

  @override
  bool updateShouldNotify(TabScope oldWidget) => oldWidget.index != index;
}

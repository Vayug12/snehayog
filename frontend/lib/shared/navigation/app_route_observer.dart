import 'package:flutter/material.dart';

/// Shared route lifecycle source for features that own media playback.
final RouteObserver<ModalRoute<dynamic>> appRouteObserver =
    RouteObserver<ModalRoute<dynamic>>();

/// Feeds a nested `Navigator`'s route events into [appRouteObserver].
///
/// Flutter asserts that a `NavigatorObserver` belongs to exactly one
/// `Navigator`, and [appRouteObserver] is already installed on the root one.
/// Bottom-navigation tabs each run their own nested `Navigator`, so without a
/// forwarder a feed inside a tab never learns that a profile (or any other
/// route) was pushed over it, and `didPushNext`/`didPopNext` stay silent.
class AppRouteObserverForwarder extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      appRouteObserver.didPush(route, previousRoute);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      appRouteObserver.didPop(route, previousRoute);

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      appRouteObserver.didRemove(route, previousRoute);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      appRouteObserver.didReplace(newRoute: newRoute, oldRoute: oldRoute);
}

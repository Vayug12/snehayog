import 'package:flutter/foundation.dart';
import 'package:vayug/features/profile/core/data/services/user_service.dart';
import 'package:vayug/shared/utils/app_logger.dart';

/// Owns the "new subscribers" red dot shown on the profile Subscribers stat.
///
/// The unseen watermark lives on the server (`user.subscribersSeenAt`), so the
/// dot survives reinstalls and stays consistent across devices. This manager
/// only mirrors that state and keeps the UI from hammering the endpoint.
class SubscribersBadgeManager extends ChangeNotifier {
  SubscribersBadgeManager({UserService? userService})
      : _userService = userService ?? UserService();

  /// The profile screen asks for a refresh from several places (init, tab
  /// select, pull-to-refresh). Repeats inside this window reuse the last value.
  static const Duration _minRefreshInterval = Duration(seconds: 45);

  final UserService _userService;

  int _newCount = 0;
  DateTime? _lastFetchedAt;
  Future<void>? _inFlight;
  bool _isDisposed = false;

  int get newCount => _newCount;

  bool get hasNewSubscribers => _newCount > 0;

  /// Pulls the unseen count. Concurrent calls share one request, and calls
  /// inside the refresh window are no-ops unless [force] is set.
  Future<void> refresh({bool force = false}) {
    final inFlight = _inFlight;
    if (inFlight != null) return inFlight;

    final lastFetchedAt = _lastFetchedAt;
    if (!force &&
        lastFetchedAt != null &&
        DateTime.now().difference(lastFetchedAt) < _minRefreshInterval) {
      return Future<void>.value();
    }

    final request = _fetchCount();
    _inFlight = request;
    return request;
  }

  Future<void> _fetchCount() async {
    try {
      final count = await _userService.getNewSubscribersCount();
      _lastFetchedAt = DateTime.now();
      _setCount(count);
    } catch (e) {
      // Badge is cosmetic: a failure keeps the last known state instead of
      // surfacing an error on the profile.
      AppLogger.log('⚠️ SubscribersBadgeManager: Refresh failed: $e');
    } finally {
      _inFlight = null;
    }
  }

  /// Clears the dot right away, then persists the watermark. [upTo] should be
  /// the newest subscription the creator actually saw, so someone subscribing
  /// mid-request stays unseen. Restores the dot if the write fails.
  Future<void> markSeen({DateTime? upTo}) async {
    final previousCount = _newCount;
    _setCount(0);

    try {
      final remaining = await _userService.markSubscribersSeen(seenAt: upTo);
      _lastFetchedAt = DateTime.now();
      _setCount(remaining);
    } catch (e) {
      AppLogger.log('⚠️ SubscribersBadgeManager: Mark seen failed: $e');
      _setCount(previousCount);
    }
  }

  /// Drops badge state on logout/account switch so counts never leak users.
  void reset() {
    _lastFetchedAt = null;
    _setCount(0);
  }

  void _setCount(int count) {
    final safeCount = count < 0 ? 0 : count;
    if (_isDisposed || safeCount == _newCount) return;
    _newCount = safeCount;
    notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }
}

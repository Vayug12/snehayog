import 'package:in_app_review/in_app_review.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vayug/shared/utils/app_logger.dart';

/// Handles the official Google Play / App Store in-app review prompt.
///
/// Google does not tell apps whether the dialog was actually displayed or
/// whether the user submitted a review. We therefore persist that the review
/// prompt was requested, so each install asks at most once.
class InAppReviewService {
  InAppReviewService._();

  static final InAppReviewService instance = InAppReviewService._();

  static const String _launchCountKey = 'in_app_review_launch_count';
  static const String _requestedKey = 'in_app_review_requested_once';
  static const int _minimumLaunchCount = 2;

  bool _isHandlingReview = false;

  Future<bool> shouldRequestReview() async {
    final prefs = await SharedPreferences.getInstance();
    final alreadyRequested = prefs.getBool(_requestedKey) ?? false;
    final launchCount = prefs.getInt(_launchCountKey) ?? 0;

    return !alreadyRequested && launchCount >= _minimumLaunchCount;
  }

  /// Counts a cold app open. Call once from the app root after startup.
  Future<void> recordAppLaunch() async {
    final prefs = await SharedPreferences.getInstance();

    if (prefs.getBool(_requestedKey) ?? false) return;

    final currentCount = prefs.getInt(_launchCountKey) ?? 0;
    await prefs.setInt(_launchCountKey, currentCount + 1);
  }

  /// Requests the native in-app review prompt once, if Play/App Store allows it.
  Future<void> requestReviewIfEligible() async {
    if (_isHandlingReview || !await shouldRequestReview()) return;

    _isHandlingReview = true;

    try {
      final inAppReview = InAppReview.instance;
      final isAvailable = await inAppReview.isAvailable();

      if (!isAvailable) {
        AppLogger.log('In-app review is not available on this device.');
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_requestedKey, true);
      await inAppReview.requestReview();
      AppLogger.log('In-app review prompt requested.');
    } catch (e, stackTrace) {
      AppLogger.error('Failed to request in-app review', e, stackTrace);
    } finally {
      _isHandlingReview = false;
    }
  }
}

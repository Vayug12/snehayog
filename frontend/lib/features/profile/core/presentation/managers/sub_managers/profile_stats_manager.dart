import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:vayug/core/interfaces/i_auth_service.dart';
import 'package:vayug/core/interfaces/i_notification_service.dart';
import 'package:vayug/features/ads/data/services/ad_service.dart';
import 'package:vayug/features/video/core/data/models/video_model.dart';
import 'package:vayug/shared/utils/app_logger.dart';

class ProfileStatsManager extends ChangeNotifier {
  final INotificationService _notificationService;
  final IAuthService _authService;
  final AdService _adService = AdService();

  ProfileStatsManager({
    required INotificationService notificationService,
    required IAuthService authService,
  })  : _notificationService = notificationService,
        _authService = authService;

  // State
  double _cachedEarnings = 0.0;
  bool _isEarningsLoading = false;
  List<dynamic> _creatorAlertStats = [];
  int _remainingAlerts = 2;
  bool _isAlertSending = false;
  bool _isAlertStatsLoading = false;

  bool _isDisposed = false;

  // Getters
  double get cachedEarnings => _cachedEarnings;
  bool get isEarningsLoading => _isEarningsLoading;
  List<dynamic> get creatorAlertStats => _creatorAlertStats;
  int get remainingAlerts => _remainingAlerts;
  bool get isAlertSending => _isAlertSending;
  bool get isAlertStatsLoading => _isAlertStatsLoading;

  void notifyListenersSafe() {
    if (_isDisposed) return;
    final scheduler = WidgetsBinding.instance;
    if (scheduler.schedulerPhase == SchedulerPhase.persistentCallbacks) {
      scheduler.addPostFrameCallback((_) {
        if (!_isDisposed) notifyListeners();
      });
    } else {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }

  Future<void> loadEarnings(List<VideoModel> userVideos, {bool forceRefresh = false, bool silent = false, Map<String, dynamic>? userData}) async {
    try {
      if (!silent) {
        _isEarningsLoading = true;
        notifyListenersSafe();
      }

      if (userVideos.isEmpty) {
        _cachedEarnings = 0.0;
        _isEarningsLoading = false;
        notifyListenersSafe();
        return;
      }

      final loggedInUser = await _authService.getUserData();
      bool isMyProfile = false;
      if (userData != null && loggedInUser != null) {
        final profileId = userData['googleId']?.toString() ?? userData['id']?.toString();
        final myId = loggedInUser['googleId']?.toString() ?? loggedInUser['id']?.toString();
        isMyProfile = (profileId != null && myId != null && profileId == myId);
      }

      double earnings = 0.0;
      bool usedBackend = false;

      if (isMyProfile) {
        try {
          final summary = await _adService.getCreatorRevenueSummary(forceRefresh: forceRefresh);
          if (summary.containsKey('thisMonth')) {
            final thisMonth = summary['thisMonth'];
            if (thisMonth is num && thisMonth >= 0) {
              earnings = thisMonth.toDouble();
              usedBackend = true;
            }
          }
        } catch (e) {
          AppLogger.log('⚠️ ProfileStatsManager: AdService fetch failed: $e');
        }
      }

      if (!usedBackend) {
        // Fallback to uploader.earnings or aggregation
        final uploaderEarnings = userVideos.first.uploader.earnings;
        if (uploaderEarnings != null && uploaderEarnings > 0) {
          earnings = uploaderEarnings;
        } else {
          double aggregated = 0.0;
          for (var video in userVideos) {
            aggregated += video.earnings;
          }
          earnings = aggregated;
        }
      }

      _cachedEarnings = earnings;
    } finally {
      _isEarningsLoading = false;
      notifyListenersSafe();
    }
  }

  Future<void> fetchCreatorAlertStats() async {
    _isAlertStatsLoading = true;
    notifyListenersSafe();
    try {
      final data = await _notificationService.getCreatorAlertStats();
      _creatorAlertStats = data['stats'] ?? [];
      _remainingAlerts = data['remainingToday'] ?? 2;
    } catch (e) {
      AppLogger.log('⚠️ ProfileStatsManager: Error fetching creator stats: $e');
    } finally {
      _isAlertStatsLoading = false;
      notifyListenersSafe();
    }
  }

  Future<void> sendCreatorAlert({required String message, String? title, String? targetUrl, List<String>? recipientIds}) async {
    _isAlertSending = true;
    notifyListenersSafe();
    try {
      await _notificationService.sendCreatorAlert(
        message: message,
        title: title,
        targetUrl: targetUrl,
        recipientIds: recipientIds,
      );
      await fetchCreatorAlertStats();
    } finally {
      _isAlertSending = false;
      notifyListenersSafe();
    }
  }
  
  void clearData() {
    _cachedEarnings = 0.0;
    _isEarningsLoading = false;
    _creatorAlertStats = [];
    _remainingAlerts = 2;
    _isAlertSending = false;
    _isAlertStatsLoading = false;
  }
}

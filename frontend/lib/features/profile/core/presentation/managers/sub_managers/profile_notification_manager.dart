import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:vayug/core/interfaces/i_notification_service.dart';
import 'package:vayug/core/interfaces/i_notice_service.dart';
import 'package:vayug/features/profile/notices/domain/models/notice_model.dart';
import 'package:vayug/shared/utils/app_logger.dart';

class ProfileNotificationManager extends ChangeNotifier {
  final INoticeService _noticeService;
  final INotificationService _notificationService;

  ProfileNotificationManager({
    required INoticeService noticeService,
    required INotificationService notificationService,
  })  : _noticeService = noticeService,
        _notificationService = notificationService;

  NoticeModel? _activeNotice;
  bool _isNoticeLoading = false;
  Timer? _noticeTimer;
  bool _isDisposed = false;

  NoticeModel? get activeNotice => _activeNotice;
  bool get isNoticeLoading => _isNoticeLoading;

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
    _noticeTimer?.cancel();
    super.dispose();
  }

  Future<void> fetchActiveNotice() async {
    _isNoticeLoading = true;
    notifyListenersSafe();
    try {
      _activeNotice = await _noticeService.getActiveNotice();
      if (_activeNotice != null) _scheduleNoticeRemoval();
    } catch (e) {
      AppLogger.log('⚠️ ProfileNotificationManager: Error fetching active notice: $e');
    } finally {
      _isNoticeLoading = false;
      notifyListenersSafe();
    }
  }

  void _scheduleNoticeRemoval() {
    _noticeTimer?.cancel();
    if (_activeNotice?.firstSeenAt == null) return;
    
    final expiresAt = _activeNotice!.firstSeenAt!.add(const Duration(hours: 24));
    final duration = expiresAt.difference(DateTime.now());
    
    if (duration.isNegative) {
      _activeNotice = null;
      notifyListenersSafe();
    } else {
      _noticeTimer = Timer(duration, () {
        _activeNotice = null;
        notifyListenersSafe();
      });
    }
  }

  Future<void> updateNotificationPreference({
    bool? globalEnabled,
    String? disabledCreatorId,
    String? enabledCreatorId,
    Map<String, dynamic>? userData,
  }) async {
    try {
      // Optimistic update should be handled by caller or passed back
      await _notificationService.updatePreferences(
        globalEnabled: globalEnabled,
        disabledCreatorId: disabledCreatorId,
        enabledCreatorId: enabledCreatorId,
      );
    } catch (e) {
      AppLogger.log('❌ ProfileNotificationManager: Failed to update preferences: $e');
      rethrow;
    }
  }
  
  Future<void> markNoticeAsSeen(String noticeId) async {
    await _noticeService.markAsSeen(noticeId);
    if (_activeNotice?.id == noticeId) {
      _activeNotice = null;
      _noticeTimer?.cancel();
      notifyListenersSafe();
    }
  }

  void clearData() {
    _activeNotice = null;
    _isNoticeLoading = false;
    _noticeTimer?.cancel();
    _noticeTimer = null;
  }
}

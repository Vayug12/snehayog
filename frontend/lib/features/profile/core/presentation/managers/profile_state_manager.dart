import 'dart:async';
import 'package:flutter/material.dart';
import 'package:vayug/features/profile/core/presentation/managers/sub_managers/profile_info_manager.dart';
import 'package:vayug/features/profile/core/presentation/managers/sub_managers/profile_video_manager.dart';
import 'package:vayug/features/profile/core/presentation/managers/sub_managers/profile_stats_manager.dart';
import 'package:vayug/features/profile/core/presentation/managers/sub_managers/profile_notification_manager.dart';
import 'package:vayug/core/interfaces/i_auth_service.dart';
import 'package:vayug/core/interfaces/i_video_service.dart';
import 'package:vayug/core/interfaces/i_user_service.dart';
import 'package:vayug/core/interfaces/i_notification_service.dart';
import 'package:vayug/core/interfaces/i_notice_service.dart';
import 'package:vayug/core/interfaces/i_payment_setup_service.dart';
import 'package:vayug/features/video/core/data/models/video_model.dart';
import 'package:vayug/features/profile/notices/domain/models/notice_model.dart';
import 'package:vayug/shared/managers/smart_cache_manager.dart';

class ProfileStateManager extends ChangeNotifier {
  final ProfileInfoManager infoManager;
  final ProfileVideoManager videoManager;
  final ProfileStatsManager statsManager;
  final ProfileNotificationManager notificationManager;

  final IAuthService _authService;

  ProfileStateManager({
    required IVideoService videoService,
    required IAuthService authService,
    required IUserService userService,
    required IPaymentSetupService paymentSetupService,
    required INoticeService noticeService,
    required INotificationService notificationService,
  })  : _authService = authService,
        infoManager = ProfileInfoManager(
          userService: userService,
          authService: authService,
          smartCacheManager: SmartCacheManager(),
        ),
        videoManager = ProfileVideoManager(
          videoService: videoService,
          authService: authService,
          smartCacheManager: SmartCacheManager(),
        ),
        statsManager = ProfileStatsManager(
          notificationService: notificationService,
          authService: authService,
        ),
        notificationManager = ProfileNotificationManager(
          noticeService: noticeService,
          notificationService: notificationService,
        ) {
    // Synchronize updates
    infoManager.addListener(notifyListeners);
    videoManager.addListener(notifyListeners);
    statsManager.addListener(notifyListeners);
    notificationManager.addListener(notifyListeners);
  }


  // --- Facade Getters ---
  Map<String, dynamic>? get userData => infoManager.userData;
  bool get isProfileLoading => infoManager.isProfileLoading;
  bool get isLoading => isProfileLoading; // Proxy for isLoading
  bool get isEditing => infoManager.isEditing;
  bool get isPhotoLoading => infoManager.isPhotoLoading;
  String? get error => infoManager.error ?? videoManager.error;

  TextEditingController get nameController => infoManager.nameController;
  TextEditingController get websiteController => infoManager.websiteController;

  bool get isDataPartial {
    final data = userData;
    if (data == null) return true;
    if (data['isFallback'] == true) return true;
    final followers = data['followersCount'] ?? data['followers'];
    return followers == null;
  }

  List<VideoModel> get userVideos => videoManager.userVideos;
  bool get isVideosLoading => videoManager.isVideosLoading;
  int get totalVideoCount => videoManager.totalVideoCount;
  bool get hasMoreVideos => videoManager.hasMoreVideos;
  bool get isFetchingMore => videoManager.isFetchingMore;
  Set<String> get selectedVideoIds => videoManager.selectedVideoIds;
  bool get needsVideoRefresh => videoManager.needsVideoRefresh;

  bool get hasUpiId {
    final data = userData;
    if (data == null) return false;
    final paymentDetails = data['paymentDetails'];
    if (paymentDetails == null) return false;
    final upiId = paymentDetails['upiId'];
    return upiId != null && upiId.toString().trim().isNotEmpty;
  }

  String get upiId {
    final data = userData;
    if (data == null) return '';
    final paymentDetails = data['paymentDetails'];
    if (paymentDetails == null) return '';
    return paymentDetails['upiId']?.toString().trim() ?? '';
  }

  String get maskedUpiId {
    final upi = upiId;
    if (upi.isEmpty) return '';
    final parts = upi.split('@');
    if (parts.length < 2) {
      if (upi.length > 4) {
        return '${upi.substring(0, 4)}•••';
      }
      return '$upi•••';
    }
    final handle = parts[0];
    return '$handle@•••';
  }

  double get cachedEarnings => statsManager.cachedEarnings;
  bool get isEarningsLoading => statsManager.isEarningsLoading;
  List<dynamic> get creatorAlertStats => statsManager.creatorAlertStats;
  int get remainingAlerts => statsManager.remainingAlerts;
  bool get isAlertSending => statsManager.isAlertSending;

  NoticeModel? get activeNotice => notificationManager.activeNotice;
  bool get isNoticeLoading => notificationManager.isNoticeLoading;

  bool get isSignedIn => _authService.currentUserId != null;
  bool get isOwner => infoManager.requestedUserId == null || infoManager.requestedUserId == _authService.currentUserId;

  Map<String, dynamic>? getUserData() => infoManager.userData;

  bool get isGlobalAlertsEnabled => userData?['notificationPreferences']?['globalCreatorAlerts'] ?? true;
  List<String> get disabledCreatorIds => List<String>.from(userData?['notificationPreferences']?['disabledCreators'] ?? []);

  // --- Facade Methods ---
  Future<void> loadUserData(String? userId, {bool forceRefresh = false, bool silent = false}) async {
    await infoManager.loadUserData(userId, forceRefresh: forceRefresh, silent: silent);
    
    // Always start loading videos, notices, etc. in parallel
    unawaited(videoManager.loadUserVideos(userId, forceRefresh: forceRefresh, silent: silent).then((_) {
      statsManager.loadEarnings(videoManager.userVideos, forceRefresh: forceRefresh, silent: silent, userData: infoManager.userData);
    }));
    
    if (isOwner && isSignedIn) {
      notificationManager.fetchActiveNotice();
      statsManager.fetchCreatorAlertStats();
    }
  }

  Future<void> refreshData() => loadUserData(infoManager.requestedUserId, forceRefresh: true);

  Future<void> loadUserVideos(String? userId, {bool forceRefresh = false, bool silent = false, int page = 1}) =>
      videoManager.loadUserVideos(userId, forceRefresh: forceRefresh, silent: silent, page: page);

  Future<void> loadMoreVideos() => videoManager.loadUserVideos(infoManager.requestedUserId, page: videoManager.totalVideoCount ~/ 1000 + 1);

  Future<void> refreshVideosOnly([String? userId]) => videoManager.loadUserVideos(userId ?? infoManager.requestedUserId, forceRefresh: true);

  Future<void> loadAllVideosInBackground({String? userId}) => videoManager.loadUserVideos(userId ?? infoManager.requestedUserId, silent: true);

  Future<void> updateProfile({required String name, String? profilePic, String? websiteUrl}) =>
      infoManager.updateProfile(name: name, profilePic: profilePic, websiteUrl: websiteUrl);

  Future<void> saveProfile() => updateProfile(
    name: nameController.text,
    websiteUrl: websiteController.text,
  );

  Future<void> updateProfilePhoto(String photoPath) => infoManager.updateProfilePhoto(photoPath);

  void setEditing(bool editing) => infoManager.isEditing = editing;

  void cancelEditing() {
    infoManager.isEditing = false;
    nameController.text = userData?['name']?.toString() ?? '';
    websiteController.text = userData?['websiteUrl']?.toString() ?? '';
  }

  void updateFollowerCount(String userId, {required bool increment}) =>
      infoManager.updateFollowerCount(userId, increment: increment);

  void addVideoOptimistically(Map<String, dynamic> videoData) =>
      videoManager.addVideoOptimistically(videoData);

  void addNewVideo(VideoModel video) => videoManager.addNewVideo(video);

  void removeVideo(String videoId) => videoManager.removeVideo(videoId);

  bool get isSelecting => videoManager.isSelecting;
  void toggleSelectionMode() => videoManager.toggleSelectionMode();
  void enterSelectionMode() => videoManager.enterSelectionMode();
  void exitSelectionMode() => videoManager.exitSelectionMode();
  void toggleVideoSelection(String videoId) => videoManager.toggleVideoSelection(videoId);

  Future<bool> deleteSingleVideo(String videoId) => videoManager.deleteSingleVideo(videoId);
  Future<void> deleteSelectedVideos() => videoManager.deleteSelectedVideos();

  Future<void> updateNotificationPreference({bool? globalEnabled, String? disabledCreatorId, String? enabledCreatorId}) =>
      notificationManager.updateNotificationPreference(
        globalEnabled: globalEnabled,
        disabledCreatorId: disabledCreatorId,
        enabledCreatorId: enabledCreatorId,
      );

  Future<void> markNoticeAsSeen(String noticeId) => notificationManager.markNoticeAsSeen(noticeId);

  Future<void> fetchCreatorAlertStats() => statsManager.fetchCreatorAlertStats();

  Future<void> sendCreatorAlert({required String message, String? title, String? targetUrl, List<String>? recipientIds}) =>
      statsManager.sendCreatorAlert(message: message, title: title, targetUrl: targetUrl, recipientIds: recipientIds);

  Future<void> ensurePaymentDetailsHydrated() => infoManager.ensurePaymentDetailsHydrated();

  Future<void> saveUpiIdQuick(String upiId) => infoManager.saveUpiIdQuick(upiId);

  void clearError() {
    infoManager.setError(null);
    videoManager.setError(null);
  }

  void notifyListenersSafe() => notifyListeners();

  void clearData() {
    infoManager.clearData();
    videoManager.clearData();
    statsManager.clearData();
    notificationManager.clearData();
    notifyListeners();
  }

  Future<void> handleLogout() async {
    await _authService.signOut();
    clearData();
  }

  @override
  void dispose() {
    infoManager.dispose();
    videoManager.dispose();
    statsManager.dispose();
    notificationManager.dispose();
    super.dispose();
  }
}

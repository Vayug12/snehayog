import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vayug/core/interfaces/i_auth_service.dart';
import 'package:vayug/core/interfaces/i_user_service.dart';
import 'package:vayug/shared/managers/smart_cache_manager.dart';
import 'package:vayug/shared/utils/app_logger.dart';
import 'package:vayug/shared/config/app_config.dart';
import 'package:vayug/shared/services/http_client_service.dart';

class ProfileInfoManager extends ChangeNotifier {
  final IUserService _userService;
  final IAuthService _authService;
  final SmartCacheManager _smartCacheManager;

  ProfileInfoManager({
    required IUserService userService,
    required IAuthService authService,
    required SmartCacheManager smartCacheManager,
  })  : _userService = userService,
        _authService = authService,
        _smartCacheManager = smartCacheManager;

  // Controllers
  final TextEditingController nameController = TextEditingController();
  final TextEditingController websiteController = TextEditingController();

  // State variables
  Map<String, dynamic>? _userData;
  bool _isProfileLoading = false;
  bool _isPhotoLoading = false;
  bool _isEditing = false;
  String? requestedUserId;
  DateTime? _lastFullLoadTime;
  String? _error;

  static const Duration _refreshThreshold = Duration(minutes: 5);
  static const Duration _userProfileCacheTime = Duration(hours: 24);

  bool _isDisposed = false;

  // Getters
  Map<String, dynamic>? get userData => _userData;
  bool get isProfileLoading => _isProfileLoading;
  bool get isPhotoLoading => _isPhotoLoading;
  bool get isEditing => _isEditing;
  DateTime? get lastFullLoadTime => _lastFullLoadTime;
  String? get error => _error;

  set isEditing(bool value) {
    _isEditing = value;
    notifyListenersSafe();
  }

  set userData(Map<String, dynamic>? value) {
    _userData = value;
    notifyListenersSafe();
  }

  void setError(String? value) {
    _error = value;
    notifyListenersSafe();
  }

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
    nameController.dispose();
    websiteController.dispose();
    super.dispose();
  }

  Future<void> loadUserData(String? userId, {bool forceRefresh = false, bool silent = false}) async {
    if (userId != requestedUserId) {
      _userData = null;
      requestedUserId = userId;
      if (!silent) {
        _isProfileLoading = true;
        notifyListenersSafe();
      }
    }

    if (!forceRefresh && _userData != null && _lastFullLoadTime != null) {
      final timeSinceLoad = DateTime.now().difference(_lastFullLoadTime!);
      if (timeSinceLoad < _refreshThreshold) {
        AppLogger.log('⚡ ProfileInfoManager: Data fresh, skipping network refresh');
        return;
      }
    }

    _error = null;
    if (!silent) {
      _isProfileLoading = true;
      notifyListenersSafe();
    }

    try {
      final cacheKey = await _resolveProfileCacheKey(userId);
      
      if (forceRefresh) {
        await _smartCacheManager.clearCacheByPattern(cacheKey);
      }

      final data = await _smartCacheManager.get<Map<String, dynamic>>(
        cacheKey,
        cacheType: 'user_profile',
        maxAge: _userProfileCacheTime,
        fetchFn: () async {
          final result = await _fetchProfileData(userId);
          return result ?? {};
        },
      );

      if (data != null && data.isNotEmpty) {
        final existingPaymentDetails = _userData?['paymentDetails'];
        final normalized = _normalizeUserData(data, userId);
        if (normalized['paymentDetails'] == null &&
            existingPaymentDetails != null) {
          normalized['paymentDetails'] = existingPaymentDetails;
          normalized['hasUpiId'] = true;
        }
        _userData = normalized;
        nameController.text = _userData?['name']?.toString() ?? '';
        websiteController.text = _userData?['websiteUrl']?.toString() ?? '';
        _lastFullLoadTime = DateTime.now();
      } else {
        _error = 'Unable to load profile data.';
      }
    } catch (e) {
      AppLogger.log('❌ ProfileInfoManager: Error loading user data: $e');
      _error = 'Error loading user data: $e';
    } finally {
      _isProfileLoading = false;
      notifyListenersSafe();
    }
  }

  Future<void> updateProfilePhoto(String photoPath) async {
    _isPhotoLoading = true;
    notifyListenersSafe();
    try {
      final googleId = _userData?['googleId'] ?? _userData?['id'];
      if (googleId == null) throw Exception('User ID not found');

      final newUrl = await _userService.updateProfilePhoto(googleId, photoPath);
      if (newUrl != null) {
        if (_userData != null) _userData!['profilePic'] = newUrl;
        await _smartCacheManager.clearCacheByPattern('user_profile_$googleId');
        _authService.clearMemoryCache();
      }
    } finally {
      _isPhotoLoading = false;
      notifyListenersSafe();
    }
  }

  Future<void> updateProfession(String? professionId) async {
    final previousId = _userData?['professionId'];
    final previousProfession = _userData?['profession'];
    try {
      final result = await _userService.updateProfession(professionId);
      if (_userData != null) {
        _userData!['professionId'] = result['professionId'];
        _userData!['profession'] = result['profession'];
      }

      final googleId = _userData?['googleId'] ?? _userData?['id'];
      if (googleId != null) {
        await _smartCacheManager.clearCacheByPattern('user_profile_$googleId');
      }
      _authService.clearMemoryCache();
      notifyListenersSafe();
    } catch (_) {
      if (_userData != null) {
        _userData!['professionId'] = previousId;
        _userData!['profession'] = previousProfession;
      }
      notifyListenersSafe();
      rethrow;
    }
  }

  Future<void> updateProfile({required String name, String? profilePic, String? websiteUrl}) async {
    try {
      _isProfileLoading = true;
      notifyListenersSafe();

      final googleId = _userData?['googleId'] ?? _userData?['id'];
      if (googleId == null) throw Exception('User ID not found');

      final success = await _userService.updateProfile(
        googleId: googleId,
        name: name,
        profilePic: profilePic,
        websiteUrl: websiteUrl,
      );

      if (success) {
        // Update SharedPreferences fallback
        final prefs = await SharedPreferences.getInstance();
        final updatedFallbackData = {
          'id': googleId,
          'googleId': googleId,
          'name': name,
          'email': _userData?['email'] ?? '',
          'profilePic': profilePic ?? _userData?['profilePic'] ?? '',
          'websiteUrl': websiteUrl ?? _userData?['websiteUrl'] ?? '',
        };
        await prefs.setString('fallback_user', jsonEncode(updatedFallbackData));

        // Clear cache and AuthService memory cache
        await _smartCacheManager.clearCacheByPattern('user_profile_$googleId');
        _authService.clearMemoryCache();

        // Update local state
        if (_userData != null) {
          _userData!['name'] = name;
          _userData!['websiteUrl'] = websiteUrl;
          if (profilePic != null) _userData!['profilePic'] = profilePic;
        }
        
        _isEditing = false;
        AppLogger.log('✅ ProfileInfoManager: Profile updated successfully');
      } else {
        throw Exception('Failed to update profile on server');
      }
    } catch (e) {
      AppLogger.log('❌ ProfileInfoManager: Error updating profile: $e');
      _error = 'Failed to update profile: $e';
      rethrow;
    } finally {
      _isProfileLoading = false;
      notifyListenersSafe();
    }
  }

  void updateFollowerCount(String userId, {required bool increment}) {
    if (_userData != null) {
      final String? currentId = _userData?['googleId'] ?? _userData?['id'];
      if (currentId == userId) {
        int currentCount = _userData!['followersCount'] ?? 0;
        _userData!['followersCount'] = increment ? currentCount + 1 : (currentCount > 0 ? currentCount - 1 : 0);
        notifyListenersSafe();
      }
    }
  }

  Future<void> ensurePaymentDetailsHydrated() async {
    if (_userData != null && _userData!['paymentDetails'] == null) {
      try {
        final token = await _authService.getUserData().then((u) => u?['token']);
        if (token != null) {
          final response = await httpClientService.get(
            Uri.parse('${NetworkHelper.apiBaseUrl}/creator-payouts/profile'),
            headers: {'Authorization': 'Bearer $token'},
          );
          if (response.statusCode == 200) {
            final data = json.decode(response.body);
            if (data['paymentDetails'] != null) {
              _userData!['paymentDetails'] = data['paymentDetails'];
              _userData!['hasUpiId'] = true;
              notifyListenersSafe();
            }
          }
        }
      } catch (e) {
        AppLogger.log('Error hydrating payment details: $e');
      }
    }
  }

  Future<void> saveUpiIdQuick(String upiId) async {
    try {
      _isProfileLoading = true;
      notifyListenersSafe();
      
      final token = await _authService.getUserData().then((u) => u?['token']);
      if (token == null) throw Exception('Not authenticated');

      final response = await httpClientService.put(
        Uri.parse('${NetworkHelper.apiBaseUrl}/creator-payouts/payment-method'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'paymentMethod': 'upi',
          'paymentDetails': {'upiId': upiId},
          'currency': 'INR',
          'country': 'IN',
        }),
      );

      if (response.statusCode == 200) {
        if (_userData != null) {
          _userData!['paymentDetails'] = {'upiId': upiId};
          _userData!['hasUpiId'] = true;
        }
        await _smartCacheManager.clearCacheByPattern('user_profile_');
      } else {
        throw Exception('Failed to update UPI ID: ${response.statusCode}');
      }
    } finally {
      _isProfileLoading = false;
      notifyListenersSafe();
    }
  }

  void setPaymentDetails(Map<String, dynamic>? paymentDetails) {
    if (_userData == null) return;
    _userData!['paymentDetails'] = paymentDetails;
    _userData!['hasUpiId'] = paymentDetails?['upiId']
            ?.toString()
            .trim()
            .isNotEmpty ??
        false;
    notifyListenersSafe();
  }

  Future<String> _resolveProfileCacheKey(String? userId) async {
    final effectiveId = userId?.trim() ?? 'self';
    if (effectiveId == 'self' || effectiveId.isEmpty) {
      final loggedInUser = await _authService.getUserData();
      final myId = (loggedInUser?['googleId'] ?? loggedInUser?['id'])?.toString();
      return 'user_profile_${myId ?? 'self'}';
    }
    return 'user_profile_$effectiveId';
  }

  Future<Map<String, dynamic>?> _fetchProfileData(String? requestedUserId) async {
    final loggedInUser = await _authService.getUserData();
    final bool isMyProfile = requestedUserId == null ||
        (loggedInUser != null && (requestedUserId == loggedInUser['id'] || requestedUserId == loggedInUser['googleId']));

    if (isMyProfile) {
      if (loggedInUser == null) return null;
      final myId = loggedInUser['googleId'] ?? loggedInUser['id'];
      final backendUser = await _userService.getUserById(myId.toString());
      return backendUser;
    } else {
      return await _userService.getUserById(requestedUserId);
    }
  }

  Map<String, dynamic> _normalizeUserData(Map<String, dynamic> data, String? requestedUserId) {
    final Map<String, dynamic> normalized = Map<String, dynamic>.from(data);
    final String? dataId = data['id']?.toString() ?? data['googleId']?.toString();
    
    String? effectiveId = requestedUserId;
    if (effectiveId == null || effectiveId == 'self') {
      effectiveId = _authService.currentUserId;
    }

    if (effectiveId != null && dataId != null && dataId != effectiveId) {
      final String? mongoId = data['_id']?.toString();
      if (mongoId != effectiveId) {
        AppLogger.log('?? ProfileInfoManager: ID mismatch. Expected $effectiveId but got $dataId');
        throw Exception('Data integrity error: User ID mismatch');
      }
    }

    normalized['googleId'] = dataId ?? requestedUserId;
    if (!normalized.containsKey('id')) normalized['id'] = normalized['googleId'];

    int parseCount(dynamic value) {
      if (value == null) return 0;
      if (value is num) return value.toInt();
      if (value is List) return value.length;
      return int.tryParse(value.toString()) ?? 0;
    }

    normalized['followersCount'] = parseCount(normalized['followersCount'] ?? normalized['followers']);
    normalized['followingCount'] = parseCount(normalized['followingCount'] ?? normalized['following']);
    normalized['rank'] = normalized['rank'] ?? 0;
    
    if (!normalized.containsKey('notificationPreferences')) {
      normalized['notificationPreferences'] = {
        'globalCreatorAlerts': true,
        'disabledCreators': []
      };
    }
    return normalized;
  }
  
  void clearData() {
    _userData = null;
    requestedUserId = null;
    _isEditing = false;
    _error = null;
    _isProfileLoading = false;
    _isPhotoLoading = false;
    nameController.clear();
    websiteController.clear();
  }

}

import 'package:flutter/material.dart';
import 'package:vayug/features/auth/data/services/authservices.dart';
import 'package:vayug/core/interfaces/i_auth_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'dart:convert';

class GoogleSignInController extends ChangeNotifier {
  final IAuthService _authService;
  bool _isLoading = true; // Start as true — auth state is unknown until init completes
  bool _isInitialized = false;
  String? _error;
  Map<String, dynamic>? _userData;

  bool get isLoading => _isLoading;
  bool get isInitialized => _isInitialized;
  String? get error => _error;
  bool get isSignedIn => _userData != null;
  Map<String, dynamic>? get userData => _userData;

  /// Manually check and refresh authentication status
  Future<void> checkAuthStatus() async {
    _isInitialized = false;
    _isLoading = true;
    notifyListeners();
    await _initInBackground();
  }

  GoogleSignInController({IAuthService? authService}) : _authService = authService ?? AuthService() {
    // **FIXED: Start loading immediately so UI shows skeleton during init**
    _initInBackground();
  }

  Future<void> _initInBackground() async {
    try {
      // **FIXED: Try cached data first for instant UI (no network call)**
      try {
        final prefs = await SharedPreferences.getInstance();
        final needsLogin = prefs.getBool('auth_needs_login') ?? false;
        final jwt = prefs.getString('jwt_token');
        final fallbackUser = prefs.getString('fallback_user');

        // If token is missing/expired, treat as signed-out
        if (needsLogin || jwt == null || jwt.isEmpty) {
          _userData = null;
          _error = needsLogin ? 'Session expired - please sign in again' : null;
          return;
        }

        // Load from cache instantly — user sees profile immediately
        if (fallbackUser != null) {
          final cachedData = jsonDecode(fallbackUser);
          _userData = {
            'id': cachedData['id'],
            'googleId': cachedData['googleId'] ?? cachedData['id'],
            'name': cachedData['name'],
            'email': cachedData['email'],
            'profilePic': cachedData['profilePic'],
            'token': jwt,
            'isFallback': true,
          };

          // Refresh from backend in background (non-blocking)
          unawaited(_refreshUserDataInBackground());
          return;
        }
      } catch (e) {
        // SharedPreferences read failed — fall through to network check
      }

      // No cached data — need network call
      _isLoading = true;
      notifyListeners();

      // Check if user is already logged in
      final isLoggedIn = await _authService.isLoggedIn();
      if (isLoggedIn) {
        _userData = await _authService.getUserData();
      } else {
        // Try to silently recover session once (refresh token / Google silent sign-in)
        final refreshed = await _authService.refreshAccessToken();
        if (refreshed != null) {
          _userData = await _authService.getUserData();
        } else {
          _userData = null;
        }
      }
    } catch (e) {
      _error = e.toString();
      _userData = null;
    } finally {
      _isInitialized = true;
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<Map<String, dynamic>?> signIn() async {
    try {


      _isLoading = true;
      _error = null;
      notifyListeners();

      final userInfo = await _authService.signInWithGoogle();
      if (userInfo != null) {
        _userData = userInfo;
        _error = null;
        // Clear "needs login" flag on successful sign-in
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('auth_needs_login', false);
        } catch (_) {}

      } else {
        _error = 'Sign in failed';

      }

      _isLoading = false;
      notifyListeners();
      return userInfo;
    } catch (e) {

      _error = e.toString();
      _isLoading = false;
      notifyListeners();
      return null;
    }
  }

  Future<Map<String, dynamic>> requestPhoneOtp(String phoneNumber) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      return await _authService.requestPhoneOtp(phoneNumber);
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<Map<String, dynamic>?> verifyPhoneOtp({
    required String challengeId,
    required String otp,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final userInfo = await _authService.verifyPhoneOtp(
        challengeId: challengeId,
        otp: otp,
      );
      if (userInfo != null) {
        _userData = userInfo;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('auth_needs_login', false);
      }
      return userInfo;
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> signOut() async {
    try {


      await _authService.signOut();

      // **FIXED: Clear ALL state and force refresh**
      _userData = null;
      _error = null;
      _isLoading = false;


      notifyListeners();
    } catch (e) {

      _error = e.toString();
      notifyListeners();
    }
  }

  /// **Clear error state for retry functionality**
  void clearError() {
    _error = null;
    notifyListeners();
  }

  /// **FIXED: Force refresh authentication state after account switch or session expiry**
  Future<void> refreshAuthState() async {
    try {
      // **CHECK: If auth_needs_login is set, this is a definitive session expiry**
      // In this case, we must clear userData to show sign-in screen, NOT show cached 0 data
      final prefs = await SharedPreferences.getInstance();
      final needsLogin = prefs.getBool('auth_needs_login') ?? false;
      
      if (needsLogin) {
        // Session definitively expired — clear state immediately to trigger sign-in UI
        _userData = null;
        _error = 'Session expired. Please sign in again.';
        _isLoading = false;
        notifyListeners();
        return;
      }

      // **OPTIMIZED: Only show loader if we have NO data. Otherwise refresh silently.**
      if (_userData == null) {
        _isLoading = true;
        notifyListeners();
      }

      // **FIXED: Get fresh user data from AuthService**
      final freshData = await _authService.getUserData();
      final sessionInvalidated =
          prefs.getBool('auth_needs_login') ?? false;

      if (freshData != null) {
        _userData = freshData;
        _error = null;
      } else if (_userData == null || sessionInvalidated) {
        // Without an existing session, a null profile means sign-in is still needed.
        _userData = null;
        _error = 'Session expired. Please sign in again.';
      } else {
        // Keep an existing session during transient profile/network failures.
        _error = null;
      }

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
    }
  }

  /// **OPTIMIZED: Refresh user data in background without blocking UI**
  Future<void> _refreshUserDataInBackground() async {
    try {
      final freshData = await _authService.getUserData();
      if (freshData != null) {
        _userData = freshData;
        notifyListeners();

      }
    } catch (e) {

      // Keep cached data on error
    }
  }
}

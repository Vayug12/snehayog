import 'package:flutter/material.dart';
import 'package:vayug/features/auth/data/services/authservices.dart';
import 'package:vayug/core/interfaces/i_auth_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'dart:convert';

class GoogleSignInController extends ChangeNotifier {
  final IAuthService _authService;
  bool _isLoading = false;
  String? _error;
  Map<String, dynamic>? _userData;

  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isSignedIn => _userData != null;
  Map<String, dynamic>? get userData => _userData;

  /// Manually check and refresh authentication status
  Future<void> checkAuthStatus() async {
    await _initInBackground();
  }

  GoogleSignInController({IAuthService? authService}) : _authService = authService ?? AuthService() {
    // **OPTIMIZED: Don't block UI during initialization**
    _initInBackground();
  }

  Future<void> _initInBackground() async {
    try {
      // **OPTIMIZED: Use cached data immediately, verify in background**
      // First, try to get cached user data instantly (no network call)
      try {
        final prefs = await SharedPreferences.getInstance();
        final needsLogin = prefs.getBool('auth_needs_login') ?? false;
        final jwt = prefs.getString('jwt_token');
        final fallbackUser = prefs.getString('fallback_user');
        // If token is missing/expired and refresh couldn't recover, treat as signed-out
        // so UI shows Sign-In CTA instead of empty state.
        if (needsLogin || jwt == null || jwt.isEmpty) {
          _userData = null;
          _isLoading = false;
          _error = needsLogin ? 'Session expired - please sign in again' : null;
          notifyListeners();
          return;
        }

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
          _isLoading = false;
          notifyListeners();


          // Refresh from backend in background (non-blocking)
          unawaited(_refreshUserDataInBackground());
          return;
        }
      } catch (e) {

      }

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
      _userData = null; // Ensure userData is null on error
    } finally {
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

      if (freshData != null) {
        _userData = freshData;
        _error = null;
      } else {
        // getUserData returned null — treat as signed-out
        _userData = null;
        _error = 'Session expired. Please sign in again.';
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

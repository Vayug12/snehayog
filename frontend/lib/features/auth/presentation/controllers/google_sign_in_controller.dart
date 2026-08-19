import 'package:flutter/material.dart';
import 'package:vayug/features/auth/data/services/authservices.dart';
import 'package:vayug/core/interfaces/i_auth_service.dart';
import 'package:vayug/features/auth/domain/entities/auth_result.dart';
import 'package:vayug/shared/utils/app_text.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'dart:convert';

class GoogleSignInController extends ChangeNotifier {
  final IAuthService _authService;
  bool _isLoading = true; // Start as true — auth state is unknown until init completes
  bool _isInitialized = false;
  String? _error;
  Map<String, dynamic>? _userData;
  bool _isSigningIn = false;

  /// Set once an interactive sign-in has produced a session. The background
  /// init reads stale storage, so it must never overwrite a session that was
  /// established while it was still in flight.
  bool _hasInteractiveSession = false;

  bool get isLoading => _isLoading;
  bool get isInitialized => _isInitialized;
  String? get error => _error;
  bool get isSignedIn => _userData != null;

  /// True while a Google sign-in sheet/exchange is in flight.
  bool get isSigningIn => _isSigningIn;
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
      if (_hasInteractiveSession) return;
      // **FIXED: Try cached data first for instant UI (no network call)**
      try {
        final prefs = await SharedPreferences.getInstance();
        final needsLogin = prefs.getBool('auth_needs_login') ?? false;
        final jwt = prefs.getString('jwt_token');
        final fallbackUser = prefs.getString('fallback_user');

        // If token is missing/expired, treat as signed-out
        if (needsLogin || jwt == null || jwt.isEmpty) {
          if (_hasInteractiveSession) return;
          _userData = null;
          _error = needsLogin ? 'Session expired - please sign in again' : null;
          return;
        }

        // Load from cache instantly — user sees profile immediately
        if (fallbackUser != null) {
          if (_hasInteractiveSession) return;
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
        final data = await _authService.getUserData();
        if (_hasInteractiveSession) return;
        _userData = data;
      } else {
        // Try to silently recover session once (refresh token / Google silent sign-in)
        final refreshed = await _authService.refreshAccessToken();
        final data =
            refreshed != null ? await _authService.getUserData() : null;
        if (_hasInteractiveSession) return;
        _userData = data;
      }
    } catch (e) {
      if (_hasInteractiveSession) return;
      _error = e.toString();
      _userData = null;
    } finally {
      _isInitialized = true;
      _isLoading = false;
      notifyListeners();
    }
  }

  /// The one Google sign-in entry point for the whole app.
  ///
  /// Never reports success for an attempt that failed: a session exists only
  /// when the backend returned one. Callers should route the result through
  /// [AuthFlow.signIn] so the user-facing message stays consistent.
  Future<AuthResult> signIn() async {
    if (_isSigningIn) {
      // Debounce: a second tap must not open a second Google sheet.
      return AuthResult.failed(
        AppText.get('error_sign_in_in_progress'),
        kind: AuthFailureKind.unknown,
      );
    }

    _isSigningIn = true;
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      final userInfo = await _authService.signInWithGoogle();

      if (userInfo == null) {
        // Google sheet dismissed — not an error, so no error state.
        _error = null;
        return AuthResult.cancelled;
      }

      _userData = userInfo;
      _hasInteractiveSession = true;
      _error = null;
      // Clear "needs login" flag on successful sign-in
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('auth_needs_login', false);
      } catch (_) {}

      return AuthResult.success(userInfo);
    } on AuthException catch (e) {
      _error = e.message;
      return AuthResult.failed(e.message, kind: e.kind);
    } catch (e) {
      final message = AppText.get('error_sign_in');
      _error = message;
      return AuthResult.failed(message);
    } finally {
      _isSigningIn = false;
      _isLoading = false;
      notifyListeners();
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
        _hasInteractiveSession = true;
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
      _hasInteractiveSession = false;
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
        _hasInteractiveSession = false;
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
        _hasInteractiveSession = false;
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

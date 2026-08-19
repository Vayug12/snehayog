import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vayug/core/interfaces/i_auth_service.dart';
import 'package:vayug/features/auth/domain/entities/auth_result.dart';
import 'package:vayug/features/auth/presentation/controllers/google_sign_in_controller.dart';

/// Fake auth service driven per-test. Only [signInWithGoogle] matters here.
class _FakeAuthService implements IAuthService {
  _FakeAuthService(this._onSignIn);

  final Future<Map<String, dynamic>?> Function() _onSignIn;
  int signInCalls = 0;

  @override
  Future<Map<String, dynamic>?> signInWithGoogle(
      {bool forceAccountPicker = true}) {
    signInCalls++;
    return _onSignIn();
  }

  @override
  String? get currentUserId => null;

  @override
  Future<Map<String, dynamic>?> getUserData(
          {bool skipTokenRefresh = false, bool forceRefresh = false}) async =>
      null;

  @override
  Future<void> signOut() async {}

  @override
  Future<bool> isSignedIn() async => false;

  @override
  Future<Map<String, dynamic>> requestPhoneOtp(String phoneNumber) async => {};

  @override
  Future<Map<String, dynamic>?> verifyPhoneOtp(
          {required String challengeId, required String otp}) async =>
      null;

  @override
  void clearMemoryCache() {}

  @override
  Future<bool> isLoggedIn() async => false;

  @override
  Future<String?> refreshAccessToken() async => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('a backend/network failure is reported as a failure, not a session',
      () async {
    final service = _FakeAuthService(() async => throw const AuthException(
          AuthFailureKind.network,
          'No stable connection.',
        ));
    final controller = GoogleSignInController(authService: service);

    final result = await controller.signIn();

    expect(result.isSuccess, isFalse);
    expect(result.isFailure, isTrue);
    expect(result.failureKind, AuthFailureKind.network);
    expect(result.message, 'No stable connection.');
    expect(controller.isSignedIn, isFalse);
  });

  test('a dismissed Google sheet is cancelled, not a failure', () async {
    final service = _FakeAuthService(() async => null);
    final controller = GoogleSignInController(authService: service);

    final result = await controller.signIn();

    expect(result.isCancelled, isTrue);
    expect(result.isSuccess, isFalse);
    expect(controller.error, isNull);
  });

  test('only a real backend session counts as success', () async {
    final service = _FakeAuthService(() async => {
          'id': 'g-1',
          'googleId': 'g-1',
          'name': 'Test',
          'token': 'jwt-token',
        });
    final controller = GoogleSignInController(authService: service);

    final result = await controller.signIn();

    expect(result.isSuccess, isTrue);
    expect(result.user?['token'], 'jwt-token');
    expect(controller.isSignedIn, isTrue);
  });

  test('a second tap while signing in does not open a second sheet', () async {
    final gate = Completer<Map<String, dynamic>?>();
    final service = _FakeAuthService(() => gate.future);
    final controller = GoogleSignInController(authService: service);

    final first = controller.signIn();
    final second = await controller.signIn();

    expect(second.isSuccess, isFalse);
    expect(service.signInCalls, 1);

    gate.complete(null);
    await first;
  });
}

abstract class IAuthService {
  String? get currentUserId;
  Future<Map<String, dynamic>?> getUserData({bool skipTokenRefresh = false, bool forceRefresh = false});
  Future<void> signOut();
  Future<bool> isSignedIn();
  Future<Map<String, dynamic>?> signInWithGoogle({bool forceAccountPicker = true});
  Future<Map<String, dynamic>> requestPhoneOtp(String phoneNumber);
  Future<Map<String, dynamic>?> verifyPhoneOtp({
    required String challengeId,
    required String otp,
  });
  void clearMemoryCache();
  Future<bool> isLoggedIn();
  Future<String?> refreshAccessToken();
}

/// Why a sign-in attempt did not produce a session.
///
/// The kind decides the copy the user sees, so it must be derived from what
/// actually failed - never guessed at the call site.
enum AuthFailureKind {
  /// User dismissed the Google/phone sheet. Not an error.
  cancelled,

  /// Device could not reach the backend (timeout, DNS, socket).
  network,

  /// Backend was reached but rejected or failed the request.
  server,

  /// Client misconfiguration (OAuth client id, missing token).
  configuration,

  unknown,
}

/// Raised by the auth layer when sign-in cannot complete.
///
/// Carries a message that is already safe to show to a user, so no screen has
/// to stringify a raw exception.
class AuthException implements Exception {
  const AuthException(this.kind, this.message, {this.cause});

  final AuthFailureKind kind;
  final String message;
  final Object? cause;

  @override
  String toString() => 'AuthException($kind): $message';
}

/// Outcome of a sign-in attempt.
enum AuthOutcome { success, cancelled, failed }

/// The single value every sign-in entry point returns.
///
/// A session exists only when [outcome] is [AuthOutcome.success] and [user] is
/// non-null, which is what keeps a network failure from being reported as a
/// successful sign-in.
class AuthResult {
  const AuthResult._(this.outcome, {this.user, this.message, this.failureKind});

  final AuthOutcome outcome;
  final Map<String, dynamic>? user;

  /// User-facing reason. Null for [AuthOutcome.success].
  final String? message;

  final AuthFailureKind? failureKind;

  factory AuthResult.success(Map<String, dynamic> user) =>
      AuthResult._(AuthOutcome.success, user: user);

  static const AuthResult cancelled =
      AuthResult._(AuthOutcome.cancelled, failureKind: AuthFailureKind.cancelled);

  factory AuthResult.failed(String message,
          {AuthFailureKind kind = AuthFailureKind.unknown}) =>
      AuthResult._(AuthOutcome.failed, message: message, failureKind: kind);

  bool get isSuccess => outcome == AuthOutcome.success && user != null;
  bool get isCancelled => outcome == AuthOutcome.cancelled;
  bool get isFailure => outcome == AuthOutcome.failed;
}
